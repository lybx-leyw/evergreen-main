# AI 变更日志 —— 供下一位 AI 接手的详细说明

> **日期**：2026-07-07  
> **工作分支**：main  
> **最后 commit**：`0a6fae0`（在此之上的一系列本地修改，尚未 commit）

---

## 一、总体变更概览

本次工作围绕 Evergreen 项目的 Agent 子系统做了上下游全线优化：新增工具选项面板、多级深度思考参数、AI 驱动 Skill 生成、渲染层视觉优化，以及修复了一个测试卡死问题。所有改动保持了上中下游三层架构的边界约束，未引入新框架依赖。

---

## 二、文件变更清单

### 修改的文件

| 文件 | 变更类别 | 说明 |
|------|---------|------|
| `evg-base/lib/providers.dart` | 上游 | 新增 `toolRegistryProvider`、`toolDisabledProvider`、`essentialToolNames` 常量、`isEssentialTool()` 函数 |
| `evg-base/lib/main.dart` | 上游 | 工具禁用状态持久化加载/保存；改用 `resolvePythonExe()` 多级回退查找 Python；覆盖新增的 Riverpod provider |
| `evg-base/lib/core/agent/agent_runtime.dart` | 上游 | 新增 `reasoningEffortProvider`（五档）；`deepThinkingEnabledProvider` 改为双向同步兼容 |
| `evg-base/lib/core/agent/provider.dart` | 上游 | 更新 `setReasoningEffort()` 注释 |
| `evg-base/lib/core/agent/agent.dart` | 上游 | barrel 导出新增 `skill_generator.dart` |
| `evg-base/lib/core/utils/python_env.dart` | 上游 | `resolvePythonExe()` 优先级调整：configuredPath 提到 scripts/python 之前 |
| `evg-base/lib/renderer/shared/chat_controller_view.dart` | 下游 | 新增工具选项面板（`_showToolsSheet`、`_ToolTile`、`_confirmDisableEssential`、`_applyToggle`）；多级 effort 选择器（`_EffortSelector`）；嵌入式输入栏加工具图标 |
| `evg-base/lib/renderer/shared/chat_view.dart` | 下游 | 添加 `_MiniEffortSelector` 替代旧 bool 开关 |
| `evg-base/lib/renderer/widgets/chat_input_bar.dart` | 下游 | 添加 `_EffortButton` 替代旧深度思考按钮 |
| `evg-base/lib/renderer/shared/composite_view.dart` | 下游 | TabBar 视觉优化（3px 指示线 + emoji 分离渲染）；Slot 卡片加阴影和圆角 |
| `evg-base/lib/renderer/widgets/app_shell.dart` | 下游 | 侧边栏 hover/splash 颜色反馈 |
| `evg-base/test/sprint2_test.dart` | 测试 | `main()` 顶部加 `SharedPreferences.setMockInitialValues({})` |
| `evg-base/windows/CMakeLists.txt` | 构建 | 加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 兼容新版 MSVC |

### 新增的文件

| 文件 | 说明 |
|------|------|
| `evg-base/lib/core/agent/skill/skill_generator.dart` | AI 驱动的 Skill 内容生成器 |
| `.internal/01-接轨文件.md` | AI 认知：项目全局理解，每次 pull 后需重写 |
| `.internal/02-上游说明.md` | AI 认知：core/ 层结构、原理、效果 |
| `.internal/03-中游说明.md` | AI 认知：plugins/ 层结构、原理、效果 |
| `.internal/04-下游说明.md` | AI 认知：renderer/ 层结构、原理、效果 |
| `.internal/05-变更内容简述.md` | AI 认知：最近一次 pull 的变更记录 |
| `.internal/README.md` | AI 认知：文件夹说明与维护规则 |
| `补丁日志.md` | 人类可读的简洁变更摘要 |
| `AI_CHANGES_LOG.md` | 本文件 |

### 删除的文件

| 文件 | 原因 |
|------|------|
| `evg-base/test/_debug_hang_test.dart` | 调试文件，含编译错误（括号不匹配） |

---

## 三、各功能模块详细说明

### 3.1 Agent 工具选项面板

