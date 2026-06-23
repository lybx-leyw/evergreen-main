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

Evergreen 项目的灵感最早可追溯到 ZJU-live-better，经历了多个迭代阶段：

- **内部原型（未公开）** — 基于 ZJU-live-better 的 Node.js 代码快速搭建的概念验证版本，用于探索"多工具集成桌面应用"的可行性。此阶段纯属内部试验，**从未公开发布**，仅为后续正式开发积累了 API 交互经验和功能需求。
- **v0.9.0_alpha.1（预发布版）** — 使用 **Dart / Flutter** 从零构建的第一个桌面应用版本，不再保留任何原始 JavaScript 源代码。此版本确立了 Flutter 桌面端的技术路线，为 v1.0 奠定了基础。自研 Agent 运行时（Greenix）、奥尔波特特质理论记忆系统、热加载 Skill 系统、两级 OCR Pipeline、FSRS 背词引擎等核心模块均为原创设计。
- **v1.3.0（当前版本）** — 在 v1.2 基础上的进一步迭代；新增 Palace 认知中间件（事件采集·AI 提炼·教训冶炼·认知回响），功能模块 17 个。

以下设计元素继承自 ZJU-live-better（内部原型阶段）：
- ZJU SSO 认证流程（RSA 加密 → CAS 登录）的基本思路
- 部分教务子系统的 API 端点发现

> ⚠️ 图书馆、一卡通、自动签到、RVPN、答题等模块已在当前版本中**停用**（后端不可用或未经完整测试），代码仅供开发者预览。实际可用的功能模块已大幅超出 ZJU-live-better 的原始范围。

**合规说明：** 根据 GPL-3.0 第 5 条，本作品以 GPL-3.0 许可证发布。原始项目的版权声明和许可证文本随附于本仓库的 LICENSE 文件中。

---

## 设计参考与算法来源

### MemGovern — AI Agent 治理与贡献规范

- **上游项目**: MemGovern — AI Agent 治理框架（经验库 + 规则系统）
- **作者**: MemGovern 贡献者
- **仓库**: https://github.com/esengine/memgovern
- **许可证**: MIT License

Evergreen 的 **Agent 贡献规范**（`agent_contributing/`）受 MemGovern 的治理框架启发而设计。

**引用范围：**

| 模块 | 说明 |
|---|---|
| `agent_contributing/SKILL.md` | Agent 贡献技能文件——定义"先读规则→翻经验→再动手"的工作流范式 |
| `agent_contributing/EXPERIENCE.md` | 经验库索引——标签化踩坑记录、成功/失败双轨制 |
| `agent_contributing/experiences/*.md` | 经验卡片——含 task_type/tags/files_touched/outcome frontmatter 的结构化案例 |
| `AGENT_CONTRIBUTING.md` | AI Agent 行为约束——禁止清单、PR 自检表、完整交付流程 |

上述系统为 Evergreen 原创设计（Dart/Flutter 场景定制），但在 Agent 治理的核心理念上承袭了 MemGovern 的"规则 + 经验"双层架构思想。

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

> ⚠️ Flow 调度模块已随智能调度功能一并暂停。另需说明，上述引用属于**设计/算法层面的参考**，Evergreen 在此基础上进行了大量独立的架构设计和功能扩展（如自研 Agent 运行时、记忆系统、Skill 热加载、两级 OCR 等），远非简单集成。

### PDFMathTranslate-next — PDF 翻译引擎

- **上游项目**: PDFMathTranslate-next — 基于 BabelDOC 的 PDF 科学论文翻译与双语对照工具
- **作者**: [@awwaawwa](https://github.com/awwaawwa) 及社区贡献者
- **仓库**: https://github.com/PDFMathTranslate-next/PDFMathTranslate-next
- **许可证**: GNU Affero General Public License v3.0 (AGPL-3.0)

Evergreen 的 **PDF 翻译** 模块将 PDFMathTranslate-next 的 `pdf2zh_next` 引擎源码内置于 `scripts/pdf2zh_next/`，通过 Python 子进程调用，实现 DeepSeek API 驱动的高质量 PDF 翻译，输出保留排版、公式、图表的双语对照 PDF。

**引用范围：**

| 模块 | 说明 |
|---|---|
| `scripts/pdf2zh_next/` | pdf2zh 引擎核心源码（`config/`, `translator/`, `high_level.py`, `utils/`），从上游仓库精简复制，删除了 GUI/CLI/assets 等不必要文件 |
| `scripts/pdf_translate.py` | 翻译子进程包装脚本，调用 `pdf2zh_next` 引擎，通过 JSON 事件流与 Flutter 前端通信 |
| DeepSeek 翻译提示词 | `base_translator.py` 中的翻译 prompt 模板（"You are a professional, authentic machine translation engine..."），移植到 Dart 层 `DeepSeekClient` 调用 |

上述源码以 Python 语言原始形式内置于项目 `scripts/` 目录中，`pdf_translate.py` 包装脚本为 Evergreen 原创。

根据 AGPL-3.0 第 13 条的要求：本项目以 GPL-3.0 许可证发布；pdf2zh 引擎的完整源代码随附于 `scripts/pdf2zh_next/` 目录。

### Qwerty Learner → WordPecker — 背词引擎

- **上游项目**: Qwerty Learner — 为键盘工作者设计的单词记忆与英语肌肉记忆锻炼软件
- **作者**: [RealKai42](https://github.com/RealKai42) 及社区贡献者
- **仓库**: https://github.com/RealKai42/qwerty-learner
- **许可证**: GNU General Public License v3.0

Evergreen 的背词模块 **WordPecker**（⏸ 当前已暂停，代码保留）基于 Qwerty Learner 的打字记忆交互模式以 Dart 重新实现，并在此基础上做了大量原创扩展。

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

**Evergreen Multi-Tools v1.3.0** 以 **GNU General Public License v3.0 (GPL-3.0)** 发布。

完整的许可证文本见本仓库根目录下的 [LICENSE](./LICENSE) 文件。

在线版本：https://www.gnu.org/licenses/gpl-3.0.html

```
Evergreen Multi-Tools — ZJU 多功能集成桌面应用
Copyright (C) 2024-2026  Evergreen Multi-Tools 贡献者

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

*最后更新：2026-06*
