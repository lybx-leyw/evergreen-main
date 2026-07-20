/// 共享原子层——所有 modle（模板）共用的"取数原语"。
///
/// 仅包含跨模板必须的取数能力，不含任何具名组件或布局策略：
/// - [resolveDataSource]：解析数据源描述符（`orch://<name>` 走数据中枢，或 HTTP）+ `dataPath` 键路径提取 + `transform` 转换
/// - [extractPath]：JSON 点路径提取（`a.b[0].c`）
/// - [applyTransform] / [transformRegistry]：数据转换注册表
library;

export 'data_source_resolver.dart';
export 'json_path.dart';
export 'transform_registry.dart';
