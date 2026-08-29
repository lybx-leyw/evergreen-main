/// 插件模块存储 → 数据中枢数据源注册 —— 把 HTML 插件的模块存储器
/// （`storage.json` 全量）注册成 [DataOrchestrator] 数据源，使其他模块/Agent
/// 可经 `platform.data.get(name)` 消费（延续「插件只声明、中枢调度」哲学，
/// 属同平台静态数据源形态）。
///
/// 与 `github_stars.dart`（services → data 依赖）同向但反向：本文件位于 **data 域**，
/// 依赖 data 域 [DataOrchestrator]/[DataType] 与 services 域
/// [ModuleStorageService]（经 `package:` 导入——根包解析到
/// `core/services/module_storage_service.dart`，数据子包独立测试解析到
/// `lib/core/services/module_storage_service.dart` 本地副本，见 data 域 CLAUDE.md
/// Stub 隔离说明）。**不触发网络**：fetcher 只读磁盘 storage.json。
library;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/services/module_storage_service.dart';

import 'orchestrator.dart';
import 'type.dart';

/// 模块存储数据源的类型名（`<pluginId>_storage`，防与插件声明的其它数据源冲突）。
String moduleStorageTypeName(String pluginId) => '${pluginId}_storage';

/// 模块存储数据源默认 TTL——30 秒。storage.json 很小（≤1MB 上限），每次 get 读盘
/// 成本可忽略，短 TTL 保证 `platform.data.get` 尽快看到插件新写入的值。
const Duration kModuleStorageSourceTtl = Duration(seconds: 30);

/// 注册插件模块存储为数据中枢数据源。
///
/// 注册一个 `DataType<Map<String, dynamic>>`：
/// - `name` = [moduleStorageTypeName]（`<pluginId>_storage`；重复调用覆盖注册，
///   对齐 orchestrator 覆盖语义），`displayName` = `<pluginId> 存储`，
///   `category` 缺省「未分类」（或传 [category]）。
/// - fetcher 只读 storage.json（经 [ModuleStorageService.forPlugin].readAll()，
///   数据源实例无待落盘写入时每次读盘），**不触发网络**；storage.json 不存在时
///   返回 `{}`（空 Map 合法——源可达，中枢空数据门控标记「源可达但数据为空」，
///   不抛错，幂等）。
/// - `persistentKey` 为 null：storage.json 本身即持久化，无需数据中枢二次磁盘缓存
///   （避免双写与一致性问题）。
///
/// 返回注册的类型名列表（`[<pluginId>_storage]`）。[pluginId] 非法（未通过
/// [moduleStoragePluginIdError]）时抛 [ArgumentError]（fail-fast，与模块加载一致）。
List<String> registerModuleStorageSource({
  required DataOrchestrator orch,
  required String pluginId,
  String? pluginsRoot,
  String? category,
  Duration? ttl,
}) {
  final name = moduleStorageTypeName(pluginId);
  final storage =
      ModuleStorageService.forPlugin(pluginId, pluginsRoot: pluginsRoot);
  final type = DataType<Map<String, dynamic>>(
    name: name,
    category: category ?? '未分类',
    displayName: '$pluginId 存储',
    ttl: ttl ?? kModuleStorageSourceTtl,
    // storage.json 即持久化载体，不设 persistentKey（不二次磁盘缓存）。
    persistentKey: null,
  );
  orch.register(type, () async => storage.readAll());
  Log().info('ModuleStorage: 注册数据源 $name',
      data: {'plugin': pluginId, 'root': storage.pluginsRoot});
  return [name];
}

/// 注销插件模块存储数据源（[registerModuleStorageSource] 的逆操作）。
///
/// 只注销类型（含状态/内存缓存），**不删除 storage.json**——存储文件归模块存储
/// 生命周期，插件卸载由插件生命周期管理负责。未注册时为无害 no-op。
void unregisterModuleStorageSource(DataOrchestrator orch, String pluginId) {
  final name = moduleStorageTypeName(pluginId);
  final type = orch.typeByName(name);
  if (type != null) {
    orch.unregister(type);
    Log().info('ModuleStorage: 注销数据源 $name', data: {'plugin': pluginId});
  }
}
