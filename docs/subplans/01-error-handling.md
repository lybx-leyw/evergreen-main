# 01 — 统一错误处理体系（细化）

**层级：** 〇（零依赖，可立即启动） | **估时：** 设计 2 天 + 渐进迁移（贯穿阶段一~三）  
**阻断：** 所有 Service 和 Provider 的返回值设计依赖此体系

---

## 1. 现状问题

当前代码中的错误处理存在以下问题：

| 问题 | 典型代码 | 后果 |
|---|---|---|
| `print()` 满天飞 | `print('[AuthInterceptor] ❌ Relogin failed')` | 用户不可见，release 模式也输出，无结构化搜索 |
| 裸 `throw Exception` | `throw Exception('courses CAS 登录失败')` | 调用方无法区分错误类型，只能靠字符串匹配 |
| Provider 异常直炸 UI | `FutureProvider` 中 throw → `AsyncValue.error` → 白屏 | 用户看到 unhandled exception 页面 |
| 无超时处理层级 | 每个 Service 自己写 `TimeoutException` catch | 重复代码，缺少统一的重试/降级策略 |
| Cookie/HTML 解析脆弱 | 正则匹配失败直接 `throw` | ZDBK 改版 → 成绩/课表/考试全部不可用 |

---

## 2. 设计目标

1. **类型安全**：编译器强制调用方处理错误分支（`Result` 是 sealed class）
2. **用户可读**：每个错误包含 `userMessage`（中文，可展示）和 `debugMessage`（英文，含技术细节）
3. **可追踪**：日志带调用栈、时间戳、模块标签，release 写文件
4. **渐进迁移**：不强制一次性改完，`Result` 与 `throw` 可短期共存
5. **UI 友好**：`AsyncValue<Result<T>>` → 统一 ErrorCard 组件展示

---

## 3. 核心类型设计

### 3.1 `Result<T>` — 密封类

```dart
// lib/core/result.dart

/// 操作结果：要么成功携带值 [T]，要么失败携带 [AppError]。
sealed class Result<T> {
  const Result();

  /// 映射成功值，错误透传。
  Result<U> map<U>(U Function(T value) fn);

  /// 串联操作：成功则调用下一个返回 Result 的函数。
  Result<U> flatMap<U>(Result<U> Function(T value) fn);

  /// 解包：成功返回值，失败抛 [AppError]（仅在确定是 Ok 时使用）。
  T unwrap();

  /// 解包：成功返回值，失败返回 [defaultValue]。
  T unwrapOr(T defaultValue);

  /// 匹配两个分支。
  U fold<U>(U Function(T value) onOk, U Function(AppError err) onErr);
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
  // ... 实现
}

final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);
  // ... 实现
}
```

**设计决策：**
- 用 Dart 3 的 `sealed class` 而非抽象类 + 子类 → `switch` 可穷尽检查，漏分支编译报错
- `unwrap()` 命名与 Rust 一致，降低学习成本
- `flatMap` 支持链式调用，避免嵌套 if-else

### 3.2 `AppError` — 错误基类

```dart
// lib/core/errors.dart

/// 应用层错误基类。
abstract class AppError implements Exception {
  /// 用户可读的中文错误消息（可直接展示在 UI）。
  String get userMessage;

  /// 开发者调试消息（英文，含技术细节）。
  String get debugMessage;

  /// 原始异常（可选，用于日志链路追踪）。
  Object? get cause;

  /// 错误发生位置（文件名:行号，通过 [StackTrace] 自动捕获）。
  String? get source;

  /// 建议的恢复操作（如 "请检查网络后重试"），可选。
  String? get recoveryHint;

  const AppError();
}
```

**子类层次：**

```
AppError
├── NetworkError         — 网络不可达、DNS 解析失败
│   ├── 包含: statusCode, requestUrl, responseBody(截断)
├── AuthError            — 登录失败、会话过期、cookie 无效
│   ├── 子类: InvalidCredentials, SessionExpired, CasRedirectFailed
├── ParseError           — HTML/JSON 解析失败
│   ├── 包含: rawContent(截断), expectedPattern
├── CacheError           — 缓存读写失败
│   └── 包含: cacheKey, operation(read/write/delete)
├── TimeoutError         — 请求超时
│   └── 包含: timeoutSeconds, requestUrl
├── ValidationError      — 用户输入不合法
│   └── 包含: fieldName, invalidValue, constraint
└── UnknownError         — 未分类错误（兜底）
    └── 包含: originalException 完整信息
```

### 3.3 错误工厂函数

每种错误类型提供语义化的构造器，而非到处 `new`：

