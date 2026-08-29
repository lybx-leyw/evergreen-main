# zju-calendar — 浙大校历（data-source 插件）

> 数据源插件 · 模型 A（CLI 一次性脚本）· 纯 Python 标准库 · 零第三方依赖
> 插件 id：`zju-calendar`（本插件唯一类型：`zju_calendar`）

## 数据源

- **站点**：浙江大学官网「学术日历」结构化页面（公开、免登录、UTF-8 服务端渲染）
  - <https://www.intl.zju.edu.cn/zh-hans/academics/calendar>
- **条目内容**：当前学年的校历事件（秋冬学期 + 春夏学期），含报到注册、开学上课、
  放假调休、考试周、运动会、校庆日等，每条约含 `start` / `end` 日期区间与事件名。
- **范围诚实声明**：本源为浙江大学官网发布的结构化学术日历，事件与全校校历一致；
  主校区校历页（ugrs.zju.edu.cn「浙江大学2026—2027学年校历」）以**图片**形式发布、
  不可机器解析，故采用官网结构化版本；历史学年为 PDF 附件（不可解析），本源仅覆盖
  **当前学年**，学年切换由站点更新自动反映。输出顶层携带 `scope` 字段说明此边界。

## CLI 契约（与平台 `register_data_source.dart` 一致）

```
fetch.py --type zju_calendar --project-root <root> --greenix-config <cfg>
```

- 参数为**空格分隔**（同时兼容 `--type=value` 形态）；未知参数忽略。
- stdout 只输出**单个 JSON 对象（顶层 Map）**，UTF-8；列表包在 `items` 键下。
- **失败**：stdout 输出 `{"error": "<人类可读信息>"}` 且退出码非 0（堆栈只进 stderr/丢弃）。
- 纯标准库（`urllib` / `json` / `re` / `html` / `ssl`），`androidSupport: true`（Chaquopy 可用）。

## 输出结构

```json
{
  "type": "zju_calendar",
  "source": "浙江大学学术日历",
  "source_url": "https://www.intl.zju.edu.cn/zh-hans/academics/calendar",
  "academic_year": "2026-2027",
  "updated_at": "2026-08-29 17:31:00",
  "tls_verified": true,
  "scope": "浙江大学官网发布的结构化学术日历（与全校校历一致）；主校区校历页为图片版，历史学年为 PDF，本源覆盖当前学年",
  "total": 29,
  "semesters": [
    { "semester": "秋冬学期", "academic_year": "2026-2027",
      "events": [ { "start": "2026-09-10", "end": "2026-09-10", "event": "研究生新生报到注册" } ] },
    { "semester": "春夏学期", "academic_year": "2026-2027",
      "events": [ { "start": "2027-02-19", "end": "2027-02-19", "event": "本科生、研究生报到注册，春季入学博士新生报到注册" } ] }
  ],
  "items": [
    { "start": "2026-09-10", "end": "2026-09-10", "event": "研究生新生报到注册", "semester": "秋冬学期" }
  ]
}
```

## 可选项

- 本源为公开免登录数据源，**无需任何登录凭据**；`_get_config` 三级降级
  （GREENIX_CONFIG_PATH 文件 → ConfigHttpServer → 环境变量）保留以兼容平台传参约定。
- `persistentKey: zju_calendar` 启用数据中枢磁盘缓存（TTL 24h）；
  `fallbackJson` 为拉取失败且无旧缓存时的静态兜底（空列表 + 说明，不含伪造数据）。
- **TLS 校验降级（如实标注）**：个别 Windows 机器的 Python/OpenSSL 3.x 加载系统
  CA 证书库会抛 `ASN1: NOT_ENOUGH_DATA`（本地证书库兼容问题，与站点无关）。此时脚本
  自动降级为不校验证书链，并在输出携带 `tls_verified: false` 如实标注，绝不静默冒充
  校验通过；正常机器为 `true`。

## 与 zju-ical 的关系（重复性判断）

- `zju-ical`（ZJU 课表 iCal 导出）输出的是**个人课表**（按学号查教务课表后生成
  RFC 5545 `.ics` 订阅文件），数据域是「我的课表」；
- `zju-calendar`（本插件）输出的是**全校校历**（报到注册/放假/考试周等校历事件），
  数据域是「学校教学日历」。
- 两者**数据语义不同、用途不同、不重复**：iCal 是个人课表导出格式，校历是校级
  日程数据源；命名虽都含「历」，但 `zju_ical` / `zju_calendar` 类型名与持久化键均不冲突。
- 结论：**不建议合并**；各自保持独立，可被同一「校园」数据看板/日历 UI 分别消费。

## 与 zju_modle（内置 Dart 数据源）的关系

- 平台内置 12 个 zju DataType（`zju_modle/zju_data_sources.dart`）全部为
  **Dart fetcher + ZJU CAS 会话**（`zju_auth/`），需要 ZJU_USERNAME/ZJU_PASSWORD，
  且**不包含校历类型**（grep 无 ical/calendar/校历 service）。
- 本插件是**全校校历**（公开页，免登录）——数据域不同、无需凭据、无重叠；
  类型名 `zju_calendar` 与内置类型无冲突。

## 已知局限 / 未决问题

1. 覆盖**当前学年**（站点每次只发布当前学年的结构化事件；历史学年为 PDF 不可解析）。
2. 站点为 CMS 模板，若 `cal-date` / `cal-event` / `cal-title` 类名变更，脚本会报
   「未解析到任何校历事件」错误（不会静默返回空数据冒充成功）。
3. 若后续平台侧希望覆盖主校区图片版校历或历史学年，可增加 Dart fetcher（复用
   zju_modle CAS 会话 + OCR/人工录入）作为扩展类型，本插件结构（items 数组）可直接复用。
