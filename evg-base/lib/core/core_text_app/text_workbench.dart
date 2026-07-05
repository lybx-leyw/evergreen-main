/// 工作台页面——已安装模块列表。
library;

import 'helpers.dart';

Future<void> textWorkbench(Map<String, int> ports) async {
  ctaHeader('工作台 — 已安装模块');
  var loaded = false;
  try {
    final resp = await ctaGet(ports['Module']!, '/module/search?q=');
    final results = resp['results'] as List? ?? [];
    if (results.isNotEmpty) {
      loaded = true;
      for (final r in results) {
        final map = r as Map;
        print('  📦 ${map['id']}  ${map['name']}  [${map['category'] ?? "-"}]');
      }
    }
  } catch (_) {}

  if (!loaded) {
    try {
      final resp = await ctaGet(ports['Core']!, '/core/plugins');
      final plugins = resp['plugins'] as List? ?? [];
      if (plugins.isEmpty) {
        print('  (暂无已安装模块/插件)');
      } else {
        for (final p in plugins) {
          final map = p as Map;
          print('  📦 ${map['id']}  v${map['version']}  ${map['name']}');
        }
      }
    } catch (_) {
      print('  (无法加载——模块服务暂不可用)');
    }
  }
}
