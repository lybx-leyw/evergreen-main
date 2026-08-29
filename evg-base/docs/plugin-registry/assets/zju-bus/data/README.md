# zju-bus · 浙大校车时刻（data-source 插件）

- 类型：data-source（模型 A CLI）
- ID：`zju-bus`（不可更改）
- 数据：浙江大学各校区班车/校车班次时刻表

## 数据来源（真实抓取，免登录）

官方公开 REST API（浙江大学生活平台「班次查询」lightapp，页面入口
[shiftManage.html](http://www.life.zju.edu.cn/_web/_apps/lightapp/busQuery/mobile/pc/pub/shiftManage.html)）：

| 接口 | 说明 |
|------|------|
| `/_web/_apps/lightapp/shuttlebus/station/api/lists.rst?state=1&page=0&rows=99999` | 站点列表 |
| `/_web/_apps/lightapp/shuttlebus/bus/api/lists.rst?state=1&page=0&rows=99999` | 班车列表 |
| `/_web/_apps/lightapp/shuttlebus/busflight/api/lists.rst?id=-1&startStationId=-1&endStationId=-1&zj=1,2,3,4,5,6,7&startTime=0000&endTime=2359&page=0&rows=99999` | 班次列表（核心） |

- 均免登录、无鉴权；站点使用 `http://`（遗留服务 HTTPS 证书异常，官方页面同样使用 http 链接）。
- API 返回**当前生效**的班次集合（寒暑假会切换为假期班车，与官方一致，无需处理）。
- `startTime`/`endTime` 为 4 位字符串（如 `810` → `08:10`），`cycle` 为逗号分隔的
  星期码（`1,2,3,4,5` = 周一至周五，`6,7` = 周末）。

## 输出 schema（stdout 顶层 Map JSON）

```json
{
  "type": "zju_bus",
  "source": "浙江大学生活平台·班次查询（shuttlebus 公开 API）",
  "source_url": "http://www.life.zju.edu.cn/_web/_apps/lightapp/busQuery/mobile/pc/pub/shiftManage.html",
  "fetched_at": "2026-08-28T15:04:00",
  "count": 79,
  "items": [
    {
      "id": "206",
      "busName": "暑期8号班车（紫金港西教学区短驳）",
      "lineName": "医药→西教",
      "startStationName": "医药组团",
      "startTime": "08:10",
      "endStationName": "西教学区",
      "endTime": "08:10",
      "cycle": "1,2,3,4,5",
      "cycleLabel": "周一至周五",
      "remark": ""
    }
  ],
  "stations": [{"id": "6", "name": "紫金港校区"}],
  "buses": [{"id": "20", "name": "研究生1号班车"}]
}
```

## 契约要点

- 参数：`--type <typeArg> --project-root <root> --greenix-config <cfg>`（空格分隔，平台形式）
- 成功：stdout 纯 JSON，exit 0；失败：`{"error": "..."}`，exit 非 0
- `_get_config` 三级降级（config.json → ConfigHttpServer → 环境变量）；本数据源公开免登录，
  不强制要求 `ZJU_USERNAME`/`ZJU_PASSWORD`，可选 `ZJU_BUS_API_BASE` 覆盖 API 基址
- 纯 Python 标准库，Windows / Android（Chaquopy）双平台兼容

## 离线兜底

`data/manifest.json` 的 `dataTypes[].fallbackJson` 内嵌一份**真实快照**（`snapshot: true` +
`snapshot_date` + 官方 source_url 标注）：网络不可达且无旧缓存时由数据中枢返回该兜底，
标注快照日期，不伪造数据。