```dart
// lib/core/errors.dart

abstract class AppError {
  // 工厂方法示例
  factory AppError.networkUnreachable(String url) = NetworkError.unreachable;
  factory AppError.httpStatus(int code, String url) = NetworkError.httpStatus;
  factory AppError.parseHtml(String raw, String pattern) = ParseError.html;
  factory AppError.parseJson(String raw, String field) = ParseError.json;
  factory AppError.authFailed(String reason) = AuthError.failed;
  factory AppError.sessionExpired(String service) = AuthError.expired;
  factory AppError.timeout(int sec, String url) = TimeoutError.request;
  factory AppError.cacheMiss(String key) = CacheError.miss;
  // ...
}
```

---

## 4. 日志系统设计

### 4.1 `Log` 单例

```dart
// lib/core/log.dart

enum LogLevel { debug, info, warn, error }

class Log {
  static final Log _instance = Log._();
  factory Log() => _instance;
  Log._();

  /// 模块标签（如 'AuthInterceptor'、'ZdbkService'），自动从调用栈提取。
  String? _moduleTag;

  /// debug 模式下输出到 console，release 模式写文件。
  void debug(String message, {Object? data});
  void info(String message, {Object? data});
  void warn(String message, {Object? data, Object? error});
  void error(String message, {Object? data, Object? error, StackTrace? stack});

  /// 导出最近 N 条日志（供用户反馈时附上）。
  Future<String> exportRecent({int lines = 200});
}
```

### 4.2 日志格式

```
[2026-07-14 14:32:01.123] [ERROR] [AuthInterceptor] Session expired for courses.zju.edu.cn
  url: https://courses.zju.edu.cn/user/index
  status: 302
  recovery: 正在尝试自动重新登录...
  stack: #0 AuthInterceptor._isSessionExpiredError (package:evergreen/core/network/auth_interceptor.dart:42)
```

### 4.3 日志存储

- Debug 模式：`stderr`（同步，不丢日志）
- Release 模式：`~/AppData/Local/evergreen/logs/`（Windows）或 `~/Library/Logs/evergreen/`（macOS）
- 文件轮转：单文件最大 5MB，保留最近 5 个文件
- `exportRecent()`：直接返回文本，方便用户复制粘贴到 GitHub Issue

---

## 5. Service 层迁移示例

### 迁移前（当前代码）

```dart
Future<ZjuAmResult> login(String username, String password) async {
  try {
    final res1 = await _client.getUrl(_u('/cas/login')).timeout(...);
    final body1 = await res1.transform(utf8.decoder).join();
    final execMatch = RegExp(r'name="execution"\s+value="([^"]+)"').firstMatch(body1);
    if (execMatch == null) {
      return ZjuAmResult.failure('无法获取 execution token');
    }
    // ...
  } on SocketException {
    return ZjuAmResult.failure('无法连接统一认证服务器');
  } on TimeoutException {
    return ZjuAmResult.failure('登录超时');
  } catch (e) {
    return ZjuAmResult.failure('登录异常: $e');
  }
}
```

### 迁移后

```dart
Future<Result<Cookie>> login(String username, String password) async {
  try {
    final res1 = await _client.getUrl(_u('/cas/login'))
        .timeout(const Duration(seconds: 10));
    final body1 = await res1.transform(utf8.decoder).join();

    final execMatch = RegExp(r'name="execution"\s+value="([^"]+)"').firstMatch(body1);
    if (execMatch == null) {
      return Err(AppError.parseHtml(
        body1.substring(0, min(body1.length, 200)),
        'execution token',
      ));
    }
    // ... 成功后
    return Ok(iPlanetCookie);

  } on SocketException catch (e) {
    Log().warn('ZJUAM unreachable', error: e);
    return Err(AppError.networkUnreachable('zjuam.zju.edu.cn')
      ..recoveryHint = '请检查网络连接后重试');

  } on TimeoutException catch (e) {
    return Err(AppError.timeout(10, 'zjuam.zju.edu.cn/cas/login')
      ..recoveryHint = '服务器响应较慢，请稍后重试');

  } catch (e, stack) {
    Log().error('Unexpected login error', error: e, stack: stack);
    return Err(AppError.unknown(e)
      ..recoveryHint = '请尝试重新登录，或联系开发者');
  }
}
```

**关键变化：**
- 不再自定义 `ZjuAmResult` 类 → 统一用 `Result<Cookie>`
- 每种 catch 分支返回语义化 `AppError`，含 `recoveryHint`
- `Log()` 记录上下文，后续可追溯

---

## 6. Provider 层迁移示例

### 迁移前

