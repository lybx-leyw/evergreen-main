# Scraper V2.0 重构 · Phase 4 交接文档

> **给下一个接手 AI 的完整交接**。本文件自包含，无需回看历史对话。
> 交接人：Phase 4 实现 AI｜日期：2026
> 当前状态：**Phase 1 ✅ + Phase 2 ✅ + Phase 3 ✅（均已用户确认）+ Phase 4 ⏳ 实现完成（commit 25f7509），待用户机器 analyze/测试/编译回归 + 用户确认**

---

## 一、任务背景

Evergreen 2.0（Flutter 桌面应用）的 **scraper 插件底层重构**，按 `Scraper_V2.0_全量重构计划.md` 分 4 Phase 交付。Phase 4 = **AI 探索模式**（需求 D1-D9、A20），与定向抓取并列的第二个工作流×harness（D9）。

权威文档（冲突时依序为准）：
1. `Scraper_决策原文归档.md`（用户 6 轮 ask 逐字归档）
2. `Scraper_V2.0_全量重构计划.md`（§八 Phase 4 详设）
3. `Scraper_PHASE3_交接文档.md`（Phase 1-3 成果与踩坑记录，**踩坑部分仍然有效必读**）

---

## 二、Phase 4 已完成改动

### 2.1 新增文件（explore/）

| 文件 | 内容 |
|---|---|
| `explore/explore_workflow.dart` | **ExploreWorkflow** 纯 Dart 状态机：idle→exploring→categorizing→confirming→building→registering→done/failed；`ExploreLimits`（20 页/50 请求/1s 节流/同域，可配置 + 可注入时钟）；`validateExploreUrl`（GET-only/同域守卫纯函数）；`sanitizeSourceName`；`exploreToolAllowedForPhase`（阶段工具白名单矩阵）+ `blockedExploreToolMessage`；`CandidateDataSource`/`CandidateField`（JSON 往返，method 强制 GET） |
| `explore/scraper_explore_tools.dart` | 6 个探索工具：`explore_page_links`（JS 枚举 a[href]，同域过滤，兼容 executeScript 双 JSON 编码）、`navigate_get`（唯一导航通道，守卫拒绝回灌）、`list_captured_requests`（仅 GET 日志）、`present_data_sources`（归类 JSON → UI 多选 → 确认推进阶段）、`build_selected_source(name, code)`、`register_batch(names)`；工厂 `createScraperExploreTools`（UI 层注入 6 个回调） |
| `explore/explore_panel.dart` | `ExplorePanel`（阶段/页数/请求计数/候选与选择 chips/开始探索按钮）；`showExploreSourcePicker`（多选弹窗：默认全选、可改名实时校验） |

### 2.2 修改文件

| 文件 | 内容 |
|---|---|
| `web/scraper_webview.dart` | 新增 **ScraperWebViewBridge**（evaluateJavaScript/navigateTo/currentUrl 三通道，initState 按平台填充：Windows `executeScript` / Android `runJavaScriptReturningResult`）；ScraperWebView 新增 `bridge` 参数 |
| `agent/scraper_gate.dart` | +6 条探索工具 PermissionRule（always；阶段白名单由 hooks 强制） |
| `agent/scraper_hooks.dart` | +`exploreWorkflow` 可选参数：探索模式阶段白名单强制、navigate_get URL 守卫预检、build_selected_source lint（假数据 guardFlag 自动置位/清除）、register_batch 假数据未清除拒绝（G6 语义） |
| `agent/scraper_ai_panel.dart` | +`mode`/`boardId`/`exploreWorkflow`/`webBridge` 参数；探索模式分支：探索工具集 + `scraperExploreSkillBody` + 探索会话（`explore_<boardId>`，无命名弹窗）；新增 `startExplore`/`reopenSourcePicker`/`_presentExploreSources`/`_buildExploreSource`/`_registerExploreBatch`；输入栏探索按钮、隐藏「操作完毕」 |
| `view/scraper_generator_view.dart` | +`mode`/`boardId` 参数；持有 ExploreWorkflow + ScraperWebViewBridge；探索模式右上面板 = ExplorePanel（替代 RequestLogPanel）；状态栏探索计数与阶段映射；窄屏日志 Tab 探索模式禁用「分析日志」 |
| `board/board_container_view.dart` | 新建画板弹窗（名称 + SegmentedButton 模式选择）；画板 tile 模式图标点击切换（确认框 + 重建工作区）；GeneratorView 透传 mode/boardId，key 含 mode |
| `scraper_skill_const.dart` | +`scraperExploreSkillBody`（探索角色：GET-only 流程、归类 JSON 格式、锁定模板、红线） |
| `scraper_exporter.dart` / `scraper_flow_facade.dart` | `exportDataManifest`/`generateAsDataPlugin` +可选 `category`/`displayName`（探索归类写入 manifest，向后兼容） |

### 2.3 测试

- 新增 `test/scraper/explore_workflow_test.dart`（状态机/上限/节流/GET 守卫拒绝路径/白名单矩阵/名称校验）
- 新增 `test/scraper/explore_tools_test.dart`（navigate 守卫、links 解析、GET 过滤、present 校验与改名、build/register 参数）
- 新增 `test/scraper/explore_hooks_test.dart`（白名单拦截、lint 门禁、假数据标记生命周期）
- 新增 `test/scraper/explore_panel_test.dart`（面板状态 + 多选弹窗交互）
- 修改 `test/scraper/board_container_view_test.dart`（适配新建弹窗 + 探索模式创建用例）

---

## 三、Phase 4 验收标准（对照主计划 §8.3）