**目标**：用户可以在聊天界面查看所有已注册的 Agent 工具，并通过 Switch 开关启用/禁用。

**上游部分**（`providers.dart`）：

```dart
// 新增 provider，由 main.dart 注入实际的 Registry 实例
final toolRegistryProvider = Provider<Registry>((ref) {
  throw UnimplementedError('...');
});

// 被用户禁用的工具名集合，UI 响应式读取
final toolDisabledProvider = StateProvider<Set<String>>((ref) => {});

// Agent 基础功能所必需的工具——禁用时弹出警告
const essentialToolNames = {'read_global_memory', 'write_global_memory', 'read_file', 'write_file'};
bool isEssentialTool(String name) => essentialToolNames.contains(name);
```

**上游部分**（`main.dart`）：
- 注册所有工具后，从 `prefs.getString('tool_disabled')` 读取逗号分隔的禁用名列表
- 调用 `toolRegistry.disable(name)` 应用
- ProviderScope.overrides 中注入 `toolRegistryProvider` 和 `toolDisabledProvider`

**下游部分**（`chat_controller_view.dart`）：
- 全屏模式：输入栏工具栏行添加 `[🔧 工具]` `_ToggleChip`
- 嵌入模式：输入框左侧添加 `IconButton(handyman_outlined)`
- 点击后弹出 `showModalBottomSheet` + `DraggableScrollableSheet`，内含 `Consumer` 响应式工具列表
- 每个工具行（`_ToolTile`）：图标（从名称推断）+ 名称 + 描述 + 标签（「核心」/「只读」）+ Switch
- 核心工具禁用时弹出 `AlertDialog` 警告具体影响
- 切换后同步更新 Registry + SharedPreferences + Riverpod state

**注意事项**：
- 底层面板内部使用了 `Consumer` 确保 toggle 后 UI 即时响应
- 工具名含逗号会破坏 `tool_disabled` 持久化格式（已知问题）
- 不影响现有 `Registry.disabled` 机制，只是暴露到 UI

### 3.2 多级深度思考参数

**目标**：将深度思考从二元开关扩展为五档选择（关/低/中/高/最强），对应 DeepSeek API 的 `reasoning_effort` 参数。

**上游**（`agent_runtime.dart`）：

```dart
// 主入口：五档 effort
final reasoningEffortProvider = StateProvider<String>((ref) => 'off');
const validReasoningEfforts = ['off', 'low', 'medium', 'high', 'max'];

// 旧 provider 保留，与 reasoningEffortProvider 双向同步
final deepThinkingEnabledProvider = StateProvider<bool>((ref) => false);
```

`agentRuntimeProvider` 内两个 listener：
1. `reasoningEffortProvider` listener → 设置 `provider.setThinking()` + `provider.setReasoningEffort()` + 更新 system prompt；同步 `deepThinkingEnabledProvider`
2. `deepThinkingEnabledProvider` listener → 旧 UI 写入 bool 时反向同步到 `reasoningEffortProvider`

**上游**（`provider.dart`）：
- `setReasoningEffort()` 注释更新为支持所有五个值

**下游**：
- `chat_controller_view.dart`：`_EffortSelector` 芯片 + `showMenu()` 弹出菜单（带图标和描述）
- `chat_view.dart`：`_MiniEffortSelector` 迷你版
- `chat_input_bar.dart`：`_EffortButton` 按钮版

**已知问题**：
- 芯片点击后弹出菜单正常，但选中后芯片视觉状态更新偶有延迟（需 pump 一次）
- `_MiniEffortSelector` 和 `_EffortButton` 菜单项较少信息（仅文字），与主 `_EffortSelector` 不完全一致

### 3.3 AI 驱动 Skill 生成

**目标**：用户用自然语言描述需求，AI 自动生成完整 Skill Markdown（含 frontmatter + body）。

**位置**：`evg-base/lib/core/agent/skill/skill_generator.dart`

**核心 API**：

```dart
final result = await SkillGenerator.generate(
  provider: deepSeekProvider,
  requirements: '需要一个帮我整理桌面文件的技能',
  name: 'desktop-organizer', // 可选
);
if (result.isSuccess) {
  // result.skill.name / description / body 可预览，调用方负责存盘
} else {
  // result.error 含错误信息
}
```

