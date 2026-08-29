#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大讲座日历 数据源适配壳（真实抓取 · 公开免登录源）。

数据源：浙江大学图书馆「讲座与展览」公告列表（苏迪 CMS，服务端渲染，UTF-8）。
  https://libweb.zju.edu.cn/jzyl/list.htm   （第 1 页）
  https://libweb.zju.edu.cn/jzyl/list2.htm  （第 2 页，listN.htm 依此类推）
条目结构（每页 14 条，共 315 条 / 23 页）：
  <li class="news nX clearfix">
    <span class="news_title"><a href='...' target='_blank' title='讲座标题'>讲座标题</a></span>
    <span class="news_meta">YYYY-MM-DD</span>
  </li>

范围说明（诚实声明）：本源覆盖**浙江大学图书馆**发布的讲座 / 展览 / 文化活动公告，
并非全校学术讲座全集（全校「学术公告」频道 www.zju.edu.cn/xs/ 为 JS 内嵌标题、
无日期无链接，不适合做日历，故未采用）。输出中带 `scope` 字段说明此边界。

CLI 契约（与平台 register_data_source.dart 完全一致）：
  fetch.py --type <typeArg> --project-root <projectRoot> --greenix-config <cfg>
  - stdout 只输出单个 JSON 对象（顶层 Map），UTF-8；
  - 失败时 stdout 输出 {"error": "<人类可读信息>"} 且退出码非 0；
  - 纯 Python 标准库（urllib/json/re/html），零第三方依赖，Android Chaquopy 可用。
