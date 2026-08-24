/// 上架脚手架生成（M4-3，纯逻辑）。
///
/// 给定仓库分类结果与元信息，生成一份可经 [ModuleDescriptor.fromJson] 校验的
/// `manifest.json`（Map 形式）。不写文件、不碰网络，便于单测「生成物可 fromJson」。
library;

import 'dart:convert';

import 'github_source.dart';
import 'lattice.dart';
import 'module_descriptor.dart';
import 'runtime.dart';

/// 脚手架输入。
class ScaffoldInput {
  /// 插件 id（小写中划线）。
  final String id;

  /// 插件显示名。
  final String name;

  /// 分类到的格。
  final Lattice lattice;

  /// 入口文件（sidecar/data-source 用）。
  final String? entry;

  /// sidecar 的语言运行时（仅 [Lattice.sidecar] 用）。
  final RuntimeKind? runtimeKind;

  /// 数据源 endpoint（仅 [Lattice.dataSource] 用，如 `orch://x`）。
  final String? dataSourceEndpoint;

  const ScaffoldInput({
    required this.id,
    required this.name,
    required this.lattice,
    this.entry,
    this.runtimeKind,
    this.dataSourceEndpoint,
  });
}

/// 生成 manifest Map（纯函数）。
///
/// 返回对象可直接 `jsonEncode` 或送 [ModuleDescriptor.fromJson] 往返。
/// 非法组合（如 sidecar 缺 runtimeKind）抛 [FormatException]（fail-closed）。
Map<String, dynamic> generateManifest(ScaffoldInput input) {
  final m = <String, dynamic>{
    'type': 'module',
    'id': input.id,
    'name': input.name,
    'lattice': formatLattice(input.lattice),
  };

  switch (input.lattice) {
    case Lattice.sidecar:
      if (input.runtimeKind == null || input.entry == null) {
        throw FormatException(
            'sidecar 格必须提供 runtimeKind 与 entry');
      }
      m['runtime'] = {
        'kind': formatRuntimeKind(input.runtimeKind!),
        'entry': input.entry!,
      };
      break;
    case Lattice.dataSource:
      if (input.dataSourceEndpoint == null) {
        throw FormatException('data-source 格必须提供 dataSourceEndpoint');
      }
      m['dataSource'] = {'endpoint': input.dataSourceEndpoint};
      break;
    case Lattice.staticWeb:
    case Lattice.webBridged:
    case Lattice.agentTool:
    case Lattice.externalApp:
      // 这些格无需额外必填字段。
      break;
  }
  return m;
}

/// 生成并校验（往返）manifest，返回 JSON 字符串。
///
/// 若生成物无法被 [ModuleDescriptor.fromJson] 解析，抛 [FormatException]。
String generateManifestJson(ScaffoldInput input) {
  final map = generateManifest(input);
  // 往返校验：能解析回描述符才算合法脚手架产物。
  ModuleDescriptor.fromJson(map);
  return jsonEncode(map);
}

/// 由 [GithubSource] + 分类一键产出脚手架（M4-4 串联的纯逻辑内核）。
Map<String, dynamic> scaffoldFromClassification(
  GithubSource source,
  RepoClassification cls, {
  required String id,
  required String name,
  String? entry,
  RuntimeKind? runtimeKind,
  String? dataSourceEndpoint,
}) {
  final lattice = cls.classify();
  final input = ScaffoldInput(
    id: id,
    name: name,
    lattice: lattice,
    entry: entry,
    runtimeKind: runtimeKind,
    dataSourceEndpoint: dataSourceEndpoint,
  );
  return generateManifest(input);
}
