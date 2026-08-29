#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""油价 数据源适配壳（真实抓取，双源降级）— WTI / 布伦特原油期货行情。

数据来源（均为公开免 key 接口）：
  1. Yahoo Finance chart API  https://query1.finance.yahoo.com/v8/finance/chart/<SYMBOL>
     —— 期货符号 CL=F（WTI）/ BZ=F（布伦特）/ GC=F（伦敦金），返回 JSON 可直接解析。
  2. 新浪财经外盘期货接口  https://hq.sinajs.cn/list=hf_CL,hf_OIL
     —— 需带 Referer 头（标准库可携带）；https 被拦截时自动降级到 http 明文端点。

纯 Python 标准库，零第三方依赖。CLI 契约（模型 A）：
  - 平台执行: python fetch.py --type <typeArg> --project-root <root> --greenix-config <cfg>
  - stdout 顶层输出单个 JSON Map（UTF-8），不混入任何日志（日志走 stderr）。
  - 成功 → 行情 Map；失败 → {"error": "...", ...} 且 exit code 非 0（平台保留旧缓存）。
  - 顶层 Map 结构（列表型数据包 {"items": [...]}）：
      {
        "type": "oil_price",          // 透传 --type
        "count": 2, "requested": 2,   // 成功条数 / 请求条数
        "items": [ {行情字段}, ... ], // 仅成功的行情项
        "errors": [ {失败详情}, ... ],// 全部源都失败的品种
        "warnings": ["brent: 所有源失败(...)"],
        "fetchedAt": "2026-08-29T04:59:58+00:00",  // UTC ISO8601（数据差异引擎按易变字段忽略）
        "source": "multi"
      }
  - 行情项字段：symbol（交易所代码 CL=F）/ kind（wti|brent|gold）/ name（中文名）/
    price / open / high / low / prev_close / change / change_pct / date / time / tz /
    currency（USD）/ unit（美元/桶）/ source（yahoo-finance | sina-finance）。

用法：
  python fetch.py --type oil_price                          # 默认 WTI + 布伦特
  python fetch.py --type oil_price --symbols wti            # 单品种
  python fetch.py --type oil_price --symbols wti,brent,gold # 含伦敦金
  python fetch.py --type oil_price --prefer sina            # 国内网络优先新浪
  python fetch.py --type oil_price --kind brent             # 兼容旧 --kind 参数
