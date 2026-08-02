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

void main() {
  final src = Directory(kSource);
  if (!src.existsSync()) {
    stderr.writeln('[bundle] 源目录不存在: $kSource');
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
  stderr.writeln('[bundle] 完成：复制 $copied 个文件，跳过 $skipped 个。');
  stderr.writeln('[bundle] 目标: $kDest');

  // 注入显式资产清单到 pubspec.yaml（本环境 Flutter 目录资产包含不递归子目录）
  _injectPubspecAssets(rels..sort());
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
