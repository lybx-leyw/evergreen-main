/// zju_modle 认证层统一导出——供 9 个 feature 的 service 与数据中枢注册引用。
///
/// B1（auth 先行）产物：SSO 登录 / 会话恢复 / 多服务编排 / Dio 客户端。
/// 自参考工程 `cp_evergreen_push` 改造：凭证走 `getSetting`、cookie 落
/// `.greenix/` 可写目录、错误/日志复用 evg-base `core/`。
library;

export 'auth_interceptor.dart';
export 'auth_provider.dart' show AuthState, AuthNotifier, zjuAuthProvider, zjuHttpClientProvider;
export 'auth_service.dart' show AuthService, AuthResult, AuthProgress, AuthStatus, ServiceResult;
export 'cookie_store.dart' show CookieStore;
export 'debug_interceptor.dart' show DebugInterceptor;
export 'dio_client.dart' show zjuCookieJarProvider, zjuDioClientProvider, createCliDio;
export 'html_parser.dart' show HtmlParser;
export 'network_config.dart' show NetworkConfig;
export 'retry_interceptor.dart' show RetryInterceptor;
export 'zdbk_patterns.dart' show ZdbkPatterns;
export 'zju_session.dart'
    show
        ensureZjuSession,
        zjuVideoHttpHeaders,
        zjuRefreshSession,
        zjuIsSessionExpiredError,
        ZjuSessionProvider,
        ZjuMediaRequestHeadersProvider;
export 'zjuam_service.dart' show ZjuAmService;
