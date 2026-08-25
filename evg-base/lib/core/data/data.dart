/// 数据谱仪器——统一的数据获取、缓存、状态追踪中枢。
///
/// 消费者通过 `import 'data.dart'` 获得全部公共 API。
library data;

export 'type.dart';
export 'exceptions.dart';
export 'orchestrator.dart';
export 'session_provider.dart';
export 'file_entries.dart';
// export 'provider.dart' show dataOrchestratorProvider; // 需要 flutter_riverpod，示例中不用
export 'cache.dart';
export 'data_diff.dart';
export 'sse_frame.dart';
export 'data_http_server.dart';
export 'plugin/data_source_manifest.dart';
export 'plugin/data_source_loader.dart';
export 'plugin/data_source_fetcher.dart';
