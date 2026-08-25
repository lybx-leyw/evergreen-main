// 构建期资产准备脚本（开发期运行一次，在 `flutter build apk` 之前）。
//
// 把工作区根 `plugins/` 复制到 `evg-base/assets/plugins_bundle/`，
// 作为 flutter assets 打进 APK，供安卓端在启动期释放到设备可写目录
// （见 lib/core/utils/plugin_asset_releaser.dart）。
//
// 排除规则（安卓无需、且会显著膨胀 APK / Chaquopy 无法执行）：
//   - 任意 `*.exe`（桌面专属，安卓不可用）
//   - `.git` 目录
//   - `classroom-demo` 的运行时缓存：ppt_cache / downloads / data/ppt
//   - 根级非插件元数据：README.md / .data_port / .plugin_states.json / .code-workspace
//
// 不变式：`assets/plugins_bundle/` 是 `plugins/` 的**纯镜像**，仅由本脚本生成。
// 运行期代码（renderer 导出等）禁止直写 bundle —— 违者产生陈旧副本/僵尸条目。
//
// 用法：
//   dart run tool/bundle_plugins.dart             # 重建 bundle + 重写 pubspec 标记块
//   dart run tool/bundle_plugins.dart --check     # 校验模式（CI 门禁）：
//                                                 #   a) pubspec.yaml PLUGIN_ASSETS 标记块
//                                                 #      与 plugins/ 源一致（提交态校验）
//                                                 #   b) assets/plugins_bundle/ 与源逐文件
//                                                 #      一致（本地存在时；CI 首建场景跳过）
//                                                 # 不一致退出码非 0
//
// 运行：C:\flutter\bin\cache\dart-sdk\bin\dart.exe tool/bundle_plugins.dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// 工作区根：环境变量 EVERGREEN_WORKSPACE 优先（CI 使用），
/// 否则从脚本位置向上找 pubspec.yaml（本地开发免传参）。
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

String get kSource => p.join(_workspaceRoot(), 'plugins');
String get kDest => p.join(_workspaceRoot(), 'assets', 'plugins_bundle');
String get kPubspec => p.join(_workspaceRoot(), 'pubspec.yaml');

/// 返回 true 表示该路径应被跳过（不复制）。
///
/// 采用"任意层级匹配"，避免漏掉嵌套结构（如
/// `classroom-demo/classroom-demo/data/ppt_cache/...`）。
bool _shouldSkip(String relative) {
  final parts = p.split(relative);

  // 任意层级的版本控制 / 工作区记忆 / Python 缓存 / 构建缓存 / PPT 渲染缓存目录
  for (final part in parts) {
    if (part == '.git' ||
        part == '.codebuddy' ||
        part == '__pycache__' ||
        part == 'ppt_cache' ||
        part == 'downloads' ||
        part == 'ppt' ||
        part == 'build' && parts.contains('src')) {
      return true;
    }
  }

  // 顶层非插件元数据（README / 端口 / 状态 / workspace 文件）
  if (parts.length == 1) {
    final name = parts[0];
    if (name == 'README.md' ||
        name == '.data_port' ||
        name == '.plugin_states.json' ||
        name.endsWith('.code-workspace')) {
      return true;
    }
  }

  // 任意层级的 OWNER 职责书（AGENT.md，仓库治理文档，非运行期资源）
  if (parts.last == 'AGENT.md') return true;

  // 点文件 / 点目录（如 .gitignore）：Flutter 资产打包器通常不把这些
  // 实际打进 APK，若仍声明在 manifest 里会导致 rootBundle.load 抛错。
  for (final part in parts) {
    if (part.startsWith('.')) return true;
  }

  // 渲染截图（非功能资源）
  if (parts.last == 'r12_dart_render.png') return true;

  // 运行时生成物（非功能资源）：Python 字节码缓存 / 渲染日志
  if (parts.last.endsWith('.pyc') || parts.last == 'render_log.html') {
    return true;
  }

  // 任意 .exe（桌面专属，Chaquopy 无法执行）
  if (parts.last.endsWith('.exe')) return true;

  return false;
}

/// 收集 [root] 下所有应打包的相对路径（应用 [_shouldSkip]），排序。
List<String> _collectRels(String root) {
  final rels = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
    if (_shouldSkip(rel)) continue;
    rels.add(rel);
  }
  rels.sort();
  return rels;
}

