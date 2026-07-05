/// PluginInstaller 测试——覆盖安装/卸载/更新/崩溃/沙箱/回退。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../services/plugin_installer.dart' show PluginInstaller, compareVersions;

// ═══════ helpers ═══════

/// 创建一个最小的合法 .plugin ZIP 字节。
List<int> _makePluginZip({
  String id = 'test_plugin',
  String name = 'Test Plugin',
  String version = '1.0.0',
  bool tamper = false,
  bool skipSignature = false,
}) {
  final manifest = {
    'type': 'plugin',
    'id': id,
    'name': name,
    'version': version,
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));

  final sigBytes = tamper
      ? utf8.encode('00deadbeef00deadbeef00deadbeef00deadbeef00deadbeef00deadbeef00deadbeef00deadbeef')
      : utf8.encode(sha256.convert(manifestBytes).toString());

  final archive = Archive();
  archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  if (!skipSignature) {
    archive.addFile(ArchiveFile('.signature', sigBytes.length, sigBytes));
  }
  final agentBytes = utf8.encode('{"name":"echo","description":"test"}');
  archive.addFile(ArchiveFile('agent/manifest.json', agentBytes.length, agentBytes));

  return ZipEncoder().encode(archive)!;
}

/// 创建一个写入 .plugin 文件的临时目录。
Directory _tmpPluginDir() => Directory.systemTemp.createTempSync('plugin_test_');

