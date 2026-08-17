// 工具能力事实源测试（P2-1 · tool-index）。
//
// 覆盖：
// 1. scanPythonSitePackages：目录包 / x.py / dist-info 识别、隐藏项跳过、黑名单过滤、排序去重
// 2. 两种 site-packages 布局（Lib/site-packages 与 site-packages）
// 3. 目录不存在 / 扫描失败 → 空清单；pythonCapabilitiesPrompt 文案
import 'dart:io';

import 'package:evergreen_base/renderer/templates/scraper_modle/agent/python_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pycap_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Directory makeSitePackages(String rel) {
    final d = Directory('${tmp.path}/$rel');
    d.createSync(recursive: true);
    return d;
  }

  group('scanPythonSitePackages', () {
    test('识别目录包 / 单文件模块 / dist-info，跳过隐藏与黑名单', () {
      final sp = makeSitePackages('site-packages');
      Directory('${sp.path}/requests').createSync();
      Directory('${sp.path}/numpy').createSync();
      File('${sp.path}/tiny.py').writeAsStringSync('x');
      Directory('${sp.path}/requests-2.31.0.dist-info').createSync();
      Directory('${sp.path}/_internal').createSync(); // 下划线跳过
      Directory('${sp.path}/.hidden').createSync(); // 隐藏跳过
      Directory('${sp.path}/subprocess').createSync(); // 黑名单跳过
      Directory('${sp.path}/selenium').createSync(); // 黑名单跳过

      final out = scanPythonSitePackages(tmp.path);
      expect(out, ['numpy', 'requests', 'tiny']); // 排序 + 去重（dist-info 与目录同名）
    });

    test('优先 Windows 嵌入版 Lib/site-packages 布局', () {
      makeSitePackages('Lib/site-packages');
      Directory('${tmp.path}/Lib/site-packages/requests').createSync();
      Directory('${tmp.path}/site-packages/bs4').createSync(recursive: true); // 不应被扫描到

      final out = scanPythonSitePackages(tmp.path);
      expect(out, ['requests']);
    });

    test('目录不存在 → 空清单', () {
      expect(scanPythonSitePackages('${tmp.path}/nonexistent'), isEmpty);
    });

    test('扫描失败（site-packages 是文件）→ 空清单不抛', () {
      File('${tmp.path}/site-packages').writeAsStringSync('x');
      expect(scanPythonSitePackages(tmp.path), isEmpty);
    });
  });

  group('pythonCapabilitiesPrompt', () {
    test('有模块：列出清单并提示 lint 拦截', () {
      final s = pythonCapabilitiesPrompt(['requests', 'numpy']);
      expect(s, contains('requests, numpy'));
      expect(s, contains('lint 拦截'));
      expect(s, contains('标准库'));
    });

    test('无模块：仅标准库提示', () {
      final s = pythonCapabilitiesPrompt(const []);
      expect(s, contains('仅 Python 标准库'));
      expect(s, contains('lint 拦截'));
    });
  });
}
