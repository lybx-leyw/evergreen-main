# 示例模块（完整插件模板）

> 演示全部 manifest 字段 + HTTP 后端协议。
> 用 Python 标准库编写（无需 pip install），但插件可用**任意语言**。

## 目录结构

```
plugins/<name>/
  module/              ← 模块类型目录
    manifest.json       ← 模块声明（必需）
    plugin.py           ← 源码
    plugin.exe          ← 后端进程（构建产物）
  README.md             ← 本文件
```

> 每个插件按类型分目录：`module/`、`theme/`、`data/`、`config/`。一个插件可同时提供多种类型。

## 快速上手

```bash
cd module/
pip install pyinstaller
pyinstaller --onefile plugin.py --distpath .
```

## 数据格式

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 → `{"status":"ok"}` |
| `/data?sort=&order=` | GET | 排序数据 |
| `/search?q=` | GET | 全文搜索 |
| `/items` | POST | 新增一条 |
| `/items/:id` | GET | 查一条 |
| `/items/:id` | PUT | 编辑一条 |
| `/items/:id` | DELETE | 删除一条 |
| `/items/batch` | DELETE | 批量删除 `{"ids":["1","2"]}` |
| `/export?format=csv` | GET | 导出 CSV |

## 技术要点

- **仅用标准库**：`http.server` 提供服务，`json` 序列化，`urllib.parse` 解析查询参数。
- **协议第一行**：`print(f"PORT:{PORT}")` 必须 flush，框架据此发现端口。
- **之后用 stderr**：PORT 之后所有日志走 `sys.stderr`，避免污染 stdout 协议。
- **CORS**：所有响应带 `Access-Control-Allow-Origin: *`。
- **内存存储**：示例用 list 存数据，生产建议 SQLite。
