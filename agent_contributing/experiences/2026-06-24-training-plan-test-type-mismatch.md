---
task_type: bug-fix
tags: [testing, training-plan, type-mismatch, compilation-error]
files_touched:
  - test/features/zdbk/training_plan_screen_test.dart
  - lib/core/models/training_plan.dart
difficulty: easy
outcome: failure
date: 2026-06-24
superseded_by: (同 PR 内修复)
---

## 尝试了什么
为培养方案页面测试编写 `_makePlan()` 辅助函数时，`minCredits` 参数声明为 `int`。

## 为什么失败
`TrainingPlan.minCredits` 字段类型是 `double`（默认值 `0`），传 `int` 类型字面量 `160` 导致编译错误：
```
Error: The argument type 'int' can't be assigned to the parameter type 'double'.
```

## 发现的问题
- 编译期类型检查失败，Dart 不会自动将 `int` 提升为 `double`（与 `num` 不同）
- 测试文件未能在提交前通过编译验证

## 学到什么
1. **写测试辅助函数时，必须对照模型源码确认字段类型**，不能凭记忆或猜测
2. `int` 字面量不能直接传给 `double` 参数，需显式写 `160.0` 或将参数声明为 `double`
3. 提交前必须运行 `flutter test` 确认编译通过

## 最终采用了什么替代方案
将 `_makePlan` 中 `minCredits` 参数类型从 `int` 改为 `double`，默认值改为 `160.0`。
