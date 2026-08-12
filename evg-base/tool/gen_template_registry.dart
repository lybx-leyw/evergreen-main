// 构建期模板注册表生成器（多套 release 打包支持）。
//
// 用途：同一仓库按 profile 生成模板注册表。配合 Dart AOT 编译的静态
// tree-shaking（可达性分析），实现"打包时选择性装入模板"：
//   注册表只 import 选中的模板 → 未选中模板在编译期不可达 → 不进产物。
//
// 输入：
//   lib/renderer/templates/templates_index.json  —— 模板清单（name → 入口文件 + 渲染器类）
//   build_profiles/<profile>.json                —— 该 release 要装入哪些模板路由
// 输出：
//   lib/renderer/templates/generated/template_registry.g.dart
//
// 运行（在 evg-base/ 目录下）：
//   C:\flutter\bin\cache\dart-sdk\bin\dart.exe tool/gen_template_registry.dart --profile release_full
//   C:\flutter\bin\cache\dart-sdk\bin\dart.exe tool/gen_template_registry.dart --profile release_std
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

const String kPackageName = 'evergreen_base';

/// 工作区根：环境变量 EVERGREEN_WORKSPACE 优先（CI 使用），
/// 否则从脚本位置向上找 pubspec.yaml（本地开发免传参）。
/// 与 tool/bundle_plugins.dart 保持一致。
String _workspaceRoot() {
  final env = Platform.environment['EVERGREEN_WORKSPACE'];
  if (env != null && env.isNotEmpty) {
    return p.normalize(p.absolute(env));
  }
  var dir = Directory(Platform.script.toFilePath()).parent; // tool/
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('无法定位工作区根（未找到 pubspec.yaml）。'
      '请从仓库根运行，或设置 EVERGREEN_WORKSPACE 环境变量。');
}

final String _root = _workspaceRoot();
final String kIndex = p.join(_root, 'lib', 'renderer', 'templates', 'templates_index.json');
final String kProfilesDir = p.join(_root, 'build_profiles');
final String kOutput = p.join(_root, 'lib', 'renderer', 'templates', 'generated', 'template_registry.g.dart');

/// 从命令行参数解析 --profile <name> 或 --profile=<name>。
String? _profileFromArgs(List<String> args) {
  const flag = '--profile';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == flag && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$flag=')) return args[i].substring('$flag='.length);
  }
  return null;
}

void main(List<String> args) {
  final profile = _profileFromArgs(args);
  if (profile == null || profile.isEmpty) {
    stderr.writeln('[gen-registry] 用法: dart tool/gen_template_registry.dart --profile <name>');
    stderr.writeln('[gen-registry] 可用 profile（build_profiles/ 下）: ${_listProfiles()}');
    exit(2);
  }

  final indexFile = File(kIndex);
  if (!indexFile.existsSync()) {
    stderr.writeln('[gen-registry] 模板清单不存在: $kIndex');
    exit(1);
  }
  final profileFile = File(p.join(kProfilesDir, '$profile.json'));
  if (!profileFile.existsSync()) {
    stderr.writeln('[gen-registry] profile 不存在: ${profileFile.path}');
    stderr.writeln('[gen-registry] 可用: ${_listProfiles()}');
    exit(1);
  }

  final index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
  final indexTemplates = (index['templates'] as List)
      .map((e) => (e as Map<String, dynamic>).cast<String, dynamic>())
      .toList();
  final byName = <String, Map<String, dynamic>>{
    for (final t in indexTemplates) t['name'] as String: t,
  };

  final profileData = jsonDecode(profileFile.readAsStringSync()) as Map<String, dynamic>;
  final names = (profileData['templates'] as List).cast<String>();
  final description = (profileData['description'] as String?) ?? '(无描述)';

  // 校验：profile 中每个模板名都必须登记在 index 中。
  final missing = names.where((n) => !byName.containsKey(n)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('[gen-registry] profile "$profile" 引用了未登记的模板: $missing');
    stderr.writeln('[gen-registry] 请先在 $kIndex 中登记。');
    exit(1);
  }

  // 校验：入口文件必须存在（避免生成无法编译的 import）。
  final entries = <String>{};
  for (final name in names) {
    final entry = byName[name]!['entry'] as String;
    final file = File(p.join(_root, 'lib', 'renderer', 'templates', entry));
    if (!file.existsSync()) {
      stderr.writeln('[gen-registry] 模板 "$name" 的入口文件不存在: ${file.path}');
      exit(1);
    }
    entries.add(entry);
  }

  final content = _generate(profile, description, names, byName, entries.toList()..sort());
  File(kOutput).parent.createSync(recursive: true);
  File(kOutput).writeAsStringSync(content);
  stderr.writeln('[gen-registry] ✅ 已生成: ${p.relative(kOutput, from: _root)}');
  stderr.writeln('[gen-registry] profile=$profile, 路由 ${names.length} 条, 入口文件 ${entries.length} 个');
  stderr.writeln('[gen-registry] 注意: 未装入的模板将由 Dart tree-shaker 自动剔除出产物。');
}

List<String> _listProfiles() {
  final dir = Directory(kProfilesDir);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.json'))
      .map((n) => n.substring(0, n.length - '.json'.length))
      .toList();
}

String _generate(
  String profile,
  String description,
  List<String> names,
  Map<String, Map<String, dynamic>> byName,
  List<String> entries,
) {
  final buf = StringBuffer();
  buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buf.writeln('//');
  buf.writeln('// 由 tool/gen_template_registry.dart 生成，勿手改。');
  buf.writeln('//   profile    : $profile');
  buf.writeln('//   说明        : $description');
  buf.writeln('//   模板清单    : lib/renderer/templates/templates_index.json');
  buf.writeln('//   修改方式    : 编辑上述输入后重新运行生成器');
  buf.writeln('library;');
  buf.writeln();
  buf.writeln("import 'package:$kPackageName/renderer/templates/template.dart';");
  for (final entry in entries) {
    buf.writeln("import 'package:$kPackageName/renderer/templates/$entry';");
  }
  buf.writeln();
  buf.writeln('/// 模板注册表（生成物）：共 ${names.length} 条路由，${entries.length} 个入口文件。');
  buf.writeln('Map<String, ModleRenderer> buildTemplateRegistry() {');
  buf.writeln('  return <String, ModleRenderer>{');
  for (final name in names) {
    buf.writeln("    '$name': const ${byName[name]!['renderer']}(),");
  }
  buf.writeln('  };');
  buf.writeln('}');
  return buf.toString();
}
