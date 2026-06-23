---
task_type: refactor
tags: [cache, offline, architecture, provider, agent-tool, dio]
files_touched:
  - lib/core/connectivity/data_status_manager.dart
  - lib/core/services/background_refresher.dart
  - lib/core/storage/database.dart
  - lib/features/agent/providers/agent_provider.dart
  - lib/features/zdbk/services/zdbk_service.dart
  - lib/features/courses/services/courses_api_service.dart
  - lib/features/classroom/services/classroom_crawler.dart
  - lib/widgets/dashboard.dart
difficulty: hard
outcome: success
date: 2026-06-16
related_pr: 2026-06-16-v1.1-release.md
---

## 做了什么

将整个应用的数据架构从"页面打开→触发网络请求"重构为"离线优先 + 缓存驱动"模式，引入 13 源数据状态面板和后台静默刷新。

## 关键决策

- **前端永读缓存**：所有数据页面打开时直接从 `WebCacheDatabase` 读取，不触发 HTTP
- **后台静默刷新**：`BackgroundRefresher` 定时静默拉取全量数据写入缓存
- **Agent 工具改为 cache-only**：`FlutterZjuDataSource` 全部方法改为读缓存，不调用网络（仅搜索/OCR 保留 live）
- **网络失败回退过期缓存**：`_withAutoRelogin` + `fallbackKey` 机制

## 踩过的坑

### 1. Agent 工具空数据提示
- **问题**：重构后 Agent 工具首次启动返回"暂无数据"，因为缓存尚未建立
- **解决**：工具空数据时提示用户"请先在数据状态面板刷新"，而不是静默失败

### 2. Provider autoDispose 导致状态丢失
- **问题**：screen-local 的 `family` provider 在页面切换后被 dispose，返回时数据丢失
- **解决**：对需要跨页面保持的 provider 移除 `autoDispose`，仅对真正的临时 provider 保留

### 3. ref.read(authProvider) vs ref.watch(authProvider)
- **问题**：多处遗留的 `ref.read(authProvider)` 导致登录完成后不自动刷新
- **解决**：全局排查，将依赖登录态的 Provider 统一改为 `ref.watch`（本次修复了 `library_provider.dart` 等多处）

### 4. 判断哪些页面该自动刷新
- **问题**：原先 `shouldRefresh()` 在多个页面打开时触发网络请求，重构后改为全手动
- **解决**：仪表盘（5 个核心 Provider 主动 invalidate）+ 其余页面手动刷新。课程/考试/待办等高频页面建议保留手动刷新以减轻服务器压力。

## 可复用的模式

### 缓存优先 + 网络回退模式
```dart
Future<Result<T>> fetchWithFallback({
  required Future<T?> Function() readCache,
  required Future<T> Function() fetchNetwork,
  required Future<void> Function(T) writeCache,
}) async {
  // 1. 先读缓存（毫秒级）
  final cached = await readCache();
  if (cached != null) return Ok(cached);

  // 2. 缓存未命中 → 网络请求
  try {
    final data = await fetchNetwork();
    await writeCache(data);
    return Ok(data);
  } catch (e) {
    // 3. 网络失败 → 回退过期缓存
    final stale = await readCache();
    if (stale != null) return Ok(stale);
    return Err(AppError.networkUnreachable(url));
  }
}
```

### 数据源状态管理模式
```dart
class DataStatusManager {
  final sources = <String, DataSourceStatus>{};
  
  void markFetching(String name);
  void markSuccess(String name);
  void markFailure(String name, String error);
  
  DataSourceStatus get(String name);
  List<DataSourceStatus> get all;
}
```

## 注意事项

- **修改 `WebCacheDatabase` 的缓存键格式**会影响所有 Feature，必须全量回归测试
- **Agent 工具改为 cache-only 后**，首次启动用户必须在数据状态面板刷新一次才能用 Agent 查询数据
- **后台刷新频率受 `AUTO_REFRESH_INTERVAL` 控制**，改这个值会影响服务器负载
- 仪表盘 `DashboardScreen` 打开时 `invalidate` 5 个 Provider，新增数据源时记得检查是否需要加入
