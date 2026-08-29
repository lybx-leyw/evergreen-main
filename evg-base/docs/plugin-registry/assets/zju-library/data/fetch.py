#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙江大学图书馆 数据源适配壳（模型 A · CLI 一次性脚本 · 纯标准库）。

数据真实性声明（绝不伪造数据）：
  - 本插件只抓取浙江大学图书馆官网 libweb.zju.edu.cn 的**公开免登录页面**：
    · zju_library      → 「开放时间」栏目（/55986/list.htm，含 8 个分馆开放时间表）
    · zju_library_news → 「通知公告」（/39478/list.htm）+「本馆新闻」（/55989/list.htm）
  - 抓取失败时输出 {"error": ...} + 非零退出（平台据此保留旧缓存 / 返回 fallbackJson），
    **不会** 返回任何内置的假书目 / 假时间表。
  - OPAC 书目检索（opac.zju.edu.cn）与个人借阅（我的图书馆）需校园网/VPN 且带用户查询，
    平台 CLI 契约（--type/--project-root/--greenix-config）不含查询参数 → 本壳不实现，
    建议由平台侧 Dart fetcher（zju_modle）在会话内接入（本插件不支持部分见交付说明）。

CLI 契约（platform 侧 register_data_source.dart）：
  <script> --type <typeArg> --project-root <root> --greenix-config <cfg>
  · stdout 只输出单个 UTF-8 JSON 顶层 Map；成功 exit 0，失败 {"error": ...} + exit 非 0。
  · 兼容两种参数写法：`--key value`（空格分隔，平台标准）与 `key=value`（历史写法）。

