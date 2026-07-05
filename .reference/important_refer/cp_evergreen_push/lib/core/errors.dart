import 'dart:math';

/// 应用层错误基类。
///
/// 每个错误同时包含：
/// - [userMessage]：用户可读的中文消息（可直接展示在 UI）
/// - [debugMessage]：开发者调试消息（英文，含技术细节）
/// - [recoveryHint]：建议的恢复操作（可选）
///
/// 子类层次（13 种）：
/// ```
/// AppError
/// ├── NetworkError         — 网络不可达、HTTP 状态异常
/// ├── AuthError            — 登录失败、会话过期
/// ├── ParseError           — HTML/JSON/iCal/YAML 语法层解析失败
/// ├── DataIntegrityError   — 数据解析成功但结构/类型不符合预期（语义层）
/// ├── CacheError           — 缓存读写失败
/// ├── TimeoutError         — 请求超时
/// ├── ValidationError      — 用户输入不合法
/// ├── MediaError           — 媒体播放失败（视频/音频/PPT）
/// ├── AiModelError         — AI 模型 API 调用失败（限流/认证/不可用）
/// ├── ContextExceededError — AI 上下文超出窗口限制
/// ├── ConfigError          — 配置缺失或无效
/// ├── FileError            — 文件读写失败（磁盘满/权限/格式）
/// ├── RenderError          — Widget 渲染失败、布局溢出、数据到 UI 映射问题
/// └── UnknownError         — 未分类错误（兜底）
/// ```
abstract class AppError implements Exception {
  /// 用户可读的中文错误消息（可直接展示在 UI）。
  String get userMessage;

  /// 开发者调试消息（英文，含技术细节）。
  String get debugMessage;

  /// 原始异常（可选，用于日志链路追踪）。
  Object? get cause;

  /// 错误发生位置（文件名:行号），通过 [StackTrace] 自动捕获。
  String? get source;

  /// 建议的恢复操作（如 "请检查网络后重试"），可选。
  String? _recoveryHint;
  String? get recoveryHint => _recoveryHint;
  set recoveryHint(String? hint) => _recoveryHint = hint;

  AppError();

