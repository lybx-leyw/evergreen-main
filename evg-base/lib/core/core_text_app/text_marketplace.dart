/// 市场页面——插件浏览与安装。
library;

import 'dart:io';
import 'helpers.dart';

Future<void> textMarketplace(Map<String, int> ports) async {
  ctaHeader('市场 — 插件浏览与安装');
  try {
    final resp = await ctaGet(ports['Module']!, '/module/search?q=');
    final results = resp['results'] as List? ?? [];
    if (results.isEmpty) {
      print('  (市场暂无插件)');
    } else {
      for (final r in results) {
        final map = r as Map;
        print('  🛒 ${map['id']}  ${map['name']}  ${map['description'] ?? ""}');
      }
    }
  } catch (_) {
    try {
      final resp = await ctaGet(ports['Core']!, '/core/plugins');
      final plugins = resp['plugins'] as List? ?? [];
      if (plugins.isEmpty) {
        print('  (暂无已安装插件——即为市场候选)');
      } else {
        for (final p in plugins) {
          final map = p as Map;
          print('  🛒 ${map['id']}  v${map['version']}  ${map['name']}');
        }
      }
    } catch (_2) {
      print('  (市场暂不可用——Module 服务未就绪)');
    }
  }

  stdout.write('\n  安装插件 (输入 URL 或回车跳过): ');
  final url = stdin.readLineSync()?.trim() ?? '';
  if (url.isNotEmpty) {
    print('  正在安装...');
    try {
      final result = await ctaPost(ports['Core']!, '/core/install', {'url': url});
      if (result['success'] == true) {
        print('  ✅ 安装成功: ${result['pluginId']}');
      } else {
        print('  ❌ 安装失败: ${result['error']}');
      }
    } catch (e) {
      print('  ❌ 安装失败: $e');
    }
  }
}
