# 07 — 网络层加固（细化版）

**阶段：** 一 | **估时：** 2 天 | **依赖：** 01 错误处理体系 + Log

---

## 1. 现状审计

### 1.1 四个拦截器现状

| 拦截器 | 行数 | `print()` 调用 | 风险 |
|--------|:---:|:---:|------|
| `AuthInterceptor` | 110 | 9 处 | Release 模式也输出敏感 URL/Cookie |
| `RetryInterceptor` | 75 | 2 处 | 新建 `Dio()` 每次重试（浪费）、延迟无上限（最大可达 32s+） |
| `DebugInterceptor` | 100 | 6 处 | 无 `kDebugMode` 条件编译——release 也打印完整请求/响应体 |
| `CookieStore` | 80 | 0 | ✅ 无 print，但 JSON 文件无事务保护 |

### 1.2 具体问题

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | `print()` → release 泄露 URL + 部分 Cookie | 全部拦截器 | 安全 + 性能 |
| 2 | `RetryInterceptor` 每次重试 `Dio()` 新建实例 | L56 | 浪费资源 |
| 3 | 延迟无上限 `pow(2, 5) = 32s` | L48 | 用户等待过久 |
| 4 | `DebugInterceptor` release 也输出 | L15-55 | 日志文件膨胀 |
| 5 | `AuthInterceptor` 没有 deep copy request options | L28 | 重试时可能携带过期 headers |
| 6 | 无 `NetworkConfig` 集中管理 | — | 超时/域名散落各处 |
| 7 | `AuthInterceptor` 没有 `Log()` 集成 | — | 与统一错误处理体系脱节 |

---

## 2. 设计目标

1. **`print()` → `Log()`**：全部拦截器统一使用 `Log()`（已在 01 子计划实现）
2. **`NetworkConfig`**：超时 + ZJU 域名白名单集中管理
3. **`RetryInterceptor`**：jitter 延迟上限 30s + 复用 Dio 实例
4. **`DebugInterceptor`**：`kDebugMode` 条件编译，release 零开销
5. **`AuthInterceptor`**：deep copy request options + `Log()` 迁移

---

## 3. 核心设计

### 3.1 `NetworkConfig` — 集中配置

```dart
// lib/core/network/network_config.dart

/// 网络层集中配置——替代散落的魔术数字。
class NetworkConfig {
  NetworkConfig._();

  // ── 超时 ──

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration casValidateTimeout = Duration(seconds: 5);

  // ── 重试 ──

  static const int maxRetries = 3;
  static const Duration maxRetryDelay = Duration(seconds: 30);
  static const Set<int> retryableStatusCodes = {429, 502, 503};

  // ── ZJU 域名白名单 ──

  static const Set<String> zjuDomains = {
    'zjuam.zju.edu.cn',
    'zdbk.zju.edu.cn',
    'courses.zju.edu.cn',
    'classroom.zju.edu.cn',
    'tgmedia.cmc.zju.edu.cn',
    'education.cmc.zju.edu.cn',
    'yjapi.cmc.zju.edu.cn',
    'api.lib.zju.edu.cn',
    'chalaoshi.top',
  };

  static bool isZjuDomain(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return zjuDomains.contains(host);
  }
}
```

### 3.2 `AuthInterceptor` 修复

| 修改 | 旧 | 新 |
|------|-----|-----|
| 日志 | `print('[AuthInterceptor] ❌ ...')` | `Log().warn('Auth session expired', data: {...})` |
| 重试 | `_dio.fetch(opts)` — 可变引用 | `_dio.fetch(_cloneOptions(opts))` — deep copy |
| 回退计数 | 实例级 `_reloginAttempts` 不重置 | 成功后 `resetReloginCounter()` |

### 3.3 `RetryInterceptor` 修复

| 修改 | 旧 | 新 |
|------|-----|-----|
| 延迟上限 | `pow(2, retryCount)` 无上限 | `min(pow, NetworkConfig.maxRetryDelay)` |
| Dio 实例 | 每次 `Dio()` 新建 | 构造函数注入 `_dio` |
| 日志 | `print('[Retry] 🔄 ...')` | `Log().warn('Retrying request', data: {...})` |

### 3.4 `DebugInterceptor` 修复

| 修改 | 旧 | 新 |
|------|-----|-----|
| 条件编译 | 无 | `if (!kDebugMode) return;` — 每个方法顶部 |
| 日志 | `print('>>> [GET] ...')` | `Log().debug('HTTP >>', data: {...})` |

---

## 4. 执行计划

| 步骤 | 内容 | 估时 |
|------|------|------|
| **Step 1** | 创建 `NetworkConfig` | 0.1 天 |
| **Step 2** | `AuthInterceptor` `print()` → `Log()` + deep copy | 0.2 天 |
| **Step 3** | `RetryInterceptor` 延迟上限 + 复用 Dio | 0.2 天 |
| **Step 4** | `DebugInterceptor` `kDebugMode` + `Log()` | 0.15 天 |
| **Step 5** | `dio_client.dart` 统一传入 `NetworkConfig` 超时 | 0.1 天 |
| **Step 6** | 测试：Mock 302 / 429 / 502 | 0.25 天 |
| **Step 7** | 全量回归 | 0.1 天 |

---

## 5. 验收标准

- [ ] `AuthInterceptor` 无 `print()` 调用
- [ ] `RetryInterceptor` 无 `print()` 调用，延迟 ≤ 30s
- [ ] `DebugInterceptor` release 模式零输出
- [ ] `NetworkConfig` 超时值被 `dio_client.dart` 使用
- [ ] `flutter analyze` 零警告
- [ ] 现有 150 测试全绿
