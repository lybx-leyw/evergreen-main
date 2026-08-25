# 豆瓣电影 Top250 插件（模型 A CLI 数据源示例）

> 爬取 [movie.douban.com/top250](https://movie.douban.com/top250)。
> 本示例是**模型 A（CLI 一次性脚本）**的完整范例：`data/manifest.json` + `data/plugin.py`，
> 无平台二进制、无 PyInstaller 打包，桌面解释器 / 安卓 Chaquopy 同一份 `.py` 直接运行。

## 快速上手

```bash
# 目录结构（manifest 的 script 相对 data/ 解析）
# data/
# ├── manifest.json   ← type: "data-source" + script + runtime: "python"
# └── plugin.py       ← CLI 脚本（纯标准库，无需 pip install）

# 独立冒烟（与平台调用同一套参数）
cd data
python plugin.py --type douban_top250 --project-root <项目根> --greenix-config <greenixConfigPath>
# stdout 应输出单个 JSON 对象（顶层 Map）：{"items": [...]}
```

## 数据格式

stdout 顶层必须是 `Map<String, dynamic>`（平台统一契约，列表型包 `{"items": [...]}`）：

```json
{
  "items": [
    {"rank": 1, "title": "肖申克的救赎", "rating": 9.7, "quote": "希望让人自由。"},
    {"rank": 2, "title": "霸王别姬", "rating": 9.6, "quote": "风华绝代。"}
  ]
}
```

失败约定（任一即视为拉取失败，平台保留旧缓存）：非零退出码，或 stdout JSON 含 `"error"` 字段。

## 技术要点

- **仅用标准库**：`urllib` 爬取、`html.parser` 解析（无需 requests，零第三方依赖——
  同步中心跨机导入不缺依赖，安卓 Chaquopy 可直接执行）。
- **User-Agent**：豆瓣需要 UA 头，否则返回 418。
- **容错**：抓取失败输出 `{"error": "..."}` + 退出码 1，平台保留旧缓存。
- **TTL=1h**：豆瓣 Top250 变化缓慢，1 小时刷新一次足够。

## 从模型 B（.exe）迁移到模型 A 的改动

| 项 | 模型 B（旧） | 模型 A（现） |
|----|--------------|--------------|
| manifest | `process: "plugin.exe"` + `dataTypes[].endpoint` | `script: "plugin.py"` + `runtime: "python"`，去掉 `endpoint`/`preferredPort` |
| 运行方式 | HTTP 长驻，`PORT:` 行 + `/health` 探测 | 每次拉取执行一次 `python plugin.py --type ...`，stdout 输出 JSON |
| 数据返回 | HTTP body JSON 数组 | stdout 顶层 Map（列表型包 `{"items": [...]}`） |
| 产物 | PyInstaller `.exe`（Windows 专用，~8MB/个） | 无（纯 .py 源码，跨平台） |
| 注册入口 | `scanAndLoadDataSources` / `DataSourceLoader` | `registerDataSourcesFromManifest`（与 `POST /data/register` 同契约） |
