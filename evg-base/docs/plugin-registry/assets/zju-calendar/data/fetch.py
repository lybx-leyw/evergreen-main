#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大校历 数据源适配壳（真实抓取 · 公开免登录源）。

数据源：浙江大学官网「学术日历」结构化页面（苏迪/Drupal CMS，服务端渲染，UTF-8）。
  https://www.intl.zju.edu.cn/zh-hans/academics/calendar

页面含当前学年两个学期（秋冬学期 + 春夏学期）的全部校历事件，结构稳定可解析：
  <li role="tab" aria-controls="quicktabs-tabpage-academic_calendar_new-0" ...>
    <div class="cal-title">2026-2027</div>
    <div class="cal-text">秋冬学期</div>
  </li>
  <div id="quicktabs-tabpage-academic_calendar_new-0" ...>
    <div class="cal-date">2026-09-10 ~ 2026-09-10</div>
    <div class="cal-event">研究生新生报到注册</div>
  </div>

范围说明（诚实声明）：本源为浙江大学官网（intl.zju.edu.cn）发布的结构化学术日历，
事件与全校校历一致（报到注册、开学、放假调休、考试周、运动会、校庆日等）。主校区
校历（ugrs.zju.edu.cn「浙江大学2026—2027学年校历」）以图片形式发布、不可机器解析，
故采用官网结构化版本。输出带 `source` / `scope` 字段说明此边界。历史学年为 PDF
附件（不可解析），本源仅覆盖当前学年，学年切换由站点更新自动反映。

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

SITE_NAME = "浙江大学学术日历"
SITE_HOST = "www.intl.zju.edu.cn"
CALENDAR_URL = "https://%s/zh-hans/academics/calendar" % SITE_HOST
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
              "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36 "
              "Evergreen/zju-calendar")
REQUEST_TIMEOUT = 15   # 单次请求超时（秒）

# TLS 校验证书链是否成功启用（True=系统证书库可加载；False=降级不校验，输出如实标注）
TLS_VERIFIED = True

# 学期标签页 id 前缀（tabpage-0 = 秋冬学期，tabpage-1 = 春夏学期）
_TABPAGE_ID = "quicktabs-tabpage-academic_calendar_new-%d"

# 学期标签头（aria-controls → 学年 + 学期名）
_TAB_LI_RE = re.compile(
    r'<li[^>]*aria-controls="quicktabs-tabpage-academic_calendar_new-(\d+)"[^>]*>(.*?)</li>',
    re.S)
_TAB_TITLE_RE = re.compile(r'<div class="cal-title">\s*([^<]+?)\s*</div>', re.S)
_TAB_TEXT_RE = re.compile(r'<div class="cal-text">\s*([^<]+?)\s*</div>', re.S)

# 单条校历事件：日期区间 + 事件名（`~` 为日期分隔符，允许任意空白）
_EVENT_RE = re.compile(
    r'<div class="cal-date">\s*(\d{4}-\d{2}-\d{2})\s*~\s*(\d{4}-\d{2}-\d{2})'
    r'\s*</div>\s*<div class="cal-event">([^<]+)</div>', re.S)


# ═══════════════════════════════════════════════════════════════════
# 配置读取（平台模式：GREENIX_CONFIG_PATH 文件 → ConfigHttpServer → 环境变量）
# 本源为公开免登录数据源，无需凭据；保留 _get_config 以兼容平台传参约定
# （--greenix-config）与后续可能的可选旋钮。
# ═══════════════════════════════════════════════════════════════════

def _get_config(key):
    """三级降级读取平台配置，全部缺失返回 None（本源无必填凭据）。"""
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


# ═══════════════════════════════════════════════════════════════════
# 抓取与解析（纯标准库）
# ═══════════════════════════════════════════════════════════════════

def _ssl_context():
    """构建 HTTPS 上下文：优先系统证书校验；本地证书库损坏时降级为不校验。

    已知问题：个别 Python 发行版（如部分 Conda 3.10 + 新版 OpenSSL）在加载
    Windows 证书存储时抛 `[ASN1: NOT_ENOUGH_DATA]`（本地证书库某条目不可解析），
    与目标站点无关。此处捕获该构建期异常，降级为 CERT_NONE（仅关闭证书链校验，
    仍强制 HTTPS），并在输出 `tls_verified: false` 如实标注（见 fetch_calendar）。
    """
    global TLS_VERIFIED
    try:
        ctx = ssl.create_default_context()
        TLS_VERIFIED = True
        return ctx
    except ssl.SSLError:
        TLS_VERIFIED = False
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx


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


