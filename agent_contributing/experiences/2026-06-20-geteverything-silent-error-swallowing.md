---
task_type: bug-fix
tags: [zdbk, cache, error-handling, provider, grades, transcript]
files_touched:
  - lib/features/zdbk/services/zdbk_service.dart
  - lib/features/zdbk/providers/zdbk_provider.dart
difficulty: medium
outcome: success
date: 2026-06-20
---

## 做了什么

修复 `getEverything()` 静默吞错误导致成绩缓存被空数据覆盖的 bug。三处改动：

1. **`getEverything()`**: 当 `getTranscript` 和 `getExams` 都失败时，返回 `Err` 而非 `Ok(空数据)`，让 provider 的缓存回退逻辑有机会执行。
2. **`zdbkEverythingProvider`**: 增加空数据守卫 — 当 fetch 返回 `grades.isEmpty && exams.isEmpty` 时不覆盖已有内存缓存。
3. **`getTranscript()`**: 将缓存回退从泛型 `_withAutoRelogin` 移到方法自身，正确执行 `Grade.fromJson` 反序列化，消除 `List<Map>` 被强转为 `List<Grade>` 的类型安全隐患。

## 关键决策

- **错误传播优于静默吞错误**：`getEverything` 是编排方法，部分失败时应让调用方（provider）决定如何处理，而不是自行折叠为空。
- **双层守卫**：service 层（`getEverything` 返回 `Err`）+ provider 层（空数据不覆盖缓存），即使一层漏了，另一层也能兜底。

## 踩过的坑

- `_withAutoRelogin` 的 `fallbackKey` 缓存回退是泛型的 — 它总是返回 `Ok(List<Map>) as Result<T>`。当 `T = List<Grade>` 时这会在运行时崩溃（`GpaCalculator` 调用 `grade.realId` 时 `NoSuchMethodError`）。其他使用 `fallbackKey` 的方法（`getTimetable`、`getCourseOfferings` 等）有相同的隐患。
- `Future.wait` 会擦除类型为 `List<Result<dynamic>>`，后续的 `as Result<List<Grade>>` 转型在 Dart 中对泛型参数不做运行时检查。

## 可复用的模式

- **编排方法的错误传播**：编排方法（如 `getEverything`）不应静默折叠子调用的错误。应区分"全部失败"和"部分成功"，全部失败时向上传播错误。
- **缓存写入的守卫条件**：在 provider 层对空结果增加守卫（`if isEmpty → use cached`），这是防御网络半失败的廉价保险。
- **缓存回退的类型安全**：涉及对象反序列化的缓存回退应放在具体方法内（而非泛型基方法），确保正确的 `fromJson` 调用。

## 注意事项

- `getTimetable`、`getCourseOfferings`、`getMajorGrade`、`getPracticeScores`、`getNotifications` 仍有相同的 `_withAutoRelogin` + `fallbackKey` 类型不匹配隐患，后续遇到相关 bug 时优先排查此处。
- `FreshnessBadge` 读取的是文件缓存时间戳（`getCacheTimestamp`），不是内存缓存。即使内存缓存被覆盖，badge 仍显示文件缓存的真实时间。
