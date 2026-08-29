# 数据中枢「手动拉取/重试入口」审计报告

> 审计范围：Evergreen renderer / 桥接层（`evg-base/lib/renderer` 及 html-creator 相关）
> 审计目标：找出并消除「用户/组件手动控制数据拉取或重试」的入口，让数据拉取完全由
> 数据中枢后台调度驱动。
> 契约依据：
> - 契约①：前端永拉缓存、后台永写缓存（`DataOrchestrator` 后台 `startAutoRefresh` / `refreshAllStale` 写缓存并广播 `DataChangeEvent`）。
> - 契约③：中枢不再让用户手动控制拉取/重试。
> 审计日期：2026-08-29（基于当前工作区代码快照）

---

## 一、结论摘要

| 处置 | 数量 | 说明 |
|------|------|------|
| **已改（本次）** | 4 处（3 个文件语义 + 1 个服务降级） | 见 §二 |
| **建议后续（本次不改）** | 20+ 处 | 见 §三（含禁止修改目录的发现） |
| **已符合契约 / 信息性** | 若干 | 见 §四 |

核心变化：

1. `resolveDataSource` 的 `forceRefresh` 参数**弃用**：组件层不再能借此绕过缓存强制重抓，统一缓存优先读（`fastRead`，内存未命中内部 fallback `get()`）。
2. `platform.data.refresh(name)`（HTML 插件 JS Bridge）**语义降级**：从「POST /data/types/:name/refresh 强制重抓」降级为「读缓存」（等价 `data.get`）。API 保留、签名不变。
3. html-creator 预览数据面板的 `DataPreviewService.refresh()` 同样降级为缓存读（按钮保留，但不再触发真实拉取）。

---

## 二、本次已改（4 处）

### 2.1 `evg-base/lib/renderer/atomic/data_source_resolver.dart`（forceRefresh 路径）

- **位置**：`resolveDataSource` 签名 `bool forceRefresh = false`（签名保留）；orch:// 分支与 dataType 分支。
- **触发者**：组件自动刷新定时器——`DataSourceSlotState`（`slot/data_source_slot.dart:79`）、`FlashcardsSlot`（`slot/slot_widgets.dart:377`）、`QuizSlot`（`slot/slot_widgets.dart:881`）均传 `forceRefresh: true`。
- **现状（改前）**：`forceRefresh=true` → `orch.refresh(t)` 强制重抓、绕过缓存（R5 注释里也承认「否则 get 命中缓存令定时刷新永远拿旧值」）。
- **处置（已改）**：
  - 参数**弃用**：doc 注释写明契约①语义与「保留仅为向后兼容，不删签名」。
  - 两条 orch 路径统一走 `orch.fastRead(t)`（缓存优先读），`forceRefresh=true` 时仅打 `debugPrint` 弃用提示，不再触发 `orch.refresh`。
  - 数据新鲜度由中枢后台 `startAutoRefresh`（每 5 分钟 `refreshAllStale(notifyOnChange: true)`）维护；组件应通过 `DataChangeEvent` 订阅感知变化。
- **向后兼容**：签名、参数名、返回类型均未变；HTTP 直连路径（`endpoint` 普通 URL）不受影响（forceRefresh 本就只作用于 orch 路径）。

### 2.2 `evg-base/lib/renderer/templates/html_modle/html_modle_view.dart`（platform.data.refresh 桥接）

- **位置**：`_executePlatformApi` 的 `case 'data.refresh'`（约 L346-354）；文件头 doc（L6-7）。
- **触发者**：HTML 插件 JS 调用 `platform.data.refresh(name)`。
- **现状（改前）**：`POST /data/types/:name/refresh` 强制重抓并写回中枢缓存。
- **处置（已改）**：
  - 语义降级为**读缓存**：与 `data.get` 完全一致——`typeByName(name)` → `fastRead(dt)`（内存未命中内部 fallback `get()`，仍缓存优先）。
  - 不再发起任何 HTTP 强制刷新请求；真实刷新由中枢后台调度，插件用 `data.subscribe` 订阅 `data:changed` 感知变化。
  - 未注册的数据源返回 `null`（与 `data.get` 行为一致）。
