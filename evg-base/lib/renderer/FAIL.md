# FAIL.md — Renderer 模块踩坑记录

## 1. 日志对象是 `Log()` 不是 `evgLog`

- **问题**：在 `composite_view.dart` 中添加诊断日志时，使用了 `evgLog.info()` / `evgLog.warn()`，编译报错 `The getter 'evgLog' isn't defined`。
- **根因**：`package:evergreen_base/core/log.dart` 导出的日志类是 `Log`（单例模式），调用方式为 `Log().info()` / `Log().warn()` / `Log().error()`。
- **教训**：添加日志前先确认该模块实际使用的日志 API 名称，不要凭记忆或猜测。

## 2. `replace_in_file` 拆分 `switch` 表达式需同步修复变量名和结尾语法

- **问题**：在 `SlotDispatch.build()` 中插入诊断日志时，将原来的 `return _buildSlotCard(context, slotKey, switch (config.component) { ... })` 拆分为 `final widget = switch(...) { ... }; return _buildSlotCard(...)`，导致：(1) 变量名 `widget` 与 `State.widget` 冲突；(2) switch 表达式的结尾 `},  );` 语法被破坏。
- **根因**：`switch` 表达式作为函数参数时是单条语句；拆成独立变量后需要同步修改变量名（避免与类成员冲突）和结尾的闭合括号。
- **教训**：对包含 `switch` 表达式作为函数参数的语句进行 `replace_in_file` 时，先通读目标代码块的完整上下文，确认没有变量名冲突后再替换。替换后立即检查 lint。

## 3. SlotDispatch 中 `SizedBox` 无高度约束 → 内部 Expanded/Flexible 级联崩溃

- **问题**：`_buildSlotCard` 的 `SizedBox(child: content)` 没有设置 height/width，导致 content 收到的垂直约束为 unbounded。当 content 内部使用 `Expanded`/`Flexible` 时（SpreadsheetView、PresentationView、DocumentView、EditorView、ChatControllerView），触发 `RenderFlex children have non-zero flex but incoming height constraints are unbounded`，级联污染整个渲染树。
- **根因**：`Card → SizedBox(无height) → content` 放入 `Column(mainAxisSize: MainAxisSize.min) → SingleChildScrollView → TabBarView` 链中，高度约束逐层丢失。
- **修复**：`SizedBox(height: 400)` 提供有界约束。400px 为经验值，后续可改为从 slot config 推断。
- **教训**：在 `SingleChildScrollView` 中嵌套使用 `Expanded`/`Flexible` 的组件时，必须确保它们的外层容器提供了有界高度约束。

## 4. Component 名称别名为 SlotDispatch 映射的第一道防线

- **问题**：Showcase manifest 使用 `chat`/`document`/`video`/`lottery-wheel`/`calendar` 等自然名称，但 SlotDispatch 映射表只有 `ai-assistant`/`doc-viewer`/`video-player` 等内部名称，导致 6/13 个 component 落入 `_UnknownSlot`。
- **修复**：在 switch 中为每个自然名称添加别名分支（如 `'chat'` 和 `'ai-assistant'` 指向同一个 `ChatControllerView`）。
- **教训**：SlotDispatch 是渲染层的入口门面——manifest 写什么名，switch 就要匹配什么名。新增 component 时先确认别名覆盖。

## 5. `_buildEmbeddedContent` Column 溢出 159px

- **问题**：`ChatControllerView._buildEmbeddedContent()` 的 Column 包含状态栏(~20px) + `ConstrainedBox(maxHeight:500)` 消息列表 + 输入栏(~50px)，总高度可达 ~570px，但父容器 `SizedBox(height:400)` 只有 400px，导致底部溢出 159px。
- **修复**：用 `Expanded` 包裹消息列表区域，替代 `ConstrainedBox`。`Expanded` 自动占据 Column 剩余空间，自动适配父容器高度，不会溢出。同时用 `ClipRect` 包裹整个 Column 防止内容溢出到边界外。
- **教训**：在固定高度的父容器中，Column 子组件总和必须 ≤ 父高度。`ConstrainedBox(maxHeight)` 只设上限不压缩，用 `Expanded` 才是正确的自适应方案。

## 9. SortHeader 列头 Row 溢出 — Flexible + TextOverflow 双保险

- **问题**：`sort_header.dart:55` 的 `Row`（文字 + 图标）在 `Expanded` 内部使用 `MainAxisSize.min`，多列时文字总宽超出 `Expanded` 分配空间，导致 RenderFlex 水平溢出 3~266px。
- **根因**：`Text` 无 `overflow` 约束 + 无 `Flexible` 包裹 → 文字按自然宽度渲染，不收缩。
- **修复**：用 `Flexible` 包裹 `Text`，加 `overflow: TextOverflow.ellipsis`。`Flexible` 让文字在空间不足时收缩，`ellipsis` 截断并显示省略号。
- **教训**：`Expanded → Row(mainAxisSize:min) → Text` 三层嵌套中，Text 必须被 `Flexible` 包裹且设置 `overflow`，否则文字不会自动截断。

## 7. 自绘组件使用 CustomPainter 而非外部依赖

