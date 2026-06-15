# P1 — 测试基础设施（细化版）

**阶段：** 前置 | **估时：** 1 周 | **可并行：** 与阶段一~二同时进行

---

## 1. 目录结构

```
test/
├── mocks/                          # Mock 对象
│   ├── mock_dio.dart               # Mock Dio（模拟 HTTP 响应）
│   ├── mock_http_client.dart       # Mock dart:io HttpClient
│   ├── mock_cookie_jar.dart        # Mock PersistCookieJar
│   └── mock_app_config.dart        # Mock AppConfig（注入测试用学号/密码）
│
├── fixtures/                       # 测试数据
│   ├── zdbk/                       # ZDBK（教务管理系统）响应
│   │   ├── transcript_ok.json      # 成绩单正常响应
│   │   ├── transcript_empty.json   # 成绩单空响应（无选课记录）
│   │   ├── transcript_broken.json  # 成绩单解析失败响应（字段缺失）
│   │   ├── exams_ok.json           # 考试列表正常响应
│   │   ├── timetable_ok.json       # 课表正常响应
│   │   └── timetable_null.json     # 课表空响应（"null"）
│   ├── cas/                        # CAS 统一认证
│   │   ├── login_page.html         # 登录页 HTML（含 execution token）
│   │   ├── pubkey_ok.json          # RSA 公钥正常响应
│   │   └── login_success.headers   # 登录成功 Set-Cookie 头
│   ├── deepseek/                   # DeepSeek API
│   │   ├── chat_ok.json            # 正常聊天响应
│   │   ├── chat_rate_limited.json  # 429 限流响应
│   │   ├── chat_context_overflow.json  # 上下文溢出响应
│   │   └── stream_chunks.txt       # 流式响应 chunk 序列
│   └── courses/                    # courses.zju.edu.cn
│       ├── my_courses_ok.json      # 课程列表正常响应
│       └── my_courses_html.html    # 未登录时返回的 CAS 重定向 HTML
│
├── core/                           # 核心模块单元测试
│   ├── result_test.dart            # Result<T> 单元测试（★ 纯函数，无依赖）
│   ├── errors_test.dart            # AppError 子类测试（★ 纯函数）
│   └── log_test.dart               # Log 单例测试
│
├── services/                       # Service 层单元测试
│   ├── zjuam_service_test.dart     # ZjuAmService.login() 测试
│   ├── zdbk_service_test.dart      # ZdbkService 全方法测试
│   ├── deepseek_client_test.dart   # DeepSeekClient 测试
│   ├── courses_api_service_test.dart
│   └── library_service_test.dart
│
├── widgets/                        # Widget 测试
│   └── error_card_test.dart        # ErrorCard 组件测试
│
└── integration/                    # 集成测试（可选，阶段三后展开）
    └── auth_flow_test.dart         # 登录 → ZDBK → 成绩展示全链路
```

---

## 2. Mock 层设计

### 2.1 `MockDio`

封装 `dio` 的拦截器机制，无需真实网络：

```dart
// test/mocks/mock_dio.dart
class MockDio extends DioForNative {
  final Map<String, dynamic> _responses = {};   // URL → 响应体
  final Map<String, int> _statusCodes = {};     // URL → HTTP 状态码
  final List<String> _requestLog = [];          // 已发出的请求 URL 列表

  /// 预设某个 URL 的响应
  void stub(String url, dynamic body, {int statusCode = 200}) {
    _responses[url] = body;
    _statusCodes[url] = statusCode;
  }

  /// 预设某个 URL 抛出 DioException
  void stubError(String url, DioExceptionType type, {int? statusCode}) {
    _responses[url] = _DioErrorMarker(type, statusCode);
  }

  /// 断言某个 URL 被请求过
  void assertRequested(String url) {
    expect(_requestLog, contains(url));
  }

  @override
  Future<Response<T>> get<T>(String path, { ... }) async {
    _requestLog.add(path);
    return _buildResponse<T>(path);
  }

  @override
  Future<Response<T>> post<T>(String path, { ... }) async {
    _requestLog.add(path);
    return _buildResponse<T>(path);
  }

  // ... put, delete 同理
}
```

### 2.2 `MockAppConfig`

注入测试用配置，避免读取真实环境变量：

