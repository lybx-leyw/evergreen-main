---
task_type: bug-fix
tags: [freshness, data-status, cacheKey, timestamp, ui-consistency]
files_touched:
  - lib/core/connectivity/data_status_manager.dart
  - lib/features/connectivity/screens/quick_connect_screen.dart
difficulty: medium
outcome: success
date: 2026-06-20
related_pr: 2026-06-20-cache-architecture-freshness-fix.md
---

## 做了什么

修复数据新鲜度面板的三个 bug：
1. cacheKey=null 的数据源时间戳一次赋值后永不过期导致永久"过期"
2. "在线" subtitle 与"过期" badge 自相矛盾
3. 遗漏 ZDBK 主修成绩和实践分数两个数据源注册

## 关键决策

### 1. 删除 `??= now` 而非改为 `= now`
曾经考虑改为每次都赋值 `now`——这样 cacheKey=null 的源永远显示"新鲜"。但这会伪造数据状态。最终选择：不自动填充，依赖 `updateDataStatus()` 在手动刷新时显式设置。初始状态"从未"比"新鲜（伪造）"更诚实。

### 2. `s.relativeTime` 替代 `s.cacheKey == null ? '在线' : s.relativeTime`
"在线"描述的是连通性（service reachable），而数据新鲜度面板展示的是数据时效。两个维度不应在同一个 UI 元素中混用。统一用 `relativeTime` 后，badge（新鲜/过期/从未）和 subtitle（时间描述）语义一致。

### 3. 补充 ZDBK 主修成绩 + 实践分数
这两个数据源在 ZDBK Service 中有缓存写入（`zdbk_MajorGrade`、`zdbk_practiceScores`），但 DataStatusManager 从未注册。补全后用户在数据状态面板可以看到全部 ZDBK 数据源的新鲜度。

## 踩过的坑

- `refreshFreshness` 的 `??=` 看似无害——第一次打开面板时所有 cacheKey=null 源都显示"新鲜"，5 分钟后全部变成"过期"且永不恢复。根因是 `??=` 只在 null 时赋值，过期后旧的 `lastFetchedAt` 不会自动更新。
- 删除 `??= now` 后，`data_status_test.dart` 中 "refreshFreshness without cache keeps timestamps null" 测试仍然通过——这正是期望行为。

## 可复用的模式

### 数据新鲜度 ≠ 服务连通性
两者是正交维度：
- 连通性 = 现在能否连上服务器（ConnectionManager）
- 新鲜度 = 缓存数据有多旧（DataStatusManager / WebCacheDatabase timestamps）

UI 不应把两个概念混在同一个 label 里。FreshnessBadge 只展示数据时效，连通性在服务连通性面板单独展示。
