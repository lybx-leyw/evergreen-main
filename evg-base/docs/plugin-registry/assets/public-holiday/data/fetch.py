#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""节假日 (public-holiday) 数据源适配壳 — 真实抓取 Nager.Date 公开节假日 API。

数据源: https://date.nager.at/api/v3/PublicHolidays/{year}/CN
        （Nager.Date，免费、无需 API key、返回 JSON；上游 MIT 许可）

主路径: 在线抓取指定年份的中国法定节假日，映射为统一 items 结构。
降级:   网络 / HTTP / 解析失败时，回退内嵌静态表（来源 holiday-cn，MIT，
        可能过期），输出标记 fallback=true + warning。
兜底:   内嵌表也无该年份数据时，输出 {"error": "..."} 且 exit code 非 0。

CLI 契约（Evergreen data-source）:
    python fetch.py --type <typeArg> [--year <YYYY>]
                    [--project-root <root>] [--greenix-config <cfg>]
    --type 必填；--year 可选（默认当前年份）；后两个参数平台可能传入，忽略即可。

输出: stdout 只输出纯 JSON（UTF-8、ensure_ascii=False）；日志/警告走 stderr。
    成功（exit 0）:
        {"type", "year", "country", "count", "items": [{"date","localName","name"}],
         "source", "fetchedAt", "fallback"?}
    失败（exit 非 0）: {"error": "人类可读信息"}

