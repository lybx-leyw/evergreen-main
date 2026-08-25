/// 流端点描述符 + 媒体请求凭证注入抽象（renderer 共享层，平台级）。
///
/// # 位置理由（为什么放 `components/shared/` 而非 `widgets/models.dart`）
///
/// - `components/shared/` 是 renderer 的**组合基础设施层**（与 `template_engine.dart` /
///   `slot_scale.dart` 同级），承载跨模板、跨组件的运行时契约；
///   `widgets/models.dart` 是「视图轻量数据模型」（Chat/Presentation/Market），两者定位不同。
/// - [StreamSource] / [MediaRequestHeadersProvider] 是**运行时已解析**的播放链路契约，
///   将被 html_modle（`platform.media.*`）、zju_modle 播放面板、通用 media 组件共同消费，
///   属平台级共享，而非某个视图的数据模型。
/// - 本文件**纯 Dart（零 Flutter 依赖）**，可被 stub 包独立 analyze（与 `template_engine.dart` 一致）。
///
/// # 与 core manifest 的关系
///
/// 与 core 的清单声明 `DataSourceStreamDecl`（`core/data/plugin/data_source_manifest.dart`）
/// 保持**字段语义对齐**（protocol 枚举 / mime / credentialed），但二者不互相依赖：
/// 本类是「数据源声明的流」在 renderer 侧的**运行时描述符**，额外携带实际端点 `url`、
/// 静态 `headers` 与 `ttl` 失效重取语义；T9 接线时在 renderer 侧做 manifest → 本类的映射。
///
/// # 契约映射（T1 manifest `stream` ↔ 本类 ↔ T3 SSE 端点）
///
/// - `protocol` 值集 `hls|mp4|http-flv|sse|stdio-jsonl` 对齐 T1
///   `DataSourceStreamDecl.protocol`；其中 `sse` 对应 T3 `GET /data/stream/:name`
///   长连接端点（`event: data/error/done` 帧，连续数据流）。
/// - `mime` / `credentialed` 对齐 T1 `DataSourceStreamDecl.mime/credentialed`。
/// - 变更通知（非连续流）走 T3 `dataChangeEvents`（`GET /data/events`，`event: change`），
///   由 `DataSubscriptionPoller` 桥接为 HTML `data:changed`，与本类（流端点播放）区分。
library;

import 'dart:async';

/// 流协议（对齐 T1 manifest `dataTypes[].stream.protocol`）。
///
/// 值集：`hls` | `mp4` | `http-flv` | `sse` | `stdio-jsonl`。
/// 未知值解析为 [StreamSourceProtocol.unknown]（容错：未知静默忽略，不抛异常）。
enum StreamSourceProtocol {
  hls('hls'),
  mp4('mp4'),
  httpFlv('http-flv'),
  sse('sse'),
  stdioJsonl('stdio-jsonl'),
  unknown('unknown');

  const StreamSourceProtocol(this.wire);

  /// 与 manifest `stream.protocol` 对齐的序列化值。
  final String wire;

  /// 从 wire 值解析；未知 / 空 → [unknown]。
  static StreamSourceProtocol fromWire(String? wire) {
    if (wire == null || wire.isEmpty) return StreamSourceProtocol.unknown;
    for (final p in StreamSourceProtocol.values) {
      if (p.wire == wire) return p;
    }
    return StreamSourceProtocol.unknown;
  }
}

/// 流端点描述符 —— 把「数据源声明的流」变成播放器可直接消费的运行时描述。
///
/// 字段语义：
/// - [url]：已解析的流端点，可含 `{port}` 占位（[resolveUrl] 替换为实际端口）或实际 URL；
/// - [protocol]：流协议（未知回退 [StreamSourceProtocol.unknown]）；
/// - [mime]：媒体 MIME（如 `video/mp4`），可选；
/// - [credentialed]：是否需经 [MediaRequestHeadersProvider] 动态注入凭据头；
/// - [headers]：可选静态注入头（如固定 UA）；动态凭据头走 [MediaRequestHeadersProvider]；
/// - [ttl]：描述符有效期，null 表示不过期；消费方以 [isExpired] 判断失效重取。
///
/// 本类是**纯数据描述符**：不管理状态、不发起网络请求（渲染层红线）。
class StreamSource {
  /// 流端点（可含 `{port}` 占位或实际 URL）。
  final String url;

  /// 流协议；未知回退 [StreamSourceProtocol.unknown]。
  final StreamSourceProtocol protocol;

  /// 媒体 MIME（如 `video/mp4`），可选。
  final String? mime;

  /// 是否需要经 [MediaRequestHeadersProvider] 注入凭据头。
  final bool credentialed;

