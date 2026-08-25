/// StreamSource → media_kit 播放器接线（renderer 共享层，通用）。
///
/// 把 [StreamSource]（运行时流端点描述符）组装成 media_kit 可直接消费的
/// [Media]：`resolveStreamUrl` 替换 `{port}` 占位 → `resolveStreamHeaders`
/// 组合静态头 + 可选的凭据注入头 → `Media(url, httpHeaders: ...)`。
///
/// # 分层（纯逻辑可单测）
///
/// - 纯逻辑（url 解析 / header 组合）在 `stream_source.dart`（纯 Dart，零
///   Flutter/media_kit 依赖，可独立 analyze/test）；
/// - 本文件仅做 media_kit `Media` 的**薄组装**：不管理状态、不发起网络请求
///   （渲染层红线）。
///
/// # 与既有播放器的对齐
///
/// media_kit 播放器是独立进程，**不带** Dio/会话 cookie jar，需把凭据头手动
/// 塞进 `httpHeaders`，否则带鉴权的流会 401/403 → 黑屏（见
/// `templates/zju_modle/classroom/widgets/video_player_panel.dart` 与
/// `components/shared/widgets/video_player.dart` 的 `Media(url, httpHeaders:)` 用法）。
/// 本函数正是把「描述符 + 凭据 provider」统一为一次 `Media` 构造，供各播放器组件复用；
/// 具体凭据实现（如 `zjuVideoHttpHeaders` 封装为 `MediaRequestHeadersProvider`）属 T9。
library;

import 'package:media_kit/media_kit.dart';
import 'stream_source.dart';

/// 组装 media_kit [Media]（组装层薄封装）。
///
/// - [headersProvider]：凭据注入实现；[StreamSource.credentialed] 为 true 时经其取头；
/// - [port]：非空时替换 [StreamSource.url] 中的 `{port}` 占位；
/// - [sessionProvider]：可选的会话提供者标识（对应 manifest `auth.sessionProvider`）。
///
/// 返回的 [Media] 可直接 `player.open(media)`（media_kit `Player` 已在调用方持有）。
Future<Media> buildMedia(
  StreamSource source, {
  MediaRequestHeadersProvider? headersProvider,
  int? port,
  String? sessionProvider,
}) async {
  final url = resolveStreamUrl(source, port: port);
  final headers = await resolveStreamHeaders(
    source,
    url,
    headersProvider: headersProvider,
    sessionProvider: sessionProvider,
  );
  return Media(url, httpHeaders: headers);
}
