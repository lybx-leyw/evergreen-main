#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GitHub Trending 数据源 — 抓取 github.com/trending 页面并解析为结构化 JSON。

Evergreen 数据源 CLI 契约（模型 A）：
  - 用法：python fetch.py --type <typeArg> [--since daily|weekly|monthly]
  - 平台调用：--type <typeArg> --project-root <root> --greenix-config <cfg>
    （--project-root / --greenix-config 会被解析但忽略）
  - stdout 只输出单个 JSON 对象（顶层 Map），UTF-8 编码；
  - 失败时 stdout 输出 {"error": "..."} 且 exit code 非 0
    （平台据此保留旧缓存 / 走 manifest fallbackJson 静态兜底）。

since 周期解析（优先级从高到低）：
  1. 显式参数：--since weekly / --since=weekly / since=weekly；
  2. typeArg 后缀推断：github_trending_weekly → weekly，github_trending_monthly → monthly；
  3. 默认 daily。
  平台只传 --type，因此「后缀推断」是在应用内切换日/周/月榜单的唯一入口。

解析健壮性：
  - 以 <article class="Box-row"> 为条目单元逐条解析，描述 / 语言 / star / fork /
    周期增量与仓库名天然对齐，单条缺字段不失败、不连坐其它条目；
  - 页面结构变化（无 <article> 包裹）时回退到旧版 <h2> 定位法；
  - 全部字段解析失败都不抛异常，条目以 null/空串占位；
  - 页面拉到但零条目可解析 → 返回 parse_failed 错误（诚实降级，不伪造空成功）。

条目字段：
  repo / owner / name / url    仓库标识（repo = owner/name 全名）
  description                  描述（HTML 净化，最长 160 字符，缺省 ""）
  language                     主要语言（缺省 null）
  stars / forks                总 star / fork 数（整数，缺省 null）
  stars_today                  榜单周期内 star 增量：daily=今日 / weekly=本周 /
                               monthly=本月（整数，缺省 null）
  stars_delta_text             页面原文增量文案，如 "4,562 stars today"（缺省 null）