- **向后兼容**：Bridge API 字段/函数未删（JS 侧仍可调用），仅语义变化；返回值形态与 `data.get` 对齐（旧 refresh 返回 HTTP 响应体，新 refresh 返回缓存数据本身——与 `data.get` 一致）。

### 2.3 `evg-base/lib/renderer/templates/html_modle/bridge_script.dart`（JS bridge 定义）

- **位置**：`buildBridgeScript()` 的 `platform.data.refresh`（约 L96-98）；文件头 doc（L36-46）。
- **触发者**：HTML 插件 JS（公开 API）。
- **现状（改前）**：`refresh: function(name) { return _call('data.refresh', [name]); }`，语义为强制重抓。
- **处置（已改）**：**函数保留、字段不删**，仅更新注释：写明契约③语义降级为「等价 `data.get` 缓存优先读，真实刷新由中枢后台调度」。JS 实现本体零改动（`_call('data.refresh', ...)` 不变），降级在 Dart 侧（2.2）完成。

### 2.4 `evg-base/lib/renderer/templates/v4_modle/components/creative/html-creator/services/data_preview_service.dart`（手动 refresh 属本范围）

- **位置**：`refresh(String name)`（约 L42-53）。
- **触发者**：html-creator 数据面板行内刷新按钮——`view/data_panel.dart:105`（`_refreshSource` → `dataService.refresh(name)`，按钮在 `data_panel.dart:242`）。
- **现状（改前）**：优先 `POST /data/types/:name/refresh`（DataHttpServer 强制重抓），端口缺失/HTTP 失败降级直连 `orch.refresh(dt)`。
- **处置（已改）**：
  - 方法名/签名/返回类型保留（向后兼容），**语义降级为缓存优先读**：委托 `fetchPreview(name)`（`fastRead` 兜底 `get`）。
  - 不再发任何强制刷新请求；真实刷新由中枢后台调度，UI 经 `data:changed` 订阅感知变化。
  - 移除已不再使用的 `flutter/foundation.dart`（debugPrint）import（analyze 通过）。
- **连带效果**：`data_panel.dart` 的「刷新」按钮仍存在且可点击，但点击后只重读缓存（按钮文案「已刷新」与事实略有出入，见 §三-4）。

---

## 三、建议后续（本次不改，仅记录）

> 含禁止修改目录中的发现（`core/**`、看板由另一子代理负责、其余模板目录不在本次允许清单）。全部只记录、不修改。

### 3.1 数据看板（禁止改——另一子代理负责）

1. `evg-base/lib/renderer/page/data_dashboard_view.dart` —— **已由看板子代理并行改造为纯只读轮询**（当前快照：文件头 L3-17 明确「移除一切用户手动拉取/重试入口」，`_refreshStatuses` 只读 `allStatuses` + 订阅 `dataChangeEvents` + 4s 轮询，无「点击拉取/重新拉取」按钮）。状态：**已处置（他代理）**，无需本任务动作。
2. `evg-base/lib/renderer/templates/v4_modle/components/data/renderDataDashboard.dart` —— 静态 HTML 导出渲染器，只读 `config.cards/sources` 渲染，**无运行时拉取入口**。状态：信息性，无需处置。

### 3.2 组件层 forceRefresh 调用点（不在允许清单，经 2.1 间接失效）

