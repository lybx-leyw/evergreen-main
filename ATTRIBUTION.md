# 致谢与开源许可

> Evergreen Multi-Tools 建立在多个优秀开源项目的基础上。
> 本文件列出了所有上游项目的归属、许可证信息及合规说明。

---

## 项目谱系

### ZJU-live-better — 原始 Node.js 项目（Evergreen 的起点）

- **项目**: ZJU-live-better — 浙江大学实用脚本集合
- **作者**: [@5dbwat4](https://github.com/5dbwat4) 及社区贡献者
- **仓库**: https://github.com/5dbwat4/ZJU-live-better
- **许可证**: GNU General Public License v3.0 (GPL-3.0-only)

**关系说明：**

Evergreen 项目始于 ZJU-live-better，经历了两个阶段：

- **预发布版（未公开发布）** — 在 ZJU-live-better 的 Node.js 代码基础上直接开发，扩展了课程待办抓取、课件下载、智云课堂 PPT 转 Markdown、图书馆借阅等功能。此版本作为原型验证了"多工具集成桌面应用"的可行性，为后续重构积累了完整的功能需求和 API 交互经验。**此版本未对外发布**，其全部工作基于 ZJU-live-better 社区贡献者的开源代码完成，在此深表感谢。
- **Evergreen v1.0（当前版本）** — 使用 **Dart / Flutter** 对预发布版进行了**完全重写**——不保留原始 JavaScript 源代码，而是基于相同的功能设计、业务逻辑和 API 交互模式，以桌面应用形态重新实现。新增了 Agent AI 助手、FSRS 背词、智能调度、一卡通等模块。

以下设计元素继承自 ZJU-live-better（预发布版）：
- 功能模块划分（courses / classroom / library / todolist）
- ZJU SSO 认证流程（RSA 加密 → CAS 登录）
- 各子系统的 API 端点和交互模式
- 配置管理方式（.env + 环境变量）
- "学在浙大·智云课堂·图书馆" 三位一体定位

**合规说明：** 根据 GPL-3.0 第 5 条，本派生作品同样以 GPL-3.0 许可证发布。原始项目的版权声明和许可证文本随附于本仓库的 LICENSE 文件中。

---

## 设计参考与算法来源

### Reasonix → Greenix — Agent 运行时

- **上游项目**: Reasonix — AI 编码助手的 Agent 运行时（Go 实现）
- **作者**: Reasonix 贡献者
- **仓库**: https://github.com/esengine/reasonix
- **许可证**: MIT License

Evergreen 的 AI 助手内核命名为 **Greenix**——基于 Reasonix Go 实现全量移植到 Dart，并在此基础上做了大量扩展和 ZJU 场景适配。

**从 Reasonix 移植的架构层（`core/agent/` 核心框架）：**

| 模块 | 对应 Reasonix 源 | 说明 |
|---|---|---|
| `message.dart` | `internal/provider/provider.go` | 消息/角色/ToolCall 数据模型 |
| `event.dart` | `internal/event/event.go` | 17 种类型化事件 + EventSink |
| `tool.dart` | `internal/tool/` | Tool 接口 + Registry + Previewer |
| `provider.dart` | `internal/provider/` + `provider/openai/` | LLM Provider 抽象 + DeepSeek 流式实现 |
| `agent/agent.dart` | `internal/agent/agent.go` | Agent 主循环 + StormBreaker + FinalReadiness |
| `agent/session.dart` | `internal/agent/session.go` | 会话管理 + token 统计 |
| `agent/compose.dart` | `internal/control/` Compose 逻辑 | 消息组装框架 |
| `agent/gate.dart` | `internal/permission/` | 权限门控 |
| `agent/hooks.dart` | `internal/hook/` | 工具钩子（pre/post tool use） |
| `controller/` | `internal/control/controller.go` | 传输无关的会话驱动器 |
| `memory/` | `internal/memory/` | 四类记忆 + 文件存储 + MEMORY.md 索引 |
| `skill/` | `internal/skill/` | 技能加载器 + 索引（路径已改为 `.greenix/skills/`） |
| `output_style/` | `internal/outputstyle/` | 输出风格系统 |
| `evidence/` | `internal/evidence/` | 工具调用证据分类账本 |
| `compact/` | `internal/agent/compact.go` | 上下文压实（三档阈值） |

**Greenix 在 Reasonix 基础上的原创扩展：**

| 模块 | 说明 |
|---|---|
| ZJU 系统提示词 | `compose.dart` 中的 `defaultSystemPrompt` 和 `defaultToolHint`——从通用编码助手改写为浙大教学助手角色，包含数学公式渲染规则、工具调用强制策略、频率限制等 |
| `ZjuDataSource` 接口 | `tools/zju_data_source.dart`——Agent 工具与 Flutter Provider 之间的解耦桥梁，使工具层不依赖 Riverpod |
| 8 个 ZJU 业务工具 | `tools/zju_courses.dart` / `zju_scores.dart` / `zju_classroom.dart` / `zju_ecard.dart` / `zju_todos.dart` / `zju_exams.dart` / `semester_info.dart` / `web_search.dart`——全部为浙大场景原创 |
| Flutter 集成层 | `features/agent/chat_screen.dart` + `features/agent/providers/agent_provider.dart`——将 Greenix Agent 嵌入 Flutter UI，连接 Riverpod 状态管理 |

每个移植模块的文件头部保留了指向 Reasonix 原始 Go 源的文档注释（如 `/// 对应 reasonix/internal/...`），原创部分则无此标记。

### Celechron — 成绩计算 & 架构参考

- **项目**: Celechron — 浙大学生时间管理器（Flutter 实现）
- **作者**: Celechron 团队
- **仓库**: https://github.com/Celechron/Celechron
- **许可证**: GNU General Public License v3.0

**引用范围（以下模块的设计/算法源自 Celechron）：**

| 模块 | 引用内容 | 性质 |
|---|---|---|
| `core/models/grade.dart` | GPA 多制式换算映射表、`realId` 归一化、`earnedCredit` 计算逻辑 | 算法重实现（Dart） |
| `core/utils/gpa_calculator.dart` | `pickFirstAttempt` / `pickHighestAttempt` 重考策略 | 算法重实现（Dart） |
| `core/storage/database.dart` | `WebCacheDatabase` 的缓存模式（`setCachedWebPage` / `getCachedWebPage`） | 设计模式移植 |
| `core/network/auth_interceptor.dart` | 会话过期检测 + `_withAutoRelogin` 自动重登模式 | 设计模式移植 |
| `features/auth/providers/auth_provider.dart` | 共享 `HttpClient` 避免 cookie 累积 bug 的架构方案 | 架构模式移植 |
| `features/auth/services/zjuam_service.dart` | RSA 加密 + CAS 登录的完整流程设计 | 流程重实现（Dart） |
| `features/zdbk/services/zdbk_service.dart` | ZDBK 教务系统 API 交互模式、CAS service validation | 流程重实现（Dart） |
| `features/scheduler/services/flow_scheduler.dart` | Flow 调度算法 | 算法重实现（Dart） |

上述模块均以 Dart 语言全新编写，包含了指向 Celechron 原始实现的文档注释（如 `/// Celechron reference: ...`），GPA 映射表等数据直接引用自 Celechron 源码。

### Qwerty Learner → WordPecker — 背词引擎

- **上游项目**: Qwerty Learner — 为键盘工作者设计的单词记忆与英语肌肉记忆锻炼软件
- **作者**: [RealKai42](https://github.com/RealKai42) 及社区贡献者
- **仓库**: https://github.com/RealKai42/qwerty-learner
- **许可证**: GNU General Public License v3.0

Evergreen 的背词模块 **WordPecker** 基于 Qwerty Learner 的打字记忆交互模式全量移植到 Dart，并在此基础上做了大量扩展。

**从 Qwerty Learner 移植的交互层：**

| 模块 | 说明 |
|---|---|
| `features/wordpecker/screens/wordpecker_screen.dart` | 打字背词交互模式：显示释义 → 用户键入单词 → 实时反馈正确/错误 → 统计正确率/速度 |
| `features/wordpecker/screens/stats_screen.dart` | 学习统计可视化（复用 Qwerty Learner 的数据维度设计） |

**WordPecker 在 Qwerty Learner 基础上的原创扩展：**

| 模块 | 说明 |
|---|---|
| FSRS 间隔重复 | `services/fsrs_service.dart` — 以 FSRS-5 算法替换原项目的简易复习调度，根据用户每次评分动态调整复习间隔 |
| AI 词源分析 | `services/etymology_service.dart` — 调用 DeepSeek API 解析单词词根、词缀、语源，辅助深层记忆 |
| 本地教材词库 | `services/dictionary_service.dart` — ZJU 大学英语教材词库，与课程同步 |
| 闪卡模式 | 翻转卡片复习（正反面），区别于打字模式 |

移植的交互代码以 Dart 语言全新编写，FSRS 调度引擎、AI 词源分析、教材同步词库均为原创。

---

## 内嵌数据致谢

### 教师评分数据 — Lazuli

- **运行副本**: `assets/data/teacher_ratings.json`（app 运行时会更新评分和热度）
- **原始副本**: [`docs/reference/teacher_ratings_original.json`](docs/reference/teacher_ratings_original.json)（冻结对照，永不被修改）
- **来源**: Lazuli — 浙江大学教务系统增强插件
- **作者**: [ADSR1042](https://github.com/ADSR1042)
- **仓库**: https://github.com/ADSR1042/Lazuli
- **许可证**: GNU General Public License v3.0

该数据集包含浙江大学教师的公开评分信息，仅用于教学辅助用途。

**运行时修改声明：** 本应用在运行时会**覆写此文件**的 `rate`（评分）和 `hot`（热度）字段——从 `chalaoshi.top` 在线抓取最新数据后写回磁盘持久化。修改逻辑位于 [`lib/features/teachers/services/chalaoshi_service.dart`](lib/features/teachers/services/chalaoshi_service.dart) 的 `_mergeOnlineResults()` 和 `_saveToLocal()` 方法。文件结构、教师 `id`/`name`/`py`/`sx`/`xy` 字段及学院数据**保持不变**，仅评分数值被更新。

根据 GPL v3 第 5 条的要求：完整源代码可在上述仓库获取，任何修改必须标明，数据以"原样"提供且无任何担保。

---

## 第三方依赖许可

本项目的 Flutter/Dart 依赖项（定义于 `pubspec.yaml`）各自采用独立的开源许可证。主要第三方库包括：

| 依赖 | 许可证 |
|---|---|
| flutter (BSD-3-Clause) | 应用框架 |
| flutter_riverpod (MIT) | 状态管理 |
| go_router (BSD-3-Clause) | 路由 |
| dio (MIT) | HTTP 客户端 |
| drift (MIT) | SQLite ORM |
| media_kit (MIT) | 视频播放 |
| fl_chart (MIT) | 图表 |
| pointycastle (MIT) | RSA 加密 |
| 其余依赖 | 见各包的 LICENSE 文件 |

---

## 本项目的许可证

**Evergreen Multi-Tools v1.0** 以 **GNU General Public License v3.0 (GPL-3.0)** 发布。

完整的许可证文本见本仓库根目录下的 [LICENSE](./LICENSE) 文件。

在线版本：https://www.gnu.org/licenses/gpl-3.0.html

```
Evergreen Multi-Tools — ZJU 多功能集成桌面应用
Copyright (C) 2024-2025  Evergreen Multi-Tools 贡献者

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
```

---

## 免责声明

本项目仅供学习交流使用，请勿用于任何商业用途，请勿用于任何非法或违规用途。使用本项目前请务必了解并遵守浙江大学相关政策和规定。作者不对因使用本项目而导致的任何后果负责。

*最后更新：2025-07*