纯 Python 标准库（urllib / re / html / datetime），Windows / macOS / Linux / Android 通用。
"""
import sys
import json
import re
import html as html_mod
import socket
import datetime
import urllib.request
import urllib.error

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass  # 非标准环境（如 Chaquopy）无 reconfigure 时保持默认编码

SOURCE_URL = "https://github.com/trending"
USER_AGENT = "Mozilla/5.0 (compatible; evergreen-data-source/2.0)"
REQUEST_TIMEOUT = 15
MAX_ITEMS = 25
DEFAULT_SINCE = "daily"
VALID_SINCE = ("daily", "weekly", "monthly")

# ── 正则（全部容错：大小写不敏感、单双引号兼容、属性顺序无关）──────────────────
_RE_ARTICLE = re.compile(r"<article\b[^>]*>(.*?)</article>", re.S | re.I)
_RE_H2 = re.compile(r"<h2\b[^>]*>(.*?)</h2>", re.S | re.I)
# 仓库全名链接：href="/owner/repo" 带前导斜杠，恰好两段，以闭合引号锚定，
# 避免误吞 /owner/repo/stargazers 等子路径
_RE_HREF_REPO = re.compile(r'href=["\']/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)["\']')
_RE_DESC = re.compile(
    r'<p\b[^>]*class=["\'][^"\']*(?:col-9|color-fg-muted)[^"\']*["\'][^>]*>(.*?)</p>',
    re.S | re.I,
)
_RE_LANG = re.compile(
    r'<span[^>]*itemprop=["\']programmingLanguage["\'][^>]*>(.*?)</span>', re.S | re.I
)
_RE_STARGZERS = re.compile(
    r'<a\b[^>]*href=["\'][^"\']*/stargazers["\'][^>]*>(.*?)</a>', re.S | re.I
)
_RE_FORKS = re.compile(
    r'<a\b[^>]*href=["\'][^"\']*/forks["\'][^>]*>(.*?)</a>', re.S | re.I
)
_RE_DELTA = re.compile(
    r"([\d,]+(?:\.\d+)?[kKmM]?)\s*stars?\s+(today|this\s+week|this\s+month)", re.I
)
_RE_B = re.compile(r"<b[^>]*>([^<]*)</b>", re.I)
_RE_NUMBER = re.compile(r"[\d,]+(?:\.\d+)?[kKmM]?")
_RE_SVG = re.compile(r"<svg\b.*?</svg>", re.S | re.I)
_RE_TAG = re.compile(r"<[^>]+>")
_RE_WS = re.compile(r"\s+")

_SPACED_KEYS = ("type", "since", "project-root", "greenix-config")


# ── 参数与周期 ─────────────────────────────────────────────────────────────────
def parse_args(argv):
    """解析命令行：支持 --k=v、--k v、k=v、k v 四种形态。

    平台注入的 --project-root / --greenix-config 会被解析但随后忽略。
    """
    args = {}
    i, n = 0, len(argv)
    while i < n:
        token = argv[i]
        if token.startswith("--"):
            token = token[2:]
        if "=" in token:
            k, _, v = token.partition("=")
            args[k] = v
        elif token in _SPACED_KEYS and i + 1 < n:
            args[token] = argv[i + 1]
            i += 1
        i += 1
    return args


def resolve_since(type_arg, explicit=None):
    """确定 since 周期：显式参数 > typeArg 后缀推断 > 默认 daily。

    返回 (since, warning)；warning 非 None 表示发生了回退。
    """
    if explicit:
        s = str(explicit).strip().lower()
        if s in VALID_SINCE:
            return s, None
        return DEFAULT_SINCE, "未知 since %r，回退 %s" % (explicit, DEFAULT_SINCE)
    m = re.search(r"_(daily|weekly|monthly)$", type_arg or "")
    if m:
        return m.group(1), None
    return DEFAULT_SINCE, None


# ── 数值与文本净化 ────────────────────────────────────────────────────────────
def parse_number(raw):
    """数值归一：'28,795'→28795、'12.3k'→12300、'1.2m'→1200000、无法解析→None。"""
    if raw is None:
        return None
    s = str(raw).strip().replace(",", "").lower()
    if not s:
        return None
    mult = 1
    if s.endswith("k"):
        mult, s = 1000, s[:-1]
    elif s.endswith("m"):
        mult, s = 1000000, s[:-1]
    try:
        f = float(s)
    except ValueError:
        return None
    return int(f * mult)


def first_number(fragment):
    """取 HTML 片段中第一个数值：优先 <b> 标签，其次裸数字；先剔除 svg 避免路径坐标噪声。"""
    if not fragment:
        return None
    text = _RE_SVG.sub(" ", fragment)
    for m in _RE_B.finditer(text):
        v = parse_number(m.group(1))
        if v is not None:
            return v
    for m in _RE_NUMBER.finditer(text):
        v = parse_number(m.group(0))
        if v is not None:
            return v
    return None


def strip_html(fragment):
    """去标签 + 反转义 HTML 实体 + 折叠空白。"""
    text = _RE_TAG.sub("", fragment)
    text = html_mod.unescape(text)
    return _RE_WS.sub(" ", text).strip()


# ── 解析 ──────────────────────────────────────────────────────────────────────
def parse_repo(fragment, full_name):
    """从单个条目 HTML 片段解析仓库信息。任何字段缺失都容错，不抛异常。"""
    owner, _, name = full_name.partition("/")
    item = {
        "repo": full_name,
        "owner": owner,
        "name": name,
        "url": "https://github.com/" + full_name,
        "description": "",
        "language": None,
        "stars": None,
        "forks": None,
        "stars_today": None,
        "stars_delta_text": None,
    }
    dm = _RE_DESC.search(fragment)
    if dm:
        item["description"] = strip_html(dm.group(1))[:160]
    lm = _RE_LANG.search(fragment)
    if lm:
        lang = strip_html(lm.group(1))
        if lang:
            item["language"] = lang
    sm = _RE_STARGZERS.search(fragment)
    if sm:
        v = first_number(sm.group(1))
        if v is not None:
            item["stars"] = v
    fm = _RE_FORKS.search(fragment)
    if fm:
        v = first_number(fm.group(1))
        if v is not None:
            item["forks"] = v
    dlt = _RE_DELTA.search(fragment)
    if dlt:
        item["stars_today"] = parse_number(dlt.group(1))
        item["stars_delta_text"] = "%s stars %s" % (dlt.group(1), dlt.group(2))
    return item


def parse_trending(html_text):
    """以 <article> 条目为单元解析；无 article 可解析时回退旧版 <h2> 定位法。"""
    repos = []
    for block in _RE_ARTICLE.findall(html_text):
        h2 = _RE_H2.search(block)
        if not h2:
            continue
        href = _RE_HREF_REPO.search(h2.group(1))
        if not href:
            continue
        full = href.group(1)
        if full.count("/") != 1:
            continue
        repos.append(parse_repo(block, full))
    if not repos:
        repos = parse_legacy(html_text)
    # 去重（防御：非贪婪 <article> 匹配在异常结构下可能产生重复）
    seen, out = set(), []
    for r in repos:
        if r["repo"] in seen:
            continue
        seen.add(r["repo"])
        out.append(r)
    return out


def parse_legacy(html_text):
    """旧版结构（无 <article> 包裹）的容错解析：h2 定位仓库 + 截取后续区域取字段。"""
    repos = []
    for m in _RE_H2.finditer(html_text):
        href = _RE_HREF_REPO.search(m.group(1))
        if not href:
            continue
        full = href.group(1)
        if full.count("/") != 1:
            continue
        region = html_text[m.end():m.end() + 4000]
        nxt = region.find("<h2")
        if nxt > 0:
            region = region[:nxt]
        repos.append(parse_repo("<h2>" + m.group(1) + "</h2>" + region, full))
    return repos


# ── 抓取入口 ──────────────────────────────────────────────────────────────────
def fetch_data(type_arg, explicit_since=None):
    """抓取并解析 github.com/trending。返回 (结果 dict, 退出码)。

    成功：exit 0；失败：stdout 含 error key + exit 非 0（平台保留旧缓存 / 静态兜底）。
    任何异常都收敛为错误 JSON，不向 stdout 输出堆栈。
    """
    type_arg = (type_arg or "github_trending").strip()
    since, warning = resolve_since(type_arg, explicit_since)
    url = "%s?since=%s" % (SOURCE_URL, since)
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "text/html,application/xhtml+xml",
            },
        )
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            charset = resp.headers.get_content_charset() or "utf-8"
            html_text = resp.read().decode(charset, errors="replace")
    except urllib.error.HTTPError as e:
        return (
            {
                "type": type_arg,
                "error": "http_error",
                "status": e.code,
                "detail": "HTTP %d %s" % (e.code, e.reason),
            },
            1,
        )
    except (TimeoutError, socket.timeout):
        return (
            {
                "type": type_arg,
                "error": "timeout",
                "detail": "请求超时（%ds）" % REQUEST_TIMEOUT,
            },
            1,
        )
    except urllib.error.URLError as e:
        reason = getattr(e, "reason", e)
        if isinstance(reason, (TimeoutError, socket.timeout)):
            return (
                {
                    "type": type_arg,
                    "error": "timeout",
                    "detail": "请求超时（%ds）" % REQUEST_TIMEOUT,
                },
                1,
            )
        return (
            {
                "type": type_arg,
                "error": "network_unavailable",
                "detail": "无法连接 %s: %s" % (SOURCE_URL, reason),
            },
            1,
        )
    except Exception as e:  # 兜底：任何异常收敛为错误 JSON
        return ({"type": type_arg, "error": "network_unavailable", "detail": str(e)}, 1)

    repos = parse_trending(html_text)
    if not repos:
        return (
            {
                "type": type_arg,
                "error": "parse_failed",
                "detail": "未能从页面解析出任何仓库条目（页面结构可能已变化）",
            },
            1,
        )

    result = {
        "type": type_arg,
        "since": since,
        "count": len(repos),
        "items": repos[:MAX_ITEMS],
        "source": url,
        "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"
        ),
    }
    if warning:
        result["warning"] = warning
    return result, 0


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    result, code = fetch_data(args.get("type"), args.get("since"))
    print(json.dumps(result, ensure_ascii=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