3. `evg-base/lib/renderer/templates/v4_modle/slot/data_source_slot.dart:66-83` —— `DataSourceSlotState` 按 `refreshInterval` 周期调 `resolveDataSource(forceRefresh: true)`。经 2.1 后该定时器**不再强制拉取**（等同每周期重读缓存），行为已符合契约①；但定时器本身已无意义，且组件未订阅 `DataChangeEvent`。**建议后续**：组件改为订阅 `dataOrchestrator.dataChangeEvents`（按 `sourceName` 过滤）驱动刷新，移除 `refreshInterval` 定时器与 `forceRefresh` 传参。
4. `evg-base/lib/renderer/templates/v4_modle/slot/slot_widgets.dart:373-379, 877-883`（`FlashcardsSlot` / `QuizSlot`）—— 同上，`forceRefresh: true` 传参经 2.1 失效。**建议后续**：改订阅事件，移除定时器。

### 3.3 html-creator 预览面板（不在允许清单）

5. `evg-base/lib/renderer/templates/v4_modle/components/creative/html-creator/view/preview_panel.dart:374-377` —— 预览面板自带 `_handlePlatformApi` 的 `data.refresh` 分支，仍 `POST /data/types/:name/refresh` 强制重抓。**建议后续**：与 `html_modle_view.dart` 对齐降级为读缓存（本文件不在本次允许清单，未改）。
6. `evg-base/lib/renderer/templates/v4_modle/components/creative/html-creator/view/data_panel.dart:102-117, 232-242` —— 行内「刷新」按钮（`_refreshSource`）。服务层（2.4）已降级为读缓存，故按钮不再触发真实拉取；但 SnackBar 文案「已刷新: $name」/「刷新失败: $name」与读缓存语义不符。**建议后续**：按钮改为「读取缓存/预览」文案，或移除按钮仅保留状态展示。

### 3.4 文档 / AI 提示文案（不在允许清单）

7. `evg-base/lib/renderer/templates/v4_modle/components/creative/html-creator/services/html_creator_skill_const.dart:41` —— Skill 常量文档表：`platform.data.refresh(name) | 强制刷新数据源（POST /data/types/:name/refresh）`。**建议后续**：改为「读缓存（等价 data.get）；真实刷新由中枢后台调度」。
8. `evg-base/lib/renderer/templates/v4_modle/components/creative/html-creator/services/html_ai_service.dart:228` —— AI 提示文案「数据源 $name 暂无缓存数据（可通过 platform.data.refresh 强制拉取）」。语义已过时。**建议后续**：改为「等待中枢后台刷新 / 使用 data.subscribe 订阅」。
9. `evg-base/lib/renderer/README.md:108` —— 示例代码 `await platform.data.refresh('zju_scores')`。**建议后续**：示例改用 `data.get` / `data.subscribe`。
10. `evg-base/lib/renderer/templates/html_modle/core_api_discovery.dart:117` —— 注释提及 `data.refresh` 为强制刷新（仅注释，无行为）。**建议后续**：注释同步。

### 3.5 zju 屏幕「刷新/重试」按钮（zju_modle 不在允许清单，且多数仍直接调 `orch.getByName`）

> 这些按钮调用 `orch.getByName`（缓存优先读），但**用户手动触发拉取/重试**的入口本身与契约③相悖，建议后续统一收敛（由中枢后台刷新 + 事件订阅驱动，屏幕只读缓存）。

11. `zju_modle/scores/screens/scores_screen.dart:114`（tooltip 刷新）、`:142`（重试）。
12. `zju_modle/exams/screens/exams_screen.dart:99`（刷新）、`:127`（重试）。
13. `zju_modle/courses/screens/courses_screen.dart:308-317`（刷新）、`:351`（刷新）、`:379`（重试）。
14. `zju_modle/classroom/screens/classroom_screen.dart:136`（刷新）、`:334`（重试）；`classroom_viewer_screen.dart:86`（`_retry`）、`:338-340`（重试按钮）。
15. `zju_modle/zdbk/screens/training_plans_screen.dart:57-75`（`_refresh` 重新拉取）、`:143-144`（刷新按钮）、`:169-171`（重试）。
16. `zju_modle/zdbk/screens/notifications_screen.dart:92`（刷新）、`:120`（重试）、`:157-159`（`RefreshIndicator` 下拉刷新）。
17. `zju_modle/zdbk/screens/course_offerings_screen.dart:111-134`（`_refresh`：重新拉取 + SnackBar）、`:241-242`（刷新按钮）、`:267-269`（重试）。
18. `zju_modle/teachers/screens/teachers_screen.dart:219`（重试按钮；`:114` 注释「在线评分后台刷新」已符合后台调度方向）。

