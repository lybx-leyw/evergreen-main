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
//   - `__pycache__` / `*.pyc` / `*.exe` / 点文件
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

  // 任意层级的缓存 / 版本控制 / 点文件 / 下划线前缀（测试与临时产物）
  for (final part in parts) {
    if (part == '__pycache__' || part == '.git') return true;
    if (part.startsWith('_')) return true;
  }
  if (name.startsWith('.')) return true;

  // 嵌入式 Python 解释器（单独供给，不进 flutter 资产）
  if (parts.first == 'python') return true;

  // Inno Setup 安装脚本 / 开发辅助脚本 / 开发验证脚本
  if (name.startsWith('installer') && name.endsWith('.iss')) return true;
  if (name == 'setup_python.cmd' || name == 'reload.cmd') return true;
  if (name == 'README.md') return true;
  if (name.startsWith('test_') || name.startsWith('verify_')) return true;

  // 二进制 / 字节码 / 渲染产物
  if (name.endsWith('.exe') || name.endsWith('.pyc')) return true;
  if (name == 'render_log.html') return true;

  return false;
}

void main() {
  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle-scripts] 源目录不存在: $kSource');
    exit(1);
  }
  final dest = Directory(kDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  dest.createSync(recursive: true);

  final rels = <String>[];
  var copied = 0;
  var skipped = 0;
  for (final entity in src.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: kSource).replaceAll('\\', '/');
    if (_shouldSkip(rel)) {
      skipped++;
      continue;
    }
    final out = File(p.join(kDest, rel));
    out.parent.createSync(recursive: true);
    entity.copySync(out.path);
    copied++;
    rels.add(rel);
  }
  stderr.writeln('[bundle-scripts] 完成：复制 $copied 个文件，跳过 $skipped 个。');
  stderr.writeln('[bundle-scripts] 目标: $kDest');

  _injectPubspecAssets(rels..sort());
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
