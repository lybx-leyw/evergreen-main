#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""汇率数据源适配壳（exchange_rate）— 真实抓取公共免费汇率 API。

数据来源（均免费、无需 API key，纯 Python 标准库实现，零第三方依赖）：
  1. 主源 open.er-api.com（仅支持 base=USD，约每小时更新一次）：
     https://open.er-api.com/v6/latest/USD
  2. 备用源 api.frankfurter.app（ECB 官方基准数据，每日 16:00 CET 前后更新，
     支持任意 3 位 base 码，币种为 ECB 一篮子）：
     https://api.frankfurter.app/latest?base=<CODE>

更新策略：主源失败（超时 / 非 200 / 网络不可达 / JSON 解析错误 / 结构异常）
自动切换备用源；两源均失败时输出结构化错误 JSON（含 error key）并以非零
退出码退出，由平台保留旧缓存（见 lib/core/data/register_data_source.dart），
绝不伪造汇率数据。

CLI 契约（模型 A 数据源）：
  fetch.py --type <typeArg> [--base <三位币种码>] [--project-root <root>] ...
  - stdout 只输出单行纯 JSON（顶层 Map），UTF-8 编码；
  - 成功：退出码 0，输出 {type, base, rates, count, updatedAt, source}；
  - 失败：退出码非 0，输出 {error(字符串), detail, type, base, updatedAt}；
  - 诊断信息一律写 stderr，绝不混入 stdout。
