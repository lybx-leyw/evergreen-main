#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""番剧更新 数据源适配壳 —— 从 Bangumi 公开日历 API 真实抓取本周番剧（纯标准库）。

数据源 URL : https://api.bgm.tv/calendar
            Bangumi 公开日历接口，无需鉴权；返回 JSON 数组（7 个星期分组 × items）。
更新策略   : 每次调用实时抓取，平台按 manifest 声明的 ttl=6h 缓存；数据全部来自
            上游 API 实时响应，脚本内不内嵌任何硬编码表、不编造数据。抓取失败时
            优雅降级：stdout 输出含 error key 的 JSON 并以非零码退出（不崩溃、
            不打印堆栈、不污染 stdout）。

CLI 契约（data-source 模型 A，与 register_data_source.dart 一致）:
    python fetch.py --type <typeArg> --project-root <projectRoot> --greenix-config <cfg>
    兼容 "--key value" / "--key=value" / "key=value" 三种拼写；
    --project-root / --greenix-config 本数据源为公开接口无需凭证，仅接受兼容。
    stdout 顶层必须为 JSON Map（成功含 type/items，失败含 type/error）。

输出结构（成功）:
    {
      "type": "anime_calendar",
      "source": "https://api.bgm.tv/calendar",
      "fetched_at": "2026-08-25T09:30:00Z",   # UTC；平台 diff 引擎视为易变字段
      "total": 287,
      "items": [ { "id", "name", "name_cn", "weekday", "weekday_id",
                   "air_date", "air_weekday", "url", "summary"?, "score"? } ]
    }
    排序确定（air_date, id），保证 data_diff 变更事件稳定不误报。

错误分级（error_code 字段区分，全部携带人类可读 error）:
    timeout        连接/读取超时
    network_error  DNS 解析失败 / 连接被拒等网络层错误
    http_error     HTTP 状态非 200（含 http_status）
    parse_error    响应体 JSON 解析失败或结构不符合预期
    ssl_error      TLS 证书/握手失败（含证书校验回退后仍失败）
    unknown        其它未预期异常（兜底，绝不崩溃）

调试开关（环境变量，可选）:
    BGM_CALENDAR_URL  覆盖数据源 URL（本地联调/测试用）
    BGM_TIMEOUT       覆盖超时秒数（默认 10）

TLS 说明: 默认使用系统证书库校验证书；当证书库不可用/校验失败时（如 Windows
    证书存储损坏导致 create_default_context 抛错），自动回退为不校验 TLS 重试一次，
    并在成功结果中显式标记 "tls_verified": false 保持透明（公开只读接口、无凭据，
    回退风险可控）。
"""
import json
import os
import socket
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8")

CALENDAR_URL = "https://api.bgm.tv/calendar"
USER_AGENT = "evergreen-anime-calendar/1.0 (data-source plugin)"
TIMEOUT_SECONDS = 10
MAX_SUMMARY_CHARS = 300

# Bangumi calendar 的 weekday.id：1=周一 … 7=周日
WEEKDAY_CN = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


class FetchError(Exception):
    """带错误码的抓取失败。error_code 供平台/消费方区分失败类型。"""

    def __init__(self, code, message, http_status=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status


def _utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _https(url):
    """上游返回 http://bgm.tv/...，统一升级为 https。"""
    if isinstance(url, str) and url.startswith("http://"):
        return "https://" + url[len("http://"):]
    return url


def _unverified_context():
    """显式构造不校验 TLS 的上下文（避免使用已弃用的 _create_unverified_context）。"""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def _http_get(url, timeout, context=None):
    """GET 数据源；返回 (status, raw_bytes)。4xx/5xx 由 urllib 抛 HTTPError。"""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout, context=context) as resp:
        return resp.status, resp.read()


def _clean_item(it, group_weekday_id):
    """把 Bangumi subject 精简为日历条目；未知/缺失字段静默置空（平台铁律）。"""
    if not isinstance(it, dict):
        return None
    weekday_id = it.get("air_weekday")
    if not isinstance(weekday_id, int) or not (1 <= weekday_id <= 7):
        weekday_id = group_weekday_id
    item = {
        "id": it.get("id"),
        "name": it.get("name"),
        "name_cn": it.get("name_cn"),
        "url": _https(it.get("url")),
        "weekday": WEEKDAY_CN[weekday_id - 1]
        if isinstance(weekday_id, int) and 1 <= weekday_id <= 7 else None,
        "weekday_id": weekday_id,
        "air_date": it.get("air_date"),
    }
    summary = (it.get("summary") or "").strip()
    if summary:
        if len(summary) > MAX_SUMMARY_CHARS:
            item["summary"] = summary[:MAX_SUMMARY_CHARS] + "…"
            item["summary_trimmed"] = True
        else:
            item["summary"] = summary
    rating = it.get("rating")
    if isinstance(rating, dict):
        score = rating.get("score")
        if isinstance(score, (int, float)) and score > 0:
            item["score"] = score
    return item