  /// 捕获当前调用栈并提取文件名:行号。
  static String? _captureSource() {
    try {
      final stack = StackTrace.current;
      final frames = stack.toString().split('\n');
      for (final frame in frames) {
        final trimmed = frame.trim();
        if (trimmed.isEmpty) continue;
        final match = RegExp(r'\((.*?)\)').firstMatch(trimmed);
        if (match != null) {
          final source = match.group(1)!;
          if (source.contains('errors.dart')) continue;
          return source;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── 语义化工厂方法（13 种） ──────────────────────────────────────

  factory AppError.networkUnreachable(String url) =>
      NetworkError.unreachable(url);

  factory AppError.httpStatus(int code, String url) =>
      NetworkError.httpStatus(code, url);

  factory AppError.parseHtml(String raw, String expectedPattern) =>
      ParseError.html(raw, expectedPattern);

  factory AppError.parseJson(String raw, String field) =>
      ParseError.json(raw, field);

  factory AppError.authFailed(String reason) => AuthError.failed(reason);

  factory AppError.sessionExpired(String service) =>
      AuthError.expired(service);

  factory AppError.timeout(int sec, String url) => TimeoutError.request(sec, url);

  factory AppError.cacheMiss(String key) => CacheError.miss(key);

  factory AppError.dataIntegrity(
          String source, String field, String expected, String actual) =>
      DataIntegrityError.typeMismatch(source, field, expected, actual);

  factory AppError.mediaFailed(String type, String url, {String? codec}) =>
      MediaError.loadFailed(type, url, codec: codec);

  factory AppError.aiModelError(String model, int? statusCode) =>
      AiModelError.apiError(model, statusCode);

  factory AppError.contextExceeded(
          String model, int currentTokens, int maxTokens) =>
      ContextExceededError.overflow(model, currentTokens, maxTokens);

  factory AppError.configMissing(String key) => ConfigError.missing(key);

  factory AppError.renderError(String widget, String field, String reason) =>
      RenderError._(
        userMessage: '界面显示异常',
        debugMessage: 'Render error in $widget.$field: $reason',
        widgetName: widget,
        fieldPath: field,
      )..recoveryHint = '请尝试刷新页面';

  factory AppError.fileError(String path, String operation,
          {String? osError}) =>
      FileError.operationFailed(path, operation, osError: osError);

  factory AppError.downloadFailed(String url, {String? reason}) =>
      FileError._(
        userMessage: '文件下载失败',
        debugMessage: 'Download failed: $url${reason != null ? ' — $reason' : ''}',
        filePath: url,
        operation: 'download',
        cause: reason,
      )..recoveryHint = '下载失败，可尝试：\n'
          '1. 检查网络连接\n'
          '2. 确认 ZDBK 登录状态\n'
          '3. 在浏览器中手动打开培养方案页面';

  factory AppError.unknown(Object exception) => UnknownError.from(exception);

  factory AppError.validationError(String message) =>
      ValidationError._(
        userMessage: message,
        debugMessage: 'Validation error: $message',
      )..recoveryHint = '请检查输入后重试';

  factory AppError.translationFailed(String message, [String? details]) =>
      TranslationError._(
        userMessage: message,
        debugMessage: details != null
            ? 'Translation failed: $message — $details'
            : 'Translation failed: $message',
        cause: details,
      )..recoveryHint = '翻译失败，请检查 API Key 和网络连接后重试';


  @override
  String toString() => '$runtimeType: $userMessage';
}

// ═══════════════════════════════════════════════════════════════════════════
// 原有 7 种错误子类
// ═══════════════════════════════════════════════════════════════════════════

/// 网络错误 —— 网络不可达、DNS 解析失败、HTTP 状态异常。
class NetworkError extends AppError {
  final int? statusCode;
  final String requestUrl;
  final String? _responseBody;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  NetworkError._({
    required this.userMessage,
    required this.debugMessage,
    required this.requestUrl,
    this.statusCode,
    String? responseBody,
    this.cause,
    String? source,
  }) : _responseBody = responseBody,
       source = source ?? AppError._captureSource();

  factory NetworkError.unreachable(String url) => NetworkError._(
        userMessage: '无法连接到服务器',
        debugMessage: 'Server unreachable: $url',
        requestUrl: url,
      )..recoveryHint = '请检查网络连接后重试';

  factory NetworkError.httpStatus(int code, String url) => NetworkError._(
        userMessage: '服务器返回错误 ($code)',
        debugMessage: 'HTTP $code for $url',
        requestUrl: url,
        statusCode: code,
      )..recoveryHint =
            code >= 500 ? '服务器暂时不可用，请稍后重试' : '请检查请求参数后重试';

  String? get responseBodySnippet => _responseBody != null
      ? _responseBody!.substring(0, min(_responseBody!.length, 200))
      : null;

  @override
  bool operator ==(Object other) =>
      other is NetworkError &&
      other.statusCode == statusCode &&
      other.requestUrl == requestUrl;

  @override
  int get hashCode => Object.hash(statusCode, requestUrl);
}

/// 认证错误 —— 登录失败、会话过期、CAS 重定向失败。
class AuthError extends AppError {
  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  AuthError._({
    required this.userMessage,
    required this.debugMessage,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory AuthError.failed(String reason) => AuthError._(
        userMessage: '登录失败：$reason',
        debugMessage: 'Auth failed: $reason',
      )..recoveryHint = '请检查学号和密码是否正确';

  factory AuthError.expired(String service) => AuthError._(
        userMessage: '登录会话已过期',
        debugMessage: 'Session expired for $service',
      )..recoveryHint = '正在尝试自动重新登录…';

  factory AuthError.casRedirectFailed(String detail) => AuthError._(
        userMessage: '统一认证跳转失败',
        debugMessage: 'CAS redirect failed: $detail',
      )..recoveryHint = '请尝试重新登录';
}

/// 解析错误 —— HTML/JSON/iCal/YAML 语法层解析失败。
class ParseError extends AppError {
  final String? _rawContent;
  final String? expectedPattern;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  ParseError._({
    required this.userMessage,
    required this.debugMessage,
    String? rawContent,
    this.expectedPattern,
    this.cause,
    String? source,
  }) : _rawContent = rawContent,
       source = source ?? AppError._captureSource();

  factory ParseError.html(String raw, String pattern) => ParseError._(
        userMessage: '数据解析失败，学校系统可能已更新',
        debugMessage: 'Failed to parse HTML: expected "$pattern"',
        rawContent: raw,
        expectedPattern: pattern,
      )..recoveryHint = '请稍后重试，如持续出现请向开发者反馈';

  factory ParseError.json(String raw, String field) => ParseError._(
        userMessage: '数据格式异常',
        debugMessage: 'Failed to parse JSON field: $field',
        rawContent: raw,
        expectedPattern: field,
      )..recoveryHint = '请稍后重试，如持续出现请向开发者反馈';

  String? get rawContentSnippet => _rawContent != null
      ? _rawContent!.substring(0, min(_rawContent!.length, 200))
      : null;
}

/// 缓存错误 —— 缓存读写失败。
class CacheError extends AppError {
  final String cacheKey;
  final String operation;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  CacheError._({
    required this.userMessage,
    required this.debugMessage,
    required this.cacheKey,
    required this.operation,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory CacheError.miss(String key) => CacheError._(
        userMessage: '本地缓存不可用',
        debugMessage: 'Cache miss: $key',
        cacheKey: key,
        operation: 'read',
      )..recoveryHint = '正在从服务器重新获取数据';

  factory CacheError.writeFailed(String key, {Object? cause}) => CacheError._(
        userMessage: '本地数据保存失败',
        debugMessage: 'Cache write failed: $key',
        cacheKey: key,
        operation: 'write',
        cause: cause,
      )..recoveryHint = '不影响正常使用，但离线时可能无法查看历史数据';
}

/// 超时错误 —— 请求超时。
class TimeoutError extends AppError {
  final int timeoutSeconds;
  final String requestUrl;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  TimeoutError._({
    required this.userMessage,
    required this.debugMessage,
    required this.timeoutSeconds,
    required this.requestUrl,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory TimeoutError.request(int sec, String url) => TimeoutError._(
        userMessage: '请求超时（${sec}秒）',
        debugMessage: 'Request timed out after ${sec}s: $url',
        timeoutSeconds: sec,
        requestUrl: url,
      )..recoveryHint = '服务器响应较慢，请稍后重试';
}

/// 验证错误 —— 用户输入不合法。
class ValidationError extends AppError {
  final String? fieldName;
  final String? invalidValue;
  final String? constraint;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  ValidationError._({
    required this.userMessage,
    required this.debugMessage,
    this.fieldName,
    this.invalidValue,
    this.constraint,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory ValidationError.invalid(
          String field, String value, String constraint) =>
      ValidationError._(
        userMessage: '输入不合法：$field',
        debugMessage:
            'Validation failed: $field="$value", expected $constraint',
        fieldName: field,
        invalidValue: value,
        constraint: constraint,
      )..recoveryHint = '请检查 $field 的输入格式';

  factory ValidationError.required(String field) => ValidationError._(
        userMessage: '请填写 $field',
        debugMessage: 'Required field missing: $field',
        fieldName: field,
        constraint: 'required',
      )..recoveryHint = '$field 为必填项，请填写后重试';
}

// ═══════════════════════════════════════════════════════════════════════════
// 扩展 6 种错误子类（阶段一设计补充）
// ═══════════════════════════════════════════════════════════════════════════

/// 媒体播放错误 —— 视频/音频/PPT 加载或解码失败。
class MediaError extends AppError {
  final String mediaType;
  final String sourceUrl;
  final String? codecError;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  MediaError._({
    required this.userMessage,
    required this.debugMessage,
    required this.mediaType,
    required this.sourceUrl,
    this.codecError,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory MediaError.loadFailed(String type, String url, {String? codec}) =>
      MediaError._(
        userMessage: '${_label(type)}加载失败',
        debugMessage: codec != null
            ? 'Failed to load $type: codec error — $codec'
            : 'Failed to load $type from $url',
        mediaType: type,
        sourceUrl: url,
        codecError: codec,
      )..recoveryHint = '请检查网络连接，或尝试切换播放器';

  factory MediaError.unsupportedFormat(String type, String format) =>
      MediaError._(
        userMessage: '不支持的${_label(type)}格式',
        debugMessage: 'Unsupported $type format: $format',
        mediaType: type,
        sourceUrl: '',
      )..recoveryHint = '请尝试将文件转换为常见格式';

  static String _label(String t) => const {
        'video': '视频',
        'audio': '音频',
        'ppt': '课件',
      }[t] ??
      '媒体';
}

/// AI 模型 API 调用错误 —— 限流、认证失败、服务不可用。
///
/// 注意：上下文超出窗口限制请使用 [ContextExceededError]。
class AiModelError extends AppError {
  final String modelName;
  final int? statusCode;
  final int? tokenCount;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  AiModelError._({
    required this.userMessage,
    required this.debugMessage,
    required this.modelName,
    this.statusCode,
    this.tokenCount,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory AiModelError.apiError(String model, int? statusCode) {
    String msg;
    String hint;
    if (statusCode == 429) {
      msg = 'AI 服务繁忙，请稍后重试';
      hint = '请求频率过高，请稍等片刻后重试';
    } else if (statusCode == 401 || statusCode == 403) {
      msg = 'AI 服务认证失败';
      hint = 'API 密钥可能已过期，请在设置中重新配置';
    } else if (statusCode != null && statusCode >= 500) {
      msg = 'AI 服务暂时不可用';
      hint = '服务端故障，请稍后重试';
    } else {
      msg = 'AI 请求失败';
      hint = '请稍后重试，如持续出现请检查 API 配置';
    }
    return AiModelError._(
      userMessage: msg,
      debugMessage: 'AI model error: $model, HTTP $statusCode',
      modelName: model,
      statusCode: statusCode,
    )..recoveryHint = hint;
  }

  factory AiModelError.quotaExhausted(String model) => AiModelError._(
        userMessage: 'AI 服务配额已用完',
        debugMessage: 'Token quota exhausted for $model',
        modelName: model,
      )..recoveryHint = '请在 API 平台充值或等待配额重置';
}

/// AI 上下文超出窗口限制。
///
/// 与 [AiModelError] 不同——这不代表 API 故障，而是对话历史积累过多。
/// UI 层应展示"开启新会话"选项（会丢失对话历史）。
class ContextExceededError extends AppError {
  final String modelName;
  final int currentTokens;
  final int maxTokens;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  ContextExceededError._({
    required this.userMessage,
    required this.debugMessage,
    required this.modelName,
    required this.currentTokens,
    required this.maxTokens,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory ContextExceededError.overflow(
          String model, int currentTokens, int maxTokens) =>
      ContextExceededError._(
        userMessage: '对话内容过长，超出 AI 处理上限',
        debugMessage:
            'Context overflow: $model — $currentTokens / $maxTokens tokens',
        modelName: model,
        currentTokens: currentTokens,
        maxTokens: maxTokens,
      )..recoveryHint = '请开启新会话以继续（当前对话历史将丢失）';

  double get usageRatio =>
      maxTokens > 0 ? currentTokens / maxTokens : 0.0;
}

/// 配置错误 —— 必需的配置项缺失或值无效。
class ConfigError extends AppError {
  final String configKey;
  final String? invalidValue;
  final String? expectedFormat;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  ConfigError._({
    required this.userMessage,
    required this.debugMessage,
    required this.configKey,
    this.invalidValue,
    this.expectedFormat,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory ConfigError.missing(String key) => ConfigError._(
        userMessage: '缺少必要配置',
        debugMessage: 'Required config missing: $key',
        configKey: key,
      )..recoveryHint = '请在设置中配置 $key';

  factory ConfigError.invalid(String key, String value, String expected) =>
      ConfigError._(
        userMessage: '配置值不合法',
        debugMessage:
            'Invalid config: $key="$value", expected $expected',
        configKey: key,
        invalidValue: value,
        expectedFormat: expected,
      )..recoveryHint = '请检查 $key 的格式（$expected）';
}

/// 文件操作错误 —— 读写失败、磁盘满、权限不足、格式不支持。
class FileError extends AppError {
  final String filePath;
  final String operation;
  final String? osError;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  FileError._({
    required this.userMessage,
    required this.debugMessage,
    required this.filePath,
    required this.operation,
    this.osError,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory FileError.operationFailed(String path, String operation,
      {String? osError}) {
    String hint;
    if (osError != null &&
        (osError.contains('No space') ||
            osError.contains('磁盘空间') ||
            osError.contains('DISK_FULL'))) {
      hint = '存储空间不足，请清理后重试';
    } else if (osError != null &&
        (osError.contains('Permission denied') ||
            osError.contains('拒绝访问') ||
            osError.contains('EACCES'))) {
      hint = '没有文件访问权限，请在系统设置中授权';
    } else if (osError != null &&
        (osError.contains('not found') ||
            osError.contains('找不到') ||
            osError.contains('ENOENT'))) {
      hint = '文件不存在，可能已被移动或删除';
    } else {
      hint = '文件操作失败，请重试';
    }
    return FileError._(
      userMessage: '文件${_label(operation)}失败',
      debugMessage: 'File $operation failed: $path'
          '${osError != null ? ' — $osError' : ''}',
      filePath: path,
      operation: operation,
      osError: osError,
    )..recoveryHint = hint;
  }

  factory FileError.unsupportedFormat(String path, String format) =>
      FileError._(
        userMessage: '不支持的文件格式',
        debugMessage: 'Unsupported file format: $format — $path',
        filePath: path,
        operation: 'read',
      )..recoveryHint = '请选择支持的格式';

  static String _label(String op) => const {
        'read': '读取',
        'write': '保存',
        'delete': '删除',
        'export': '导出',
      }[op] ??
      op;
}

/// 数据完整性错误 —— 语法层解析成功，但数据结构/类型/值不符合预期。
///
/// 与 [ParseError] 的区别：
/// - [ParseError]：`jsonDecode()` 抛出 `FormatException`（语法层失败）
/// - [DataIntegrityError]：`jsonDecode()` 成功，但字段缺失或类型错误（语义层失败）
class DataIntegrityError extends AppError {
  final String dataSource;
  final String? fieldPath;
  final String? expectedType;
  final String? actualValue;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  DataIntegrityError._({
    required this.userMessage,
    required this.debugMessage,
    required this.dataSource,
    this.fieldPath,
    this.expectedType,
    this.actualValue,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory DataIntegrityError.typeMismatch(
          String source, String field, String expected, String actual) =>
      DataIntegrityError._(
        userMessage: '数据格式异常，学校系统可能已更新',
        debugMessage:
            'Data type mismatch in $source: $field expected $expected, got $actual',
        dataSource: source,
        fieldPath: field,
        expectedType: expected,
        actualValue: actual,
      )..recoveryHint =
            '请稍后重试，如持续出现请向开发者反馈（数据源：$source）';

  factory DataIntegrityError.missingField(String source, String field) =>
      DataIntegrityError._(
        userMessage: '数据不完整',
        debugMessage: 'Missing required field in $source: $field',
        dataSource: source,
        fieldPath: field,
      )..recoveryHint = '请稍后重试，如持续出现请向开发者反馈';

  factory DataIntegrityError.logicalError(String source, String reason) =>
      DataIntegrityError._(
        userMessage: '数据异常',
        debugMessage: 'Logical error in $source: $reason',
        dataSource: source,
      )..recoveryHint = '请尝试刷新数据，如持续出现请向开发者反馈';
}

/// 渲染错误 —— Widget 渲染失败、布局溢出、数据到 Widget 映射问题。
///
/// 与 [ParseError]/[DataIntegrityError] 的区别：
/// - [ParseError]：数据获取/解析阶段失败
/// - [DataIntegrityError]：数据解析成功但语义异常
/// - [RenderError]：数据正确但 Widget 无法正确渲染（布局约束、类型映射、空安全）
class RenderError extends AppError {
  final String widgetName;
  final String? fieldPath;
  final String? expectedType;
  final String? actualValue;

  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  RenderError._({
    required this.userMessage,
    required this.debugMessage,
    required this.widgetName,
    this.fieldPath,
    this.expectedType,
    this.actualValue,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory RenderError.layoutOverflow(String widget, String constraint) =>
      RenderError._(
        userMessage: '页面布局异常，部分内容可能不可见',
        debugMessage: 'Layout overflow in $widget: $constraint',
        widgetName: widget,
        fieldPath: constraint,
      )..recoveryHint = '请尝试调整窗口大小或旋转屏幕';

  factory RenderError.typeMismatch(
          String widget, String field, String expected, String actual) =>
      RenderError._(
        userMessage: '数据格式与显示组件不匹配',
        debugMessage:
            'Render type mismatch in $widget.$field: expected $expected, got $actual',
        widgetName: widget,
        fieldPath: field,
        expectedType: expected,
        actualValue: actual,
      )..recoveryHint = '请稍后重试，如持续出现请向开发者反馈';

  factory RenderError.nullDisplay(String widget, String field) =>
      RenderError._(
        userMessage: '数据缺失导致无法显示',
        debugMessage: 'Null display value in $widget.$field',
        widgetName: widget,
        fieldPath: field,
      )..recoveryHint = '请尝试刷新数据';

  factory RenderError.missingWidget(String widget, String reason) =>
      RenderError._(
        userMessage: '界面组件加载失败',
        debugMessage: 'Missing widget in $widget: $reason',
        widgetName: widget,
      )..recoveryHint = '请尝试刷新页面';
}

/// 未知错误 —— 未分类错误的兜底类型。
class UnknownError extends AppError {
  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  UnknownError._({
    required this.userMessage,
    required this.debugMessage,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();

  factory UnknownError.from(Object exception) => UnknownError._(
        userMessage: '发生了未知错误',
        debugMessage:
            'Unknown error: ${exception.runtimeType} — $exception',
        cause: exception,
      )..recoveryHint = '请尝试重新操作，或联系开发者';
}

/// PDF 翻译错误 —— Python 子进程或 pdf2zh 引擎返回的错误。
class TranslationError extends AppError {
  @override
  final String userMessage;
  @override
  final String debugMessage;
  @override
  final Object? cause;
  @override
  final String? source;

  TranslationError._({
    required this.userMessage,
    required this.debugMessage,
    this.cause,
    String? source,
  }) : source = source ?? AppError._captureSource();
}
