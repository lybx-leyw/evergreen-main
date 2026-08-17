# 【WIP】scraper 工具可用性

> 状态：待修复（WIP）。本文档仅记录现状，暂不修复。
> 日期：2026-08-17

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
| list_captured_requests | ⚠️ 可用但无数据 | 工具本身可用，但返回「暂无 GET 捕获日志」 |
| explore_page_links | ❌ 不可用 | 持续报「浏览器 JS 通道不可用或页面未就绪」 |
| present_data_sources | ⚠️ 受限 | 本身可用，但候选源必须有 sourceLogId 证据，无捕获日志会被守卫拒绝 |
| register_batch | ⚠️ 受限 | 注册前证据终闸：url 无捕获日志证据 → 拒绝 |

## 状态图例

- ✅ 正常：实测可用，返回符合预期。
- ⚠️ 可用但无数据：工具本身能调通，但依赖的数据（捕获日志）为空，导致功能不完整。
- ⚠️ 受限：工具逻辑正常，但被守卫/证据终闸拦截（因缺少捕获日志证据）。
- ❌ 不可用：持续报错，无法正常返回。

## 根因链条（待查证）

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

核心疑点：**浏览器 JS 通道（WebView bridge）为何未就绪 / 未捕获 GET 请求**。
可能方向（待排查，勿盲改）：
1. `ScraperWebViewBridge.ready` 状态机时序（初始化完成前/后是否误判）。
2. CDP 网络监听 / JS 拦截器未真正挂上（新窗口、iframe、重定向场景）。
3. 页面 `window.open` / `target="_blank"` 逃逸主 WebView（历史坑：webview popup policy）。

## 待办

- [ ] 定位浏览器 JS 通道未就绪根因（navigate_get 能导航，但捕获日志为空，说明「导航」与「捕获」两条链路状态不一致）。
- [ ] 修复后复测 `explore_page_links` / `list_captured_requests` → 解锁 `present_data_sources` / `register_batch`。
- [ ] 回归：navigate_get / list_python_capabilities / guardian_review / ask / build_selected_source 五项已正常工具勿破坏。