```dart
// test/mocks/mock_app_config.dart
void setupTestAppConfig({
  String? username = 'test_user',
  String? password = 'test_pass',
  String? apiKey = 'sk-test-key',
  String? model = 'deepseek-v4-flash',
}) {
  // 通过 AppConfig 的测试模式注入
  AppConfig.testMode(
    zjuUsername: username,
    zjuPassword: password,
    deepseekApiKey: apiKey,
    deepseekModel: model,
  );
}
```

### 2.3 `MockHttpClient`

模拟 `dart:io` 的原生 HTTP 客户端（ZjuAmService / ZdbkService 使用）：

```dart
// test/mocks/mock_http_client.dart
class MockHttpClient extends Fake implements HttpClient {
  final Map<String, MockHttpClientResponse> _responses = {};

  void stubGet(String url, {String? body, List<Cookie>? cookies, int statusCode = 200}) {
    _responses[url] = MockHttpClientResponse(body: body, cookies: cookies ?? [], statusCode: statusCode);
  }

  void stubPost(String url, {String? body, List<Cookie>? cookies, int statusCode = 200}) {
    _responses[url] = MockHttpClientResponse(body: body, cookies: cookies ?? [], statusCode: statusCode);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => MockHttpClientRequest(url, 'GET', _responses);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => MockHttpClientRequest(url, 'POST', _responses);
}
```

---

## 3. 测试 Fixture（测试数据）

### 3.1 ZDBK 成绩单（正常）

```json
// test/fixtures/zdbk/transcript_ok.json
{
  "items": [
    {
      "xkkh": "CS101",
      "kcmc": "数据结构基础",
      "xf": "4.0",
      "cj": "92",
      "jd": "4.0",
      "kcsx": "必修",
      "ksxz": "正常"
    },
    {
      "xkkh": "CS201",
      "kcmc": "操作系统",
      "xf": "3.0",
      "cj": "85",
      "jd": "3.7",
      "kcsx": "必修",
      "ksxz": "正常"
    }
  ]
}
```

### 3.2 ZDBK 成绩单（空）

```json
// test/fixtures/zdbk/transcript_empty.json
{ "items": [] }
```

### 3.3 ZDBK 成绩单（字段缺失 — 触发 DataIntegrityError）

```json
// test/fixtures/zdbk/transcript_broken.json
{
  "items": [
    { "kcmc": "数据结构基础", "xf": "not_a_number", "cj": "92" }
  ]
}
```

### 3.4 DeepSeek 上下文溢出响应

```json
// test/fixtures/deepseek/chat_context_overflow.json
{
  "error": {
    "message": "This model's maximum context length is 131072 tokens. However, your request has 250000 tokens.",
    "type": "invalid_request_error",
    "code": "context_length_exceeded"
  }
}
```

### 3.5 DeepSeek 限流响应

```json
// test/fixtures/deepseek/chat_rate_limited.json
{
  "error": {
    "message": "Rate limit exceeded",
    "type": "rate_limit_error"
  }
}
```

---

## 4. 核心模块单元测试（★ 第一优先级）

> 这些测试是**纯函数测试**，不依赖 Flutter 框架，不需要 mock 任何外部依赖。
> 可以用 `dart test` 直接运行，速度极快。

### 4.1 `test/core/result_test.dart` — Result<T> 全覆盖

```
测试目标：验证 Result<T> 的所有组合子行为正确。

测试用例（12 个）：

1. Ok.map — 对 Ok 值应用映射函数 → 返回新 Ok
2. Err.map — 对 Err 应用 map → 错误透传，映射函数不被调用
3. Ok.flatMap — 对 Ok 链式调用 → 返回内层 Result
4. Err.flatMap — 对 Err 链式调用 → 错误透传
5. Ok.unwrap — 返回内部值
6. Err.unwrap — 抛出 AppError
7. Ok.unwrapOr — 返回内部值（不返回 default）
8. Err.unwrapOr — 返回 default 值
9. Ok.fold — 调用 onOk 分支
10. Err.fold — 调用 onErr 分支
11. Ok.isOk / Ok.isErr — 布尔标记正确
12. Err.isOk / Err.isErr — 布尔标记正确

13. Result.fromThrowable — 正常函数 → Ok
14. Result.fromThrowable — 抛出异常的函数 → Err(UnknownError)
15. Result.fromThrowable — Future 正常完成 → Ok
16. Result.fromThrowable — Future 抛出 TimeoutException → Err(UnknownError)

额外验证：
- Ok/Err 的 == 和 hashCode 正确
- sealed class 穷尽匹配（switch 只有两个分支可通过编译）
```