/// 从 pubspec 内容中提取 PLUGIN_ASSETS 标记块行（trim 后，不含标记行）。
/// 标记块缺失返回 null。
List<String>? _readPubspecBlock(String content) {
  final startIdx = content.indexOf('>>>PLUGIN_ASSETS_START>>>');
  final endIdx = content.indexOf('<<<PLUGIN_ASSETS_END<<<');
  if (startIdx < 0 || endIdx < 0) return null;
  final startLineEnd = content.indexOf('\n', startIdx) + 1;
  final endLineStart = content.lastIndexOf('\n', endIdx);
  if (startLineEnd <= 0 || endLineStart < startLineEnd) return const [];
  return content
      .substring(startLineEnd, endLineStart)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// 与 [_injectPubspecAssets] 同一格式的期望标记块行（trim 后）。
List<String> _expectedBlockLines(List<String> rels) =>
    rels.map((rel) => '- assets/plugins_bundle/$rel').toList();

/// 逐字节比较。
bool _bytesEqual(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// --check 校验模式：返回进程退出码（0=一致，1=不一致）。
///
/// 校验三件事：
///   1) pubspec.yaml PLUGIN_ASSETS 标记块与 plugins/ 源一致（**提交态门禁**，
///      CI 关键检查——bundle 目录被 .gitignore，提交态只有 pubspec 块能守）；
///   2) assets/plugins_bundle/ 与 plugins/ 源**文件清单**一致（无陈旧副本/缺漏）；
///   3) 两侧**文件内容**一致（逐字节）。
/// bundle 目录不存在（CI 首建场景，构建前将重建）时仅做 pubspec 门禁并提示。
int _check() {
  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle-check] ❌ 源目录不存在: $kSource');
    return 1;
  }
  final expected = _collectRels(kSource);
  final failures = <String>[];

  // ── 1) pubspec 标记块（提交态门禁）──
  final pubspec = File(kPubspec);
  if (!pubspec.existsSync()) {
    stderr.writeln('[bundle-check] ❌ pubspec.yaml 不存在: $kPubspec');
    return 1;
  }
  final block = _readPubspecBlock(pubspec.readAsStringSync());
  final expectedBlock = _expectedBlockLines(expected);
  if (block == null) {
    failures.add('pubspec.yaml 缺少 PLUGIN_ASSETS 标记块'
        '（>>>PLUGIN_ASSETS_START>>> / <<<PLUGIN_ASSETS_END<<<）');
  } else {
    final missing =
        expectedBlock.where((l) => !block.contains(l)).toList();
    final extra = block.where((l) => !expectedBlock.contains(l)).toList();
    if (missing.isNotEmpty) {
      failures.add('pubspec 标记块缺 ${missing.length} 条：'
          '${missing.take(3).join(', ')}${missing.length > 3 ? ', ...' : ''}');
    }
    if (extra.isNotEmpty) {
      failures.add('pubspec 标记块含 ${extra.length} 条陈旧引用：'
          '${extra.take(3).join(', ')}${extra.length > 3 ? ', ...' : ''}');
    }
  }

  // ── 2)+3) bundle 目录镜像（本地存在时；CI 首建场景仅提示）──
  final dest = Directory(kDest);
  if (!dest.existsSync()) {
    stderr.writeln('[bundle-check] ℹ assets/plugins_bundle/ 不存在'
        '（CI 首建场景，构建前将重建）；本次仅校验 pubspec 提交态。');
  } else {
    final actual = _collectRels(kDest);
    final missingInDest =
        expected.where((r) => !actual.contains(r)).toList();
    final extraInDest =
        actual.where((r) => !expected.contains(r)).toList();
    if (missingInDest.isNotEmpty) {
      failures.add('bundle 缺 ${missingInDest.length} 个镜像文件：'
          '${missingInDest.take(3).join(', ')}${missingInDest.length > 3 ? ', ...' : ''}');
    }
    if (extraInDest.isNotEmpty) {
      failures.add('bundle 含 ${extraInDest.length} 个非镜像文件（陈旧副本）：'
          '${extraInDest.take(3).join(', ')}${extraInDest.length > 3 ? ', ...' : ''}');
    }
    for (final rel in expected) {
      if (!actual.contains(rel)) continue;
      final a = File(p.join(kSource, rel)).readAsBytesSync();
      final b = File(p.join(kDest, rel)).readAsBytesSync();
      if (a.length != b.length || !_bytesEqual(a, b)) {
        failures.add('文件内容不一致: $rel');
      }
    }
  }

  if (failures.isEmpty) {
    stderr.writeln('[bundle-check] ✅ 一致：${expected.length} 个插件资产，'
        'pubspec 标记块 ${expectedBlock.length} 条。');
    return 0;
  }
  stderr.writeln('[bundle-check] ❌ 发现 ${failures.length} 处不一致：');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  stderr.writeln('[bundle-check] 修复：重新运行 `dart run tool/bundle_plugins.dart`'
      ' 重建 bundle 与 pubspec 标记块，并把 pubspec.yaml 变更一并提交。');
  return 1;
}

void main(List<String> args) {
  if (args.contains('--check')) {
    exit(_check());
  }

  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle] 源目录不存在: $kSource');
    exit(1);
  }
  final dest = Directory(kDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  dest.createSync(recursive: true);

  final rels = _collectRels(kSource);
  var copied = 0;
  for (final rel in rels) {
    final out = File(p.join(kDest, rel));
    out.parent.createSync(recursive: true);
    File(p.join(kSource, rel)).copySync(out.path);
    copied++;
  }
  stderr.writeln('[bundle] 完成：复制 $copied 个文件。');
  stderr.writeln('[bundle] 目标: $kDest');

  // 注入显式资产清单到 pubspec.yaml（本环境 Flutter 目录资产包含不递归子目录）
  _injectPubspecAssets(rels);
}

/// 把 [rels] 显式写入 pubspec.yaml 的标记块之间，保证 APK 打包包含所有插件资产。
void _injectPubspecAssets(List<String> rels) {
  final pubspec = File(kPubspec);
  if (!pubspec.existsSync()) {
    stderr.writeln('[bundle] pubspec.yaml 不存在: $kPubspec');
    return;
  }
  var content = pubspec.readAsStringSync();
  final startIdx = content.indexOf('>>>PLUGIN_ASSETS_START>>>');
  final endIdx = content.indexOf('<<<PLUGIN_ASSETS_END<<<');
  if (startIdx < 0 || endIdx < 0) {
    stderr.writeln('[bundle] 未在 pubspec.yaml 找到资产标记块，跳过注入。');
    return;
  }
  final startLineEnd = content.indexOf('\n', startIdx) + 1;
  final endLineStart = content.lastIndexOf('\n', endIdx);
  final before = content.substring(0, startLineEnd);
  final after = content.substring(endLineStart);
  final block =
      rels.map((rel) => '    - assets/plugins_bundle/$rel').join('\n');
  content = '$before$block\n$after';
  pubspec.writeAsStringSync(content);
  stderr.writeln('[bundle] 已注入 ${rels.length} 条资产到 pubspec.yaml');
}
