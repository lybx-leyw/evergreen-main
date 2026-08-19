# 【WIP】scraper 工具可用性

> 状态：已定位根因并修复，待运行时实跑复测。
> 初始记录：2026-08-17　·　修复：2026-08-18

## 背景

Scraper 探索模式（explore）依赖浏览器 JS 通道捕获网络请求日志，作为数据源注册的「证据」来源。
近期实测发现：浏览器通道的**捕获日志链路失效**（`list_captured_requests` 返回「暂无 GET 捕获日志」），
导致下游依赖证据的工具（`present_data_sources`、`register_batch`）被守卫/证据终闸拒绝，形成连锁受限。

## 工具状态总览

| 工具 | 状态 | 说明 |
| --- | --- | --- |
| navigate_get | ✅ 正常 | 已成功导航 9 次（页面请求 9/50），纯 GET 通道无问题 |
| list_python_capabilities | ✅ 正常 | 实测返回了完整第三方模块清单 |
| guardian_review | ✅ 正常 | 刚实测返回裁决 allow / low risk |
| ask | ✅ 正常 | 之前提问正常返回 |
| build_selected_source | ✅ 正常 | 构建插件目录，不依赖浏览器通道 |
| list_captured_requests | 🔧 已修复待复测 | 根因已定位，修复后待实跑验证捕获日志回灌 |
| explore_page_links | 🔧 已修复待复测 | 根因已定位，修复后待实跑验证 JS 结果通道 |
| present_data_sources | 🔧 依赖修复 | 守卫逻辑正常，依赖 list_captured_requests 有证据后自动解锁 |
| register_batch | 🔧 依赖修复 | 证据终闸逻辑正常，依赖捕获日志证据后自动解锁 |

## 状态图例

- ✅ 正常：实测可用，返回符合预期。
- 🔧 已修复待复测：代码根因已定位并修复，但尚未在真实 WebView2 运行时端到端复测。
- ⚠️ 可用但无数据：工具本身能调通，但依赖的数据（捕获日志）为空，导致功能不完整。
- ⚠️ 受限：工具逻辑正常，但被守卫/证据终闸拦截（因缺少捕获日志证据）。
- ❌ 不可用：持续报错，无法正常返回。

## 根因链条（已定位）

```
浏览器 JS 通道未就绪 / 页面未就绪
        │
        ▼
explore_page_links 报「浏览器 JS 通道不可用或页面未就绪」
        │
        ▼
list_captured_requests 返回「暂无 GET 捕获日志」
        │
        ├─► present_data_sources：候选源缺 sourceLogId 证据 → 被守卫拒绝
        │
        └─► register_batch：url 无捕获日志证据 → 证据终闸拒绝
```

### 根因结论（2026-08-18 静态分析 + webview_windows 0.4.0 源码坐实）

核心矛盾：`navigate_get` 能导航（`bridge.ready=true`、`loadUrl` 正常），但「捕获」与「JS 结果」两条链路失效——它们**共同依赖 WebView2 的消息/结果回传能力，而导航不依赖**。

1. **CDP 环境初始化其实已正确**：`app_bootstrap.dart` 的 `_stepWebView2` 已用
   `WebviewController.initializeEnvironment(additionalArguments: '--remote-debugging-port=9222')`
   在启动早期初始化。但 `scraper_webview.dart` 里的 `_ensureRemoteDebuggingPort()`
   （FFI 设 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` 环境变量）是**无效冗余**——
   webview_windows 插件不读该 env var，而是用
   `CreateCoreWebView2EnvironmentWithOptions` + `put_AdditionalBrowserArguments`。

2. **`_evaluateJs` 的 Windows 实现绕路（根因）**：旧代码误以为
   `WebviewController.executeScript` 不回传结果，自己发明了 postMessage 桥接
   （`chrome.webview.postMessage` + `webMessage` 流 + 10s 超时）。实际
   webview_windows 0.4.0 的 C++ `ExecuteScript` 回调 `Success(json_result)`，
   Dart 侧 `jsonDecode` 后**原生回传结果**。这个脆弱的桥接任一环节失效即返回 null
   → `explore_page_links` 报「JS 通道不可用」。

## 修复内容（2026-08-18）

### A. JS 结果通道（scraper_webview.dart）
- `_evaluateJs` Windows 分支改为直接消费 `executeScript` 原生返回值
  （字符串原样 / 对象 jsonEncode / null 返回 null），删除 postMessage 桥接。
- 删除不再使用的字段 `_jsRequestSeq`/`_pendingJsResults`、`_handleWebMessage` 里的
  `__evgJsResult` 路由分支、`dispose` 里的清理。
- 删除无效的 `_ensureRemoteDebuggingPort()` 及 FFI 辅助函数，移除 `dart:ffi` import。
- `_connectCdp` 加诊断日志：成功打印 `bridge.ready` 状态；失败提示检查 CDP 环境与 9222 端口占用。

### B. 画板-会话双向绑定（附带修复）
- 会话 ↔ 画板双向绑定：`_ScraperSession` 增加 `id` + `boardId`；`ScraperBoard.sessionId` → `sessionIds: List<String>`。
- 孤儿过滤：加载时过滤「无 boardId 的会话」「无绑定会话的画板」，移除 legacy 全局 `scraper_sessions.json` 迁移。

### 验证
- `flutter test test/scraper/` 359 条全绿（含新增 loadBoardSessionIds 过滤测试）。
- `flutter build windows --release` 构建成功。

## 待办

- [ ] **运行时复测（关键）**：真实 WebView2 端到端验证
  `explore_page_links` 正常枚举链接、`list_captured_requests` 返回 GET 日志，
  从而解锁 `present_data_sources` / `register_batch`。
- [ ] 若 CDP 仍连不上（9222 被占/环境未初始化），查看控制台
  `⚠ CDP 连接失败（端口 9222 不可达）` 日志进一步排查。
- [ ] 回归：navigate_get / list_python_capabilities / guardian_review / ask /
  build_selected_source 五项已正常工具勿破坏。
