/// 主题加载器——扫描 theme.json 文件（扁平语义色板模型）。
///
/// # 顶层函数
///
/// | 函数 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `scanThemes(dir)` | `String` | `List<ThemeDescriptor>` | 扫描目录 |
/// | `scanThemeFile(path)` | `String` | `ThemeDescriptor` | 加载单个 theme.json |
/// | `loadThemes(dir, store)` | `String`, `ThemeStore` | `void` | 扫描 + 注册 |
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'theme_descriptor.dart';
import 'theme_store.dart';

// ═══════ 扫描 ═══════

/// 扫描目录下所有子目录中的 theme.json，返回 [ThemeDescriptor] 列表。
///
/// 格式错误（缺 8 必填色 / hex 非法）的主题会跳过并在 stderr 输出
/// ❌ 明细与汇总，便于插件作者定位问题（不再静默丢弃）。
List<ThemeDescriptor> scanThemes(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return [];

  final themes = <ThemeDescriptor>[];
  final failures = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final file = File(p.join(entity.path, 'theme', 'theme.json'));
    if (!file.existsSync()) continue;

    try {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (map['type'] != 'theme') continue;
      themes.add(ThemeDescriptor.fromJson(map));
    } on FormatException catch (e) {
      failures.add('${file.path}: $e');
      stderr.writeln('[theme] ❌ 主题加载失败: ${file.path} → $e');
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln(
        '[theme] ⚠ 共 ${failures.length} 个主题加载失败，已跳过：\n  - '
        '${failures.join('\n  - ')}');
  }
  return themes;
}

/// 加载单个 theme.json 文件并解析为 [ThemeDescriptor]。
///
/// 文件不存在或格式错误时抛异常。
ThemeDescriptor scanThemeFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('theme.json 不存在', filePath);
  }
  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return ThemeDescriptor.fromJson(map);
}

/// 扫描目录并注册到 [ThemeStore]。
void loadThemes(String dirPath, ThemeStore store) {
  for (final t in scanThemes(dirPath)) {
    store.register(t);
  }
}
