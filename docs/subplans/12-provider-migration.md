# 12 — Provider Result 迁移

**层级：** 三 | **估时：** 3 天 | **依赖：** 01 错误处理, 09 登录, 10 ZDBK

## 目标

Auth 和 ZDBK 的 Provider 率先迁移到 `Result<T>` 错误模型。

## 任务

- [ ] `authProvider` 迁移：`login()` / `restoreSession()` 返回 `Result`
- [ ] `zdbkServiceInstanceProvider` 所有 FutureProvider 迁移
- [ ] 下游 Feature Provider 同步适配

## 验收

- [ ] 登录失败 → UI 展示 `Result.err.userMessage`
- [ ] ZDBK 请求失败 → UI 展示友好错误 + 重试按钮
