#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校园天气（campus-weather）数据源适配壳 — 模型 A（CLI 一次性脚本）。

数据来源：wttr.in 公开天气 API（https://wttr.in/<city>?format=j1&lang=zh），
返回真实实时天气与未来数日预报。纯 Python 标准库，零第三方依赖，
Windows / macOS / Linux / Android(Chaquopy) 通用。

== 平台契约（模型 A CLI）==
  平台执行: python fetch.py --type <typeArg> --project-root <root> --greenix-config <cfg>
  工作目录: <plugin>/data/
  stdout  : 单个 JSON 对象（顶层 Map，UTF-8）；日志一律写 stderr，绝不污染 stdout
  成功    : exit 0 + 真实天气数据 Map
  失败    : exit 非 0 + {"error": "<人类可读信息>", "errorCode": "<机器码>", ...}
            —— 平台检测到 exitCode!=0 或 stdout 含 error key 即判定拉取失败，
            保留旧缓存 / 返回兜底，优雅降级不崩溃。

== 城市配置 ==
  优先级（高 → 低）：
    1. --city <城市>         命令行显式指定（如 --city Wuhan / --city 武汉）
    2. CAMPUS_WEATHER_CITY   环境变量指定
    3. --type 分发表 CITY_MAP（manifest 中每个 dataType 对应一座城市）
    4. DEFAULT_CITY          默认杭州（浙大紫金港校区所在市）
  未收录的城市名也可通过 --city / 环境变量直接使用（wttr.in 支持中英文城市名）。
