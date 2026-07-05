/// 设置页面——主题切换、模型配置、源管理。
library;

import 'dart:io';
import 'helpers.dart';

Future<void> textSettings(Map<String, int> ports) async {
  while (true) {
    ctaHeader('设置');
    try {
      final themesResp = await ctaGet(ports['Theme']!, '/theme/themes');
      final themes = themesResp['themes'] as List? ?? [];
      final activeResp = await ctaGet(ports['Theme']!, '/theme/active');
      final activeTheme = activeResp['id'] as String? ?? '?';
      print('  🎨 主题: $activeTheme (可用: ${themes.map((t) => (t as Map)['id']).join(', ')})');

      final modelResp = await ctaGet(ports['Config']!, '/config/settings/DEEPSEEK_MODEL');
      print('  🤖 模型: ${modelResp['value']}');

      final sourcesResp = await ctaGet(ports['Config']!, '/config/sources');
      final sources = sourcesResp['sources'] as List? ?? [];
      print('  📡 源: ${sources.length} 个');

      print('\n  [t] 切换主题  [m] 修改模型  [s] 管理源  [q] 返回');
      stdout.write('  > ');
      final cmd = stdin.readLineSync()?.trim() ?? '';

      if (cmd == 'q') break;
      if (cmd == 't') {
        stdout.write('  主题 id: ');
        final id = stdin.readLineSync()?.trim() ?? '';
        if (id.isNotEmpty) {
          await ctaPost(ports['Theme']!, '/theme/active', {'id': id});
          print('  ✅ 已切换');
        }
      }
      if (cmd == 'm') {
        stdout.write('  模型名: ');
        final model = stdin.readLineSync()?.trim() ?? '';
        if (model.isNotEmpty) {
          await ctaPost(ports['Config']!, '/config/settings/DEEPSEEK_MODEL', {'value': model});
          print('  ✅ 已更新');
        }
      }
    } catch (e) {
      print('  ❌ 设置加载失败: $e');
    }
  }
}
