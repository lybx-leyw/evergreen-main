# Core

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | core 声明层 |

> 示例 `example/`、子模块 `agent/` `config/` `data/` `module/` `theme/` `services/` `utils/` `plugin/` `feedback/`、工具 `errors.dart` `log.dart` `result.dart`、测试 `test/`

Evergreen 平台底层依赖——对外提供统一的模块注册、AI 基建、OCR 服务、文件工作区等基础能力。

> **用户插件创作事实**：用户侧主路径是 **HTML 插件**。用户通过 `html-creator` 编写 HTML/CSS/JS，
> 导出为 `plugins/<id>/module/index.html + manifest.json`（`"template":"html"`），由 `html_modle` 渲染。
> 本目录中的 JSON 声明模块、`.exe` 数据源/Agent 工具属于平台/开发者模式能力，供高级插件和内置功能使用。

---

## 子模块

| 模块 | 说明 | 文档 |
|------|------|------|
| `agent/` | AI 运行时核心——Agent 主循环、Tool 注册、Memory、Skill、插件桥接 | [`agent/README.md`](agent/README.md) |
| `config/` | 应用配置——设置项声明、plugin 配置热加载 | [`config/README.md`](config/README.md) |
| `data/` | 数据管线——DataType 注册、插件数据源加载、缓存 | [`data/README.md`](data/README.md) |
| `module/` | 模块注册——manifest.json 驱动、路由生成、导航配置、UI 范式声明 | [`module/README.md`](module/README.md) |
| `theme/` | 主题注册——theme.json 驱动的全局配色方案 | [`theme/README.md`](theme/README.md) |
| `services/` | 平台服务——OCR、插件安装、更新、Core HTTP、GitHub 集成、同步中心导入 | [`services/README.md`](services/README.md) |
| `utils/` | 通用工具——安全解析、Token 估算、Python 环境、运行路径、资产释放、文件管理 | [`utils/README.md`](utils/README.md) |
| `plugin/` | 插件运行器——桌面子进程 / 安卓 Chaquopy 统一抽象 | — |
| `feedback/` | 用户反馈——浮窗入口、反馈表单、Issue 发布、截图 | — |

## 核心工具

| 文件 | 说明 |
|------|------|
| `errors.dart` | `AppError` — 应用层错误（Network / Auth / Parse / Cache / Timeout / Validation / Media / AI / Config / File / DataIntegrity / Render / …） |
| `log.dart` | `Log` — 日志单例（debug→stderr、release→文件轮转） |
| `result.dart` | `Result<T>` — Dart 3 sealed class（Ok / Err + map / flatMap / fold） |

---

## 插件目录规范

所有插件统一放在 `plugins/<name>/` 下，按功能类型分子目录，避免不同模块的扫描器互相干扰：

```
plugins/<name>/
  module/index.html               ← HTML 插件（用户侧主路径，可含 css/js 等静态资源）
  module/manifest.json            ← 页面模块声明（HTML 插件模板为 "template":"html"）
  agent/manifest.json + .exe      ← AI 工具（开发者模式，PluginBridge 扫描）
  theme/theme.json                ← 配色主题（ThemeLoader 扫描）
  data/manifest.json              ← 数据源（开发者模式，DataSourceLoader 扫描）
  config/config.json              ← 配置项（SettingsLoader 扫描）
```

一个插件可同时提供多种类型——取名相同、各子目录互不冲突。

---

## 规则

- 子模块通过 barrel 导出公共 API；含 Flutter 依赖的服务（如 `services/release_downloader.dart`）保持直接 import，不进 barrel。
- 子模块间的依赖通过 `package:evergreen_base/core/` 路径引用。
- agent、config、data、module、theme 五个模块由专门工程师维护，其余模块不可修改。