依赖: 纯 Python 标准库（urllib / json / datetime / sys），零第三方依赖。
"""

import json
import sys
import urllib.error
import urllib.request
from datetime import date, datetime

# ---------- 配置 ----------
NAGER_BASE_URL = "https://date.nager.at/api/v3/PublicHolidays/{year}/CN"
NAGER_SOURCE = "Nager.Date https://date.nager.at/api/v3/PublicHolidays/{year}/CN"
COUNTRY_CODE = "CN"
TIMEOUT_SECONDS = 10
USER_AGENT = "Evergreen-data-source/public-holiday/2.0 (+https://github.com/lybx-leyw/evg-plugins)"

# ---------- 内嵌降级表（holiday-cn，MIT；仅作离线兜底，可能过期） ----------
# 格式: 节日名 -> {start, end, workdays(调休上班日)}
_EMBEDDED = {
    "2025": {
        "元旦": {"start": "2025-01-01", "end": "2025-01-01", "workdays": []},
        "春节": {"start": "2025-01-28", "end": "2025-02-04", "workdays": ["2025-01-26", "2025-02-08"]},
        "清明节": {"start": "2025-04-04", "end": "2025-04-06", "workdays": []},
        "劳动节": {"start": "2025-05-01", "end": "2025-05-05", "workdays": ["2025-04-27"]},
        "端午节": {"start": "2025-05-31", "end": "2025-06-02", "workdays": []},
        "国庆节": {"start": "2025-10-01", "end": "2025-10-08", "workdays": ["2025-09-28", "2025-10-11"]},
    },
    "2026": {
        "元旦": {"start": "2026-01-01", "end": "2026-01-03", "workdays": []},
        "春节": {"start": "2026-02-15", "end": "2026-02-22", "workdays": ["2026-02-14", "2026-02-28"]},
        "清明节": {"start": "2026-04-04", "end": "2026-04-06", "workdays": []},
        "劳动节": {"start": "2026-05-01", "end": "2026-05-05", "workdays": ["2026-04-26", "2026-05-09"]},
        "端午节": {"start": "2026-06-19", "end": "2026-06-21", "workdays": []},
        "中秋节": {"start": "2026-09-25", "end": "2026-09-27", "workdays": []},
        "国庆节": {"start": "2026-10-01", "end": "2026-10-08", "workdays": ["2026-09-26", "2026-10-10"]},
    },
}
EMBEDDED_SOURCE = "embedded-fallback (holiday-cn, MIT; 可能过期)"

# ---------- 异常分类 ----------
class FetchError(Exception):
    """抓取失败基类。message 为人类可读信息，直接进 {"error": ...}。"""

class InvalidYearError(FetchError):
    """年份参数非法。"""

class NetworkError(FetchError):
    """网络层失败（DNS / 连接 / 超时 / HTTP 非 2xx）。"""

class DataError(FetchError):
    """响应内容非法（非 JSON / 结构不符）。"""


# ---------- 参数解析 ----------
def parse_args(argv):
    """解析命令行参数，兼容 '--key value' 与 '--key=value' 两种形式。

    返回 (type_arg, year_str)。平台可能额外传入 --project-root / --greenix-config，
    本插件无需凭证，直接忽略。
    """
    type_arg = None
    year_str = None
    i = 0
    while i < len(argv):
        token = argv[i]
        if token.startswith("--"):
            key, _, inline_val = token[2:].partition("=")
            if inline_val != "":
                val = inline_val
            elif i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                i += 1
                val = argv[i]
            else:
                val = None
            if key == "type":
                type_arg = val
            elif key == "year":
                year_str = val
            # --project-root / --greenix-config 忽略
        else:
            # 容忍旧式 'type=public_holiday' 的裸传参
            key, _, val = token.partition("=")
            if key == "type":
                type_arg = val
            elif key == "year":
                year_str = val
        i += 1
    return type_arg or "public_holiday", year_str


def resolve_year(year_str):
    """校验年份参数；缺省返回当前年份。非法年份抛 InvalidYearError。"""
    if year_str is None:
        return date.today().year
    value = year_str.strip()
    if not (value.isdigit() and len(value) == 4):
        raise InvalidYearError(
            "年份参数无效: %r（应为 4 位数字，如 2026）" % year_str)
    return int(value)


# ---------- 抓取 ----------
def fetch_from_nager(year):
    """从 Nager.Date 抓取指定年份中国节假日，返回 [(date, localName, name)]。

    失败时抛出 NetworkError / DataError，由上层决定降级。
    """
    url = NAGER_BASE_URL.format(year=year)
    request = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise NetworkError(
            "Nager.Date 返回 HTTP %d（%s），可能是不支持的年份" % (exc.code, url))
    except OSError as exc:
        # 涵盖 URLError / ssl.SSLError（如 Windows 证书库损坏）/ socket 超时
        reason = getattr(exc, "reason", None) or exc
        raise NetworkError("无法连接 Nager.Date（%s）：%s" % (url, reason))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise DataError("Nager.Date 响应不是有效 JSON：%s" % exc)

    if not isinstance(payload, list):
        raise DataError("Nager.Date 响应结构异常（期望数组，实际 %s）"
                        % type(payload).__name__)

    items = []
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        local_name = entry.get("localName")
        name = entry.get("name")
        if date_str and local_name and name:
            items.append({"date": date_str, "localName": local_name, "name": name})
    items.sort(key=lambda item: item["date"])
    return items


def embedded_fallback(year):
    """从内嵌静态表生成 items（展开为逐日条目）；无该年份数据返回 None。"""
    table = _EMBEDDED.get(str(year))
    if not table:
        return None
    items = []
    for name, info in table.items():
        start = date.fromisoformat(info["start"])
        end = date.fromisoformat(info["end"])
        for offset in range((end - start).days + 1):
            day = (start.toordinal() + offset)
            items.append({
                "date": date.fromordinal(day).isoformat(),
                "localName": name,
                "name": name,
            })
    items.sort(key=lambda item: item["date"])
    return items


def build_success(type_arg, year, country, items, source, fetched_at, warning=None):
    result = {
        "type": type_arg,
        "year": year,
        "country": country,
        "count": len(items),
        "items": items,
        "source": source,
        "fetchedAt": fetched_at,
    }
    if warning:
        result["fallback"] = True
        result["warning"] = warning
    return result


# ---------- 入口 ----------
def _emit(result):
    """以 UTF-8 纯 JSON 输出结果到 stdout。"""
    print(json.dumps(result, ensure_ascii=False))


def _fail(message):
    """输出结构化错误 JSON 并以非 0 退出。"""
    _emit({"error": message})
    sys.exit(1)


def _run(type_arg, year):
    """主路径：在线抓取并输出成功结果。失败抛 FetchError 交上层降级。"""
    try:
        items = fetch_from_nager(year)
    except FetchError as exc:
        # 原因写 stderr（stdout 保持纯 JSON）
        print("[fetch] 在线抓取失败: %s" % exc, file=sys.stderr)
        raise
    _emit(build_success(type_arg, year, COUNTRY_CODE, items,
                        NAGER_SOURCE.format(year=year),
                        datetime.now().isoformat(timespec="seconds")))


def main():
    # 确保 Windows 控制台输出 UTF-8（平台解析 stdout 依赖 UTF-8 JSON）
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:  # 极老 Python 无 reconfigure
        pass

    type_arg, year_str = parse_args(sys.argv[1:])
    try:
        year = resolve_year(year_str)
    except InvalidYearError as exc:
        _fail(str(exc))

    try:
        _run(type_arg, year)
        return
    except FetchError:
        # 降级：内嵌静态表（可能过期，标记 fallback）
        items = embedded_fallback(year)
        if items is not None:
            _emit(build_success(
                type_arg, year, COUNTRY_CODE, items, EMBEDDED_SOURCE,
                datetime.now().isoformat(timespec="seconds"),
                warning="在线节假日 API 不可达，已使用内嵌静态数据（可能过期）"))
            return
        # 兜底：内嵌表也无该年份 → 结构化错误
        _fail("暂不支持年份 %d：在线 API 不可达且无该年份内嵌数据" % year)
    except Exception as exc:  # 铁律兜底：任何异常都收敛为错误 JSON，不污染 stdout
        _fail("内部错误: %s" % exc)


if __name__ == "__main__":
    main()
