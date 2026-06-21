---
task_type: bug-fix
tags: [testing, dart, flutter, import, transitive-dependency]
files_touched:
  - test/features/zdbk/zdbk_cache_fallback_test.dart
difficulty: easy
outcome: failure
date: 2026-06-20
superseded_by: 自包含纯 Dart 测试（本地类型定义，零 project 依赖）
---

## 尝试了什么

为 ZDBK service 缓存逻辑写测试，直接 import `package:flutter_test/flutter_test.dart` 和 project 类型（`Result`、`Ok`、`Err`、`Grade`、`EverythingResult` 等）。

## 为什么失败

用 `dart test -p vm` 运行时，`package:flutter_test` 依赖 `dart:ui`，纯 Dart VM 不提供此库。错误链：

```
test.dart → flutter_test/flutter_test.dart → dart:ui ❌
```

以为去掉 `flutter_test` 换成 `package:test/test.dart` 就能跑，但仍然失败。因为 `package:evergreen_multi_tools/core/result.dart` → `core/log.dart` → `package:flutter/foundation.dart` → `dart:ui ❌`。

**结论：只要 import 链中任何一环触及 Flutter SDK，`dart test -p vm` 就必定失败。**

## 最终采用了什么替代方案

测试文件完全自包含：
- 本地定义 `R<T>` / `Ok<T>` / `Err<T>`（模拟 `Result<T>` 语义）
- 本地定义 `AppErr`（模拟 `AppError` 语义）
- 本地定义 `TestGrade` / `TestEverything`（模拟 `Grade` / `EverythingResult` 语义）
- 零 project import，零 Flutter import
- 只用 `package:test/test.dart`

## 学到什么

1. **写 Flutter 项目的测试前，先确认运行方式**：`flutter test` vs `dart test -p vm`。如果要用后者，测试文件不能碰任何 Flutter package。
2. **`result.dart` → `log.dart` → `flutter/foundation.dart`** 这个传递依赖链会导致几乎所有 project 类型都无法在纯 VM 测试中使用。
3. 逻辑测试（不涉及 Widget/UI）用自包含类型定义是最稳妥的方案——虽然冗长，但避免了整个 Flutter 依赖图。