```dart
final zdbkEverythingProvider = FutureProvider<EverythingResult>((ref) async {
  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.read(authProvider);
  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    throw Exception('请先登录统一认证');
  }
  return service.getEverything(httpClient);
});
```

### 迁移后

```dart
final zdbkEverythingProvider = FutureProvider<Result<EverythingResult>>((ref) async {
  final service = await ref.read(zdbkServiceInstanceProvider.future);
  final auth = ref.read(authProvider);

  if (!auth.isLoggedIn || auth.ssoCookie == null) {
    return Err(AppError.authFailed('未登录').recovery('请先在设置中配置学号和密码'));
  }

  return service.getEverything(httpClient); // 已返回 Result<EverythingResult>
});
```

---

## 7. UI 层解包

```dart
// scores_screen.dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final resultAsync = ref.watch(zdbkEverythingProvider);

  return resultAsync.when(
    loading: () => const LoadingIndicator(),
    error: (e, _) => ErrorCard(
      title: '加载失败',
      message: e is AppError ? e.userMessage : '未知错误',
      hint: e is AppError ? e.recoveryHint : null,
      onRetry: () => ref.invalidate(zdbkEverythingProvider),
    ),
    data: (result) => result.fold(
      (everything) => ScoresContent(data: everything),   // Ok → 正常展示
      (error) => ErrorCard(                              // Err → 错误卡片 + 重试
        title: '数据获取失败',
        message: error.userMessage,
        hint: error.recoveryHint,
        onRetry: () => ref.invalidate(zdbkEverythingProvider),
      ),
    ),
  );
}
```

---

## 8. 渐进迁移策略

不要求一次性全改。三阶段推进：

| 阶段 | 范围 | 策略 |
|---|---|---|
| 阶段一（设计） | `core/result.dart` + `core/errors.dart` + `core/log.dart` | 新文件，不影响现有代码 |
| 阶段二（核心） | `ZjuAmService`、`ZdbkService`、`AuthNotifier` | 率先迁移为 `Result<T>` 返回值 |
| 阶段三（扩展） | 其余 12 个 Feature Service | 按模块优先级逐个迁移 |

**兼容期：** 提供 `Result.fromThrowable(Future<T> fn)` 适配器，让未迁移的 Service 方法也能被 `Result` 包装：

```dart
static Future<Result<T>> fromThrowable<T>(Future<T> Function() fn) async {
  try {
    return Ok(await fn());
  } catch (e, stack) {
    Log().error('Unhandled exception', error: e, stack: stack);
    return Err(AppError.unknown(e));
  }
}
```

---

## 9. 与现有 `print()` 的共存期

阶段一不删除任何现有 `print()`，而是并行引入 `Log()`：

```dart
// 旧代码保留
print('[AutoLogin] courses redirect: $url');

// 新代码追加
Log().debug('Courses redirect', data: {'url': url});
```

阶段五 UI 优化时批量替换 `print()` → `Log()`。

---

## 10. 测试策略

- `Result<T>` 的 `map`/`flatMap`/`fold`/`unwrap` 单元测试（纯函数，无依赖）
- `AppError` 子类的 `userMessage` 覆盖测试（确保中文消息不为空、有 `recoveryHint`）
- Mock Service 返回 `Err(...)`，验证 UI 层正确展示 `ErrorCard`
- 日志文件轮转测试：写入 6MB → 验证旧文件被删除

---

## 11. 验收标准

- [ ] `core/result.dart` 单元测试 100% 覆盖
- [ ] `AppError` 所有子类的 `userMessage` 不为空
- [ ] ZjuAmService.login() 返回 `Result<Cookie>` 而非自定义 `ZjuAmResult`
- [ ] ZdbkService 所有方法返回 `Result<T, AppError>`
- [ ] 至少一个 Feature 的 UI 层正确展示 `ErrorCard`（含 retry 按钮）
- [ ] Release 模式日志写入文件（非 stderr）
- [ ] 旧 `print()` 在阶段五前可保留，但新代码禁止新增裸 print

---

## 12. 风险

| 风险 | 缓解 |
|---|---|
| Provider 从 `FutureProvider<T>` 改为 `FutureProvider<Result<T>>` 导致所有 UI 代码报编译错误 | 阶段性迁移：先用 `Result.fromThrowable` 包装旧 Service，UI 层逐步适配 |
| `sealed class` 要求 Dart 3.x，老版本崩溃 | 检查 `pubspec.yaml` 已设 `sdk: ^3.9.2`，确认 CI 使用对应版本 |
| 过度抽象导致简单 Service 变复杂 | `Result.fromThrowable()` 提供快捷包装，不强制每个 Service 方法手写 catch |