"""
import json
import socket
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

REQUEST_TIMEOUT = 10  # 单源请求超时（秒）；两源串行最坏 20s < 平台 60s 上限
USER_AGENT = "evergreen-exchange-rate/1.1"

ER_API_URL = "https://open.er-api.com/v6/latest/USD"  # 仅支持 USD 基准
FRANKFURTER_URL = "https://api.frankfurter.app/latest?base={base}"


def _utc_now_iso():
    """当前 UTC 时间，ISO 8601（秒精度），如 2025-08-29T12:00:01+00:00。"""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _parse_args(argv):
    """解析命令行参数，兼容 `--key value` 与 `--key=value` 两种形式。

    平台按契约传入 `--type <typeArg> --project-root <root> --greenix-config <cfg>`
    （分隔 token），本适配壳只消费 `--type` 与可选 `--base`，其余参数忽略。
    """
    args = {}
    i = 0
    while i < len(argv):
        token = argv[i]
        if token.startswith("--") and "=" in token:
            key, value = token[2:].split("=", 1)
            args[key] = value
        elif token.startswith("--") and i + 1 < len(argv):
            args[token[2:]] = argv[i + 1]
            i += 1
        i += 1
    return args


def _classify(exc):
    """把异常分类为 (code, message)，供结构化错误输出。

    覆盖四类常见失败：超时 / 非 200 / 网络不可达 / JSON 解析，其余归 unexpected。
    """
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return "timeout", "请求超时（>%ss）" % REQUEST_TIMEOUT
    if isinstance(exc, urllib.error.HTTPError):
        return "http_error", "HTTP %s %s" % (exc.code, exc.reason)
    if isinstance(exc, ssl.SSLError):
        # TLS/SSL 失败（证书库损坏/握手被拦截/防火墙干扰），与普通网络错误区分，
        # 便于定位「本地证书存储损坏导致全部 https 失败」这类环境问题
        return "ssl_error", "TLS/SSL 错误: %s" % exc
    if isinstance(exc, urllib.error.URLError):
        return "network_error", "网络不可达: %s" % getattr(exc, "reason", exc)
    if isinstance(exc, json.JSONDecodeError):
        return "parse_error", "JSON 解析失败: %s" % exc
    return "unexpected", "%s: %s" % (type(exc).__name__, exc)


def _http_get_json(url, timeout=REQUEST_TIMEOUT):
    """GET url 并解析 JSON；任何失败抛出原始异常，由调用方分类。"""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if resp.status != 200:
            raise urllib.error.HTTPError(
                url, resp.status, "HTTP %s" % resp.status, resp.headers, None
            )
        body = resp.read().decode("utf-8", errors="replace")
    return json.loads(body)


def _normalize_rates(raw):
    """规范化汇率表：key 转大写、仅保留「3 位纯字母码 + 数值型汇率」。

    返回 (rates, count)；源返回空表或全非法条目时由调用方判为失败。
    """
    rates = {}
    if not isinstance(raw, dict):
        return rates
    for code, value in raw.items():
        if not isinstance(code, str):
            continue
        code = code.upper()
        if len(code) != 3 or not code.isalpha():
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        rates[code] = float(value)
    return rates


def _fetch_er_api():
    """主源 open.er-api.com（仅支持 USD 基准，约每小时更新）。

    返回 (rates, updated_iso, source_url)；异常抛给调用方分类。
    """
    data = _http_get_json(ER_API_URL)
    if not isinstance(data, dict) or data.get("result") not in (None, "success"):
        raise ValueError("er-api 返回异常结构: %r" % (str(data)[:200]))
    rates = _normalize_rates(data.get("rates"))
    if not rates:
        raise ValueError("er-api 返回空汇率表")
    updated = _utc_now_iso()
    raw = data.get("time_last_update_utc")
    if isinstance(raw, str):
        try:
            updated = parsedate_to_datetime(raw).isoformat(timespec="seconds")
        except (ValueError, TypeError, IndexError, OverflowError):
            updated = _utc_now_iso()  # 无法解析时退化为抓取时刻
    return rates, updated, ER_API_URL


def _fetch_frankfurter(base):
    """备用源 api.frankfurter.app（ECB 官方数据，每日更新，支持任意 3 位 base）。

    返回 (rates, updated_iso, source_url)；异常抛给调用方分类。
    """
    url = FRANKFURTER_URL.format(base=base)
    data = _http_get_json(url)
    if not isinstance(data, dict):
        raise ValueError("frankfurter 返回异常结构: %r" % (str(data)[:200]))
    rates = _normalize_rates(data.get("rates"))
    if not rates:
        raise ValueError("frankfurter 返回空汇率表")
    day = data.get("date")
    if isinstance(day, str) and day:
        updated = "%sT00:00:00+00:00" % day  # ECB 按日更新，无精确时刻
    else:
        updated = _utc_now_iso()
    return rates, updated, url


def fetch_exchange_rates(base, type_arg):
    """依次尝试主源/备用源；两源均失败返回结构化错误 Map（含 error key）。

    成功 Map：{type, base, rates, count, updatedAt, source}
    失败 Map：{error, detail, type, base, updatedAt}（error 恒为字符串）
    """
    base = (base or "USD").strip().upper() or "USD"
    providers = []
    errors = []

    if base == "USD":  # er-api 仅支持 USD 基准；其它 base 直接走 frankfurter
        try:
            providers.append(_fetch_er_api())
        except Exception as exc:
            code, msg = _classify(exc)
            errors.append("open.er-api.com: [%s] %s" % (code, msg))

    try:
        providers.append(_fetch_frankfurter(base))
    except Exception as exc:
        code, msg = _classify(exc)
        errors.append("api.frankfurter.app: [%s] %s" % (code, msg))

    if providers:  # 主源优先
        rates, updated, source = providers[0]
        return {
            "type": type_arg,
            "base": base,
            "rates": rates,
            "count": len(rates),
            "updatedAt": updated,
            "source": source,
        }

    return {
        "error": "汇率数据抓取失败：主源与备用源均不可用",
        "detail": "; ".join(errors),
        "type": type_arg,
        "base": base,
        "updatedAt": _utc_now_iso(),
    }


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass  # 极老解释器无 reconfigure：保持默认编码

    args = _parse_args(sys.argv[1:])
    type_arg = args.get("type", "exchange_rate")
    base = args.get("base", "USD")
    result = fetch_exchange_rates(base, type_arg)

    if "error" in result:
        sys.stderr.write("[exchange-rate] %s\n" % result["error"])
        print(json.dumps(result, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
