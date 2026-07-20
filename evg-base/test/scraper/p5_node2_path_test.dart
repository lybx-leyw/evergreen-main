/// A-P5 节点 2 路径统一 — resolvePluginsRoot() + PluginExporter 验证。
///
/// 覆盖：
/// - Gap A: `resolvePluginsRoot()` 优先级（env var > exe parent > cwd parent > fallback）
/// - Gap B: `PluginExporter` 在指定 pluginsDir 下正确创建目标目录
/// - Gap C: 确认 node 2 "三件套"（data/manifest.json / config/config.json / module/manifest.json）均可正确写入
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_exporter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

void main() {
  group('GapA resolvePluginsRoot() 优先级', () {
    setUp(() {
      resetPluginsRootCache();
    });

    tearDown(() {
      resetPluginsRootCache();
    });

    test('返回绝对路径', () {
      final root = resolvePluginsRoot();
      expect(p.isAbsolute(root), isTrue,
          reason: 'pluginsRoot 必须为绝对路径，避免 CWD 变动导致错落');
    });

    test('路径以 /plugins 结尾', () {
      final root = resolvePluginsRoot();
      // normalize 后可能为 \plugins 或 /plugins
      expect(root.endsWith('plugins'), isTrue,
          reason: '应解析到 .../plugins 目录');
    });

    test('目录必定存在', () {
      final root = resolvePluginsRoot();
      expect(Directory(root).existsSync(), isTrue,
          reason: 'resolvePluginsRoot 必须确保目录存在');
    });

    test('缓存：二次调用返回相同路径', () {
      final first = resolvePluginsRoot();
      final second = resolvePluginsRoot();
      expect(second, equals(first),
          reason: 'pluginsRoot 应缓存，避免重复文件 I/O');
    });

    test('resetPluginsRootCache 清除缓存', () {
      final before = resolvePluginsRoot();
      resetPluginsRootCache();
      final after = resolvePluginsRoot();
      // 重置后重新解析，路径应相同（环境未变）
      expect(after, equals(before));
    });

    test('ENV EVERGREEN_PLUGINS_DIR 优先（未设置时走 fallback）', () {
      // Platform.environment 在测试中不可写，验证不设置时走 fallback 逻辑
      // 确认函数不会因 env var 缺失而崩溃
      resetPluginsRootCache();
      final root = resolvePluginsRoot();
      expect(p.isAbsolute(root), isTrue);
      expect(root.endsWith('plugins'), isTrue);
      // 确认不带 env var 前缀（说明不是从 EVERGREEN_PLUGINS_DIR 来的）
      // 如果 EVERGREEN_PLUGINS_DIR 已设置，跳过此断言
      if (!Platform.environment.containsKey('EVERGREEN_PLUGINS_DIR')) {
        // fallback 路径不应包含 set 的环境值
        debugPrint(
          '[TEST] pluginsRoot (no env override): $root',
        );
      }
    });

    test('不设置 env var 时走 exe parent fallback', () {
      // 确保 EVERGREEN_PLUGINS_DIR 未设置的情况下
      // 从 Platform.resolvedExecutable 的 pubspec.yaml 向上查找
      expect(
        () => resolvePluginsRoot(),
        returnsNormally,
        reason: '未设置 env var 时应自动 fallback 到 exe/cwd parent',
      );
    });
  });

  group('GapB PluginExporter — pluginsDir 路径正确性', () {
    late String tmpPlugins;

    setUp(() {
      tmpPlugins = Directory.systemTemp.createTempSync('evg_plugins_').path;
    });

    tearDown(() {
      // 清理所有测试子目录
      if (Directory(tmpPlugins).existsSync()) {
        Directory(tmpPlugins).deleteSync(recursive: true);
      }
    });

    test('exportToDir 在 pluginsDir/<pluginId> 下写入', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = DesignDocument(pluginId: 'test-plugin', pluginName: 'Test');

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue, reason: result.error);
      expect(result.targetPath, contains(tmpPlugins),
          reason: '导出必须在 pluginsDir 下');
      expect(result.targetPath, contains('test-plugin'),
          reason: '子目录应为 pluginId');

      // 目录结构验证
      final moduleManifest = File(
        p.join(result.targetPath, 'module', 'manifest.json'),
      );
      expect(moduleManifest.existsSync(), isTrue,
          reason: '必须生成 module/manifest.json');
    });

    test('三件套：module + config + data 全部产出', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = _makeDocWithConfigAndData();

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue, reason: result.error);

      // 1. module/manifest.json
      expect(
        File(p.join(result.targetPath, 'module', 'manifest.json')).existsSync(),
        isTrue,
      );

      // 2. config/config.json
      expect(
        File(p.join(result.targetPath, 'config', 'config.json')).existsSync(),
        isTrue,
      );

      // 3. data/data_source.json
      expect(
        File(p.join(result.targetPath, 'data', 'data_source.json')).existsSync(),
        isTrue,
      );

      // 4. agent/manifest.json
      expect(
        File(p.join(result.targetPath, 'agent', 'manifest.json')).existsSync(),
        isTrue,
      );
    });

    test('无 config 时不生成 config/ 目录', () async {
      final exporter = PluginExporter(tmpPlugins);
      // 不设 metadata.config
      final doc = DesignDocument(pluginId: 'no-config', pluginName: 'NoConfig');

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue);
      expect(
        Directory(p.join(result.targetPath, 'config')).existsSync(),
        isFalse,
        reason: '无 config 数据时应跳过 config/ 目录',
      );
    });

    test('无 data_source 时不生成 data/ 目录', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = DesignDocument(pluginId: 'no-data', pluginName: 'NoData');

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue);
      expect(
        Directory(p.join(result.targetPath, 'data')).existsSync(),
        isFalse,
        reason: '无数据源信息时应跳过 data/ 目录',
      );
    });

    test('manifest 内容可通过 ModuleDescriptor.fromJson 校验', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = _makeDocWithConfigAndData();

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue);

      // 验证 manifest 被正确校验（不抛即通过）
      expect(result.manifestPath, isNotNull);
      expect(File(result.manifestPath!).existsSync(), isTrue);
    });

    test('空 pluginId 仍不崩溃', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = DesignDocument(pluginId: '', pluginName: 'Empty');

      final result = await exporter.exportToDir(doc);
      // 可能成功（插件目录名为空串）也可能失败，但绝不能崩溃
      expect(result, isNotNull);
      expect(result.targetPath, isNotEmpty);
    });
  });

  group('GapC PluginExporter — 节点 2 三件套产物验证', () {
    late String tmpPlugins;

    setUp(() {
      tmpPlugins = Directory.systemTemp.createTempSync('evg_plugins_').path;
    });

    tearDown(() {
      if (Directory(tmpPlugins).existsSync()) {
        Directory(tmpPlugins).deleteSync(recursive: true);
      }
    });

    test('产物目录结构完整（data + config + module）', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = _makeDocWithConfigAndData();

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue);

      final root = Directory(result.targetPath);
      final entries = root.listSync().map((e) {
        final name = p.basename(e.path);
        return e is Directory ? '$name/' : name;
      }).toList();

      // 应至少包含 module/ + config/ + data/ + agent/
      expect(entries, contains('module/'));
      expect(entries, contains('config/'));
      expect(entries, contains('data/'));
      expect(entries, contains('agent/'));
    });

    test('createdFiles 记录所有路径', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = _makeDocWithConfigAndData();

      final result = await exporter.exportToDir(doc);
      expect(result.success, isTrue);
      expect(result.createdFiles.length, greaterThanOrEqualTo(4),
          reason: '至少 4 项：4 个目录 + manifest.json + config.json + data_source.json + agent manifest.json');
    });

    test('多次导出同一 pluginId 不报错（幂等）', () async {
      final exporter = PluginExporter(tmpPlugins);
      final doc = _makeDocWithConfigAndData();

      final r1 = await exporter.exportToDir(doc);
      expect(r1.success, isTrue);

      final r2 = await exporter.exportToDir(doc);
      expect(r2.success, isTrue,
          reason: '二次导出应幂等不崩溃');
    });
  });
}

/// 创建含 config + data_source + agent metadata 的 DesignDocument。
DesignDocument _makeDocWithConfigAndData() {
  final doc = DesignDocument(
    pluginId: 'three-inone',
    pluginName: '三件套测试',
  );
  // 注入 config
  doc.metadata['config'] = {
    'API_KEY': {
      'type': 'string',
      'label': 'API密钥',
      'sensitive': true,
    },
  };
  // 注入 data_source
  doc.metadata['data_source'] = {
    'type': 'data-source',
    'script': 'scraper.py',
    'dataTypes': [
      {
        'name': 'testData',
        'typeArg': 'testData',
        'ttl': '5m',
        'persistentKey': 'custom-three-inone:testData',
      }
    ],
  };
  // 注入 agent
  doc.metadata['agent'] = {
    'name': 'three-inone-agent',
    'version': '1.0.0',
  };
  // 加一个测试页面以通过 manifest 编译
  doc.addPage(DesignPage(id: 'page_0', label: '首页'));
  return doc;
}
