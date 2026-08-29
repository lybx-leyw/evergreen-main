#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""股票行情 数据源适配壳（真实抓取，双源降级）。

数据来源（均为公开免 key 接口）：
  1. 新浪财经行情接口  https://hq.sinajs.cn/list=<code>
     —— A 股 / 港股 / 中概 / 国内期货，需带 Referer 头（标准库可携带）。
  2. Yahoo Finance chart API  https://query1.finance.yahoo.com/v8/finance/chart/<SYMBOL>
     —— 全球股票（AAPL/MSFT/0700.HK 等），免费无 key，返回 JSON。

纯 Python 标准库，零第三方依赖。CLI 契约（模型 A）：
  - stdout 顶层输出单个 JSON Map（UTF-8），不混入任何日志（日志走 stderr）。
  - 成功 → 行情字段 Map；失败 → {"error": "...", ...} 且 exit code 非 0。
  - 股票代码可经 --symbol 传入（支持 sh600519 / 600519 裸代码 / AAPL / 逗号分隔多只）。

用法：
  python fetch.py --type stock_quote                        # 默认 sh600519（贵州茅台）
  python fetch.py --type stock_quote --symbol AAPL          # Yahoo 源
  python fetch.py --type stock_quote --symbol 600519        # 裸 6 位数字自动归一化为 sh/sz
  python fetch.py --type stock_quote --symbol sh600519,000001,AAPL  # 多只 → {"items": [...]}