"""
import json
import os
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

try:
    sys.stdout.reconfigure(encoding="utf-8")  # Python 3.7+；旧解释器走默认编码
except AttributeError:
    pass

DEFAULT_CITY = "Hangzhou"  # 默认城市：杭州（浙大紫金港校区所在市）

# --type → 城市 分发表（与 data/manifest.json 的 dataTypes 一一对应）。
# 未收录的 type 会回退 DEFAULT_CITY；任意城市仍可经 --city / 环境变量覆盖。
CITY_MAP = {
    "campus_weather": "Hangzhou",      # 杭州（默认，紫金港校区）
    "beijing_weather": "Beijing",      # 北京
    "shanghai_weather": "Shanghai",    # 上海
    "shenzhen_weather": "Shenzhen",    # 深圳
    "chengdu_weather": "Chengdu",      # 成都
    "guangzhou_weather": "Guangzhou",  # 广州
}

USER_AGENT = "Evergreen campus-weather/2.0 (+https://github.com/lybx-leyw/evg-plugins)"
HTTP_TIMEOUT = 15  # 秒，wttr.in 无响应即放弃
DETAIL_CAP = 300   # 错误 detail 最长字符数（避免超长堆栈写进 stdout）

# wttr.in weatherCode → 中文描述 确定性映射（官方码表）。
# 实测 wttr.in 的 lang=zh 目前返回英文原文（翻译层失效），故以 weatherCode 为
# 中文主源；lang_zh / weatherDesc 仅作兜底。
WEATHER_CODE_ZH = {
    "113": "晴", "116": "局部多云", "119": "多云", "122": "阴",
    "143": "薄雾", "176": "可能有零星阵雨", "179": "可能有零星阵雪",
    "182": "可能有零星雨夹雪", "185": "可能有零星冻毛毛雨",
    "200": "可能有雷阵雨", "227": "吹雪", "230": "暴风雪",
    "248": "雾", "260": "冻雾", "263": "零星小毛毛雨", "266": "小毛毛雨",
    "281": "冻毛毛雨", "284": "强冻毛毛雨", "293": "零星小雨",
    "296": "小雨", "299": "间歇性中雨", "302": "中雨", "305": "间歇性大雨",
    "308": "大雨", "311": "小冻雨", "314": "中到大冻雨", "321": "小霰",
    "326": "小雪", "329": "间歇性中雪", "332": "中雪", "335": "间歇性大雪",
    "338": "大雪", "350": "冰粒", "353": "小阵雨", "356": "中到大阵雨",
    "359": "强阵雨", "362": "小阵霰", "365": "中到大阵霰", "368": "小阵雪",
    "371": "中到大阵雪", "374": "小阵冰粒", "377": "中到大阵冰粒",
    "386": "局部雷阵雨", "389": "雷阵雨", "392": "局部雷雪", "395": "雷雪",
}


# ═════════════════════════════════════════════════════════════════════════
# 类型安全的取值助手（wttr.in 结构变化时静默降级为 None/空，绝不抛异常）
# ═════════════════════════════════════════════════════════════════════════

def _first_str(node, *keys):
    """按顺序取 node 中第一个存在且可转 str 的值；类型安全，绝不抛。"""
    if not isinstance(node, dict):
        return None
    for k in keys:
        v = node.get(k)
        if v is None:
            continue
        if isinstance(v, str):
            return v
        if isinstance(v, (int, float)):
            return str(v)
    return None


def _desc(node):
    """天气描述（中文优先）：weatherCode 映射表 → lang_zh → weatherDesc（英文兜底）。

    类型安全：node 非 dict / 字段缺失 / 值类型异常均安全降级为 None，绝不抛。
    """
    if not isinstance(node, dict):
        return None
    code = _first_str(node, "weatherCode")
    if code and code in WEATHER_CODE_ZH:
        return WEATHER_CODE_ZH[code]
    for key in ("lang_zh", "weatherDesc"):
        arr = node.get(key)
        if isinstance(arr, list) and arr and isinstance(arr[0], dict):
            value = arr[0].get("value")
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def _to_int(value):
    """宽松转 int（'20' / 20 → 20；非法 → None）。"""
    if value is None:
        return None
    try:
        return int(str(value).strip())
    except (ValueError, TypeError):
        return None


# ═════════════════════════════════════════════════════════════════════════
# 解析器
# ═════════════════════════════════════════════════════════════════════════

def _parse_current(cc):
    """解析 wttr.in current_condition[0]；字段缺失安全降级为 None。"""
    return {
        "updated": _first_str(cc, "observation_time"),
        "observed_local": _first_str(cc, "localObsDateTime"),
        "temp_c": _first_str(cc, "temp_C"),
        "feels_like_c": _first_str(cc, "FeelsLikeC"),
        "humidity": _first_str(cc, "humidity"),
        "wind_kmh": _first_str(cc, "windspeedKmph"),
        "wind_dir": _first_str(cc, "winddir16Point"),
        "cloudcover": _first_str(cc, "cloudcover"),
        "precip_mm": _first_str(cc, "precipMM"),
        "pressure_mb": _first_str(cc, "pressure"),
        "visibility_km": _first_str(cc, "visibility"),
        "uv_index": _first_str(cc, "uvIndex"),
        "weather_code": _first_str(cc, "weatherCode"),
        "condition": _desc(cc),
    }


def _parse_day(day):
    """解析 wttr.in weather[] 中某一天：日期 + 极值 + 首时段描述 + 降水概率。"""
    hourly = day.get("hourly") if isinstance(day, dict) else None
    first = hourly[0] if isinstance(hourly, list) and hourly else None
    desc = _desc(first)
    rain = None
    if isinstance(hourly, list):
        values = [
            _to_int(h.get("chanceofrain"))
            for h in hourly if isinstance(h, dict)
        ]
        values = [v for v in values if v is not None]
        if values:
            rain = str(max(values))
    astro = day.get("astronomy") if isinstance(day, dict) else None
    astro0 = astro[0] if isinstance(astro, list) and astro else None
    return {
        "date": _first_str(day, "date"),
        "max_c": _first_str(day, "maxtempC"),
        "min_c": _first_str(day, "mintempC"),
        "avg_c": _first_str(day, "avgtempC"),
        "desc": desc,
        "chanceofrain": rain,
        "sunrise": _first_str(astro0, "sunrise") if isinstance(astro0, dict) else None,
        "sunset": _first_str(astro0, "sunset") if isinstance(astro0, dict) else None,
    }


def _parse_hourly(hourly):
    """解析今日 3 小时间隔明细（wttr.in hourly[]）；非列表/空 → []。"""
    out = []
    if not isinstance(hourly, list):
        return out
    for h in hourly:
        if not isinstance(h, dict):
            continue
        out.append({
            "time": _first_str(h, "time"),
            "temp_c": _first_str(h, "tempC"),
            "desc": _desc(h),
            "chanceofrain": _first_str(h, "chanceofrain"),
            "humidity": _first_str(h, "humidity"),
            "wind_kmh": _first_str(h, "windspeedKmph"),
        })
    return out


# ═════════════════════════════════════════════════════════════════════════
# 错误分类与结构化错误
# ═════════════════════════════════════════════════════════════════════════

def _classify(e):
    """把异常归类为 (errorCode, 人类可读消息, 技术细节)。

    覆盖：HTTP 非 2xx / 超时 / 网络不可达（DNS、连接拒绝）/ JSON 解析失败 /
    编码异常 / 其它 OSError / 未知异常。任何异常都不允许逃逸到 main。
    """
    if isinstance(e, urllib.error.HTTPError):
        return ("http_error", "天气服务暂不可用（HTTP %s）" % e.code,
                "status=%s" % e.code)
    if isinstance(e, socket.timeout):
        return ("timeout", "请求天气服务超时（%ss 无响应）" % HTTP_TIMEOUT, str(e))
    if isinstance(e, urllib.error.URLError):
        reason = getattr(e, "reason", None)
        detail = str(reason) if reason is not None else str(e)
        low = detail.lower()
        if "timed out" in low or "timeout" in low:
            return ("timeout", "请求天气服务超时", detail)
        return ("network_unavailable", "无法连接天气服务（网络不可达）", detail)
    if isinstance(e, UnicodeDecodeError):
        return ("parse_error", "天气数据编码异常", str(e))
    if isinstance(e, (json.JSONDecodeError, ValueError)):
        return ("parse_error", "天气数据解析失败", str(e))
    if isinstance(e, OSError):
        return ("network_unavailable", "无法连接天气服务（网络不可达）", str(e))
    return ("unknown_error", "获取天气数据失败", str(e))


def _error_payload(type_arg, city, code, message, detail=""):
    """构造契约化错误 Map（stdout 顶层含 error key = 拉取失败）。"""
    return {
        "type": type_arg,
        "city": city,
        "error": message,   # 人类可读（平台展示 / lastError）
        "errorCode": code,  # timeout|http_error|network_unavailable|parse_error|unexpected_format|unknown_error
        "detail": (detail or "")[:DETAIL_CAP],
    }


# ═════════════════════════════════════════════════════════════════════════
# 主流程
# ═════════════════════════════════════════════════════════════════════════

def fetch_weather(type_arg, city):
    """从 wttr.in 拉取真实天气（JSON）。任何失败均返回结构化 error Map，绝不抛。"""
    url = "https://wttr.in/%s?format=j1&lang=zh" % urllib.parse.quote(city)
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            body = resp.read().decode("utf-8")
    except Exception as e:  # noqa: BLE001 —— 网络层异常全部收敛为结构化 error
        return _error_payload(type_arg, city, *_classify(e))

    try:
        raw = json.loads(body)
    except Exception as e:  # noqa: BLE001
        return _error_payload(
            type_arg, city, "parse_error", "天气数据解析失败", str(e))

    cc = raw.get("current_condition") if isinstance(raw, dict) else None
    days = raw.get("weather") if isinstance(raw, dict) else None
    if not (isinstance(raw, dict) and isinstance(cc, list) and cc
            and isinstance(days, list) and days):
        # 结构不符合预期（如城市名无效时 wttr.in 返回非 j1 结构）
        return _error_payload(
            type_arg, city, "unexpected_format",
            "天气数据格式异常（可能城市名无效或服务返回了非预期内容）",
            "payload missing current_condition/weather",
        )

    day_list = [_parse_day(d) for d in days if isinstance(d, dict)]
    first_day = days[0] if isinstance(days[0], dict) else None
    hourly_today = _parse_hourly(first_day.get("hourly")) if first_day else []

    result = {
        "type": type_arg,
        "city": city,
        "source": "wttr.in",
        "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **_parse_current(cc[0]),
        "forecast": day_list,      # 未来数日逐日预报（wttr.in 通常返回 3 天）
        "hourly_today": hourly_today,  # 今日 3 小时间隔明细（可选，空列表不破坏消费方）
    }
    return result


def _parse_args(argv):
    """解析命令行：兼容 `--type X`（空格，平台契约）与 `--type=X`（等号）两种形式。

    平台实际下发空格分隔参数：--type <t> --project-root <r> --greenix-config <c>。
    """
    opts = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("--") and "=" in arg:
            key, _, value = arg[2:].partition("=")
            opts[key] = value
        elif arg.startswith("--") and i + 1 < len(argv):
            opts[arg[2:]] = argv[i + 1]
            i += 1
        else:
            key, _, value = arg.partition("=")
            opts[key.lstrip("-")] = value
        i += 1
    return opts


def _resolve_city(type_arg, city_opt):
    """城市选择优先级：--city 参数 > 环境变量 CAMPUS_WEATHER_CITY > --type 分发表 > 默认。"""
    city = (city_opt or "").strip()
    if city:
        return city
    env = (os.environ.get("CAMPUS_WEATHER_CITY") or "").strip()
    if env:
        return env
    return CITY_MAP.get(type_arg, DEFAULT_CITY)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    opts = _parse_args(argv)
    type_arg = (opts.get("type") or "campus_weather").strip() or "campus_weather"
    city = _resolve_city(type_arg, opts.get("city"))
    result = fetch_weather(type_arg, city)
    print(json.dumps(result, ensure_ascii=False))
    return 1 if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
