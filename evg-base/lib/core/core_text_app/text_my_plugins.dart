/// 我的插件页面——管理已安装插件（卸载）。
library;

import 'dart:io';
import 'helpers.dart';

Future<void> textMyPlugins(Map<String, int> ports) async {
  ctaHeader('我的插件 — 管理已安装插件');
  try {
    final resp = await ctaGet(ports['Core']!, '/core/plugins');
    final plugins = resp['plugins'] as List? ?? [];
    if (plugins.isEmpty) {
      print('  (暂无已安装插件)');
    } else {
      for (final p in plugins) {
        final map = p as Map;
        final status = map['isUnstable'] == true ? '⚠️' : '✅';
        print('  $status ${map['id']}  v${map['version']}  ${map['name']}');
      }
    }

    stdout.write('\n  卸载插件 (输入 id 或回车跳过): ');
    final id = stdin.readLineSync()?.trim() ?? '';
    if (id.isNotEmpty) {
      final result = await ctaPost(ports['Core']!, '/core/uninstall/$id', {});
      if (result.containsKey('uninstalled')) {
        print('  ✅ 已卸载: $id');
      } else {
        print('  ❌ 卸载失败: ${result['error']}');
      }
    }
  } catch (e) {
    print('  ❌ 加载失败: $e');
  }
}