def _build_success(base, payload):
    if not isinstance(payload, list):
        raise FetchError(
            "parse_error",
            "响应结构异常：期望 7 个星期分组的 JSON 数组，实际为 %s" % type(payload).__name__,
        )
    items = []
    for group in payload:
        if not isinstance(group, dict):
            continue
        wd = group.get("weekday")
        group_weekday_id = wd.get("id") if isinstance(wd, dict) else None
        for raw in group.get("items") or []:
            item = _clean_item(raw, group_weekday_id)
            if item is not None:
                items.append(item)
    # 排序保证输出确定（data_diff 变更事件不误报）
    items.sort(key=lambda x: (x.get("air_date") or "", x.get("id") or 0))
    out = dict(base)
    out["total"] = len(items)
    out["items"] = items
    return out


def _build_error(base, err):
    out = dict(base)
    out["error"] = err.message
    out["error_code"] = err.code
    if err.http_status is not None:
        out["http_status"] = err.http_status
    return out


def _parse_timeout():
    try:
        t = float(os.environ.get("BGM_TIMEOUT") or TIMEOUT_SECONDS)
        return t if t > 0 else TIMEOUT_SECONDS
    except (TypeError, ValueError):
        return TIMEOUT_SECONDS


def fetch_data(type_arg):
    url = os.environ.get("BGM_CALENDAR_URL") or CALENDAR_URL
    timeout = _parse_timeout()
    base = {"type": type_arg, "source": url, "fetched_at": _utc_now()}
    verified = True
    try:
        try:
            status, raw = _http_get(url, timeout)
        except ssl.SSLError:
            # 系统证书库不可用（如 Windows 证书存储损坏）时退化为不校验 TLS 重试一次，
            # 并在结果中显式标记 tls_verified=false，保证透明可审计。
            status, raw = _http_get(url, timeout, context=_unverified_context())
            verified = False
        if status != 200:
            raise FetchError("http_error", "数据源返回 HTTP %d" % status, http_status=status)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise FetchError("parse_error", "响应不是合法 UTF-8 JSON：%s" % exc)
        result = _build_success(base, payload)
        if not verified:
            result["tls_verified"] = False
        return result
    except FetchError as exc:
        return _build_error(base, exc)
    except ssl.SSLError as exc:
        return _build_error(
            base, FetchError("ssl_error", "TLS/证书错误（含证书校验回退后仍失败）：%s" % exc))
    except urllib.error.HTTPError as exc:
        return _build_error(
            base, FetchError("http_error", "HTTP %d %s" % (exc.code, exc.reason),
                             http_status=exc.code))
    except (TimeoutError, socket.timeout):
        return _build_error(base, FetchError("timeout", "请求超时（%.0fs）" % timeout))
    except urllib.error.URLError as exc:
        reason = exc.reason if hasattr(exc, "reason") else exc
        if isinstance(reason, (TimeoutError, socket.timeout)):
            return _build_error(base, FetchError("timeout", "请求超时（%.0fs）" % timeout))
        return _build_error(base, FetchError("network_error", "网络错误：%s" % reason))
    except Exception as exc:  # noqa: BLE001 —— 兜底收敛，任何异常都不得让进程崩溃
        return _build_error(base, FetchError("unknown", "未预期错误：%s" % exc))


def parse_args(argv):
    """解析 CLI 参数，兼容 "--key value" / "--key=value" / "key=value" 三种拼写。"""
    opts = {}
    i, n = 0, len(argv)
    while i < n:
        tok = argv[i]
        if tok.startswith("--"):
            if "=" in tok:
                key, _, val = tok.partition("=")
                opts[key] = val
            else:
                key = tok
                val = argv[i + 1] if i + 1 < n else ""
                opts[key] = val
                i += 1
        elif "=" in tok:  # 兼容历史写法 type=anime_calendar
            key, _, val = tok.partition("=")
            opts["--" + key] = val
        i += 1
    return opts


def main(argv=None):
    args = parse_args(list(sys.argv[1:] if argv is None else argv))
    type_arg = args.get("--type") or "anime_calendar"
    result = fetch_data(type_arg)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