### 3.6 scraper 模板（作者工具，抓取工作流；不在允许清单）

19. `scraper_modle` 多处 AI/工具提示「重试」：`explore/scraper_explore_tools.dart`（158/636/759/829/890/1235/1253/1357/1477/1513/1546/1560 行附近）、`agent/tools/scraper_tools.dart`（48/144/373/463/625）、`agent/scraper_ai_panel.dart`（1014/1965/1997/2023/2512/2525）、`agent/scraper_hooks.dart:113`、`scraper_json_validator.dart:87-121`、`scraper_skill_const.dart`（291/379/445/699/755 等）、`view/scraper_terminal.dart:277`、`explore/explore_workflow.dart:402` —— 均为 scraper 创作/调试流程的**提示文案**（AI 自我修正循环），非数据中枢消费入口。**建议后续**：若要将 scraper 产出接入数据中枢统一调度，需另行评审（本次不动）。
20. `scraper_modle/web/scraper_webview.dart:872, 1081-1082` —— 地址栏「刷新」按钮（`_refresh` 重载 WebView 页面）。属浏览器页面刷新，非数据中枢拉取。**建议后续**（信息性）。

### 3.7 其他模板（信息性 / 不属于数据中枢消费入口）

21. `skill_creator_modle/skill_creator_view.dart:214-215, 660, 794-796, 858` —— Agent 任务重试按钮（`retryFailedTasks` / `retryTask` / `retryMaterialOcr`）。属 **Agent 执行任务重试**，非数据中枢数据拉取。**信息性**。
22. `skill_creator_modle/services/skill_creator_orchestrator.dart:216-250` —— 上述重试逻辑本体。**信息性**。
23. `v4_modle/components/marketplace/marketplace_slot.dart:600, 679, 759` —— 插件市场列表 `RefreshIndicator` / 重试。属插件列表 UI，非数据中枢。**信息性**。
24. `dsh_modle/dsh_modle_view.dart:82` —— 注释「下次轮询重试」（后台轮询自愈，非用户手动）。**信息性**。
25. `zju_modle/zju_auth/retry_interceptor.dart` + `network_config.dart:12-15` —— Dio 指数退避自动重试（429/502/503）。属**网络层自动重试**（非用户手动），方向与「后台自愈」一致。**信息性**；如要求「所有拉取都经中枢」，zju 直连网络层收敛为数据源 fetcher 属更大重构，建议后续单独评审。
26. `v4_modle/composite_view.dart:144-179` —— 模块级 `dataBindings` 拉取用 `orch.fastRead`（缓存优先读）。**已符合契约①**，信息性。
27. `v4_modle/components/document/plugin-designer/plugin_designer_view.dart:1431-1436` —— `orch.getByName`（缓存优先读）。**已符合契约①**，信息性。

### 3.8 测试断言（不在允许清单，行为语义变化后需同步）