"""
import datetime
import json
import re
import ssl
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

# kind -> (Yahoo 期货符号, 新浪外盘代码, 中文名)
SYMBOLS = {
    "wti":   ("CL=F", "hf_CL", "WTI原油"),
    "brent": ("BZ=F", "hf_OIL", "布伦特原油"),
    "gold":  ("GC=F", "hf_GC", "伦敦金"),
}
DEFAULT_SYMBOLS = ("wti", "brent")
_SINA_LINE = re.compile(r'var\s+hq_str_(\w+)="([^"]*)";')


def _http_get(url, headers, timeout=10):
    """GET 并返回原始字节；网络类异常原样抛出，由上层分类。"""
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _num(parts, i):
    """安全转数值：空串/非数字 → None；整数值转 int，其余保留 4 位小数。"""
    if i >= len(parts):
        return None
    v = parts[i].strip()
    if not v:
        return None
    try:
        f = float(v)
        return int(f) if f.is_integer() else round(f, 4)
    except ValueError:
        return None


def _last_not_null(lst):
    if not lst:
        return None
    for v in reversed(lst):
        if v is not None:
            return v
    return None


def _rounded(v):
    """数值规整：None 透传；浮点噪声保留 4 位小数。"""
    if v is None:
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return v
    return int(f) if f.is_integer() else round(f, 4)


def _change_fields(price, prev):
    """涨跌额 / 涨跌幅。缺价或缺昨收 → (None, None)。"""
    if price is None or not prev:
        return None, None
    return round(price - prev, 4), round((price - prev) / prev * 100, 2)


def classify_error(e):
    """把异常归类为人类可读的 error key。"""
    if isinstance(e, urllib.error.HTTPError):
        return "http_error_%d" % e.code
    if isinstance(e, (TimeoutError, socket.timeout)):
        return "timeout"
    # TLS 握手/证书校验失败（代理拦截、证书链不全等）单独归类；
    # 可能被 urllib 包装成 URLError(reason=SSLError)，也可能原样抛出
    if isinstance(e, ssl.SSLError):
        return "ssl_error"
    if isinstance(e, urllib.error.URLError):
        if isinstance(e.reason, ssl.SSLError):
            return "ssl_error"
        return "network_unavailable"
    if isinstance(e, json.JSONDecodeError):
        return "bad_response"
    if isinstance(e, ValueError):
        return str(e) or "fetch_failed"
    return "fetch_failed"


def fetch_yahoo(kind):
    """Yahoo Finance chart API 抓取单个品种（https，校验证书）。

    返回行情 dict；失败抛异常由上层分类。期货符号如 CL=F（WTI）。
    """
    yahoo_sym, _, name = SYMBOLS[kind]
    url = (
        "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&range=1d"
        % urllib.parse.quote(yahoo_sym, safe="")
    )
    raw = _http_get(url, {"User-Agent": UA}, timeout=8)
    data = json.loads(raw.decode("utf-8", errors="replace"))
    chart = data.get("chart") or {}
    if chart.get("error"):
        err = chart["error"]
        raise ValueError(
            str(err.get("description") or err.get("code") or "yahoo_error")
        )
    result = chart.get("result") or []
    if not result:
        raise ValueError("no_data")
    r0 = result[0]
    meta = r0.get("meta") or {}
    quotes = (r0.get("indicators") or {}).get("quote") or [{}]
    q0 = quotes[0] if quotes else {}

    price = meta.get("regularMarketPrice")
    if price is None:
        price = _last_not_null(q0.get("close"))
    if price is None:
        raise ValueError("no_price")
    prev = meta.get("chartPreviousClose")
    if prev is None:
        prev = meta.get("previousClose")
    high = meta.get("regularMarketDayHigh")
    low = meta.get("regularMarketDayLow")
    if high is None:
        high = _last_not_null(q0.get("high"))
    if low is None:
        low = _last_not_null(q0.get("low"))
    change, change_pct = _change_fields(price, prev)

    ts = meta.get("regularMarketTime")
    date, tm = "", ""
    if ts:
        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        date = dt.strftime("%Y-%m-%d")
        tm = dt.strftime("%H:%M:%S")

    return {
        "symbol": yahoo_sym,
        "kind": kind,
        "name": name,
        "price": _rounded(price),
        "open": _rounded(_last_not_null(q0.get("open"))),
        "high": _rounded(high),
        "low": _rounded(low),
        "prev_close": _rounded(prev),
        "change": change,
        "change_pct": change_pct,
        "date": date,
        "time": tm,
        "tz": "UTC",
        "currency": meta.get("currency") or "USD",
        "unit": "美元/桶" if kind in ("wti", "brent") else "美元/盎司",
        "source": "yahoo-finance",
    }


def fetch_sina(kinds):
    """新浪财经外盘期货接口抓取多个品种（一次请求）。

    hf_ 外盘期货字段布局（实测）：0 现价 / 3 今开 / 4 最高 / 5 最低 / 6 时间 /
    7 昨收 / 12 日期 / 13 名称。https 被拦截时自动降级到 http 明文端点。

    返回 {kind: 行情 dict}；整批失败抛异常，单个品种无数据抛 ValueError。
    """
    codes = [SYMBOLS[k][1] for k in kinds]
    url = "https://hq.sinajs.cn/list=" + ",".join(codes)
    headers = {"User-Agent": UA, "Referer": "https://finance.sina.com.cn"}
    try:
        raw = _http_get(url, headers)
    except Exception:
        # TLS 被拦截/校验失败等 → 降级 http 明文（行情为公开数据，无敏感信息）
        raw = _http_get(url.replace("https://", "http://", 1), headers)

    text = raw.decode("gbk", errors="replace")
    found = {}
    for m in _SINA_LINE.finditer(text):
        code, payload = m.group(1), m.group(2)
        if not payload:
            continue
        parts = payload.split(",")
        # 字段不足或现价为空视为该品种无数据
        if len(parts) < 8 or not parts[0]:
            continue
        kind = next((k for k, (_, c, _) in SYMBOLS.items() if c == code), None)
        if kind is None:
            continue
        price = _num(parts, 0)
        prev = _num(parts, 7)
        change, change_pct = _change_fields(price, prev)
        found[kind] = {
            "symbol": SYMBOLS[kind][0],
            "kind": kind,
            "name": SYMBOLS[kind][2],
            "price": price,
            "open": _num(parts, 3),
            "high": _num(parts, 4),
            "low": _num(parts, 5),
            "prev_close": prev,
            "change": change,
            "change_pct": change_pct,
            "date": parts[12] if len(parts) > 12 else "",
            "time": parts[6],
            "tz": "Asia/Shanghai",
            "currency": "USD",
            "unit": "美元/桶" if kind in ("wti", "brent") else "美元/盎司",
            "source": "sina-finance",
        }
    if not found:
        raise ValueError("no_data")
    return found


def _err_item(kind, source, err_key, detail):
    """单品种失败详情（含降级链汇总）。"""
    return {
        "kind": kind,
        "symbol": SYMBOLS[kind][0],
        "name": SYMBOLS[kind][2],
        "error": err_key,
        "detail": detail,
        "chain": [source],
    }


def _note_error(errors, kind, source, err_key, detail):
    """登记品种失败：同一品种已有错误则追加降级链（fallback_* 字段），否则新建条目。"""
    for e in errors:
        if e["kind"] == kind:
            e["chain"].append(source)
            e["fallback_error"] = err_key
            e["fallback_detail"] = detail
            return
    errors.append(_err_item(kind, source, err_key, detail))


def _drop_error(errors, kind):
    """品种成功兜底后清除其临时失败记录（降级成功 ≠ 失败）。"""
    for i, e in enumerate(errors):
        if e["kind"] == kind:
            del errors[i]
            return


def fetch_symbols(type_arg, kinds, prefer):
    """按顺序抓取多个品种，双源降级。返回 (items, errors, warnings)。"""
    items, errors = [], []

    def try_yahoo(kind):
        try:
            items.append(fetch_yahoo(kind))
            _drop_error(errors, kind)
            return True
        except Exception as e:
            _note_error(errors, kind, "yahoo-finance", classify_error(e), str(e))
            return False

    def try_sina_batch(kinds_):
        """新浪批量拉取；返回仍未覆盖的品种。整批异常按品种记账后返回全部待补品种
        （供调用方继续走 Yahoo 补救），调用方丢弃返回值时无副作用。"""
        if not kinds_:
            return []
        try:
            got = fetch_sina(kinds_)
        except Exception as e:
            for k in kinds_:
                _note_error(errors, k, "sina-finance", classify_error(e), str(e))
            return list(kinds_)
        remaining = []
        for k in kinds_:
            if k in got:
                items.append(got.pop(k))
                _drop_error(errors, k)
            else:
                remaining.append(k)
                _note_error(errors, k, "sina-finance", "no_data", "新浪无该品种数据")
        return remaining

    if prefer == "sina":
        # 新浪批量一次拉全 → 缺的品种逐一到 Yahoo 补
        for k in try_sina_batch(kinds):
            try_yahoo(k)
    else:
        # 默认 Yahoo 优先：逐品种 Yahoo → 缺的品种新浪批量补
        remaining = []
        for k in kinds:
            if not try_yahoo(k):
                remaining.append(k)
        try_sina_batch(remaining)

    warnings = [
        "%s: 所有数据源均失败 (%s)" % (e["kind"], " / ".join(e["chain"]))
        for e in errors
    ]
    return items, errors, warnings


def parse_args(argv):
    """同时支持 --key value 与 --key=value 两种形式（平台以空格形式传参）。"""
    args = {}
    positionals = []
    i, n = 0, len(argv)
    while i < n:
        a = argv[i]
        if a.startswith("--") and "=" in a:
            k, v = a.split("=", 1)
            args[k] = v
        elif a.startswith("-") and i + 1 < n:
            args[a] = argv[i + 1]
            i += 1
        else:
            positionals.append(a)
        i += 1
    return args, positionals


def main():
    try:
        args, positionals = parse_args(sys.argv[1:])
        # 优先级：--type/--symbols/--kind 显式参数 > 位置参数 > 默认值
        type_arg = (
            args.get("--type")
            or (positionals[0] if positionals else None)
            or "oil_price"
        )
        symbols_raw = args.get("--symbols") or args.get("--kind")
        if symbols_raw is None and len(positionals) > 1:
            symbols_raw = positionals[1]
        symbols_raw = (symbols_raw or "").strip() or "wti,brent"
        kinds = [s.strip().lower() for s in re.split(r"[,\s]+", symbols_raw) if s.strip()]
        kinds = [k for k in kinds if k in SYMBOLS]
        if not kinds:
            kinds = list(DEFAULT_SYMBOLS)

        prefer = (args.get("--prefer") or "").strip().lower()
        if prefer not in ("yahoo", "sina"):
            prefer = "yahoo"  # 默认 Yahoo 优先，新浪为降级

        items, errors, warnings = fetch_symbols(type_arg, kinds, prefer)

        out = {
            "type": type_arg,
            "count": len(items),
            "requested": len(kinds),
            "items": items,
            "fetchedAt": datetime.datetime.now(
                datetime.timezone.utc
            ).isoformat(timespec="seconds"),
            "source": "multi",
        }
        if errors:
            out["errors"] = errors
            out["warnings"] = warnings
        if not items:
            # 全部失败：error key + 非零退出码（平台保留旧缓存/静态兜底）
            out["error"] = "all_failed"
            out["detail"] = "; ".join(warnings) or "所有数据源均不可用"

        print(json.dumps(out, ensure_ascii=False))
        sys.stdout.flush()
        sys.exit(0 if items else 1)
    except Exception as e:  # 兜底：任何未预期异常收敛为错误 JSON，绝不污染 stdout
        print(json.dumps({"error": "unexpected", "detail": str(e)}, ensure_ascii=False))
        sys.stdout.flush()
        sys.exit(1)


if __name__ == "__main__":
    main()
