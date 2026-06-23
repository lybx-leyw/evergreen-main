---
task_type: bug-fix
tags: [cache, offline, zdbk, classroom, courses, performance, cache-first]
files_touched:
  - lib/features/zdbk/services/zdbk_service.dart
  - lib/features/classroom/services/classroom_crawler.dart
  - lib/features/courses/services/courses_api_service.dart
  - lib/widgets/dashboard.dart
  - lib/core/services/background_refresher.dart
difficulty: hard
outcome: success
date: 2026-06-20
related_pr: 2026-06-20-cache-architecture-freshness-fix.md
---

## 做了什么

补全缓存优先架构——在 ZDBK/Classroom/Courses 所有服务层网络方法前添加新鲜度守卫，用户打开页面时若文件缓存未过期则直接返回、不发 HTTP。

## 关键决策

### 1. `_tryFreshCache<T>` helper
选择在每个方法顶层添加守卫（而非改 `_withAutoRelogin`），因为不同方法的 TTL、缓存 key 格式、反序列化逻辑各不相同。`_withAutoRelogin` 的泛型 `List<Map>` 缓存回退是类型不安全的——这正是上次修复中 `getTranscript` 绕开它的原因。

### 2. Dashboard initState 完全移除 invalidation
注释从 6 月 16 日起就说"不再自动刷新"，但代码一直保留 invalidate。这次彻底让它知行合一。Provider 首次 build 时通过 service 层的缓存优先逻辑自动返回缓存数据。

### 3. getPracticeScores 缓存格式变更
旧缓存存的是原始 HTML（`jsonDecode` 永远失败，fallback 永远不工作）。改为存 `jsonEncode(scores)` Map——向下兼容：旧 HTML 缓存解析失败后自动走网络，新缓存从此生效。

### 4. BackgroundRefresher 跳过新鲜数据
每个数据源拉取前检查 `db.getFreshCachedWebPage(key, ttl)`——新鲜则跳过。这大幅减少了后台流量（原来每 3 分钟拉全部 14 学期课表+开课情况等）。

## 踩过的坑

- `getPracticeScores` 的 `_db.setCachedWebPage` 在 `scores` 变量声明之前调用——编译没问题但逻辑 bug。修复：移到 for 循环之后、`return Ok(scores)` 之前。
- BackgroundRefresher 需要额外 import `database.dart`（CacheTtl）和 `connectivity_provider.dart`（dataStatusManagerProvider）。
- `getTimetable` 的缓存优先 guard 需复制原有的 `kcb != null && sfyjskc != '1'` 过滤逻辑。

## 可复用的模式

### 缓存优先守卫三元模式
```dart
// 1. 新鲜缓存 → 直接返回
final cached = _tryFreshCache(cacheKey, ttl, parser);
if (cached != null) return Ok(cached);

// 2. 走网络（_withAutoRelogin 内部处理重登+错误回退）
return _withAutoRelogin(() async { ... }, fallbackKey: cacheKey);
// 3. 过期缓存兜底（_withAutoRelogin 在非 Auth 错误时自动 fallback）
```

### WebCacheDatabase.instanceOrNull 用法
在非 ZDBK Service 的类中（ClassroomCrawler、BackgroundRefresher），用 `instanceOrNull` 而非 `await getInstance()`——避免引入不必要的 async 依赖。