28. `evg-base/test/renderer/atomic/data_source_resolver_cache_test.dart:72-87` —— 用例「forceRefresh → 绕过缓存强制重拉（供自动刷新使用）」断言 `forceRefresh:true` 后 `calls == 2`。新语义下 `forceRefresh` 不再绕过缓存，该断言**会失败**。**建议后续**：改为断言「forceRefresh 与默认一致，均缓存优先读（calls 保持 1，返回缓存值）」，并新增「后台 refreshAllStale 后 fastRead 返回新值」用例。
29. `evg-base/test/renderer/slots/data_slot_test.dart:83-118` —— 用例「到点经 forceRefresh 重新拉取并刷新 UI（非命中缓存）」依赖定时器触发 `forceRefresh` 二次拉取（`calls > 1`）。新语义下定时器只重读缓存，断言会失败。**建议后续**：改用「中枢 refreshAllStale → DataChangeEvent → 组件订阅刷新」的驱动方式重写该用例（组件订阅改造见 §三-3/4）。

---

## 四、已符合契约 / 无需处置（信息性）

- `html_modle_view.dart` 的 `data.get` / `data.subscribe`：`data.get` 走 `fastRead`（缓存优先读）；`data.subscribe` 事件驱动 + 轮询兜底，均为读缓存路径。✔
- `bridge_script.dart` 的 `DataSubscriptionPoller`：`_fetch` 注入的是 `fastRead`（缓存读）。✔
- `data_preview_service.dart` 的 `listSources` / `fetchPreview` / `testConnectivity`：`fetchPreview` 读缓存；`testConnectivity` 是连通性诊断（非数据拉取/重试）。✔
- `DataOrchestrator` 后台调度（`startAutoRefresh` / `refreshAllStale` / `dataChangeEvents` / 同域后台重试）：唯一被允许的「拉取/重试」来源，写缓存并广播事件。✔（core 域由另一子代理负责，本报告不涉及改动）

---

## 五、语义变化清单（重要）

| API / 入口 | 旧语义 | 新语义 |
|------------|--------|--------|
| `resolveDataSource(forceRefresh: true)` | `orch.refresh` 强制重抓、绕过缓存 | **弃用**：一律 `orch.fastRead` 缓存优先读；后台由中枢调度刷新 |
| `platform.data.refresh(name)`（HTML 插件） | `POST /data/types/:name/refresh` 强制重抓 | **读缓存**：等价 `data.get`（`fastRead` 兜底 `get`）；真实刷新由中枢后台调度，插件用 `data.subscribe` 感知变化 |
| `DataPreviewService.refresh(name)`（html-creator 数据面板） | HTTP refresh / `orch.refresh` 强制重抓 | **读缓存**：等价 `fetchPreview`（`fastRead` 兜底 `get`） |

> 向后兼容承诺：所有公开 API 签名/字段均未删除；`forceRefresh` 参数、`platform.data.refresh` 函数、`DataPreviewService.refresh` 方法全部保留。调用方传入旧参数不会编译失败；行为按契约①/③ 收敛为缓存读。

---

## 六、遗留建议汇总（按优先级）

1. **[P0] 组件订阅化**：`data_source_slot.dart` / `slot_widgets.dart` 的 `refreshInterval` 定时器改为订阅 `dataChangeEvents`（§三-3/4），彻底移除组件级定时拉取。
2. **[P1] 测试同步**：更新 `data_source_resolver_cache_test.dart` 与 `data_slot_test.dart` 中断言旧 forceRefresh 语义的用例（§三-28/29）。
3. **[P1] preview_panel 对齐**：html-creator 预览面板 `data.refresh` 分支与运行期 bridge 对齐为读缓存（§三-5）。
4. **[P2] UI 文案**：`data_panel.dart` 刷新按钮文案、`html_ai_service.dart` / `html_creator_skill_const.dart` / `renderer/README.md` 文档同步（§三-6~10）。
5. **[P3] zju 屏幕收敛**：zju 各屏幕「刷新/重试」按钮统一改为读缓存 + 事件订阅驱动（§三-11~18）。
6. **[P3] zju 直连网络层**：`retry_interceptor.dart` 等网络层收敛为数据源 fetcher 或统一经中枢（§三-25），属更大范围重构，需单独立项。

---

*报告生成：2026-08-29 · renderer/桥接层审计工程师 · 改动文件见交付说明*
