// 构建期资产准备脚本——把运行时 Python 管线脚本打进 flutter 资产。
//
// 把工作区 `scripts/` 下的 *.py + requirements.txt + translate/ 复制到
// `assets/scripts_bundle/`，作为 flutter assets 打进 APK / Windows 构建，
// 供启动期释放到 `.greenix/scripts/`（见 plugin_asset_releaser.dart）。
//
// 排除规则（与 bundle_plugins.dart 同类思路）：
//   - `python/`（嵌入式解释器，体积大；Android 用 Chaquopy、Windows 由安装包预置）
//   - Inno Setup 安装脚本 installer*.iss / 平台安装器
//   - 开发辅助脚本 setup_python.cmd / reload.cmd
//   - `__pycache__` / `*.pyc` / `*.exe` / 点文件 / AGENT.md / README.md / 单下划线前缀
//
// 不变式：`assets/scripts_bundle/` 是 `scripts/` 的**纯镜像**（按排除规则），
// 仅由本脚本生成；运行期代码禁止直写 bundle。
//
// 用法：
//   dart run tool/bundle_scripts.dart             # 重建 bundle + 重写 pubspec SCRIPTS 标记块
//   dart run tool/bundle_scripts.dart --check     # 校验模式（CI 门禁，O4 扩展，与
//                                                 # bundle_plugins.dart 同款）：
//                                                 #   a) pubspec.yaml SCRIPTS 标记块与
//                                                 #      scripts/ 源一致（提交态校验）
//                                                 #   b) assets/scripts_bundle/ 与源逐文件
//                                                 #      一致（本地存在时；CI 首建场景跳过）
//                                                 # 不一致退出码非 0
//
// 运行：dart run tool/bundle_scripts.dart
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

String get kSource => p.join(_workspaceRoot(), 'scripts');
String get kDest => p.join(_workspaceRoot(), 'assets', 'scripts_bundle');
String get kPubspec => p.join(_workspaceRoot(), 'pubspec.yaml');

/// 返回 true 表示该路径应被跳过（不复制）。
bool _shouldSkip(String relative) {
  final parts = p.split(relative);
  final name = parts.isNotEmpty ? parts.last : '';

  // 任意层级的缓存 / 版本控制 / 点文件 / 单下划线前缀（测试与临时产物）。
  // ⚠️ 双下划线（__init__.py / __main__.py）是 Python 包必需文件，不能跳过。
  for (final part in parts) {
    if (part == '__pycache__' || part == '.git') return true;
    if (part.startsWith('_') && !part.startsWith('__')) return true;
  }
  if (name.startsWith('.')) return true;

  // 嵌入式 Python 解释器（单独供给，不进 flutter 资产）
  if (parts.first == 'python') return true;

  // Inno Setup 安装脚本 / 开发辅助脚本 / 开发验证脚本
  if (name.startsWith('installer') && name.endsWith('.iss')) return true;
  if (name == 'setup_python.cmd' || name == 'reload.cmd') return true;
  if (name == 'README.md' || name == 'AGENT.md') return true;
  if (name.startsWith('test_') || name.startsWith('verify_')) return true;

  // 二进制 / 字节码 / 渲染产物
  if (name.endsWith('.exe') || name.endsWith('.pyc')) return true;
  if (name == 'render_log.html') return true;

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

/// 从 pubspec 内容中提取 SCRIPTS 标记块行（trim 后，不含标记行）。
/// 标记块缺失返回 null。
List<String>? _readPubspecBlock(String content) {
  final startIdx = content.indexOf('>>>SCRIPTS_ASSETS_START>>>');
  final endIdx = content.indexOf('<<<SCRIPTS_ASSETS_END<<<');
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
    rels.map((rel) => '- assets/scripts_bundle/$rel').toList();

/// 逐字节比较。
bool _bytesEqual(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// --check 校验模式：返回进程退出码（0=一致，1=不一致）。
///
/// 与 bundle_plugins.dart 的 --check 同款（O4 扩展）：
///   1) pubspec.yaml SCRIPTS 标记块与 scripts/ 源一致（**提交态门禁**，
///      CI 关键检查——bundle 目录被 .gitignore，提交态只有 pubspec 块能守）；
///   2) assets/scripts_bundle/ 与 scripts/ 源**文件清单**一致（无陈旧副本/缺漏）；
///   3) 两侧**文件内容**一致（逐字节）。
/// bundle 目录不存在（CI 首建场景，构建前将重建）时仅做 pubspec 门禁并提示。
int _check() {
  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle-scripts-check] ❌ 源目录不存在: $kSource');
    return 1;
  }
  final expected = _collectRels(kSource);
  final failures = <String>[];

  // ── 1) pubspec 标记块（提交态门禁）──
  final pubspec = File(kPubspec);
  if (!pubspec.existsSync()) {
    stderr.writeln('[bundle-scripts-check] ❌ pubspec.yaml 不存在: $kPubspec');
    return 1;
  }
  final block = _readPubspecBlock(pubspec.readAsStringSync());
  final expectedBlock = _expectedBlockLines(expected);
  if (block == null) {
    failures.add('pubspec.yaml 缺少 SCRIPTS 标记块'
        '（>>>SCRIPTS_ASSETS_START>>> / <<<SCRIPTS_ASSETS_END<<<）');
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
    stderr.writeln('[bundle-scripts-check] ℹ assets/scripts_bundle/ 不存在'
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
    stderr.writeln('[bundle-scripts-check] ✅ 一致：${expected.length} 个脚本资产，'
        'pubspec 标记块 ${expectedBlock.length} 条。');
    return 0;
  }
  stderr.writeln('[bundle-scripts-check] ❌ 发现 ${failures.length} 处不一致：');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  stderr.writeln('[bundle-scripts-check] 修复：重新运行 `dart run tool/bundle_scripts.dart`'
      ' 重建 bundle 与 pubspec 标记块，并把 pubspec.yaml 变更一并提交。');
  return 1;
}

void main(List<String> args) {
  if (args.contains('--check')) {
    exit(_check());
  }

  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle-scripts] 源目录不存在: $kSource');
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
  stderr.writeln('[bundle-scripts] 完成：复制 $copied 个文件。');
  stderr.writeln('[bundle-scripts] 目标: $kDest');

  _injectPubspecAssets(rels);
}

/// 把 [rels] 显式写入 pubspec.yaml 的 SCRIPTS 标记块之间。
void _injectPubspecAssets(List<String> rels) {
  final pubspec = File(kPubspec);
  if (!pubspec.existsSync()) {
    stderr.writeln('[bundle-scripts] pubspec.yaml 不存在: $kPubspec');
    return;
  }
  var content = pubspec.readAsStringSync();
  final startIdx = content.indexOf('>>>SCRIPTS_ASSETS_START>>>');
  final endIdx = content.indexOf('<<<SCRIPTS_ASSETS_END<<<');
  if (startIdx < 0 || endIdx < 0) {
    stderr.writeln('[bundle-scripts] 未在 pubspec.yaml 找到 SCRIPTS 资产标记块，跳过注入。');
    return;
  }
  final startLineEnd = content.indexOf('\n', startIdx) + 1;
  final endLineStart = content.lastIndexOf('\n', endIdx);
  final before = content.substring(0, startLineEnd);
  final after = content.substring(endLineStart);
  final block =
      rels.map((rel) => '    - assets/scripts_bundle/$rel').join('\n');
  content = '$before$block\n$after';
  pubspec.writeAsStringSync(content);
  stderr.writeln('[bundle-scripts] 已注入 ${rels.length} 条资产到 pubspec.yaml');
}