- **问题**：lottery-wheel 和 calendar 最初为占位组件，需要引入 `flutter_fortune_wheel` 和 `table_calendar` 等外部包来实现真实渲染。
- **根因**：renderer 包使用 stub 依赖隔离（11 个 stub），引入新 pub 包需要同步创建 stub，增加维护负担。
- **修复**：使用 `CustomPainter` 自绘转盘（扇形分区 + 旋转动画 + 指针），使用 `GridView` 自绘日历（月视图 + 事件标记 + 今日高亮）。零外部依赖，代码可控。
- **教训**：在 stub 隔离架构中，优先自绘而非引入新依赖。CustomPainter 可满足大多数自定义 UI 需求。

## 8. DashboardCard 渐变色改造需保持构造函数签名兼容

- **问题**：DashboardCard 改造为渐变色设计时，需确保 `DashboardView` 中的调用方式不变。
- **修复**：新增 `cardTheme` 可选参数（默认 `DashboardCardTheme.blue`），保持原有 `title/value/trend/subtitle/display/onTap` 参数不变。旧代码无需修改即可获得新视觉。
- **教训**：UI 升级时保持 API 向后兼容，用可选参数扩展而非修改现有签名。

- **问题**：多列布局中 `Row → Expanded` 的列宽计算依赖 `constraints.maxWidth`，但 `Card` 内部的 `border` + `SizedBox` padding 导致实际可用宽度略小于计算值，造成水平溢出（从 1.3px 到 265px 不等）。
- **修复**：用 `LayoutBuilder` 获取精确的可用宽度，计算 `colWidth = (maxWidth - totalGap) / columns`，然后用 `SizedBox(width: colWidth)` 替代 `Expanded`。这避免了 `Expanded` 按 flex 比例分配的舍入误差。
- **教训**：在 `Card → SizedBox` 嵌套中使用 `Row → Expanded` 时，Expanded 的 flex 分配可能因 sub-pixel rounding 导致溢出。用 `LayoutBuilder` + 精确宽度计算更可靠。

## 10. `flutter test` 是本环境编译正确性的唯一可靠裁定（vs `dart analyze` 误报）

- **问题**：M1 补齐 12 个 Dart slot + 升级 19 个 HTML 渲染函数后，运行 `dart analyze` / `flutter analyze lib/renderer/` 对大量**既有文件**报 `Undefined class Widget/BuildContext/Color` 等成片错误（data_table.dart、theme_provider.dart、composite_view.dart 等），但这些文件明明 `import 'package:flutter/material.dart'`。
- **根因**：本环境 `flutter pub get` 重新生成 `.dart_tool/package_config.json` 后，analyzer 解析出现环境性假错（与既有「Flutter analyze 在本环境对 material 报全局 false-error」同源）。**不是代码缺陷**。
- **裁定**：以 `flutter test` 真实编译器为唯一正确性来源。M1 三个测试套件（`r10_render_log`、`renderer_components_test`、`slot_widgets_test`）全部 `All tests passed!`（exit 0，R10 33 模块全通过）即证明整个 app（含新增 renderer 代码）编译通过。
- **附带捕获的真实 bug**：`slot_widgets_test` 首次运行时加载失败，暴露 `_terminal_slot.dart:49` 的预存编译错误——`const Text('$ ', ...)` 中的裸 `$` 触发字符串插值解析失败 → 改为 `const Text(r'$ ', ...)`（raw string）。这是 analyzer 假错之外**唯一真实的编译问题**，被 widget 测试捕获。
- **教训**：(1) 本环境 analyze 假错不可信，`flutter test` 才是 oracle；(2) 每个新 slot 必须有 widget 测试承载，否则预存编译错误（即便从未被编译过）会漏网；(3) 字符串里的 `$` 必须转义或用 raw string。

## 11. `flutter build windows --release` 在本环境因 NuGet 缺失不可行

- **问题**：M1 收尾时尝试跑 `flutter build windows --release` 做终检，直接失败：`Nuget is not installed.`（另有一条非致命 CMake 警告：`webview_windows/.../CMakeLists.txt:34 add_custom_command(TARGET): DEPENDS ... Policy CMP0175`，仅 warning）。
- **根因**：本机未安装 Visual Studio 构建工具 / Windows SDK / NuGet（Windows 桌面目标编译必需）。与代码无关。
- **裁定**：在装好 NuGet+VS 构建工具前，`flutter build windows` 无法执行；继续以 `flutter test`（真实编译整个 app，含全部 renderer 代码）作为"可编译/可运行"的验证裁定。若用户要求产出 release exe，需先在本机安装 Windows 桌面构建依赖（或由用户在其环境 build）。

## 12. 全局字符串替换会误伤"图例/非任务行"中的同一 token

- **问题**：用脚本 `s.replace('⚪待启动', '✅完成')` 批量翻转 M1 状态，结果 `count` 报 32 而非预期 31。排查发现多出的 1 处是**状态图例行**（`状态图例：\`✅完成\` \`🔧进行中\` \`⚪待启动\` \`⛔阻塞\``）里的 `⚪待启动` 也被一并替换，导致图例变成 `✅完成 🔧进行中 ✅完成 ⛔阻塞`，丢失"待启动"色块。
- **根因**：状态 token 同时出现在任务行状态列**和**文档图例中；blind 全文替换不分语境。
- **教训**：批量替换状态/标记类 token 时，(1) 先 `count` 并与预期逐项对账，差值往往来自图例/说明/重复行；(2) 优先用带语境的定点 `replace_in_file` 或正则限定列位置，避免误伤；(3) 替换后通读图例与统计行。本例由 `/Intro`→`/iloop` 自评暴露。
