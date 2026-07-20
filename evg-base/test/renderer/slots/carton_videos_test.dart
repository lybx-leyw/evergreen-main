/// 动画视频插件（carton-videos）× classroom_modle 泛化性验证。
///
/// 验证点：
/// 1. 模块清单声明 template=classroom + dataSource(endpoint=orch://carton_videos) + 完整 bindings；
/// 2. 真实 scraper（scraper.exe）输出符合 classroom_modle 期望的 {courses:[...]} 形状；
/// 3. 视频为真实动画 mp4 的绝对路径且文件确实存在（PPT 留空、字幕为占位）；
/// 4. 用模块声明的 bindings 经 [extractPath] 提取，能正确还原语义字段
///    （证明 classroom_modle 拿到这份「非课堂录播」的数据也能正确驱动 UI）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/atomic/json_path.dart';
import 'package:path/path.dart' as p;

const _moduleId = 'carton-videos';
const _typeName = 'carton_videos';

String get _projectRoot => Directory.current.path;
String get _pluginsDir => p.join(_projectRoot, '..', 'plugins');
String get _moduleManifestPath =>
    p.join(_pluginsDir, _moduleId, 'module', 'manifest.json');
String get _scraperExePath =>
    p.join(_pluginsDir, _moduleId, 'data', 'scraper.exe');

/// 运行真实 scraper.exe 拉取数据（与平台 Process.run 契约一致）。
Map<String, dynamic> _fetchViaScraper() {
  final exe = File(_scraperExePath);
  expect(exe.existsSync(), isTrue,
      reason: 'scraper.exe 不存在，请先编译（PyInstaller --onefile）');
  final result = Process.runSync(
    _scraperExePath,
    ['--type', _typeName, '--project-root', _projectRoot],
    workingDirectory: p.dirname(_scraperExePath),
  );
  expect(result.exitCode, 0,
      reason: 'scraper.exe 异常退出: ${result.stderr}');
  final parsed = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  expect(parsed.containsKey('error'), isFalse,
      reason: 'scraper 返回 error: ${parsed['error']}');
  return parsed;
}

void main() {
  group('carton-videos × classroom_modle 泛化性', () {
    late ModuleDescriptor mod;
    late DataSourceDescriptor ds;
    late Map<String, dynamic> bindings;
    late Map<String, dynamic> data;
    late List<dynamic> courses;
    late Map<String, dynamic> course;
    late List<dynamic> videos;

    setUpAll(() {
      final mf = File(_moduleManifestPath);
      expect(mf.existsSync(), isTrue,
          reason: '模块清单缺失: $_moduleManifestPath');
      mod = ModuleDescriptor.fromJson(
          jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>);
      ds = mod.dataSource!;
      bindings = ds.bindings!;
      data = _fetchViaScraper();
      courses = extractPath(data, bindings['courses']!) as List<dynamic>;
      course = courses.first as Map<String, dynamic>;
      videos = extractPath(course, bindings['course.videos']!) as List<dynamic>;
    });

    test('模块声明：template=classroom + 正确的 dataSource/bindings', () {
      expect(mod.template, 'classroom');
      expect(ds.endpoint, 'orch://$_typeName');
      // 关键语义键都有绑定
      for (final k in [
        'courses',
        'course.id',
        'course.title',
        'course.videos',
        'video.id',
        'video.title',
        'video.videoUrl',
        'video.slides',
        'video.subtitles',
        'subtitle.text',
      ]) {
        expect(bindings.containsKey(k), isTrue, reason: '缺少绑定键: $k');
      }
    });

    test('数据形状：单课程 + 大批量视频（动画全集）', () {
      expect(courses, isNotEmpty);
      expect(videos.length, greaterThanOrEqualTo(50),
          reason: '应至少收录 50 集动画（第12集为残片已排除）');
    });

    test('视频字段：真实动画 mp4 绝对路径且文件存在', () {
      for (final v in videos) {
        final url = extractPath(v, bindings['video.videoUrl']!) as String?;
        expect(url, isNotNull);
        expect(p.isAbsolute(url!), isTrue, reason: 'videoUrl 应为绝对路径');
        expect(File(url!).existsSync(), isTrue,
            reason: '动画视频文件不存在: $url');
        expect(url!.toLowerCase().endsWith('.mp4'), isTrue);
      }
    });

    test('PPT 填空 + 字幕占位', () {
      for (final v in videos) {
        final slides = extractPath(v, bindings['video.slides']!);
        expect(slides, isEmpty, reason: 'PPT 应为空列表');
        final subs = extractPath(v, bindings['video.subtitles']!) as List<dynamic>;
        expect(subs, isNotEmpty, reason: '字幕应为占位（非空）');
        final text = extractPath(subs.first, bindings['subtitle.text']!) as String?;
        expect(text, contains('字幕占位'), reason: '字幕应为占位文本');
      }
    });

    test('bindings 驱动提取：course.title / video.title 正确还原', () {
      final title = extractPath(course, bindings['course.title']!) as String?;
      expect(title, contains('火星娃'));
      final firstVideoTitle =
          extractPath(videos.first, bindings['video.title']!) as String?;
      expect(firstVideoTitle, startsWith('第'));
    });
  });
}