"""
import datetime
import json
import re
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

_SINA_PREFIX = re.compile(r"^(sh|sz|bj|hk|gb_|hf_)(.+)$", re.I)


def _http_get(url, headers, timeout=12):
    """GET 并返回原始字节；网络类异常原样抛出，由上层分类。"""
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _num(parts, i):
    """安全转数值：空串/非数字 → None；整数值转 int（如成交量），其余保留 4 位小数。"""
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


def _clean_num(v):
    """数值去噪：int 保持 int，float 保留 4 位小数（避免 JSON 浮点噪声）。"""
    if v is None or isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v
    try:
        f = float(v)
        return int(f) if f.is_integer() else round(f, 4)
    except (TypeError, ValueError):
        return v


def _change_fields(price, prev):
    if price is None or not prev:
        return None, None
    return round(price - prev, 4), round((price - prev) / prev * 100, 2)


def normalize_symbol(raw):
    """代码归一化：600519 → sh600519；SH600519 → sh600519；AAPL → AAPL（Yahoo 符号）。"""
    s = (raw or "").strip()
    if not s:
        return ""
    up = s.upper()
    if re.fullmatch(r"\d{6}", up):
        # 6 位数字裸代码：6/9 开头为沪市（sh），0/2/3 开头为深市（sz）
        return ("sh" + up) if up[0] in "69" else ("sz" + up)
    m = _SINA_PREFIX.match(s)
    if m:
        return m.group(1).lower() + m.group(2)
    return up


def sina_to_yahoo(norm):
    """新浪代码 → Yahoo 代码（用于新浪失败时的降级）：sh600519 → 600519.SS。"""
    if norm[:2] == "sh" and len(norm) == 8:
        return norm[2:] + ".SS"
    if norm[:2] == "sz" and len(norm) == 8:
        return norm[2:] + ".SZ"
    if norm[:2] == "bj" and len(norm) == 8:
        return norm[2:] + ".BJ"
    if norm[:2] == "hk" and len(norm) == 7:
        return norm[2:] + ".HK"
    return None


def classify_error(e):
    """把异常归类为人类可读的 error key。"""
    if isinstance(e, urllib.error.HTTPError):
        return "http_error_%d" % e.code
    if isinstance(e, (TimeoutError, socket.timeout)):
        return "timeout"
    if isinstance(e, urllib.error.URLError):
        return "network_unavailable"
    if isinstance(e, json.JSONDecodeError):
        return "bad_response"
    if isinstance(e, ValueError):
        return str(e) or "fetch_failed"
    return "fetch_failed"


def fetch_sina(type_arg, symbol):
    """新浪财经行情。symbol 需为新浪代码（sh600519 等）。字段: 0名 1开 2昨收 3现价
    4高 5低 6买 7卖 8量 9额 ... 30日期 31时间。"""
    url = "https://hq.sinajs.cn/list=" + symbol
    raw = _http_get(
        url,
        {"User-Agent": UA, "Referer": "https://finance.sina.com.cn"},
    )
    text = raw.decode("gbk", errors="replace")
    m = re.search(r'="([^"]*)"', text)  # var hq_str_sh600519="...";
    if not m or not m.group(1):
        raise ValueError("no_data")
    parts = m.group(1).split(",")
    if len(parts) < 10 or not parts[0]:
        raise ValueError("no_data")
    price = _num(parts, 3)
    prev = _num(parts, 2)
    change, change_pct = _change_fields(price, prev)
    return {
        "type": type_arg,
        "symbol": symbol,
        "name": parts[0],
        "open": _num(parts, 1),
        "prev_close": prev,
        "price": price,
        "high": _num(parts, 4),
        "low": _num(parts, 5),
        "change": change,
        "change_pct": change_pct,
        "volume": _num(parts, 8),
        "amount": _num(parts, 9),
        "date": parts[30] if len(parts) > 30 else "",
        "time": parts[31] if len(parts) > 31 else "",
        "currency": "CNY",
        "source": "sina-finance",
    }


def fetch_yahoo(type_arg, yahoo_symbol, user_symbol=None):
    """Yahoo Finance chart API。yahoo_symbol 形如 AAPL / 600519.SS / 0700.HK。"""
    url = (
        "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&range=1d"
        % urllib.parse.quote(yahoo_symbol, safe="")
    )
    raw = _http_get(url, {"User-Agent": UA})
    data = json.loads(raw.decode("utf-8", errors="replace"))
    chart = data.get("chart") or {}
    if chart.get("error"):
        err = chart["error"]
        raise ValueError(str(err.get("description") or err.get("code") or "yahoo_error"))
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
    out = {
        "type": type_arg,
        "symbol": user_symbol or yahoo_symbol,
        "name": meta.get("longName") or meta.get("shortName") or yahoo_symbol,
        "open": _clean_num(_last_not_null(q0.get("open"))),
        "prev_close": _clean_num(prev),
        "price": _clean_num(price),
        "high": _clean_num(high),
        "low": _clean_num(low),
        "change": change,
        "change_pct": change_pct,
        "volume": _clean_num(meta.get("regularMarketVolume")),
        "amount": None,
        "date": date,
        "time": tm,
        "currency": meta.get("currency"),
        "source": "yahoo-finance",
    }
    if user_symbol and user_symbol != yahoo_symbol:
        out["yahoo_symbol"] = yahoo_symbol
    return out


def fetch_one(type_arg, symbol):
    """抓取单只股票：新浪代码走新浪（失败降级 Yahoo），其它符号直接走 Yahoo。
    失败时返回含 error key 的 Map（不抛异常）。"""
    norm = normalize_symbol(symbol)
    if not norm:
        return {"type": type_arg, "symbol": symbol or "", "error": "invalid_symbol",
                "detail": "股票代码为空"}
    if norm[:2] in ("sh", "sz", "bj", "hk"):
        try:
            return fetch_sina(type_arg, norm)
        except Exception as e:
            yahoo_sym = sina_to_yahoo(norm)
            if yahoo_sym:
                try:
                    return fetch_yahoo(type_arg, yahoo_sym, user_symbol=norm)
                except Exception as e2:
                    return {"type": type_arg, "symbol": norm,
                            "error": classify_error(e), "detail": str(e),
                            "fallback": "yahoo-finance", "fallback_symbol": yahoo_sym,
                            "fallback_error": classify_error(e2),
                            "fallback_detail": str(e2)}
            return {"type": type_arg, "symbol": norm,
                    "error": classify_error(e), "detail": str(e)}
    try:
        return fetch_yahoo(type_arg, norm, user_symbol=norm)
    except Exception as e:
        return {"type": type_arg, "symbol": norm,
                "error": classify_error(e), "detail": str(e)}


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
        # 优先级：--type/--symbol 显式参数 > 位置参数 > 默认值
        type_arg = args.get("--type") or (positionals[0] if positionals else None) or "stock_quote"
        symbol_arg = (
            args.get("--symbol")
            or (positionals[1] if len(positionals) > 1 else None)
            or "sh600519"
        )
        symbols = [s for s in re.split(r"[,\s]+", symbol_arg.strip()) if s] or ["sh600519"]
        if len(symbols) == 1:
            out = fetch_one(type_arg, symbols[0])
        else:
            items = [fetch_one(type_arg, s) for s in symbols]
            ok = [it for it in items if "error" not in it]
            out = {"type": type_arg, "count": len(items), "items": items, "source": "multi"}
            if not ok:
                out["error"] = "all_failed"
                out["detail"] = items[0].get("detail") if items else "no results"
        print(json.dumps(out, ensure_ascii=False))
        sys.stdout.flush()
        # 失败契约：error key + 非零 exit code
        sys.exit(0 if "error" not in out else 1)
    except Exception as e:  # 兜底：任何未预期异常收敛为错误 JSON，绝不污染 stdout
        print(json.dumps({"error": "unexpected", "detail": str(e)}, ensure_ascii=False))
        sys.stdout.flush()
        sys.exit(1)


if __name__ == "__main__":
    main()
