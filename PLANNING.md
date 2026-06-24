# PLANNING — Evergreen Multi-Tools v1.3.1

> 2026 暑假迭代计划 · 内测版 → 稳定版

---

## 概述

- **当前版本**: v1.3.1 内测版（功能模块 17 个：16 个原有 + Palace 认知中间件）
- **目标版本**: v1.3.2
- **时间窗口**: 2026 年暑假
- **用户范围**: 内测用户，暂不公开推广
- **总方针**: 修 Bug > 体验优化 > 功能补全；暂停模块不激活（除非有 PR 或 Issues 强烈反馈）

---

## 已完成

### ✅ Palace 认知中间件（2026-06-23）

- [x] 数据模型：ConsciousnessEvent（意识事件）+ ContextSnapshot（情境快照）+ StructuredLesson（结构化教训）
- [x] EventStore：文件存储 + 三重索引（EVENTS_BY_DATE/TYPE/TAG.md）+ 文件系统扫描回退
- [x] 捕捉管线：QuickCaptureService 编排（写入→AI 摘要→自动标签→教训提取→追问生成）
- [x] Agent 工具：`capture_to_palace` — 用户用自然语言指挥 AI 写入 Palace
- [x] Palace 主页面：类型过滤栏 + 标签栏 + 三层树状视图（类型→日期→卡片）+ 事件详情面板
- [x] 快速捕捉弹窗：手动录入事件（内容 + 类型 + 情绪 + 标签）
- [x] 侧边栏「宫殿」入口（桌面展开/收起 + 移动端抽屉/导航栏）
- [x] `/palace` 路由（fade transition）
- [x] Bug 修复：EventStore 双重实例、📌 emoji 解析、索引回退、空断言安全、Provider 缓存复用、copyWith 清空类型

### ✅ 并行测试脚本 + Release 修复 + 文档同步（2026-06-23）

- [x] 并行测试脚本 `scripts/run_tests_parallel.py`：6 组 job 对齐 CI，含失败明细总结栏
- [x] Release workflow 修复：权限 `actions:read` 缺失导致 `download-artifact` 失败
- [x] 测试文档更新：`CONTRIBUTING.md` §2.4 运行测试 · `AGENT_CONTRIBUTING.md` 步骤 7
- [x] 全量 .md 文档同步：版本号 v1.2→v1.3.0、模块数 16→17、测试数 1006→1067

### ✅ PDF 翻译功能（2026-06-19）

- [x] DeepSeek API 驱动的 PDF 翻译（通过 Python 子进程调用 pdf2zh 引擎）
- [x] 输出保留排版、公式、图表的双语对照 PDF
- [x] 内嵌 PDF 预览、批量翻译、翻译历史
- [x] 设置页面：源/目标语言、Python 路径
- [x] 侧边栏 "PDF 翻译" 入口（AI 工具区）
- [x] 复用 AppConfig.deepseekApiKey，无需额外配置
- [x] 首次使用自动检测 Python 并安装依赖（babeldoc, pymupdf, openai）
- [x] pdf2zh 引擎源码精简至必要部分（config/ translator/ high_level.py），删除 GUI/CLI/资源文件
- [x] SharedPreferences 类型修复：`_healLegacyPrefs()` 启动时统一所有配置键为 String 类型
- [x] 运算符优先级 fix：`translate_screen.dart:267` 的 `??` / `?:` 优先级陷阱导致 String→bool 崩溃

---

## 优先级列表（按顺序执行）

### 1. Agent 渲染优化 + 思维导图修复

**问题**: AI 助手渲染长嵌入块时出现红屏（Flutter 布局溢出 / Markdown 渲染异常）
**目标**: 排查根因，修复长内容块渲染崩溃
**关联**: 子计划 23（Agent 多会话 + Skill）

- [ ] 定位红屏根因（布局溢出 vs 解析崩溃）
- [ ] 修复思维导图/长嵌入块渲染
- [ ] 回归验证：长内容场景不红屏

### 2. 滚动条回归修复

**问题**: 新版意外撤销了课表（Courses）和 AI 笔记（Tutor）页面的滚动栏，导致内容溢出、无法触底
**目标**: 恢复滚动行为，确保内容可完整浏览
**关联**: 子计划 14（Courses）、19（Tutor）

