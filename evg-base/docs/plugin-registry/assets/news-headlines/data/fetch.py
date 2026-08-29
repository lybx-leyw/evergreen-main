#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""新闻头条 数据源适配壳（模型 A / CLI 一次性脚本，纯 Python 标准库，零第三方依赖）。

抓取多个公开中文新闻 RSS 源，解析为统一结构输出到 stdout（仅 JSON，日志走 stderr）。

数据源（按优先级降序，逐个尝试，全部失败才报错）：
  1. 中新网即时新闻  http://www.chinanews.com.cn/rss/scroll-news.xml
  2. 人民网时政      http://www.people.com.cn/rss/politics.xml
  3. 新华网时政      http://www.xinhuanet.com/politics/news_politics.xml
  4. BBC 中文(简)    https://feeds.bbci.co.uk/zhongwen/simp/rss.xml  （HTTPS 兜底源）

说明：
  - 前三个为国内官方媒体公开 RSS，经实测可达；BBC 中文为 HTTPS 源，在具备正常
    TLS 链路的机器上可作为国际源兜底（本机若 HTTPS 握手失败仅记录该源错误，不影响其余源）。
  - 新鲜度过滤：条目日期（pubDate 优先、链接 URL 中的日期兜底）超过 MAX_AGE_DAYS 的
    过期条目会被剔除，避免把陈旧内容当作"头条"返回。

CLI 契约（Evergreen data-source 模型 A）：
  python fetch.py --type <typeArg> --project-root <root> --greenix-config <cfg>
  - stdout 输出单个 JSON 对象（顶层 Map），UTF-8；
  - 成功：exit code 0，结构 {"type", "source", "sources", "count", "fetchedAt", "items"}，
    items: [{"title", "link", "published", "source"}, ...]；
  - 失败：stdout 输出 {"error": "...", "error_code": "...", "sources_tried": [...],
    "source_errors": {...}} 且 exit code 非 0（stdout 顶层含 error key，平台视为拉取失败）。

错误分类（error_code）：
  http_error          目标返回非 2xx（附带状态码）
  timeout             连接/读取超时
  network_unavailable DNS 失败 / 连接拒绝 / 网络不可达
  ssl_error           TLS 握手失败（如被代理/防火墙拦截）
  parse_error         RSS XML 解析失败
  empty               所有源可达但无可用的新鲜条目
  all_sources_failed  所有源均抓取失败