**内部流程**：
1. 构造 system prompt：教 LLM Skill 的 YAML frontmatter + Markdown body 格式及最佳实践
2. 构造 user prompt：用户的需求描述
3. 调用 `Provider.chat()` 流式获取响应，收集所有 `ProviderEvent.content` 拼接
4. 自动去除 LLM 可能包裹的 ``` 代码块
5. 正则解析 frontmatter 提取 name / description / run_as
6. 返回 `SkillGenerateResult`（成功含 Skill 对象，失败含 error）
7. 不自动保存——调用方拿到 Skill 后自行决定是否写入 `.md` 文件

**容错**：
- 空需求 → error
- LLM 返回空内容 → error
- 无 frontmatter → 从首行提取名称为 name
- 无 description → 用 name 填充
- LLM 调用异常 → error

**导出**：`agent.dart` barrel 文件已添加 `export 'skill/skill_generator.dart'`

**状态**：仅上游完成。下游 `SkillManagementView` 的 `_NewSkillDialog` 尚未接入此 API。

### 3.4 渲染优化

**TabBar**（`composite_view.dart`）：
- `_buildTabBar` 重写：指示线粗 3px + 圆角 + 颜色跟随主题 primary
- `_buildTab` 新增 emoji 检测（rune 判断），emoji 前缀与文字分离为 Row 布局
- TabBar 增加 `splashBorderRadius: 8` 圆角波纹
- 容器加微阴影 `elevation: 1`

**Slot 卡片**（`composite_view.dart`）：
- `_buildSlotCard` 升级：`BorderRadius.circular(10)` + `boxShadow`（0.04/0.12 透明度）
- 边框色按暗亮模式区分

**侧边栏**（`app_shell.dart`）：
- 所有 `InkWell` 增加 `hoverColor`（主题色 8% 透明）、`splashColor`（12%）、`highlightColor`（4%）
- `_NavItem` 增加 `AnimatedContainer`（200ms）包裹 padding

### 3.5 flutter test 卡死修复

**问题**：`sprint2_test.dart` 中两个 SettingsView 测试调用了 `SharedPreferences.getInstance()`，在测试环境无平台通道时永久挂起。

**根因**：SettingsView 重写后直接调用 SharedPreferences（不再通过 HTTP 代理 settings.exe），但测试未同步更新——缺少 `SharedPreferences.setMockInitialValues({})`。

**修复**：`test/sprint2_test.dart` 的 `main()` 函数顶部加入 `SharedPreferences.setMockInitialValues({})`。

**附加**：删除了 `test/_debug_hang_test.dart`（调试文件，含括号不匹配编译错误）。

---

## 四、架构边界说明

以下内容**未做更改**，请勿误认为需要修复：
- Agent 主循环（`agent.dart`）逻辑未变
- StormBreaker 抑制机制未变
- Compactor 压缩逻辑未变
- HTTP API（`agent_http_server.dart`）未变
- ModuleDescriptor、ModuleRegistry、ModuleLoader 核心逻辑未变
- PluginBridge 插件发现机制未变
- `.exe` 进程管理未变

---

## 五、给下一位 AI 的建议

1. **下游 UI 对接**：Skill 生成的 AI 能力（上游已完成）需要接入 `SkillManagementView`，在 `_NewSkillDialog` 中增加「AI 生成」按钮，调用 `SkillGenerator.generate()` 后将结果填入表单供用户预览和修改。

2. **多级 effort UI 完善**：当前三个文件的 effort 选择器各自独立实现（`_EffortSelector` / `_MiniEffortSelector` / `_EffortButton`），存在代码重复。建议提取为共享 widget。

3. **展示大厅问题**：`现在在做的事情.md` 中列出的展示大厅缺陷仍未处理——HTML/Dart 渲染不一致、Dart 版本组件功能缺失。这些属于展示层问题，不影响核心 Agent 功能。

4. **补丁日志维护**：本项目根目录 `补丁日志.md` 用于记录人类可读的变更。`.internal/` 文件夹是内部 AI 认知缓存，每次 `git pull` 后需重写其中 5 个文件并更新 `05-变更内容简述.md`。