- [ ] 课表页滚动条恢复
- [ ] AI 笔记页滚动条恢复
- [ ] 回归验证：内容溢出 & 触底正常

### 3. 下载逻辑统一优化

**问题**: 下载进度 UI 已实现，但整体下载逻辑分散、未完工
**目标**: 统一下载管理，优化下载体验
**关联**: 子计划 22（Downloads）

- [ ] 梳理现有下载逻辑（课件下载等多处）
- [ ] 统一下载管理接口/状态
- [ ] 优化下载进度 UI & 错误处理
- [ ] 回归验证：各下载场景正常

### 4. Plan 管理 Excel 风格表格优化

**问题**: 计划管理的表格体验不足
**目标**: 优化 Excel 风格表格的功能和交互体验
**关联**: Plan 模块

- [ ] 梳理当前表格功能缺口
- [ ] 优化编辑/选中/复制粘贴等交互
- [ ] 优化视觉效果（对齐、间距、响应式）

### 5. 键盘细致滚动支持

**问题**: 长屏幕中鼠标滚轮粒度不够，无法精细控制滚动位置
**目标**: 支持键盘快捷键进行细致滚动（如方向键逐行、PageUp/PageDown 逐页）
**关联**: 全局 UI

- [ ] 键盘方向键逐行滚动
- [ ] PageUp/PageDown 逐页滚动
- [ ] Home/End 快速跳转首尾
- [ ] 确保与现有快捷键不冲突

### 6. Agent 会话懒加载

**问题**: 会话记忆过长时一次性加载全部，性能差、体验不佳
**目标**: 首屏只加载最近几条，上滑加载更多（类似聊天记录）
**关联**: 子计划 23（Agent 多会话）

- [ ] 实现分页加载逻辑（首屏 N 条）
- [ ] 上滑触底 → "加载更多" 交互
- [ ] 每次展开固定条数，可连续展开
- [ ] 会话切换时重置分页状态

### 7. GitHub Issues 处理

**问题**: Issues 中用户反馈的 BUG 和 IDEAS 待处理
**目标**: 全部 Issues 给予反馈，所有已知 BUG 尽量修复
**关联**: 全局

- [ ] 遍历所有 open Issues，逐一回复/标注
- [ ] 可复现 BUG → 修复
- [ ] 有价值 IDEAS → 标记标签，纳入后续规划
- [ ] 重复/无效 Issue → 关闭并说明原因

---

## 本轮不做

| 事项 | 原因 |
|------|------|
| 背词（WordPecker）激活 | 暂停模块，需完整集成测试 |
| 自动签到（Autosign）激活 | 暂停模块，无试运行机制 |
| 一卡通（Ecard）激活 | BlueWare 认证待实现 |
| 图书馆（Library）激活 | API 端点可能已变更，连接超时 |
| RVPN 激活 | 需 zju-connect Go 二进制，集成不良 |
| Android 端适配 | 可编译 APK，不承诺任何功能可用 |
| AI Tutoring 新功能 | 远期规划（子计划 29） |

> **例外**: 若收到相关 PR 或 Issues 强烈反馈，可重新评估优先级。

---

## 不在此计划但已知的待办

以下条目来自 `docs/ALL_PLANS.md`，本轮不主动推进，但不阻止顺手修复：

- 子计划 02：CI 流程搭建
- 子计划 03：AppConfig 旧静态类清理
- 子计划 04：`tryParse` 安全解析加固
- 子计划 07：NetworkConfig 完善
- 子计划 08：工具类边界测试
- 子计划 09：app.dart 内联登录逻辑抽离
- 子计划 10：ZDBK HTML 解析加固 + 缓存策略
- 子计划 12：Provider `ref.read→ref.watch` 残余修复
- 子计划 13：Scores 懒加载/图表交互
- 子计划 15：Exams 倒计时精确到秒
- 子计划 16：Todo 多源聚合/优先级
- 子计划 26：Android 可编译但无功能承诺

---

*创建于 2026-06-16 · 更新于 2026-06-24（UI 溢出修复，版本升至 v1.3.1）*