void main() {
  late String tmpDir;
  late PluginInstaller installer;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('installer_test_').path;
    installer = PluginInstaller(pluginsDir: p.join(tmpDir, 'plugins'), dio: Dio());
  });

  tearDown(() {
    try { Directory(tmpDir).deleteSync(recursive: true); } catch (_) {}
  });

  // ═══════ install ═══════

  group('install', () {
    test('安装合法 .plugin 包创建目录结构', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);

      final result = await installer.install(pkgFile.path);

      expect(result.isOk, isTrue);
      final ir = result.unwrap();
      expect(ir.success, isTrue);
      expect(ir.pluginId, 'test_plugin');

      // 校验目录结构
      final pluginDir = Directory(p.join(tmpDir, 'plugins', 'test_plugin'));
      expect(pluginDir.existsSync(), isTrue);
      expect(File(p.join(pluginDir.path, '.manifest')).existsSync(), isTrue);
      expect(File(p.join(pluginDir.path, '.signature')).existsSync(), isTrue);
      expect(Directory(p.join(pluginDir.path, 'agent')).existsSync(), isTrue);
    });

    test('安装触发 onInstall 回调', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);

      String? notifiedId;
      installer.onInstall = (id) => notifiedId = id;

      await installer.install(pkgFile.path);
      expect(notifiedId, 'test_plugin');
    });

    test('签名校验失败拒绝安装', () async {
      final zipBytes = _makePluginZip(tamper: true);
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);

      final result = await installer.install(pkgFile.path);

      expect(result.isErr, isTrue);
      final pluginDir = Directory(p.join(tmpDir, 'plugins', 'test_plugin'));
      expect(pluginDir.existsSync(), isFalse);
    });

    test('缺少 .signature 文件拒绝安装', () async {
      final zipBytes = _makePluginZip(skipSignature: true);
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);

      final result = await installer.install(pkgFile.path);

      expect(result.isErr, isTrue);
    });

    test('重复安装同一插件拒绝', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);

      await installer.install(pkgFile.path);
      final result = await installer.install(pkgFile.path);

      expect(result.isErr, isTrue);
    });

    test('安装不存在文件返回错误', () async {
      final result = await installer.install('/nonexistent/path.plugin');
      expect(result.isErr, isTrue);
    });

    test('缺少 manifest name 字段拒绝', () async {
      final manifest = {'type': 'plugin', 'id': 'no_name', 'version': '1.0.0'};
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      final sigBytes = utf8.encode(sha256.convert(manifestBytes).toString());

      final archive = Archive();
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
      archive.addFile(ArchiveFile('.signature', sigBytes.length, sigBytes));

      final pkgFile = File(p.join(tmpDir, 'no_name.plugin'));
      await pkgFile.writeAsBytes(ZipEncoder().encode(archive)!);

      final result = await installer.install(pkgFile.path);
      expect(result.isErr, isTrue);
    });
  });

  // ═══════ uninstall ═══════

  group('uninstall', () {
    test('卸载已安装插件删除目录', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      final result = await installer.uninstall('test_plugin');

      expect(result.isOk, isTrue);
      expect(Directory(p.join(tmpDir, 'plugins', 'test_plugin')).existsSync(), isFalse);
    });

    test('卸载触发 onUninstall 回调', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      String? notifiedId;
      installer.onUninstall = (id) => notifiedId = id;

      await installer.uninstall('test_plugin');
      expect(notifiedId, 'test_plugin');
    });

    test('卸载不存在的插件返回错误', () async {
      final result = await installer.uninstall('nonexistent');
      expect(result.isErr, isTrue);
    });
  });

  // ═══════ verifyAll ═══════

  group('verifyAll', () {
    test('校验通过返回空列表', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      final corrupt = await installer.verifyAll();
      expect(corrupt, isEmpty);
    });

    test('签名不匹配返回损坏插件 ID', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      // 篡改 .manifest
      final manifestFile = File(p.join(tmpDir, 'plugins', 'test_plugin', '.manifest'));
      await manifestFile.writeAsString('{"tampered": true}');

      final corrupt = await installer.verifyAll();
      expect(corrupt, contains('test_plugin'));
    });

    test('空插件目录返回空列表', () async {
      final corrupt = await installer.verifyAll();
      expect(corrupt, isEmpty);
    });
  });

  // ═══════ listPlugins / pluginStatus ═══════

  group('listPlugins / pluginStatus', () {
    test('listPlugins 空目录返回空列表', () {
      expect(installer.listPlugins(), isEmpty);
    });

    test('安装后 listPlugins 包含插件', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      final plugins = installer.listPlugins();
      expect(plugins.length, 1);
      expect(plugins.first.id, 'test_plugin');
      expect(plugins.first.name, 'Test Plugin');
      expect(plugins.first.version, '1.0.0');
    });

    test('pluginStatus 不存在的插件返回 null', () {
      expect(installer.pluginStatus('nonexistent'), isNull);
    });

    test('subComponents 检测各子目录', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      final status = installer.pluginStatus('test_plugin')!;
      expect(status.subComponents['agent'], isTrue);
      expect(status.subComponents['module'], isFalse);
    });
  });

  // ═══════ 崩溃监控 ═══════

  group('崩溃监控', () {
    test('recordCrash 2 次不足阈值不标记为不稳定', () {
      installer.recordCrash('p1');
      installer.recordCrash('p1');
      expect(installer.isUnstable('p1'), isFalse);
    });

    test('recordCrash 3 次标记为不稳定', () {
      installer.recordCrash('p1');
      installer.recordCrash('p1');
      installer.recordCrash('p1');
      expect(installer.isUnstable('p1'), isTrue);
    });

    test('不同插件独立计数', () {
      installer.recordCrash('a');
      installer.recordCrash('a');
      installer.recordCrash('b');
      expect(installer.isUnstable('a'), isFalse);
      expect(installer.isUnstable('b'), isFalse);
    });
  });

  // ═══════ 沙箱隔离 ═══════

  group('沙箱隔离', () {
    test('isWithinPluginDir 自身目录通过', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      final pluginDir = p.join(tmpDir, 'plugins', 'test_plugin');
      expect(installer.isWithinPluginDir('test_plugin', pluginDir), isTrue);
      expect(
        installer.isWithinPluginDir('test_plugin', p.join(pluginDir, 'agent')),
        isTrue,
      );
    });

    test('isWithinPluginDir 越界路径拒绝', () async {
      final zipBytes = _makePluginZip();
      final pkgFile = File(p.join(tmpDir, 'test.plugin'));
      await pkgFile.writeAsBytes(zipBytes);
      await installer.install(pkgFile.path);

      expect(
        installer.isWithinPluginDir('test_plugin', p.join(tmpDir, 'plugins', 'other')),
        isFalse,
      );
    });
  });

  // ═══════ checkUpdate ═══════

  group('checkUpdate', () {
    test('未安装插件返回 hasUpdate=false', () async {
      final result = await installer.checkUpdate('nonexistent');
      expect(result.hasUpdate, isFalse);
    });
  });

  // ═══════ compareVersions ═══════

  group('compareVersions', () {
    test('相同版本返回 0', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('2.3.1', '2.3.1'), 0);
    });

    test('a 较新返回 1', () {
      expect(compareVersions('2.0.0', '1.0.0'), 1);
      expect(compareVersions('1.1.0', '1.0.0'), 1);
      expect(compareVersions('1.0.1', '1.0.0'), 1);
      expect(compareVersions('10.0.0', '9.9.9'), 1);
    });

    test('a 较旧返回 -1', () {
      expect(compareVersions('1.0.0', '2.0.0'), -1);
      expect(compareVersions('1.0.0', '1.1.0'), -1);
      expect(compareVersions('1.0.0', '1.0.1'), -1);
    });

    test('pre-release 后缀被忽略', () {
      expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
      expect(compareVersions('2.0.0-alpha.1', '1.9.9'), 1);
      expect(compareVersions('1.0.0', '1.0.0-rc2'), 0);
    });

    test('缺失段视为 0', () {
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.0', '1.0.1'), -1);
      expect(compareVersions('2', '1.9.9'), 1);
    });

    test('非数字部分按 0 处理', () {
      expect(compareVersions('x.y.z', '0.0.0'), 0);
      expect(compareVersions('1.0.0', 'abc'), 1);
    });
  });
}