  /// 可选静态注入头；动态凭据头走 [MediaRequestHeadersProvider]。
  final Map<String, String> headers;

  /// 描述符有效期；null 表示不过期（TTL 失效重取语义）。
  final Duration? ttl;

  const StreamSource({
    required this.url,
    this.protocol = StreamSourceProtocol.unknown,
    this.mime,
    this.credentialed = false,
    this.headers = const {},
    this.ttl,
  });

  /// 用实际 [port] 替换 [url] 中的 `{port}` 占位符（无占位则原样返回）。
  String resolveUrl(int port) => url.replaceAll('{port}', '$port');

  /// [fetchedAt] 时刻获取的描述符是否已失效（[ttl] 为 null 恒为 false）。
  bool isExpired(DateTime fetchedAt) {
    final t = ttl;
    if (t == null) return false;
    return DateTime.now().difference(fetchedAt) >= t;
  }

  /// 序列化为 JSON（供 bridge / 日志 / 后续 `platform.media.*` 传递）。
  Map<String, dynamic> toJson() => {
    'url': url,
    'protocol': protocol.wire,
    if (mime != null) 'mime': mime,
    'credentialed': credentialed,
    if (headers.isNotEmpty) 'headers': headers,
    if (ttl != null) 'ttl': ttl!.inSeconds,
  };

  @override
  String toString() =>
      'StreamSource($url, protocol:${protocol.wire}, credentialed:$credentialed)';
}

/// 媒体请求凭证注入抽象（平台级，不接具体域）。
///
/// 职责：从会话中心（SessionProvider，T2 实现）导出 Cookie / Referer / User-Agent
/// 等凭据头，供播放器（media_kit `Media(httpHeaders: ...)`）或 `<video>` 直连流端点时注入。
///
/// 现状与接线：zju 的具体实现 `zjuVideoHttpHeaders()`（
/// `templates/zju_modle/zju_auth/zju_session.dart`，从共享 CookieJar 拼 Cookie/Referer/UA）
/// 属 **T9 接线**——届时用一个实现了本接口的 provider 封装之；本层只定义抽象 +
/// 默认实现 + 用法注释，不接具体域。
abstract class MediaRequestHeadersProvider {
  /// 为 [url] 返回需注入的请求头（如 Cookie / Referer / User-Agent）。
  ///
  /// [sessionProvider] 为可选的会话提供者标识（对应 manifest `auth.sessionProvider`，
  /// 如 `"zju"`），用于多 provider 路由；缺省由实现自行判断。
  ///
  /// 返回空 Map 表示无需注入（或会话未就绪），播放器按原样请求，失败由 UI 兜底。
  Future<Map<String, String>> headersFor(Uri url, {String? sessionProvider});
}

/// 默认空实现：不注入任何凭据头（存量行为）。
///
/// 未接入具体会话中心的场景（公开流、本地 `127.0.0.1` 流）直接使用本实现，
/// 保证「凭证注入」对未接线方零行为变化。
class EmptyMediaRequestHeadersProvider implements MediaRequestHeadersProvider {
  const EmptyMediaRequestHeadersProvider();

  @override
  Future<Map<String, String>> headersFor(
    Uri url, {
    String? sessionProvider,
  }) async => const {};
}

/// 解析流端点 URL：[port] 非空时经 [StreamSource.resolveUrl] 替换 `{port}` 占位；
/// [port] 为 null 时原样返回 [StreamSource.url]（调用方须保证已无 `{port}` 占位）。
///
/// 纯函数，供 [buildMedia]（`components/shared/stream_playback.dart`）与
/// HTML 插件 `platform.media.*` 桥复用。
String resolveStreamUrl(StreamSource source, {int? port}) {
  if (port == null) return source.url;
  return source.resolveUrl(port);
}

/// 组合流请求头：静态 [StreamSource.headers] 打底，`credentialed` 时经
/// [headersProvider] 追加动态凭据头（凭据头覆盖同名静态头；未接线用
/// [EmptyMediaRequestHeadersProvider]，零行为变化）。
///
/// [url] 为**已解析**端点（供 provider 按域路由，如按 `.zju.edu.cn` 拼
/// Cookie/Referer/UA）。纯函数，独立单测 url/header 组合。
Future<Map<String, String>> resolveStreamHeaders(
  StreamSource source,
  String url, {
  MediaRequestHeadersProvider? headersProvider,
  String? sessionProvider,
}) async {
  final headers = <String, String>{...source.headers};
  if (source.credentialed) {
    final provider =
        headersProvider ?? const EmptyMediaRequestHeadersProvider();
    final cred = await provider.headersFor(
      Uri.parse(url),
      sessionProvider: sessionProvider,
    );
    headers.addAll(cred);
  }
  return headers;
}