- [ ] `flutter analyze` 全项目 0 error（⚠️ 必须全项目，子目录有嵌套同名包假阳性）
- [ ] `flutter test test/scraper/` 全绿（含 5 个新/改文件）
- [ ] 编译回归：`flutter build windows --debug`
- [ ] 手工验证点：
  1. 新建「AI 探索」画板 → 浏览器登录 → 点「开始探索」（确认框）→ AI 循环 explore_page_links/navigate_get/list_captured_requests，状态栏与面板页数/请求计数推进
  2. 触达上限/节流时 AI 收到守卫拒绝并结束探索
  3. AI 调 present_data_sources → 多选弹窗（默认全选、改名生效）→ 确认
  4. AI 逐源 build_selected_source → plugins/data-{name}/（scraper.py + data/manifest.json 含 category/displayName + config/config.json）
  5. register_batch → 数据看板出现新数据源且 orch.get 全部通过 → 面板显示「✅ 探索完成」
  6. 轨迹视图可见探索工具调用（Phase 3 Trace 自动复用）

---

## 四、关键设计决策（下一个 AI 务必先读）

1. **两套状态机并列（D9）**：探索画板 = ScraperWorkflow（只管日志累积/guardFlags）+ ExploreWorkflow（探索阶段）。定向工具在探索模式由 hooks 白名单全程禁用（含 save_credential——探索不注册凭证，凭证走 _get_config 三级降级 + 用户设置面板）。
2. **register_batch 允许在 building 阶段过 preToolUse**：工具 execute 内部先 `startRegistering()` 再注册（hooks 在工具执行前检查白名单，若 building 不放行则永远无法注册——这是有意为之的时序设计）。
3. **build 时 lint 假数据 warning 不阻断**（A5 语义）：写 guardFlag，register_batch 拒绝直到修正代码自动清除标记。定向模式的 G5 用户弹窗在探索模式不适用（用户已在多选弹窗确认过数据源）。
4. **模式切换 = 重建工作区**：`ValueKey('board-{id}-{mode}')` 使切换模式重挂载 GeneratorView（两套 harness 无法热切换）；切换前有确认框防丢状态。画板元数据持久化不受影响。
5. **Windows JS 结果通道（重要）**：webview_windows 的 `executeScript` 返回 `Future<void>`、**不回传求值结果**（flutter-webview-windows #69/#161）。因此 `_evaluateJs` 在 Windows 走「executeScript 发起 + 包装脚本 `chrome.webview.postMessage` 回传 + `_pendingJsResults` Completer 桥接 + 10s 超时」；Android 用 `runJavaScriptReturningResult`（回传 JSON 编码结果）。`_decodeJsJson` 兼容「裸 JSON」与「JSON 编码包一层」两种形态（测试覆盖双编码形态）。静态审查曾发现第一版直接 `return _controller.executeScript(...)` 的类型不匹配问题，已按此方案修复。
6. **G6 Guardian 复用**：批量注册前单次 `_guardianReview`（审 trace + 产物），deny 拒绝整批 + rationale 回灌。
7. **manifest category/displayName**：探索归类信息经 `generateAsDataPlugin(category:, displayName:)` 写入 manifest，定向模式不传（默认行为不变）。

---

## 五、遗留/风险（待 debug 回归确认）

1. **本环境无 Flutter 工具链**：analyze/test/编译未跑，已做静态审查（见第六节）；交接后第一步先跑 `flutter analyze` 全项目。
2. **webview_windows executeScript spike 已确认**：代码库 html_modle_view/preview_panel 已在用 `_controller.executeScript(script)`（0.4.0 API），非首次使用；但探索模式下的实际返回值形态仍需手工验证（已做双形态解析兜底）。
3. **多画板会话文件共享**：探索会话名 `explore_<boardId>` 与定向会话共存于 scraper_sessions.json（Phase 2 遗留：定向会话按数据名共享，未按画板隔离——非本次改动范围）。
4. **探索构建的 scraper.py 不单独试运行**：与定向 `_generatePlugin` 一致（lint + 注册 + orch.get 真拉取即验证）；AI 失败重试路径为 build→register 循环（3 轮换策略在 Skill 中约定）。

---

## 六、静态审查结论（debug 记录）

实现完成后做了编译级静态审查（子代理交叉验证全部新/改文件的符号引用、类型、null 安全）。发现并已修复：

1. **阻断**：`scraper_webview.dart` `_evaluateJs` Windows 分支 `return _controller.executeScript(...)` 类型不匹配（webview_windows 返回 `Future<void>` 不回传结果）→ 改为 postMessage 结果通道桥接（见 §四.5）。
2. **加固**：`scraper_ai_panel.dart` 探索模式缺 ExploreWorkflow 时显式抛 StateError（替代隐式 `ew!`）。

其余交叉验证项（工具构造/import 符号/注册函数签名/riverpod providers/闭包类型/测试引用）均确认真实存在且类型匹配。**本环境无 Flutter 工具链，analyze/test/编译未执行——遗留项 = 真机回归**。

---

## 七、协作约定（不变，从 Phase 3 继承）

1. 每个里程碑先汇报再继续（本次 Phase 4 应用户要求"全部结束后一次性 debug"）
2. 需求冲突以 `Scraper_决策原文归档.md` 为准
3. 颜色从 colorScheme 派生，不硬编码
4. 交付：实现 + 测试 + analyze 0 error + 编译回归 + 手工验证点说明
5. Phase 1-3 均未提交时先 commit（本 Phase 开始前已 commit b40c876 = P1-3 存档）
