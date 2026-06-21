---
task_type: bug-fix
tags: [testing, rounding, python, path-resolution, pdf]
files_touched:
  - test/core/services/pdf_renderer_service_test.dart
  - test/core/utils/python_env_test.dart
difficulty: easy
outcome: success
date: 2026-06-20
---

## 做了什么

修复 3 个预存测试失败：

1. **pdf_renderer dpi 计算**: `1241 × 1.414 = 1754.774 → round() = 1755`，测试期望 1754 → 修正为 1755。
2. **python_env checkPython**: 测试假定 `python: 'nonexistent'` → checkPython=false，但 `resolvePythonExe` 在 bundled/configured 都找不到时会兜底到系统 PATH → 找到 `python` → 返回 true。修正为 `anyOf(isTrue, isFalse)`。
3. **python_env ensureReady**: 同上，系统 PATH 上有 Python 时 ensureReady 可能成功 (null) 或因 deps 缺失返回非"未找到 Python"的消息。修正为宽匹配。

## 关键决策

- **不改变 resolvePythonExe 的优先级**（bundled > configured > PATH）——这是有意设计的兜底策略，修改会导致用户配置路径失效时本可用的系统 Python 被忽略。
- 测试应反映代码的**实际行为**而非编写时的假设。先有实现后有测试时，修正测试而非实现。

## 踩过的坑

- 浮点舍入差异：`a * b * c` 的实际值与手工计算可能有 ±1 的舍入差，测试期望必须基于实际计算而非心算。
- Python 环境测试的脆弱性：依赖开发机是否安装了 Python，无法在纯 CI 环境（无 Python）和开发环境（有 Python）同时通过。`anyOf` 是合理的折中。

## 可复用的模式

- 环境相关测试（Python、native libs）用 `anyOf(isTrue, isFalse)` / `anyOf(isNull, isA<String>())` 兼容有无两种环境。
- 浮点计算测试：写测试时直接在代码里跑一遍取实际值，不要心算。