"""
import html as _html
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime

# stdout 固定 UTF-8（旧 Python 无 reconfigure 时静默跳过）
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

SITE_NAME = "浙江大学图书馆·讲座与展览"
SITE_HOST = "libweb.zju.edu.cn"
LIST_URL = "https://%s/jzyl/list.htm" % SITE_HOST
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
              "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36 "
              "Evergreen/zju-lectures")
PAGE_SIZE = 14          # 站点每页条数（结构变化时用于判断是否到达末页）
DEFAULT_PAGES = 3       # 默认抓取页数（14×3 = 42 条近期讲座）
MAX_PAGES = 10          # 页数上限（约束单次抓取成本）
REQUEST_TIMEOUT = 10    # 单页请求超时（秒）

_LI_RE = re.compile(r'<li class="news\s[^>]*>(.*?)</li>', re.S)
_TITLE_RE = re.compile(r'<span class="news_title">\s*<a[^>]*?title=(["\'])(.*?)\1', re.S)
_HREF_RE = re.compile(r'<a[^>]*?href=(["\'])(.*?)\1', re.S)
_DATE_RE = re.compile(r'<span class="news_meta">\s*(\d{4}-\d{2}-\d{2})\s*</span>', re.S)
_TAG_RE = re.compile(r'<[^>]+>')


# ═══════════════════════════════════════════════════════════════════
# 配置读取（平台模式：GREENIX_CONFIG_PATH 文件 → ConfigHttpServer → 环境变量）
# 本源无需凭据；ZJU_LECTURE_PAGES 为可选抓取页数旋钮（1..10，默认 3）。
# ═══════════════════════════════════════════════════════════════════

def _get_config(key):
    """三级降级读取平台配置，全部缺失返回 None（可选旋钮，非凭据）。"""
    # Tier 1（主）：.greenix/config.json 本地文件（GREENIX_CONFIG_PATH 指定）
    cfg_path = os.environ.get('GREENIX_CONFIG_PATH')
    if cfg_path and os.path.exists(cfg_path):
        try:
            with open(cfg_path, 'r', encoding='utf-8') as f:
                val = json.load(f).get(key)
            if val:
                return str(val)
        except Exception:
            pass
    # Tier 2（降级）：HTTP 从 ConfigHttpServer 读（沿 cwd 向上找 .config_port）
    try:
        port_file = None
        for base in (os.getcwd(), os.environ.get('PROJECT_ROOT', '.')):
            d = os.path.abspath(base)
            while True:
                pf = os.path.join(d, '.config_port')
                if os.path.exists(pf):
                    port_file = pf
                    break
                parent = os.path.dirname(d)
                if parent == d:
                    break
                d = parent
            if port_file:
                break
        if port_file:
            with open(port_file, 'r') as f:
                port = f.read().strip()
            req = urllib.request.Request(
                'http://127.0.0.1:%s/config/settings/%s' % (port, key),
                headers={'User-Agent': USER_AGENT})
            with urllib.request.urlopen(req, timeout=5) as resp:
                val = json.loads(resp.read().decode('utf-8')).get('value')
            if val:
                return str(val)
    except Exception:
        pass
    # Tier 3（兜底）：系统环境变量
    return os.environ.get(key)


def _max_pages():
    raw = _get_config('ZJU_LECTURE_PAGES')
    try:
        n = int(raw) if raw else DEFAULT_PAGES
    except (TypeError, ValueError):
        n = DEFAULT_PAGES
    return max(1, min(n, MAX_PAGES))


# ═══════════════════════════════════════════════════════════════════
# 抓取与解析（纯标准库）
# ═══════════════════════════════════════════════════════════════════

def _ssl_context():
    """构建校验证书的 TLS 上下文。

    部分 Windows 机器（Conda/自带 OpenSSL 3.x）加载系统 CA 证书库时可能抛
    `ASN1: NOT_ENOUGH_DATA`（本地证书库与 OpenSSL 解析不兼容，与远端无关）。
    此时仅当用户显式设置 ZJU_LECTURE_INSECURE=1 才降级为不校验证书（公开只读
    公告页，风险可控）；否则抛可读错误，绝不静默降级。
    """
    try:
        return ssl.create_default_context()
    except ssl.SSLError:
        if os.environ.get('ZJU_LECTURE_INSECURE') == '1':
            _SSL_INSECURE[0] = True
            return ssl._create_unverified_context()
        raise RuntimeError(
            '系统 CA 证书库加载失败（Windows 证书存储与 OpenSSL 不兼容：'
            'ASN1 解析错误，与目标站点无关）。如网络环境可信，'
            '可设置环境变量 ZJU_LECTURE_INSECURE=1 跳过证书校验后重试。')


_SSL_INSECURE = [False]  # 本进程是否使用了不校验证书模式（供输出如实标注）


def _fetch_page(url, timeout=REQUEST_TIMEOUT):
    """GET 单页，返回解码文本（utf-8 优先，gbk 兜底）。"""
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout, context=_ssl_context()) as resp:
        raw = resp.read()
    for enc in ('utf-8', 'gbk'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    raise RuntimeError('无法解码站点内容（utf-8 / gbk 均失败）')


def _resolve_url(href):
    href = href.strip()
    if href.startswith('//'):
        return 'https:' + href
    if href.startswith('/'):
        return 'https://%s%s' % (SITE_HOST, href)
    return href


def _parse_items(html_text):
    """从单页 HTML 提取讲座条目列表（title / url / date）。"""
    items = []
    for m in _LI_RE.finditer(html_text):
        block = m.group(1)
        tm = _TITLE_RE.search(block)
        if tm:
            title = _html.unescape(tm.group(2)).strip()
        else:
            # 兜底：剥离标签取纯文本
            title = _html.unescape(_TAG_RE.sub('', block)).strip()
        if not title:
            continue
        hm = _HREF_RE.search(block)
        url = _resolve_url(hm.group(2)) if hm else ''
        dm = _DATE_RE.search(block)
        date = dm.group(1) if dm else ''
        items.append({'title': title, 'url': url, 'date': date})
    return items


def _friendly_error(exc):
    """把异常收敛为人类可读的中文错误信息。"""
    if isinstance(exc, urllib.error.HTTPError):
        return '浙大讲座源返回 HTTP %s（%s）：%s' % (exc.code, exc.reason, exc.url)
    if isinstance(exc, urllib.error.URLError):
        reason = getattr(exc, 'reason', exc)
        return '无法连接浙大讲座源（%s）：%s（需公网访问，校园网/VPN 不影响）' % (SITE_HOST, reason)
    return str(exc) or exc.__class__.__name__


def fetch_lectures(pages):
    """抓取前 pages 页讲座公告，去重后按站点顺序返回条目列表。"""
    items, seen = [], set()
    for page in range(1, pages + 1):
        url = LIST_URL if page == 1 else 'https://%s/jzyl/list%d.htm' % (SITE_HOST, page)
        try:
            html_text = _fetch_page(url)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                break                       # 页码越界 = 已到末页
            raise
        parsed = _parse_items(html_text)
        if not parsed:
            break                           # 空页 = 已到末页
        for it in parsed:
            key = (it['title'], it['url'], it['date'])
            if key in seen:
                continue
            seen.add(key)
            items.append(it)
        if len(parsed) < PAGE_SIZE:
            break
    if not items:
        raise RuntimeError('未解析到任何讲座条目（站点结构可能已变化）')
    return items


# ═══════════════════════════════════════════════════════════════════
# CLI 入口
# ═══════════════════════════════════════════════════════════════════

def _parse_args(argv):
    """空格分隔参数解析：--key value 与 --key=value 双形态（契约要求空格分隔）。"""
    args = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith('--') and '=' in tok:
            key, val = tok.split('=', 1)
            args[key] = val
            i += 1
        elif tok.startswith('--') and i + 1 < len(argv):
            args[tok] = argv[i + 1]
            i += 2
        else:
            i += 1
    return args


def main():
    args = _parse_args(sys.argv[1:])
    type_arg = args.get('--type') or 'zju_lectures'
    try:
        if type_arg != 'zju_lectures':
            raise ValueError('未知数据源类型：%s（本插件仅支持 zju_lectures）' % type_arg)
        items = fetch_lectures(_max_pages())
        result = {
            'type': type_arg,
            'source': SITE_NAME,
            'source_url': LIST_URL,
            'updated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'scope': '覆盖浙江大学图书馆发布的讲座/展览/文化活动公告，非全校学术讲座全集',
            'tls_verified': not _SSL_INSECURE[0],
            'total': len(items),
            'items': items,
        }
        sys.stdout.write(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        # 契约：错误走 stdout 的 {"error": ...} + 非零退出码，绝不输出堆栈污染 stdout
        sys.stdout.write(json.dumps({'error': _friendly_error(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == '__main__':
    main()
