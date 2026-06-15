# 10 — ZDBK Service 加固（细化版）

**层级：** 二 | **估时：** 1.5 天 | **依赖：** 01 错误处理, 04 数据模型

---

## 1. 现状审计

| 项目 | 状态 |
|------|------|
| `Result<T>` 返回类型 | ✅ 已在子计划 01 完成 |
| `AppError` 错误类型 | ✅ 全部方法返回 `Err(ParseError/NetworkError/...)` |
| 会话过期重登 | ✅ `_withAutoRelogin` 已实现 |
| 缓存回退 | ✅ `fallbackKey` 机制已实现 |
| 正则集中管理 | ❌ 散落在 `getTimetable`、`HtmlParser` 各处 |
| 缓存 TTL | ❌ `WebCacheDatabase` 无时间戳，缓存永不过期 |
| 并发请求 | ❌ `getEverything()` 串行，无 `Future.wait` |

---

## 2. 执行计划

| 步骤 | 内容 | 估时 |
|------|------|------|
| **Step 1** | 创建 `ZdbkPatterns`——正则集中管理 | 0.15 天 |
| **Step 2** | 缓存加时间戳 + `isStale` 标记 | 0.3 天 |
| **Step 3** | `getEverything()` 并发 | 0.1 天 |
| **Step 4** | 测试 + 全量回归 | 0.2 天 |

---

## 3. 验收标准

- [ ] `ZdbkPatterns` 集中所有 ZDBK 正则
- [ ] 缓存有 TTL，超时返回 `isStale: true`
- [ ] `getEverything()` 使用 `Future.wait` 并发
- [ ] 171 测试全绿