### 4.2 `test/core/errors_test.dart` — AppError 全覆盖

```
测试目标：验证 13 种 AppError 子类的 userMessage 非空、
       debugMessage 非空、recoveryHint 合理。

测试用例（按子类）：

NetworkError (4 个):
17. NetworkError.unreachable → userMessage 含"无法连接"
18. NetworkError.httpStatus(500, url) → userMessage 含"500"; recoveryHint 含"稍后"
19. NetworkError.httpStatus(404, url) → recoveryHint 含"参数"
20. responseBodySnippet 截断 ≤ 200 字符

AuthError (3 个):
21. AuthError.failed("密码错误") → userMessage 含"密码错误"
22. AuthError.expired("ZDBK") → recoveryHint 含"自动重新登录"
23. AuthError.casRedirectFailed → userMessage 含"跳转失败"

ParseError (2 个):
24. ParseError.html(raw, pattern) → userMessage 含"学校系统可能已更新"
25. ParseError.json(raw, field) → userMessage 含"数据格式异常"

DataIntegrityError (3 个):
26. DataIntegrityError.typeMismatch → userMessage 含"数据格式异常"
27. DataIntegrityError.missingField → userMessage 含"数据不完整"
28. DataIntegrityError.logicalError → userMessage 含"数据异常"

CacheError (2 个):
29. CacheError.miss → recoveryHint 含"从服务器重新获取"
30. CacheError.writeFailed → recoveryHint 含"离线时"

TimeoutError (1 个):
31. TimeoutError.request(10, url) → userMessage 含"10秒"

ValidationError (2 个):
32. ValidationError.invalid → userMessage 含字段名
33. ValidationError.required → recoveryHint 含"必填"

MediaError (2 个):
34. MediaError.loadFailed("video", url) → userMessage 含"视频"
35. MediaError.unsupportedFormat("audio", "ogg") → userMessage 含"不支持"

AiModelError (3 个):
36. AiModelError.apiError("deepseek", 429) → userMessage 含"繁忙"
37. AiModelError.apiError("deepseek", 401) → userMessage 含"认证失败"
38. AiModelError.quotaExhausted → recoveryHint 含"充值"

ContextExceededError (2 个):
39. ContextExceededError.overflow — userMessage 含"超出"; recoveryHint 含"新会话"
40. usageRatio — 正确计算 10000/131072 ≈ 0.076

ConfigError (2 个):
41. ConfigError.missing("学号") → recoveryHint 含"配置"
42. ConfigError.invalid("端口", "abc", "int") → userMessage 含"不合法"

FileError (2 个):
43. FileError.operationFailed(path, "write", osError: "No space") → recoveryHint 含"空间不足"
44. FileError.unsupportedFormat(path, "exe") → userMessage 含"不支持"

UnknownError (1 个):
45. UnknownError.from(Exception("test")) → userMessage 含"未知错误"

额外验证：
- 每种错误都有 source（文件名:行号）且不为 null
- AppError 工厂方法返回正确子类型
```

### 4.3 `test/core/log_test.dart` — Log 单例

```
测试目标：验证 Log() 单例的行为

46. Log.debug() 在 debug 模式输出（不崩溃）
47. Log.info() 带 data 参数输出
48. Log.warn() 带 error 参数输出
49. Log.error() 带 stack 参数输出
50. Log().exportRecent() 返回最近 N 条日志
51. Log() 单例模式 — 两次 Log() 调用返回同一实例
```

---

## 5. Service 层单元测试（★ 第二优先级）

> 这些测试依赖 Mock 层。验证 Service 方法的 Result 返回值类型正确。

### 5.1 `test/services/zjuam_service_test.dart`