def _parse_semester_tabs(html_text):
    """解析学期标签头：tab 序号 → (学年, 学期名)。"""
    tabs = {}
    for m in _TAB_LI_RE.finditer(html_text):
        idx = m.group(1)
        inner = m.group(2)
        tm = _TAB_TITLE_RE.search(inner)
        sm = _TAB_TEXT_RE.search(inner)
        tabs[idx] = {
            'year': _html.unescape(tm.group(1)).strip() if tm else '',
            'name': _html.unescape(sm.group(1)).strip() if sm else '',
        }
    return tabs


def _parse_semester_events(html_text, tab_index):
    """从某个 tabpage 段落提取校历事件列表（start/end/event）。"""
    marker = _TABPAGE_ID % tab_index
    start = html_text.find('id="%s"' % marker)
    if start < 0:
        return []
    end = html_text.find('id="%s"' % (_TABPAGE_ID % (tab_index + 1)), start)
    if end < 0:
        end = len(html_text)
    segment = html_text[start:end]
    events = []
    for m in _EVENT_RE.finditer(segment):
        events.append({
            'start': m.group(1),
            'end': m.group(2),
            'event': _html.unescape(m.group(3)).strip(),
        })
    return events


def fetch_calendar():
    """抓取当前学年校历 → (学年, 学期列表, 展平 items)。"""
    html_text = _fetch_page(CALENDAR_URL)
    tabs = _parse_semester_tabs(html_text)
    if not tabs:
        raise RuntimeError('未解析到学期标签（站点结构可能已变化）')

    academic_year = ''
    semesters = []
    items = []
    for idx in sorted(tabs.keys(), key=int):
        tab = tabs[idx]
        events = _parse_semester_events(html_text, int(idx))
        if not events:
            continue
        if not academic_year and tab['year']:
            academic_year = tab['year']
        semesters.append({
            'semester': tab['name'] or '第%s学期' % idx,
            'academic_year': tab['year'],
            'events': events,
        })
        for ev in events:
            items.append({
                'start': ev['start'],
                'end': ev['end'],
                'event': ev['event'],
                'semester': tab['name'],
            })
    if not items:
        raise RuntimeError('未解析到任何校历事件（站点结构可能已变化）')
    # 按开始日期升序（学期内站点顺序即时间序，此处做防御性排序）
    items.sort(key=lambda x: (x['start'], x['end']))
    return academic_year, semesters, items


def _friendly_error(exc):
    """把异常收敛为人类可读的中文错误信息。"""
    if isinstance(exc, urllib.error.HTTPError):
        return '浙大校历源返回 HTTP %s（%s）：%s' % (exc.code, exc.reason, exc.url)
    if isinstance(exc, urllib.error.URLError):
        reason = getattr(exc, 'reason', exc)
        return '无法连接浙大校历源（%s）：%s（需公网访问，校园网/VPN 不影响）' % (SITE_HOST, reason)
    return str(exc) or exc.__class__.__name__


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
    type_arg = args.get('--type') or 'zju_calendar'
    # 兼容平台传参：--greenix-config <cfg> 与 --project-root <root> 仅用于
    # 配置定位（_get_config 内已覆盖），这里接受即可。
    if args.get('--greenix-config'):
        os.environ.setdefault('GREENIX_CONFIG_PATH', args['--greenix-config'])
    if args.get('--project-root'):
        os.environ.setdefault('PROJECT_ROOT', args['--project-root'])
    try:
        if type_arg != 'zju_calendar':
            raise ValueError('未知数据源类型：%s（本插件仅支持 zju_calendar）' % type_arg)
        academic_year, semesters, items = fetch_calendar()
        result = {
            'type': type_arg,
            'source': SITE_NAME,
            'source_url': CALENDAR_URL,
            'academic_year': academic_year,
            'updated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'tls_verified': TLS_VERIFIED,
            'scope': '浙江大学官网发布的结构化学术日历（与全校校历一致）；主校区校历页为图片版，' 
                     '历史学年为 PDF，本源覆盖当前学年',
            'total': len(items),
            'semesters': semesters,
            'items': items,
        }
        sys.stdout.write(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        # 契约：错误走 stdout 的 {"error": ...} + 非零退出码，绝不输出堆栈污染 stdout
        sys.stdout.write(json.dumps({'error': _friendly_error(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == '__main__':
    main()
