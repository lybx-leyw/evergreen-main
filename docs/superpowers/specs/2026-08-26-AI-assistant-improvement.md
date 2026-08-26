# AI 助手插件 · AI 视图优化计划

## 一、文档信息

| 字段 | 内容 |
|------|------|
| 创建日期 | 2026-08-26 |
| 状态 | 规划（待执行） |
| 涉及范围 | AI 助手插件：AI 视图 UI、搜索能力、Agent Tool 工具链、会话管理、文件管理 |
| 任务总数 | 7 个 Task |

## 二、背景与目标

修复 AI 助手插件的 7 个问题域：AI 视图 UI 稳定性、联网搜索能力、Agent Tool 注入与进程管理、统一读文件与 OCR 工具链、会话撤回/分支与滚动体验、工作区文件下载。

## 三、任务分解

### Task 一：AI 视图界面灰黑问题修复

**问题**
- Bug 1.1：文件预览时下滑后最上面的 Bar 变灰黑
- Bug 1.2：对话历史删除/重命名的按键面板背景变灰黑

**决策**：参考 `.codebuddy/memory/2026-08-26.md` 已沉淀经验（该文件不入 git，以下为脱敏要点，以本文档为长期保存）。

**参考经验（脱敏）**

*经验 1｜AppBar 滚动后变灰黑（对应 Bug 1.1）*
- 弯路：`surfaceTintColor: transparent` + `scrolledUnderElevation: 0` 无效（只去 tint 叠加，不阻止底色切换）
- 根因：AppBar 未显式设 `backgroundColor` 时，`scrolledUnder` 状态背景回退到 `colorScheme.surfaceContainer`（深色主题近黑）
- 修复：显式 `backgroundColor: colorScheme.surfaceContainerLowest`，滚动前后一致
- 关键坑：先确认页面走全屏 Scaffold + AppBar 路径还是嵌入工具栏路径（`embedded` 注册），路径不同修法不同

*经验 2｜弹出菜单背景深灰近黑（对应 Bug 1.2，可能同类）*
- 根因：`showMenu()` 的 `color` 参数默认 `surfaceContainer`，深色主题下近黑
- 修复：`showMenu(..., color: colorScheme.surfaceContainerLowest)`
- 关键坑：所有弹出菜单类组件均需显式传色，逐处排查

*经验 3｜去硬编码灰/深色通用规则（Task 一全局约束）*
- 只去中性灰（`Colors.grey.*`）+ 纯黑 + 纯白；大面积品牌蓝也去，小面积品牌色可保留
- 功能色 chip（思考过程语义色）、语义色 `Colors.red`/`orange` 保留
- 全部映射 `Theme.of(context).colorScheme` 语义色，深色自动适配
- 常用映射：`grey.shade100/300` → `surfaceContainerLow/Lowest`；`grey.shade400/600/800` → `outlineVariant/onSurfaceVariant`；`black87` → `onSurface`；primary 背景上的 `white` → `onPrimary`；blue 系 → `primary/primaryContainer`

**验收**：深浅色模式下滚动前后顶部 Bar 颜色一致；删除/重命名等按键面板背景不再是灰黑。

### Task 二：联网搜索能力增强

**问题**
- Bug 2：联网搜索能力可能较差

**决策**：把 skill 创作中心插件中不依赖 ocr 等重依赖工具的部分能力轻量化后集成。

**评估方式（重点）**：难点是修好后不好评估。需撰写**搜索找回测试文件**——本身不会 fail/pass，而是作为 debug 探针检验搜索能力：
- 预设关键词，观察搜索工具能否召回**全面、专业、可靠、时效强**的信息
- 根据探针结果对搜索工具做**多轮迭代**

**验收**：基于探针多次观察并迭代，搜索召回达标。

### Task 三：Agent Tool 插件注入能力增强

**问题**
- Bug 3：注入新的 py tool 功能不够强大

**决策 3.1｜新增 agent tool 示例插件**

在 `evg-base\docs\plugin-registry\examples` 下新增示例插件，并确保放入 plugin 后一定能跑通：

```
evg-base\docs\plugin-registry\examples\example-agent-current_time\
├── agent\manifest.json
├── agent\tool.py
└── README.md
```

与 data 插件的区别：data 插件由平台自动管理并运行 python 文件爬取数据（不是所有 python 工具都应划为 data 插件）；agent 插件由 AI 主动运行某既定 python 脚本（如 `current_time`），平台运行 `tool.py` 并把输出返回给 AI。

关键点：manifest 需注明 `tool.py` 是**一次性进程**还是**常驻进程**：
- 一次性进程：AI 调用该 tool 后即被 kill
- 常驻进程：AI 调用后持续运行，直到 AI 主动 kill 该 tool

