# Core

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | core 声明层 |

> 示例 `example/`、子模块 `agent/` `config/` `data/` `module/` `theme/` `services/` `utils/`、工具 `errors.dart` `log.dart` `result.dart`、测试（待添加）

Evergreen 平台底层依赖——对外提供统一的模块注册、AI 基建、OCR 服务、文件工作区等基础能力。

---

## 子模块

| 模块 | 说明 | 文档 |
|------|------|------|
| `agent/` | AI 运行时核心——Agent 主循环、Tool 注册、Memory、Skill、插件桥接 | [`agent/README.md`](agent/README.md) |
| `config/` | 应用配置——设置项声明、plugin 配置热加载 | [`config/README.md`](config/README.md) |
| `data/` | 数据管线——DataType 注册、插件数据源加载、缓存 | [`data/README.md`](data/README.md) |
| `module/` | 模块注册——manifest.json 驱动、路由生成、导航配置、UI 范式声明 | [`module/README.md`](module/README.md) |
| `theme/` | 主题注册——theme.json 驱动的全局配色方案 | [`theme/README.md`](theme/README.md) |
| `services/` | 平台服务——OCR 文字识别、应用更新 | [`services/README.md`](services/README.md) |
| `utils/` | 通用工具——安全解析、Token 估算、Python 环境、运行路径、文件管理 | [`utils/README.md`](utils/README.md) |

## 核心工具

| 文件 | 说明 |
|------|------|
| `errors.dart` | `AppError` — 13 种应用层错误（Network / Auth / Parse / AI / File / Render / …） |
| `log.dart` | `Log` — 日志单例（debug→stderr、release→文件轮转） |
| `result.dart` | `Result<T>` — Dart 3 sealed class（Ok / Err + map / flatMap / fold） |

---

## 插件目录规范

所有插件统一放在 `plugins/<name>/` 下，按功能类型分子目录，避免不同模块的扫描器互相干扰：

```
plugins/<name>/
  agent/manifest.json + .exe      ← AI 工具 (PluginBridge 扫描)
  module/manifest.json            ← 页面模块 (ModuleLoader 扫描)
  theme/theme.json                ← 配色主题 (ThemeLoader 扫描)
  data/manifest.json              ← 数据源 (DataSourceLoader 扫描)
  config/config.json              ← 配置项 (SettingsLoader 扫描)
```

一个插件可同时提供多种类型——取名相同、各子目录互不冲突。

---

## 规则

- 所有子模块通过 barrel 导出全部公共 API。
- 子模块间的依赖通过 `package:evergreen_base/core/` 路径引用。
- agent、config、data、module、theme 五个模块由专门工程师维护，其余模块不可修改。