"""
import sys
import json
import re
import socket
import ssl
import http.client
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import urljoin
from xml.etree import ElementTree

try:
    sys.stdout.reconfigure(encoding="utf-8")  # py3.7+；低版本忽略
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, OSError):
    pass

# ── 数据源表：(key, 展示名, URL) ────────────────────────────────────────────
SOURCES = [
    ("chinanews", "中新网", "http://www.chinanews.com.cn/rss/scroll-news.xml"),
    ("people", "人民网", "http://www.people.com.cn/rss/politics.xml"),
    ("xinhua", "新华网", "http://www.xinhuanet.com/politics/news_politics.xml"),
    ("bbc_zhongwen", "BBC中文", "https://feeds.bbci.co.uk/zhongwen/simp/rss.xml"),
]

REQUEST_TIMEOUT = 10          # 单源超时（秒），4 源最坏约 40s < 平台 CLI 60s 超时
MAX_AGE_DAYS = 7              # 新鲜度窗口：超过该天数的条目剔除
MAX_ITEMS_PER_SOURCE = 20     # 单源最多取 20 条
MAX_ITEMS_TOTAL = 20          # 返回总量上限
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) evergreen-news-headlines/1.0"

# 链接 URL 中的日期兜底：如 /2022-12/14/、/2025/0605/、/2026/08-29/
_LINK_DATE_RE = re.compile(r"(20\d{2})[/-](\d{1,2})[/-](\d{1,2})")
_HTML_TAG_RE = re.compile(r"<[^>]+>")


def _classify_source_error(exc):
    """把抓取异常归类为 (error_code, 人类可读信息)。"""
    if isinstance(exc, urlerror.HTTPError):
        return "http_error", "HTTP %d %s" % (exc.code, exc.reason)
    if isinstance(exc, socket.timeout):
        return "timeout", "连接或读取超时"
    if isinstance(exc, urlerror.URLError):
        reason = exc.reason
        if isinstance(reason, socket.timeout):
            return "timeout", "连接或读取超时"
        if isinstance(reason, ssl.SSLError):
            return "ssl_error", "TLS 握手失败: %s" % str(reason)[:100]
        return "network_unavailable", str(reason)[:120]
    if isinstance(exc, (OSError, http.client.HTTPException)):
        # 连接拒绝/重置、DNS、代理失败等（URLError 为 OSError 子类，已在上面优先处理）
        return "network_unavailable", "%s: %s" % (type(exc).__name__, str(exc)[:120])
    return "unknown", "%s: %s" % (type(exc).__name__, str(exc)[:120])


def _parse_item_date(raw_pub, link):
    """解析条目日期：pubDate 优先（ISO8601 / RFC822 / 纯日期），其次链接 URL 中的日期。
    解析失败返回 None（日期未知，不参与新鲜度判断）。"""
    if raw_pub:
        s = raw_pub.strip()
        try:
            dt = datetime.fromisoformat(s)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            pass
        try:
            dt = parsedate_to_datetime(s)
            return dt.astimezone(timezone.utc)
        except (TypeError, ValueError):
            pass
    if link:
        m = _LINK_DATE_RE.search(link)
        if m:
            try:
                return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                tzinfo=timezone.utc)
            except ValueError:
                pass
    return None


def _is_fresh(dt, now):
    """日期已知时判定是否在新鲜度窗口内；日期未知视为新鲜（无法判定不误杀）。"""
    if dt is None:
        return True
    return dt >= now - timedelta(days=MAX_AGE_DAYS)


def _fetch_source(key, display, url, now):
    """抓取并解析单个 RSS 源。

    返回 (error_code_or_None, items)；items 为 [{title, link, published, source, _dt}]，
    _dt 为解析出的日期对象（排序用，不输出）。"""
    req = urlrequest.Request(url, headers={"User-Agent": USER_AGENT})
    with urlrequest.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
        body = resp.read().decode("utf-8", errors="replace")
    root = ElementTree.fromstring(body)  # 解析失败抛 ET.ParseError
    items = []
    for it in root.findall(".//item"):
        title = (it.findtext("title") or "").strip()
        raw_link = (it.findtext("link") or "").strip()
        raw_pub = (it.findtext("pubDate") or "").strip()
        if not title:
            continue
        link = urljoin(url, raw_link) if raw_link else ""
        dt = _parse_item_date(raw_pub, link)
        if not _is_fresh(dt, now):
            continue
        published = raw_pub
        if dt is not None:
            published = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        items.append({
            "title": _clean_text(title),
            "link": link,
            "published": published,
            "source": display,
            "_dt": dt,
        })
    items = items[:MAX_ITEMS_PER_SOURCE]
    return None, items


def _clean_text(s):
    """去除 HTML 标签与常见 XML 实体，得到纯文本。"""
    s = s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    s = s.replace("&quot;", '"').replace("&#39;", "'").replace("&apos;", "'")
    s = _HTML_TAG_RE.sub("", s)
    return re.sub(r"\s+", " ", s).strip()


def fetch_data(type_arg):
    """依次尝试所有源，聚合新鲜条目。永远返回 dict（成功或错误结构）。"""
    now = datetime.now(timezone.utc)
    seen_links = set()
    merged = []
    source_errors = {}
    contributing = []
    ok_sources = []

    for key, display, url in SOURCES:
        try:
            err, items = _fetch_source(key, display, url, now)
            if err is not None:
                source_errors[key] = {"error_code": err, "message": display + "抓取失败"}
                continue
            ok_sources.append(key)
            kept = 0
            for it in items:
                link = it["link"]
                dedupe_key = link or it["title"]
                if dedupe_key in seen_links:
                    continue
                seen_links.add(dedupe_key)
                merged.append(it)
                kept += 1
            if kept > 0:
                contributing.append(key)
        except Exception as exc:  # 单源失败不致命，记录后继续
            code, _msg = _classify_source_error(exc)
            source_errors[key] = {
                "error_code": code,
                "message": "%s: %s" % (display, str(exc)[:120]),
            }

    # 按发布时间倒序（日期未知的排最后，保持稳定）
    merged.sort(key=lambda it: (it["_dt"] is None, it["_dt"] or datetime.min),
                reverse=True)
    merged = merged[:MAX_ITEMS_TOTAL]
    for it in merged:
        it.pop("_dt", None)

    if merged:
        return {
            "type": type_arg,
            "source": contributing[0] if contributing else ok_sources[0],
            "sources": contributing,
            "count": len(merged),
            "fetchedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "items": merged,
        }

    # 全部失败 / 无可新鲜条目：错误结构
    if ok_sources:
        error_code, message = "empty", "所有新闻源可达，但 %d 天内无新鲜条目" % MAX_AGE_DAYS
    else:
        error_code, message = "all_sources_failed", "所有新闻源抓取失败（网络不可达或源异常）"
    return {
        "type": type_arg,
        "error": message,
        "error_code": error_code,
        "sources_tried": [s[0] for s in SOURCES],
        "source_errors": source_errors,
    }


def _parse_args(argv):
    """解析 CLI 参数：支持 `--key value`、`--key=value`、`key=value` 三种写法；
    未知参数（如 --project-root / --greenix-config）静默忽略。"""
    out = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("--"):
            body = arg[2:]
            if "=" in body:
                k, _, v = body.partition("=")
                out[k] = v
            elif i + 1 < len(argv):
                out[body] = argv[i + 1]
                i += 1
        elif "=" in arg:
            k, _, v = arg.partition("=")
            out[k.strip("-")] = v
        i += 1
    return out


def main(argv=None):
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    type_arg = args.get("type") or "news_headlines"
    result = fetch_data(type_arg)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if "error" not in result else 1


if __name__ == "__main__":
    sys.exit(main())
