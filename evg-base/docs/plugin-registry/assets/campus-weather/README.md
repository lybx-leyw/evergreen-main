# 校园天气（campus-weather）数据源插件

数据源插件（`lattice: data-source`，模型 A / CLI 一次性脚本）：通过
[wttr.in](https://wttr.in) 公开天气 API 拉取**真实实时天气与未来数日预报**。
纯 Python 标准库实现，零第三方依赖，Windows / macOS / Linux / Android(Chaquopy) 通用。

## 文件

| 文件 | 说明 |
|------|------|
| `data/manifest.json` | 数据源清单（6 个 dataType，每个绑定一座城市） |
| `data/fetch.py` | 适配壳（模型 A：CLI 一次性脚本） |
| `README.md` | 本说明 |

## 城市与 `--type` 分发表

| dataType | typeArg | 城市 | 说明 |
|----------|---------|------|------|
| `campus_weather` | `campus_weather` | Hangzhou | 默认（浙大紫金港校区所在市） |
| `beijing_weather` | `beijing_weather` | Beijing | 北京 |
| `shanghai_weather` | `shanghai_weather` | Shanghai | 上海 |
| `shenzhen_weather` | `shenzhen_weather` | Shenzhen | 深圳 |
| `chengdu_weather` | `chengdu_weather` | Chengdu | 成都 |
| `guangzhou_weather` | `guangzhou_weather` | Guangzhou | 广州 |

**城市选择优先级（高 → 低）**：

1. `--city <城市>` 命令行显式指定（如 `--city Wuhan` / `--city 武汉`）
2. 环境变量 `CAMPUS_WEATHER_CITY`
3. `--type` 分发表（上表）
4. 默认 `Hangzhou`

未收录的城市名也可经 `--city` / 环境变量直接使用（wttr.in 支持中英文城市名，
如 `--city 武汉`、`--city Xiamen`）；未收录的 `--type` 回退默认城市。

> 数据粒度为市区级（wttr.in 不提供具体校区/街道级数据）。

## 平台契约（模型 A CLI）

- 平台执行：`python fetch.py --type <typeArg> --project-root <root> --greenix-config <cfg>`
  （工作目录 `<plugin>/data/`）
- **stdout 只输出单个 JSON 对象**（顶层 Map，UTF-8）；日志一律走 stderr，绝不污染 stdout
- 成功：exit 0 + 天气数据 Map
- 失败：exit 非 0 + `{"error": "<人类可读信息>", "errorCode": "<机器码>", ...}`
  —— 平台检测到 `exitCode != 0` 或 stdout 含 `error` key 即判定拉取失败，
  保留旧缓存 / 返回兜底，优雅降级不崩溃

## 输出结构（成功）

```jsonc
{
  "type": "campus_weather",
  "city": "Hangzhou",
  "source": "wttr.in",
  "fetched_at": "2026-08-25T06:00:00Z",      // 本地拉取时刻（UTC）
  "updated": "06:00 AM",                       // wttr.in 观测时间
  "observed_local": "2026-08-25 02:00 PM",
  "temp_c": "28", "feels_like_c": "30",
  "humidity": "65", "wind_kmh": "12", "wind_dir": "SE",
  "cloudcover": "25", "precip_mm": "0.0",
  "pressure_mb": "1009", "visibility_km": "10", "uv_index": "6",
  "weather_code": "353", "condition": "小阵雨",  // 中文：weatherCode 确定性映射优先，lang_zh/weatherDesc 兜底
  "forecast": [                                 // 未来数日逐日预报（通常 3 天）
    { "date": "2026-08-25", "max_c": "32", "min_c": "25", "avg_c": "28",
      "desc": "多云", "chanceofrain": "10",
      "sunrise": "05:24 AM", "sunset": "06:33 PM" }
  ],
  "hourly_today": [                             // 今日 3 小时间隔明细（可选）
    { "time": "0", "temp_c": "26", "desc": "多云",
      "chanceofrain": "10", "humidity": "70", "wind_kmh": "8" }
  ]
}
```

> 字段缺失时安全降级为 `null` / 空列表，不抛异常；`fetched_at` 属易变字段，
> 数据中枢 diff 引擎比较时自动忽略，不会造成假变更事件。
> `condition` 中文描述来自 wttr.in `weatherCode` 的确定性映射表（脚本内置）；
> 实测 wttr.in 的 `lang=zh` 目前仍返回英文原文，故 `lang_zh` / `weatherDesc` 仅作兜底。

## errorCode 一览（失败）

| errorCode | 含义 |
|-----------|------|
| `timeout` | 请求 wttr.in 超时（15s 无响应） |
| `http_error` | 服务返回非 2xx（含 `status` 细节） |
| `network_unavailable` | 网络不可达（DNS 解析失败 / 连接拒绝等） |
| `parse_error` | 响应 JSON 解析或编码失败 |
| `unexpected_format` | 响应结构不符合预期（常见于城市名无效） |
| `unknown_error` | 其它未知异常（兜底，绝不崩溃） |

## 本地验证

```bash
python fetch.py --type campus_weather            # 空格分隔（平台实际形式）
python fetch.py --type=beijing_weather           # 等号分隔（兼容形式）
python fetch.py --type campus_weather --city=Shanghai   # 显式城市覆盖
python fetch.py --city 武汉                      # 未收录城市
set CAMPUS_WEATHER_CITY=Wuhan && python fetch.py --type campus_weather
```
