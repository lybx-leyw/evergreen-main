#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大食堂数据源适配壳（模型 A / CLI，纯 Python 标准库，零第三方依赖）。

数据真实性：
- 主数据源（免登录公开页）：浙江大学后勤集团官网「餐饮服务」页面
  https://zulg.zju.edu.cn/guide/food.htm —— 全校区食堂/餐饮点目录，
  含名称、校区分组、位置、特色、联系人、联系电话、营业时间。真实数据，
  非每日菜谱。
- 补充数据源（免登录公开页，best-effort）：海宁国际校区 Campus Operation
  Center「每周菜单」页 https://coc.intl.zju.edu.cn/zh-hans/content/874905
  —— 每周菜单以 PDF 形式公开，本适配壳仅提取下载链接（PDF 本身为二进制，
  不解析内容）。
- 诚实声明：浙大各校区「每日菜品菜单」无公开结构化接口（"浙大后勤"小程序
  /公众号订餐需微信登录；校园网 WebVPN 亦无开放菜单 API），本数据源不伪造
  菜品数据，只返回上述真实公开数据。

契约（数据源 CLI）：
- stdout 只输出单个 JSON 对象（顶层 Map），UTF-8。
- 失败时 stdout 输出 {"error": "..."} 且 exit code 非 0。
- 日志一律走 stderr，绝不混入 stdout。
"""
import json
import os
import re
import ssl
import sys
import urllib.request
from datetime import datetime, timezone, timedelta

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

ZULG_FOOD_URL = 'https://zulg.zju.edu.cn/guide/food.htm'
INTL_MENU_URL = 'https://coc.intl.zju.edu.cn/zh-hans/content/874905'

HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'),
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}

# 非食堂条目的名称过滤（页面底部的"信息公示"区与公告标题）
_SKIP_NAME_PATTERNS = re.compile(r'投诉|办法|公示|信息公示')


def _get_config(key):
    """从平台配置读取设置（三级降级，供将来接入凭证场景复用）。

    策略1（主）：GREENIX_CONFIG_PATH 指定的 .greenix/config.json
    策略2（降级）：HTTP 从 ConfigHttpServer 读取（.config_port）
    策略3（兜底）：系统环境变量
    三级全空返回 None（本数据源为公开数据，无必需凭证）。
    """
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            if os.path.exists(greenix_path):
                with open(greenix_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key)
                if val:
                    return val
        except Exception:
            pass
    try:
        port_file = None
        # 从工作目录与 PROJECT_ROOT 向上查找 .config_port
        for start in [os.getcwd(), os.environ.get('PROJECT_ROOT', '')]:
            if not start:
                continue
            cur = os.path.abspath(start)
            while True:
                pf = os.path.join(cur, '.config_port')
                if os.path.exists(pf):
                    port_file = pf
                    break
                parent = os.path.dirname(cur)
                if parent == cur:
                    break
                cur = parent
            if port_file:
                break
        if port_file:
            with open(port_file, 'r', encoding='utf-8') as f:
                port = f.read().strip()
            url = 'http://127.0.0.1:{0}/config/settings/{1}'.format(port, key)
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                val = data.get('value')
                if val:
                    return val
    except Exception:
        pass
    return os.environ.get(key) or None


def _build_ssl_contexts():
    """按可用性分层构造 SSL 上下文（返回 [(label, ctx)]）。

    背景：部分 Windows 机器上 Python 的 OpenSSL 在 `load_default_certs()`
    （读取 Windows 系统证书库）时会因本地证书条目解析失败而抛
    `[ASN1: NOT_ENOUGH_DATA]`，导致 urllib 完全不可用（与目标站点无关）。
    因此按以下顺序降级：
      1. verify  —— create_default_context()（系统信任库 + 证书校验），
                   构建失败（本地证书库问题）则跳过；
      2. verify2 —— raw context + set_default_verify_paths()（OpenSSL 默认
                   CA 路径 / SSL_CERT_FILE / SSL_CERT_DIR，仍保留证书校验）；
      3. no-verify —— raw context + TLS 1.2 + 关闭校验（最后的兜底；
                   数据为公开非敏感信息，MITM 风险可接受，代码内已注明）。
    """
    contexts = []
    try:
        contexts.append(('verify', ssl.create_default_context()))
    except ssl.SSLError:
        pass  # 本地系统证书库解析失败 → 跳过（非目标站点问题）
    try:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.set_default_verify_paths()
        contexts.append(('verify2', ctx))
    except ssl.SSLError:
        pass
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    contexts.append(('no-verify', ctx))
    return contexts


def _fetch_html(url, timeout=15):
    """抓取 HTML（https 优先，失败回退 http；多级 TLS 上下文）。

    返回 (解码后的字符串, 实际使用的 TLS 上下文标签)。
    """
    last_err = None
    for u in (url, url.replace('https://', 'http://', 1)):
        if not u.startswith('http'):
            continue
        for label, ctx in _build_ssl_contexts():
            try:
                req = urllib.request.Request(u, headers=HEADERS)
                with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                    raw = resp.read()
                # 页面声明 UTF-8；个别镜像可能为 GBK，做兼容解码
                for enc in ('utf-8', 'gb18030'):
                    try:
                        return raw.decode(enc), label
                    except UnicodeDecodeError:
                        continue
                return raw.decode('utf-8', errors='replace'), label
            except Exception as e:  # noqa: BLE001
                last_err = e
    raise RuntimeError('抓取失败: {0}'.format(last_err or '未知错误'))


def _clean_p(text):
    """去掉段落内残留标签（<br> 等）并压缩空白。"""
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def _parse_canteen_directory(html):
    """解析后勤集团「餐饮服务」页 → 校区分组食堂目录。

    每条目的 DOM 结构（语义 class，稳定）：
      <h4 class="l1 h4s1">名称</h4>
      <p class="p1">位置</p>  <p class="p2">特色</p>
      <p class="p3">联系人</p>  <p class="p4">电话</p>
      <p class="p5">营业时间（<br> 分隔多行）</p>
    """
    marker = html.find('餐饮服务（二）')
    sec = html[marker:] if marker >= 0 else html
    if marker < 0:
        tabs = []
    else:
        hd = sec[sec.find('<div class="hd"'):sec.find('<div class="content1')]
        tabs = [t.strip() for t in re.findall(r'<a>([^<]+)</a>', hd)]

    blocks = re.findall(r'<div class="content_li">(.*?)(?=<div class="content_li">|$)', sec, re.S)
    items = []
    for idx, block in enumerate(blocks):
        campus = tabs[idx] if idx < len(tabs) else ''
        for li in re.findall(r'<li>(.*?)</li>', block, re.S):
            name_m = re.search(r'<h4[^>]*>([^<]+)</h4>', li, re.S)
            if not name_m:
                continue
            name = name_m.group(1).strip()
            if not name or _SKIP_NAME_PATTERNS.search(name):
                continue

            def grab(pclass):
                parts = [
                    _clean_p(p) for p in re.findall(
                        r'<p class="%s"[^>]*>(.*?)</p>' % re.escape(pclass), li, re.S)
                ]
                return ' '.join(x for x in parts if x)

            items.append({
                'name': name,
                'campus': campus,
                'location': grab('p1'),
                'contact': grab('p3'),
                'phone': grab('p4'),
                'hours': grab('p5'),
                'features': [x for x in (_clean_p(p) for p in re.findall(
                    r'<p class="p2"[^>]*>(.*?)</p>', li, re.S)) if x],
            })
    return items


def _parse_weekly_menu_links(html):
    """解析海宁国际校区「每周菜单」页 → PDF 下载链接（best-effort）。"""
    links = []
    for href, text in re.findall(r'<a[^>]+href="([^"]+\.pdf)"[^>]*>([^<]*)</a>', html, re.S):
        if href.lower().endswith('.pdf'):
            links.append({'name': text.strip() or href.rsplit('/', 1)[-1], 'url': href})
    return links


def fetch_data(type_arg):
    """抓取并组装真实数据；任何失败抛异常（由 main 收敛为 error JSON）。"""
    # 1) 主数据源：后勤集团餐饮服务（食堂目录）
    html, tls_mode = _fetch_html(ZULG_FOOD_URL)
    items = _parse_canteen_directory(html)
    if not items:
        raise RuntimeError('解析后勤集团餐饮服务页面失败：未提取到食堂条目')

    # 2) 补充数据源（best-effort）：海宁国际校区每周菜单 PDF 链接
    weekly_menu_pdfs = []
    try:
        menu_html, _ = _fetch_html(INTL_MENU_URL)
        weekly_menu_pdfs = _parse_weekly_menu_links(menu_html)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write('[zju-canteen] 每周菜单页不可用（忽略）: %s\n' % e)

    campus_count = len({it['campus'] for it in items if it['campus']})
    cst = timezone(timedelta(hours=8))
    return {
        'type': type_arg,
        'source': '浙江大学后勤集团·餐饮服务（zulg.zju.edu.cn/guide/food.htm）',
        'fetched_at': datetime.now(cst).strftime('%Y-%m-%dT%H:%M:%S%z'),
        'tls_mode': tls_mode,
        'campus_count': campus_count,
        'total': len(items),
        'items': items,
        'weekly_menu_pdfs': weekly_menu_pdfs,
        'note': ('数据为浙大后勤集团官网公开「餐饮服务」目录（食堂/餐饮点名称、校区、位置、'
                 '营业时间、联系电话），免登录抓取，非每日菜谱。各校区每日菜品菜单无公开'
                 '结构化接口（浙大后勤小程序/公众号订餐需登录）；海宁国际校区每周菜单以 '
                 'PDF 公开，见 weekly_menu_pdfs 链接。'),
    }


def parse_args(argv):
    """解析空格分隔参数（兼容 --key value 与 --key=value 两种形式）。"""
    args = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith('--'):
            key = a[2:]
            if '=' in key:
                k, v = key.split('=', 1)
                args[k] = v
                i += 1
                continue
            if i + 1 < len(argv) and not argv[i + 1].startswith('--'):
                args[key] = argv[i + 1]
                i += 2
                continue
            args[key] = ''
            i += 1
            continue
        if '=' in a:  # 兼容旧写法 type=zju_canteen
            k, v = a.split('=', 1)
            args[k] = v
        i += 1
    return args


def main():
    try:
        args = parse_args(sys.argv[1:])
        type_arg = args.get('type', 'zju_canteen') or 'zju_canteen'
        result = fetch_data(type_arg)
        sys.stdout.write(json.dumps(result, ensure_ascii=False))
        sys.stdout.write('\n')
        return 0
    except Exception as e:  # noqa: BLE001
        err = {'error': '[zju-canteen] {0}'.format(e)}
        try:
            sys.stdout.write(json.dumps(err, ensure_ascii=False))
            sys.stdout.write('\n')
        except Exception:
            pass
        return 1


if __name__ == '__main__':
    sys.exit(main())