**决策 3.2｜后台进程管理 UI 与工具**

为 AI 助手工具新增按钮：UI 显示「后台 N 个 tool 进程运行中」，点击可查看挂起的 tool 名称。新增两个工具：
- 监听（list、listen）：查看后台进程
- kill：结束后台进程

运行模式：
- 后台运行：运行完毕后进程输出自动回填
- wait 模式：直接运行并查看输出

**验收**：示例插件放入 plugin 后 AI 自动注册 `current_time` 工具，调用后返回当前时间。

### Task 四：统一 AI 读文件与 OCR 工具链

**问题**
- Bug 4：AI 助手文件上传和 OCR 能力常常失效（现未接通），设计不够优雅

**决策 4.1**（需在 Task 三之后处理）：统一 AI 读文件工具。底层逻辑改为：用户上传任意类型文件 = 把目标文件放入工作区，并在 message 里填入 prompt（如「用户上传了 xxx 在：xxx 位置 …」）。UI 保持文件夹伪装，不暴露 prompt，让用户有「上传文件给 AI 看」的体感。

**决策 4.2**：将 OCR 工具转成内置 agent tool 插件（相关 py 依赖仍内嵌，安装时按 Android / Windows 分别下载，不给用户下载负担），即把 OCR 脚本工具链搬家到 `plugins/xxx/agent/xxx` 下，变成标准插件格式便于维护。预期注册一个能 OCR pdf 或图片的 tool。

**依赖**：Task 四依赖 Task 三完成（统一 AI 读文件工具链）。

**验收**：用户上传 pdf/图片后，AI 能调用 ocr tool 阅读工作区对应文件。

### Task 五：AI 循环与 effort 参数验证

**问题**
- Bug 5（提示项）：每个 agent 循环里每轮自动调用读全局记忆的工具是**预期行为，不要顺手修改**
- Bug 6：AI 面板可调整 effort（无、low、high 等），但不确定是否有实际底层效果。需静态验证一遍，重点检查 effort 调整是否符合 OpenAI/DeepSeek API 调用的协议标准格式

**验收**：静态验证 effort 传参格式与 API 协议一致，确认面板调整真实作用于请求参数。

### Task 六：撤回功能改造为 edit/branch

**问题**
- Bug 7：改造撤回功能
  - 现状：直接撤回一条消息
  - 目标：撤回按钮改为 edit（branch 工具）。edit 后旧历史不删除，而是开新分支；UI 用「< 2/2 >」按钮切换不同分支
  - 约束：分支不与工作区挂钩；rewind（edit）后开新分支**不会撤销**工作区变更——工作区变更不可逆
- Bug 8：进入已有旧较长会话时不会自动滑到最新 → 添加自动滑动到底即可

**验收**：分支切换 UI 可用；进入会话自动滚动到最新消息。

### Task 七：工作区文件下载

**问题**
- Bug 9：工作区无法下载

**决策 9.1**：AI 助手面板工作区抽屉加「管理文件」按钮，支持下载/删除，支持多选批量处理。下载路径先硬编码一个固定目录（不支持自定义），确保 Android 和 Win 都通用。下载成功弹窗显示路径并支持一键复制（失败也报错）。

**决策 9.2**：给 AI 注册内置 dart 工具 `show_file4u`（4u = for you）。参数为相对路径，效果是向用户展示工作区指定文件：
- UI 出现文件卡片（显示文件名），点击进入文件预览面板（与工作区点击编辑文件相同逻辑，不支持预览的文件也返回同样效果）
- 卡片右侧有下载按钮，点击触发 9.1 的下载，成功弹窗、失败报错

**说明**：9.2 更多是 UI 逻辑，基础设施全部复用 9.1 或已有能力。

## 四、任务依赖与执行顺序

| Task | 依赖 | 说明 |
|------|------|------|
| Task 一 | 无 | 经验已沉淀，可直接执行 |
| Task 二 | 无 | 先撰写搜索探针 |
| Task 三 | 无 | 平台能力建设，先行 |
| Task 四 | Task 三 | 需先统一 AI 读文件工具链 |
| Task 五 | 无 | 静态验证，随时可做 |
| Task 六 | 无 | 独立 |
| Task 七 | 无（9.2 依赖 9.1） | 9.2 复用 9.1 基础设施 |

## 五、风险与注意事项

- Bug 5 为提示项：读全局记忆工具每轮调用是预期，勿顺手修改
- 工作区变更是不可逆的，rewind/edit 不撤销工作区变更
- 下载路径先硬编码，不支持自定义（后续再扩展）
- 搜索评估不依赖 fail/pass，用探针迭代
- `.codebuddy/memory/2026-08-26.md` 不入 git，Task 一关键经验已脱敏内置本文档
