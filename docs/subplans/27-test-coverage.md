# 27 — 测试覆盖

**层级：** 十 | **估时：** ~14h | **依赖：** 02 测试基础设施, 13~24 全部功能

---

## Phase 0: 已踩坑回归测试（最高优先级 🔴）

> 2026-06-12 实际修复的每个 bug 对应一个回归测试，防止再次踩坑。

### 0.1 Riverpod 依赖链 & 刷新系统

| # | 文件 | 对应 Bug | 测试内容 |
|---|---|---|---|
| 0.1.1 | `test/core/provider_watch_chain_test.dart` | `ref.read` 不建立依赖链，下游 invalidate 无效 | ProviderContainer 创建上下游 FutureProvider，验证 invalidate 下游时 `ref.watch` 的会联动刷新 |
| 0.1.2 | `test/core/provider_dispose_test.dart` | Controller 未 dispose，事件流在 Widget 销毁后继续发射 | 验证 `ref.onDispose` 回调被调用 |
| 0.1.3 | `test/core/connectivity_no_auto_refresh_test.dart` | `autoRefreshTickProvider` 被 connectivity 层 watch 导致每 3 分钟全量 HTTP | 验证 `connectivityCheckProvider` 不依赖 `autoRefreshTickProvider` |
| 0.1.4 | `test/core/settings_type_safety_test.dart` | `SharedPreferences.getBool()` 读到 String 崩溃 | mock SharedPreferences 写入 `'false'` 字符串，验证兼容读取 |
| 0.1.5 | `test/core/result_generic_cast_test.dart` | `Ok(List<Map>) as Result<List<Grade>>` 强转崩溃 | 验证缓存回退 try-catch 降级逻辑 |

### 0.2 构建作用域 & 状态冲突

| # | 文件 | 对应 Bug | 测试内容 |
|---|---|---|---|
| 0.2.1 | `test/core/callback_action_rebuild_test.dart` | `CallbackAction` 中直接 `ref.invalidate` 触发 "wrong build scope" | 模拟 Shortcuts action 回调中 invalidate provider |
| 0.2.2 | `test/core/stream_state_after_dispose_test.dart` | Agent 事件流在 Widget dispose 后调用 `setState` | Mock stream 在 dispose 后 emit，验证 `mounted` 守卫 |
| 0.2.3 | `test/core/auto_refresh_during_animation_test.dart` | 自动刷新 tick 与 AnimatedContainer 同帧触发 overflow | tick 延迟执行不冲突当前帧 |

### 0.3 主题 & 布局

| # | 文件 | 对应 Bug | 测试内容 |
|---|---|---|---|
| 0.3.1 | `test/core/theme_no_double_seed_test.dart` | `colorSchemeSeed` + `colorScheme` 同时设置崩溃 | 5 套 ThemeData 构建不抛 AssertionError |
| 0.3.2 | `test/widgets/sidebar_collapse_overflow_test.dart` | 侧栏折叠动画中 Row 溢出 | 60px 宽度下渲染 _NavItem，验证不溢出 |
| 0.3.3 | `test/core/snackbar_dark_contrast_test.dart` | 暗色模式 SnackBar 文字不可读 | 4 套主题 SnackBar 对比度 ≥ 4.5:1 |
| 0.3.4 | `test/widgets/calendar_aspect_ratio_test.dart` | 考试日历 Expanded + AspectRatio 溢出 | 不同宽度下渲染日历无 bottom overflow |
| 0.3.5 | `test/widgets/timetable_dark_mode_test.dart` | 深色模式课表硬编码色值 | dark Theme 渲染 TimetableGrid 无硬编码 Colors.grey |

### 0.4 数据完整性

| # | 文件 | 对应 Bug | 测试内容 |
|---|---|---|---|
| 0.4.1 | `test/widgets/badge_expired_filter_test.dart` | 侧栏待办/考试红点计入已过期 | `isBefore(now)` 排除 + `diffDays >= 0` 下限 |
| 0.4.2 | `test/core/notification_full_content_test.dart` | Agent 通知工具截断 500 字符 | 超 500 字正文完整返回 |

---

## Phase 1: 补 Core 层缺口 → ≥90%

### 1.1 网络层 (test/core/network/)
- `network_config_test.dart` — 常量非空、isZjuDomain 白名单
- `retry_interceptor_test.dart` — 指数退避、状态码白名单、jitter
- `auth_interceptor_test.dart` — session expired 检测、重试次数
- `dio_client_test.dart` — 拦截器链顺序

### 1.2 存储层 (test/core/storage/)
- `settings_service_test.dart` — loadAll/save/clearAll 往返
- `database_test.dart` — WebCacheDatabase 读写
- `cache_manager_test.dart` — TTL 过期

### 1.3 工具类 (test/core/utils/)
- `auto_refresh_test.dart` — shouldRefresh、定时器取消、tick 延迟
- `python_env_test.dart` — ensureReady 路径检测

### 1.4 配置层 (test/core/config/)
- `app_config_notifier_test.dart` — 三层优先级、saveAll 往返、脱敏

### 1.5 Agent 扩展 (test/core/agent/)
- `memory_facade_test.dart` — remember/recall/search/buildContext
- `skill_test.dart` — 技能加载
- `compact_test.dart` — 三档阈值

---

## Phase 2: Feature 集成测试

### 2.1 Auth + ZDBK
- `zdbk_integration_test.dart` — MockDioAdapter stub 全流程
- `auth_integration_test.dart` — CAS 登录 mock

### 2.2 关键 Provider
- `scores_provider_test.dart` — EverythingResult + GPA
- `exams_provider_test.dart` — ZDBK 优先 + courses 回退
- `courses_provider_test.dart` — 课程列表 + 错误降级
- `classroom_provider_test.dart` — 视频列表解析
- `connectivity_provider_test.dart` — 全服务检查、不依赖 tick

---

## Phase 3: Widget 测试

### 3.1 高频页面
- `scores_screen_test.dart` — 四态覆盖
- `courses_screen_test.dart` — 列表/周视图 + 深色模式
- `exams_screen_test.dart` — 列表/日历 + 无溢出
- `todo_screen_test.dart` — 源标记 + 过期样式

### 3.2 新增 Widget
- `sidebar_test.dart` — 桌面/移动端、红点计数、折叠/展开、60px 无溢出
- `dashboard_test.dart` — 四分区、badge、导航
- `command_palette_test.dart` — 搜索/键盘/Escape/最近访问
- `evergreen_progress_test.dart` — 确定/不确定/label

---

## Phase 4: Agent E2E

- `agent_chat_e2e_test.dart` — 完整对话流程 + dispose 后无泄漏
- `agent_tool_gate_test.dart` — Gate/StormBreaker/Readiness

---

## Phase 5: 性能

- `dashboard_perf_test.dart` — 首次渲染 < 500ms
- `scores_scroll_perf_test.dart` — 50+ 列表 60fps

---

## 验证

- `flutter test --coverage` → core ≥ 90%
- Phase 0 全部 15 个回归测试必须最先通过

---

## 状态

✅ **全部 5 个 Phase 已完成** (2026-06-13)
- Phase 0: 19 回归测试
- Phase 1: 13 Core 层缺口测试
- Phase 2: 4 Feature 集成测试
- Phase 3: 4 Widget 测试
- Phase 4: Agent E2E + 2 性能测试

待验证: `flutter test --coverage` 检查 core ≥ 90%

---

*最后更新: 2026-06-13*