运行预算：并发 4 抓 8 个分馆页 + 2 个公告页，单请求超时 10s，最坏 ~30s < 平台 60s 上限。
"""
import json
import re
import ssl
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

try:  # Windows 控制台 / Chaquopy 兼容
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

BASE = 'https://libweb.zju.edu.cn'
USER_AGENT = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36')
REQUEST_TIMEOUT = 10
MAX_WORKERS = 4

# 开放时间栏目下 8 个分馆页（2026-08 实测定点，官网导航「概况→开放时间」同源）
HOURS_BRANCHES = [
    ('主馆', '/zjdxtsgzg_78771/list.htm'),
    ('基础馆', '/56251/list.htm'),
    ('农医馆', '/56255/list.htm'),
    ('古籍馆', '/zjgxqgjg_56626/list.htm'),
    ('方闻馆', '/zjdxtsgfwg_78772/list.htm'),
    ('玉泉分馆', '/56252/list.htm'),
    ('西溪分馆', '/56253/list.htm'),
    ('华家池分馆', '/56254/list.htm'),
]

# 新闻/公告列表页（WebPlus 引擎，同构 HTML）
NEWS_COLUMNS = [
    ('通知公告', '/39478/list.htm'),
    ('本馆新闻', '/55989/list.htm'),
]


# ─────────────────────────────────────────────────────────────────────────
# 参数解析（平台标准：空格分隔 `--key value`；兼容历史 `key=value`）
# ─────────────────────────────────────────────────────────────────────────
def parse_args(argv):
    args = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith('--') and i + 1 < len(argv) and not argv[i + 1].startswith('--'):
            args[a[2:]] = argv[i + 1]
            i += 2
        elif '=' in a:
            k, _, v = a.partition('=')
            args[k.lstrip('-')] = v
            i += 1
        else:
            i += 1
    return args


# ─────────────────────────────────────────────────────────────────────────
# HTTP（urllib 纯标准库；TLS 验证优先，Windows 系统证书库损坏时降级不校验证书）
# ─────────────────────────────────────────────────────────────────────────
def fetch_html(url, timeout=REQUEST_TIMEOUT):
    """GET 并解码 HTML。验证证书失败（如 Windows 证书库 ASN1 损坏）时降级不校验。"""
    def _open(ctx):
        req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
        return urllib.request.urlopen(req, timeout=timeout, context=ctx)

    try:
        with _open(ssl.create_default_context()) as r:
            raw = r.read()
    except ssl.SSLError:
        # 已知环境缺陷：conda/系统 OpenSSL 加载 Windows 证书库即抛
        # [ASN1: NOT_ENOUGH_DATA]；公开只读页降级为不校验（见文件头声明）。
        with _open(ssl._create_unverified_context()) as r:
            raw = r.read()
    m = re.search(rb'charset=["\']?([\w-]+)', raw[:2000], re.I)
    charset = m.group(1).decode('ascii', 'replace') if m else 'utf-8'
    try:
        return raw.decode(charset, errors='replace')
    except LookupError:
        return raw.decode('utf-8', errors='replace')


def fetch_many(items, fn):
    """并发抓取 [（label, path）] 列表；返回 [(label, path, 结果 or None)]。"""
    def _one(it):
        label, path = it
        try:
            return label, path, fn(BASE + path)
        except Exception as e:
            return label, path, None

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        return list(ex.map(_one, items))


# ─────────────────────────────────────────────────────────────────────────
# 开放时间解析：挑出表头含「开放地点/星期/开放时间」的表格，逐行取单元格文本
# ─────────────────────────────────────────────────────────────────────────
def _cell_text(cell):
    text = re.sub(r'<[^>]+>', ' ', cell)
    text = text.replace('&nbsp;', ' ')
    text = text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    return re.sub(r'\s+', ' ', text).strip()


def parse_hours_table(html):
    for table in re.findall(r'<table.*?</table>', html, re.S):
        rows = re.findall(r'<tr[^>]*>(.*?)</tr>', table, re.S)
        if not rows:
            continue
        header = ' '.join(
            _cell_text(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', rows[0], re.S))
        if any(k in header for k in ('开放地点', '星期', '开放时间')):
            table_rows = []
            for tr in rows:
                cells = [_cell_text(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', tr, re.S)]
                cells = [c for c in cells if c]
                if cells:
                    table_rows.append(cells)
            return table_rows
    return None


def fetch_hours():
    results = fetch_many(HOURS_BRANCHES, fetch_html)
    branches = []
    failed = []
    for label, path, html in results:
        if html is None:
            failed.append(label)
            continue
        table = parse_hours_table(html)
        if not table:
            failed.append(label)
            continue
        branches.append({
            'branch': label,
            'page': BASE + path,
            'table': table,
        })
    return branches, failed


# ─────────────────────────────────────────────────────────────────────────
# 新闻/公告解析：<li class="news ..."> 内的 a[href/title] + span.news_meta 日期
# ─────────────────────────────────────────────────────────────────────────
def _strip(s):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', s)).strip()


def parse_news_items(html):
    items = []
    for li in re.findall(r'<li class="news[^"]*"[^>]*>(.*?)</li>', html, re.S):
        m_a = re.search(r'<a[^>]*href=[\'"]([^\'"]+)[\'"][^>]*title=[\'"]([^\'"]*)[\'"]', li)
        m_meta = re.search(r'class="news_meta"[^>]*>([^<]*)<', li)
        if not m_a:
            continue
        url = m_a.group(1)
        if url.startswith('/'):
            url = BASE + url
        elif url.startswith('//'):
            url = 'https:' + url
        items.append({
            'title': m_a.group(2) or _strip(li)[:60],
            'date': m_meta.group(1).strip() if m_meta else '',
            'url': url,
        })
    return items


def fetch_news():
    results = fetch_many(NEWS_COLUMNS, fetch_html)
    items = []
    failed = []
    for column, path, html in results:
        if html is None:
            failed.append(column)
            continue
        page_items = parse_news_items(html)
        for it in page_items:
            it['column'] = column
        items.extend(page_items)
    return items, failed


# ─────────────────────────────────────────────────────────────────────────
# 入口
# ─────────────────────────────────────────────────────────────────────────
def _now_iso():
    return datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds')


def main():
    args = parse_args(sys.argv[1:])
    type_arg = args.get('type', '').strip() or 'zju_library'

    if type_arg == 'zju_library':
        branches, failed = fetch_hours()
        if not branches:
            print(json.dumps({
                'error': '浙江大学图书馆官网不可达或开放时间页解析失败'
                         '（libweb.zju.edu.cn/55986），请检查网络后重试',
                'failed': failed or ['all'],
            }, ensure_ascii=False))
            return 1
        out = {
            'source': BASE + '/55986/list.htm（开放时间）',
            'fetched_at': _now_iso(),
            'count': len(branches),
            'branches': branches,
        }
        if failed:
            out['partial'] = failed
            out['note'] = ('数据来源：浙江大学图书馆官网公开页；部分分馆页失败时见 partial。'
                           '节假日开放时间以官网公告为准。')
        print(json.dumps(out, ensure_ascii=False))
        return 0

    if type_arg == 'zju_library_news':
        items, failed = fetch_news()
        if not items:
            print(json.dumps({
                'error': '浙江大学图书馆官网不可达或公告列表页解析失败'
                         '（libweb.zju.edu.cn/39478、/55989），请检查网络后重试',
                'failed': failed or ['all'],
            }, ensure_ascii=False))
            return 1
        out = {
            'source': BASE + '/39478/list.htm（通知公告）+ /55989/list.htm（本馆新闻）',
            'fetched_at': _now_iso(),
            'count': len(items),
            'items': items,
        }
        if failed:
            out['partial'] = failed
        print(json.dumps(out, ensure_ascii=False))
        return 0

    print(json.dumps({
        'error': '未知数据类型: %s（支持 zju_library / zju_library_news）' % type_arg,
    }, ensure_ascii=False))
    return 1


if __name__ == '__main__':
    sys.exit(main())