```
52. ZjuAmService.login() 成功 → Ok(Cookie)
    - 预设 MockHttpClient: CAS 登录页 HTML（含 execution token）
    - 预设公钥 JSON
    - 预设登录成功 Set-Cookie: iPlanetDirectoryPro=xxx
    - 验证: result.isOk == true
    - 验证: result.unwrap().name == 'iPlanetDirectoryPro'

53. ZjuAmService.login() 密码错误 → Err(AuthError.failed)
    - 预设 CAS 响应不含 iPlanetDirectoryPro cookie
    - 验证: result.isErr == true
    - 验证: error.userMessage 含"学号或密码错误"

54. ZjuAmService.login() 网络不可达 → Err(NetworkError.unreachable)
    - 预设 MockHttpClient 抛出 SocketException
    - 验证: error 是 NetworkError 类型

55. ZjuAmService.login() 超时 → Err(TimeoutError)
    - 预设 MockHttpClient 抛出 TimeoutException
    - 验证: error.userMessage 含"超时"

56. ZjuAmService.login() 执行 token 解析失败 → Err(ParseError)
    - 预设登录页 HTML 不含 execution token
    - 验证: error 是 ParseError 类型
```

### 5.2 `test/services/zdbk_service_test.dart`

```
57. ZdbkService.getTranscript() 成功 → Ok(List<Grade>)
    - 预设 __zdbkPost 返回 transcript_ok.json
    - 验证: 返回 2 门成绩

58. ZdbkService.getTranscript() 空响应 → Err(ParseError)
    - 预设 __zdbkPost 返回 transcript_empty.json
    - 验证: error 是 ParseError

59. ZdbkService.getTranscript() 会话过期 → Err(AuthError.expired)
    - 预设 __zdbkPost 返回 CAS 重定向 HTML
    - 验证: _withAutoRelogin 触发重登
    - 验证: 重登失败后返回 Err(AuthError.sessionExpired)

60. ZdbkService.getMajorGrade() → Ok(MajorGradesResult)
    - 验证: result 含 gpa 字段且值合理

61. ZdbkService.getTimetable() 成功 → Ok(List<TimetableSession>)
    - 预设课表 JSON

62. ZdbkService.getTimetable() null 响应 → Ok(空列表)

63. ZdbkService.getCourseOfferings() JSON 成功 → Ok
64. ZdbkService.getCourseOfferings() JSON 解析失败 → Err(ParseError.json)
65. ZdbkService.getCourseOfferings() 模型转换失败 → Err(DataIntegrityError)

66. ZdbkService.getEverything() → Ok(EverythingResult)
    - 验证: 同时获得 grades + exams + GPA
```

### 5.3 `test/services/deepseek_client_test.dart`

```
67. DeepSeekClient.chat() 成功 → Ok(String)
    - 预设 MockDio 返回 chat_ok.json
    - 验证: result.unwrap() 含 AI 回复内容

68. DeepSeekClient.chat() 429 限流 → Err(AiModelError)
    - 预设 MockDio 返回 429，重试 3 次
    - 验证: error 是 AiModelError
    - 验证: error.userMessage 含"繁忙"

69. DeepSeekClient.chat() 上下文溢出 → Err(ContextExceededError)
    - 预设 MockDio 返回 chat_context_overflow.json
    - 验证: error 是 ContextExceededError

70. DeepSeekClient.chat() 网络错误 → Err(UnknownError)
    - 预设 MockDio 抛出连接错误

71. DeepSeekClient.streamChat() 成功 → yield content chunks + done
    - 预设 MockDio 返回 stream_chunks.txt
    - 验证: 收集到至少 3 个 content chunk
    - 验证: 最后 yield done chunk

72. DeepSeekClient.streamChat() 连接失败 → yield error chunk
    - 预设 MockDio 抛出 DioException
    - 验证: 收集到 error chunk
```

---

## 6. Widget 测试（★ 第三优先级）

### 6.1 `test/widgets/error_card_test.dart`

