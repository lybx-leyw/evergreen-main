# zju-lectures — 浙大讲座日历（data-source 插件）

> 数据源插件 · 模型 A（CLI 一次性脚本）· 纯 Python 标准库 · 零第三方依赖
> 插件 id：`zju-lectures`（本插件唯一类型：`zju_lectures`）

## 数据源

- **站点**：浙江大学图书馆「讲座与展览」公告列表（公开、免登录、UTF-8 服务端渲染）
  - 首页：<https://libweb.zju.edu.cn/jzyl/list.htm>（每页 14 条，`list2.htm` / `list3.htm` … 翻页）
- **条目内容**：讲座 / 展览 / 文化活动公告的标题、发布链接、发布日期（`YYYY-MM-DD`）
- **范围诚实声明**：覆盖**浙江大学图书馆**发布的讲座与展览/文化活动公告，
  **不是全校学术讲座全集**。全校「学术公告」频道（<https://www.zju.edu.cn/xs/>）
  为前端 JS 内嵌标题数据、无日期无详情链接，不适合做日历，故未采用；
  亦不存在公开的 `lecture.zju.edu.cn` 聚合站或免登录 JSON API
  （苏迪 CMS `_wp3services/generalQuery` 返回 503）。
  输出顶层携带 `scope` 字段说明此边界，消费方不应宣称「全校讲座」。

## CLI 契约（与平台 `register_data_source.dart` 一致）

```
fetch.py --type zju_lectures --project-root <root> --greenix-config <cfg>
```

- 参数为**空格分隔**（同时兼容 `--type=value` 形态）；未知参数忽略。
- stdout 只输出**单个 JSON 对象（顶层 Map）**，UTF-8；列表包在 `items` 键下。
- **失败**：stdout 输出 `{"error": "<人类可读信息>"}` 且退出码非 0（堆栈只进 stderr/丢弃）。
- 纯标准库（`urllib` / `json` / `re` / `html`），`androidSupport: true`（Chaquopy 可用）。

## 输出结构

```json
{
  "type": "zju_lectures",
  "source": "浙江大学图书馆·讲座与展览",
  "source_url": "https://libweb.zju.edu.cn/jzyl/list.htm",
  "updated_at": "2026-08-29 12:00:00",
  "scope": "覆盖浙江大学图书馆发布的讲座/展览/文化活动公告，非全校学术讲座全集",
  "total": 42,
  "items": [
    { "title": "书香浙大·开卷有益报告会 | …", "url": "https://libweb.zju.edu.cn/2026/0611/c53489a3177574/page.htm", "date": "2026-06-11" }
  ]
}
```

## 可选项

- `ZJU_LECTURE_PAGES`（config.json / 环境变量）：抓取页数 1..10，默认 3（42 条）。
  走平台 `_get_config` 三级降级（GREENIX_CONFIG_PATH 文件 → ConfigHttpServer → 环境变量）。
- `ZJU_LECTURE_INSECURE`（环境变量，`1` 开启）：部分 Windows 机器的 Python/OpenSSL 3.x
  加载系统 CA 证书库会抛 `ASN1: NOT_ENOUGH_DATA`（本地证书库兼容问题，与站点无关）。
  默认不校验证书**绝不静默降级**——遇到该问题会返回可读错误；网络环境可信时可设
  为 `1` 跳过证书校验（公开只读公告页，风险可控），输出会带 `tls_verified: false`
  如实标注。
- 本源无需任何登录凭据；`persistentKey: zju_lectures` 启用数据中枢磁盘缓存
  （TTL 30m），`fallbackJson` 为拉取失败且无旧缓存时的静态兜底（空列表 + 说明）。

## 与 zju_modle（内置 Dart 数据源）的关系

- 平台内置的 12 个 zju DataType（`zju_modle/zju_data_sources.dart`：
  courses / scores / exams / zdbk×6 / classroom_courses / teachers / timetable）
  全部是 **Dart fetcher + ZJU CAS 会话**（`zju_auth/`），需要 ZJU_USERNAME/ZJU_PASSWORD。
- `classroom`（智云课堂）是**课程回看元数据**（education.cmc.zju.edu.cn 等，登录态）；
  本插件是**图书馆讲座公告**（公开页，免登录）——数据域不同、无需凭据、无重叠。
- 命名无冲突：内置类型名与 `zju_lectures` 不同；持久化键 `zju_lectures` 亦不冲突。

## 已知局限 / 未决问题

1. 覆盖范围为图书馆讲座公告，非全校讲座（见上「范围诚实声明」）。
2. 站点为 CMS 模板，若 `news_title` / `news_meta` 类名变更，脚本会报「未解析到任何
   讲座条目」错误（不会静默返回空数据冒充成功）。
3. 官方「学术公告」频道（www.zju.edu.cn/xs）无日期/链接的公开接口，若后续平台侧
   增加 Dart fetcher（复用 zju_modle CAS 会话）直连校内学术公告 API，可作为扩展类型
   `zju_academic` 并入，本插件结构（items 数组）可直接复用。
