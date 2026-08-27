/// 皮肤包加载器——扫描 `plugins/<id>/skin/manifest.json`（镜像 theme_loader）。
///
/// # 顶层函数
///
/// | 函数 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `scanSkins(dir)` | `String` | `List<SkinDescriptor>` | 扫描目录 |
/// | `scanSkinFile(path)` | `String` | `SkinDescriptor` | 加载单个 manifest.json |
/// | `loadSkins(dir, store)` | `String`, `SkinStore` | `void` | 扫描 + 注册 |
///
/// 失败策略（与 scanThemes 一致）：格式错误（type 非 skin / JSON 非法）的皮肤包
/// 跳过并在 stderr 输出 ❌ 明细与汇总，便于插件作者定位问题，不阻塞其余包。
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'skin_descriptor.dart';
import 'skin_store.dart';

// ═══════ 扫描 ═══════

/// 扫描目录下所有子目录中的 `skin/manifest.json`，返回 [SkinDescriptor] 列表。
///
/// 每个皮肤的 `sourceDir` 会被填充为对应插件目录（`plugins/<id>`），
/// 供渲染层解析皮肤内图片资源（logo / 头像等）。
List<SkinDescriptor> scanSkins(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return [];

  final skins = <SkinDescriptor>[];
  final failures = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final file = File(p.join(entity.path, 'skin', 'manifest.json'));
    if (!file.existsSync()) continue;

    try {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (map['type'] != kSkinType) continue;
      skins.add(SkinDescriptor.fromJson(map).withSourceDir(entity.path));
    } on FormatException catch (e) {
      failures.add('${file.path}: $e');
      stderr.writeln('[skin] ❌ 皮肤包加载失败: ${file.path} → $e');
    } on TypeError catch (e) {
      // JSON 顶层非对象（如数组/标量）：同样视为坏 manifest 跳过。
      failures.add('${file.path}: $e');
      stderr.writeln('[skin] ❌ 皮肤包加载失败: ${file.path} → $e');
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln(
        '[skin] ⚠ 共 ${failures.length} 个皮肤包加载失败，已跳过：\n  - '
        '${failures.join('\n  - ')}');
  }
  return skins;
}

/// 加载单个 `skin/manifest.json` 文件并解析为 [SkinDescriptor]。
///
/// 文件不存在或格式错误时抛异常。
SkinDescriptor scanSkinFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('skin/manifest.json 不存在', filePath);
  }
  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return SkinDescriptor.fromJson(map);
}

/// 扫描目录并注册到 [SkinStore]。
void loadSkins(String dirPath, SkinStore store) {
  for (final s in scanSkins(dirPath)) {
    store.register(s);
  }
}
