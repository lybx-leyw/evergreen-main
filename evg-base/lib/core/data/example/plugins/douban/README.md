# 豆瓣电影 Top250 插件（真实爬虫示例）

> 爬取 [movie.douban.com/top250](https://movie.douban.com/top250)。
> 本示例用 Python 标准库编写（无需 pip install），但插件可用**任意语言**。

## 快速上手

```bash
pip install pyinstaller
pyinstaller --onefile plugin.py
cp dist/plugin.exe .
```

## 数据格式

`GET /api/top250` 返回：

```json
[
  {"rank": 1, "title": "肖申克的救赎", "rating": 9.7, "quote": "希望让人自由。"},
  {"rank": 2, "title": "霸王别姬", "rating": 9.6, "quote": "风华绝代。"},
  ...
]
```

## 技术要点

- **仅用标准库**：`urllib` 爬取、`html.parser` 解析、`http.server` 提供服务。
- **User-Agent**：豆瓣需要 UA 头，否则返回 418。
- **健康检查**：`/health` 真实请求豆瓣首页，连不上返回 503。
- **容错**：爬取失败返回空列表，旧缓存保留。
- **TTL=1h**：豆瓣 Top250 变化缓慢，1 小时刷新一次足够。