```
73. ErrorCard 展示 message
    - await tester.pumpWidget(ErrorCard(message: '测试错误'))
    - 验证: find.text('测试错误') 存在

74. ErrorCard 展示 detail
    - ErrorCard(message: '标题', detail: '技术细节')
    - 验证: find.text('技术细节') 存在

75. ErrorCard 展示 hint（恢复建议）
    - ErrorCard(message: '错误', hint: '请检查网络后重试')
    - 验证: find.text('请检查网络后重试') 存在
    - 验证: find.byIcon(Icons.lightbulb_outline) 存在

76. ErrorCard 展示 retry 按钮
    - ErrorCard(message: '错误', onRetry: () {})
    - 验证: find.text('重试') 存在

77. ErrorCard retry 按钮回调
    - var called = false
    - ErrorCard(message: '错误', onRetry: () => called = true)
    - await tester.tap(find.text('重试'))
    - 验证: called == true

78. ErrorCard 无 retry 时无按钮
    - ErrorCard(message: '错误')
    - 验证: find.text('重试') 不存在
```

---

## 7. CI 配置

### 7.1 GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.x'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter analyze

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test-dir: [test/core, test/services, test/widgets]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.x'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter test ${{ matrix.test-dir }}
```

### 7.2 CI 缓存策略

- Flutter SDK 缓存：`subosito/flutter-action` 自带
- `pub get` 缓存：GitHub Actions `actions/cache@v4` 缓存 `~/.pub-cache`
- 缓存 key：`pub-${{ runner.os }}-${{ hashFiles('pubspec.lock') }}`

---

## 8. 执行计划（分步实施）

| 步骤 | 内容 | 产出物 | 估时 |
|------|------|--------|------|
| **Step 1** | 搭建 Mock 层 | `test/mocks/mock_dio.dart` + `mock_app_config.dart` | 0.5 天 |
| **Step 2** | 编写 Fixture | `test/fixtures/` 下 15+ JSON/HTML 文件 | 0.5 天 |
| **Step 3** | `result_test.dart` | 16 个纯函数测试 | 0.5 天 |
| **Step 4** | `errors_test.dart` | 29 个纯函数测试（13 种类型全覆盖） | 0.5 天 |
| **Step 5** | `log_test.dart` | 6 个测试 | 0.25 天 |
| **Step 6** | `zjuam_service_test.dart` + `zdbk_service_test.dart` | 14 个测试 | 1 天 |
| **Step 7** | `deepseek_client_test.dart` | 6 个测试 | 0.5 天 |
| **Step 8** | `error_card_test.dart` | 6 个 Widget 测试 | 0.25 天 |
| **Step 9** | CI 配置 | `.github/workflows/test.yml` | 0.25 天 |
| **Step 10** | 集成验证 | `flutter test` 全部通过，CI 绿灯 | 0.5 天 |

**总计：~5 天**（与原始估时"1 周"吻合）

---

## 9. 验收标准（与统一错误处理模块联动）

- [ ] `test/core/result_test.dart` 中 16 个用例全部通过
- [ ] `test/core/errors_test.dart` 中 29 个用例全部通过，覆盖 13 种 AppError 子类
- [ ] `test/core/log_test.dart` 中 6 个用例全部通过
- [ ] `test/services/zjuam_service_test.dart` 验证 `Result<Cookie>` 类型正确
- [ ] `test/services/zdbk_service_test.dart` 验证 `Result<T>` + 会话过期重试
- [ ] `test/services/deepseek_client_test.dart` 验证 `AiModelError` / `ContextExceededError` 正确识别
- [ ] `test/widgets/error_card_test.dart` 验证 `hint` 字段展示正常
- [ ] `flutter test` 总用例数 ≥ 77，通过率 100%
- [ ] `flutter analyze` 零错误零警告
- [ ] CI 绿勾出现在 PR 页面
- [ ] 测试执行时间 < 30 秒（纯函数测试应毫秒级完成）

---

## 10. 风险

| 风险 | 缓解 |
|------|------|
| `MockHttpClient` mock dart:io 的复杂性 | dart:io `HttpClient` 是抽象类，可用 `Fake` + `@override`；如遇困难可降级为只测试 Dio 路径 |
| `ZdbkService` 依赖 `WebCacheDatabase`（drift），需要 mock 数据库 | 注入 mock 数据库或使用 `MemoryDatabase` |
| `flutter_test` 需要 Flutter SDK，CI 环境须安装 | `subosito/flutter-action` 已处理 |
| 某些 Widget 测试依赖 `Theme` 或 `MaterialApp` 包装 | 使用 `MaterialApp(home: ErrorCard(...))` 包装 |
