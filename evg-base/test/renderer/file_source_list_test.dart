/// `FileSourceList`（选择性下载 UI）widget 测试 —— 方案 P2。
///
/// ⚠️ **本文件尚未在沙箱内跑过**：`lib/renderer/**` 是嵌套子包，其
/// `dart analyze` 上下文无法解析 `package:flutter/*`（A/B 实测：同目录未改动的
/// `file_export_bar.dart` 也有 55 个 `uri_does_not_exist` 假错误）。
/// 权威验证 = 根上下文 `flutter test`（沙箱内 `flutter test` 已被 SIGKILL）。
/// 环境恢复后请执行：
///   cd evg-base && flutter test test/renderer/file_source_list_test.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/data/file_source_entries.dart';
import 'package:evergreen_base/core/result.dart';
import 'package:evergreen_base/core/services/data_file_service.dart';
import 'package:evergreen_base/renderer/components/shared/file_source_list.dart';

/// 起一个最小 HTTP 服务（供「待下载」项）。
Future<(HttpServer, String)> startServer(List<int> body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    try {
      req.response.statusCode = 200;
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    } catch (_) {}
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 假下载服务——**widget 测试不做真实 I/O**。
///
/// 原因：`testWidgets` 运行在 fake-async zone，真实 socket 完成回调不会被推进，
/// `await` 真实 HTTP 会**永久挂起**（实测 pumpUntil 超时）。真实下载链路已由
/// `lib/core/test/data_file_service_test.dart` + `data_file_service_streaming_test.dart`
/// 覆盖；此处只验证 **UI 的状态迁移与进度接线**。
class FakeDownloadService extends DataFileService {
  final List<String> downloaded = [];
  final List<int> progress = [];

  @override
  Future<Result<String>> downloadFile({
    required String url,
    required String targetPath,
    Map<String, String>? headers,
    Duration? timeout,
    int maxRetries = 3,
    DownloadProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 10);
    onProgress?.call(5, 10);
    File(targetPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(10, 0));
    progress.add(10);
    onProgress?.call(10, 10);
    downloaded.add(url);
    return Ok(targetPath);
  }
}

/// 轮询直到 [cond] 成立。
///
/// ⚠️ **不能用 `pumpAndSettle`**：下载中 `LinearProgressIndicator` 在未知 total
/// 时是**无限动画**，`pumpAndSettle` 永远等不到静止（实测卡死超时）。
Future<void> pumpUntil(WidgetTester tester, bool Function() cond,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (cond()) return;
  }
  fail('pumpUntil 超时：条件始终未成立');
}

void main() {
  testWidgets('已缓存项：显示「已缓存」+ 打开按钮，无勾选框', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fsl_cached_');
    addTearDown(() => dir.deleteSync(recursive: true));
    FileSourceEntry? opened;

    await tester.pumpWidget(wrap(FileSourceList(
      entries: [
        const FileSourceEntry(
            path: '/c/file_cache/a-b.mp4', name: '第1讲.mp4', size: 5 * 1024 * 1024),
      ],
      service: DataFileService(),
      targetDir: dir.path,
      onOpen: (e) => opened = e,
    )));

    expect(find.text('第1讲.mp4'), findsOneWidget);
    expect(find.textContaining('已缓存 ·'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing,
        reason: '已缓存项不需要勾选（零下载）');

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(opened, isNotNull, reason: 'onOpen 应被回调');
  });

  testWidgets('待下载项：勾选 → 下载选中 → 落盘 → 状态转「已下载」', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fsl_dl_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final svc = FakeDownloadService();

    await tester.pumpWidget(wrap(FileSourceList(
      entries: const [FileSourceEntry(url: 'https://x/a.mp4', name: 'a.mp4')],
      service: svc,
      targetDir: dir.path,
    )));

    // 初始：有勾选框，无下载按钮
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.textContaining('待下载'), findsOneWidget);
    expect(find.textContaining('下载选中'), findsNothing);

    // 勾选 → 按钮出现
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(find.textContaining('下载选中 (1)'), findsOneWidget);

    // 点击下载 → 经服务落盘 → 状态迁移
    await tester.tap(find.textContaining('下载选中'));
    await pumpUntil(tester, () => svc.downloaded.isNotEmpty);
    await pumpUntil(
        tester, () => find.textContaining('已下载').evaluate().isNotEmpty);

    expect(File(p.join(dir.path, 'a.mp4')).existsSync(), isTrue,
        reason: '文件应落盘到 targetDir（文件名经 sanitizeFileName）');
    expect(svc.progress, equals([10]), reason: '进度回调应被透传');
  });

  testWidgets('全选/取消全选', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fsl_all_');
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(wrap(FileSourceList(
      entries: const [
        FileSourceEntry(url: 'https://x/1.mp4', name: '1'),
        FileSourceEntry(url: 'https://x/2.mp4', name: '2'),
      ],
      service: DataFileService(),
      targetDir: dir.path,
    )));

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.textContaining('下载选中 (2)'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(find.text('取消全选'));
    await tester.pump();
    expect(find.textContaining('下载选中'), findsNothing);
  });

  testWidgets('空列表 → 显示提示', (tester) async {
    await tester.pumpWidget(wrap(FileSourceList(
      entries: const [],
      service: DataFileService(),
      targetDir: '/tmp/x',
      emptyHint: '暂无可下载文件',
    )));
    expect(find.text('暂无可下载文件'), findsOneWidget);
  });

  testWidgets('混合列表：已缓存与待下载各自渲染', (tester) async {
    await tester.pumpWidget(wrap(FileSourceList(
      entries: const [
        FileSourceEntry(path: '/c/file_cache/x.mp4', name: '本地.mp4', size: 1024),
        FileSourceEntry(url: 'https://x/y.mp4', name: '待下载.mp4'),
      ],
      service: DataFileService(),
      targetDir: '/tmp/x',
    )));
    expect(find.textContaining('已缓存 ·'), findsOneWidget,
        reason: '已缓存项显示副标题（避免与条目名撞词，用 " · " 区分）');
    expect(find.textContaining('待下载 ·'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget,
        reason: '只有待下载项有勾选框');
  });
}
