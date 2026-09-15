/// DataFileService 流式落盘与进度回调测试（P0）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §6 P0。
///
/// 锁定契约（旧实现全量 `BytesBuilder` + `writeAsBytes` 会违反第 1 条）：
///  1. **边读边写**：下载**进行中**磁盘上就已有 `.part` 且含有数据
///     （旧实现直到全部下载完才创建目标文件 ⇒ 大文件必 OOM）；
///  2. **原子改名**：成功后目标文件就位，且**无** `.part` 残留；
///  3. **失败清理**：HTTP 5xx / 重试耗尽后**无** `.part` 残留；
///  4. **进度回调**：单调不减；`received` 最终等于总长；`total` 来自 Content-Length。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../services/data_file_service.dart';

Future<(HttpServer, String)> startServer(
    Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    handler(req).catchError((_) {});
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

/// 列出目标文件对应的所有 `.part` 临时文件。
List<File> partFilesOf(Directory dir, String targetBaseName) =>
    dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('$targetBaseName.part.'))
        .toList();

/// 轮询等待 [test] 成立，最长 [timeout]。
Future<bool> waitFor(bool Function() test,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (test()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return test();
}

void main() {
  group('流式落盘（P0 契约 1–3）', () {
    test('下载进行中磁盘已存在 .part 且含数据（证明边读边写）', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_stream_');
      addTearDown(() => dir.deleteSync(recursive: true));

      // 分块发出后挂起，等待测试信号 —— 制造「下载进行中」窗口。
      final firstChunkSent = Completer<void>();
      final release = Completer<void>();
      const chunk1Size = 512 * 1024;
      const chunk2Size = 64 * 1024;
      final total = chunk1Size + chunk2Size;

      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentLength = total;
        req.response.add(List<int>.filled(chunk1Size, 7));
        await req.response.flush();
        if (!firstChunkSent.isCompleted) firstChunkSent.complete();
        await release.future; // 挂起：下载处于「进行中」
        req.response.add(List<int>.filled(chunk2Size, 9));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final target = p.join(dir.path, 'out.bin');
      final fut = DataFileService().downloadFile(
        url: '$base/stream',
        targetPath: target,
        timeout: const Duration(seconds: 30),
      );

      await firstChunkSent.future;
      // 关键断言：此刻下载尚未完成，但磁盘上必须已有 .part 且写入过数据。
      final appeared = await waitFor(() {
        final parts = partFilesOf(dir, 'out.bin');
        return parts.isNotEmpty && parts.first.lengthSync() > 0;
      });
      final partsDuring = partFilesOf(dir, 'out.bin');
      expect(appeared, isTrue,
          reason: '下载进行中就应有 .part（旧实现全量驻留内存，此时磁盘无任何文件）');
      expect(partsDuring.first.lengthSync(), greaterThan(0));
      // 目标文件此时不应存在（原子改名尚未发生）
      expect(File(target).existsSync(), isFalse,
          reason: '未完成前不应出现「看起来完整」的目标文件');

      release.complete();
      final r = await fut;
      expect(r.isOk, isTrue,
          reason: r.fold((_) => '', (e) => '下载失败: $e'));
      expect(File(target).lengthSync(), equals(total));
    });

    test('成功：目标就位且无 .part 残留（契约 2）', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_clean_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('payload'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final target = p.join(dir.path, 'ok.bin');
      final r = await DataFileService()
          .downloadFile(url: '$base/f', targetPath: target);
      expect(r.isOk, isTrue);
      expect(await File(target).readAsString(), equals('payload'));
      expect(partFilesOf(dir, 'ok.bin'), isEmpty, reason: '原子改名后不应残留 .part');
    });

    test('5xx 重试耗尽：无 .part 残留（契约 3）', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_fail_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 500;
        req.response.write('boom');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final target = p.join(dir.path, 'bad.bin');
      final r = await DataFileService().downloadFile(
        url: '$base/f',
        targetPath: target,
        maxRetries: 1,
        timeout: const Duration(seconds: 10),
      );
      expect(r.isOk, isFalse);
      expect(partFilesOf(dir, 'bad.bin'), isEmpty, reason: '失败必须清理自己的 .part');
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('进度回调（P0 契约 4）', () {
    test('已知 Content-Length：单调不减，最终 received == total', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_prog_');
      addTearDown(() => dir.deleteSync(recursive: true));
      const total = 300 * 1024;
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentLength = total;
        for (var i = 0; i < 3; i++) {
          req.response.add(List<int>.filled(total ~/ 3, i));
          await req.response.flush();
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final events = <(int, int?)>[];
      final r = await DataFileService().downloadFile(
        url: '$base/p',
        targetPath: p.join(dir.path, 'p.bin'),
        onProgress: (received, tot) => events.add((received, tot)),
      );
      expect(r.isOk, isTrue);
      expect(events, isNotEmpty, reason: '至少回调一次，UI 才能进入下载中');
      // 单调不减
      for (var i = 1; i < events.length; i++) {
        expect(events[i].$1, greaterThanOrEqualTo(events[i - 1].$1));
      }
      expect(events.first.$2, equals(total), reason: 'total 来自 Content-Length');
      expect(events.last.$1, equals(total), reason: '完成时必须回调到满');
      expect(events.last.$2, equals(total));
    });

    test('无 Content-Length：total 为 null 且仍回调（不抛）', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_nolen_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        // 不设 contentLength → 分块传输，Content-Length 未知
        req.response.add(List<int>.filled(64 * 1024, 1));
        await req.response.flush();
        req.response.add(List<int>.filled(64 * 1024, 2));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final totals = <int?>[];
      final r = await DataFileService().downloadFile(
        url: '$base/n',
        targetPath: p.join(dir.path, 'n.bin'),
        onProgress: (received, tot) => totals.add(tot),
      );
      expect(r.isOk, isTrue);
      expect(totals, isNotEmpty);
      expect(totals.every((t) => t == null), isTrue,
          reason: '响应无 Content-Length 时 total 应为 null');
    });

    test('未传 onProgress：行为不变（零行为变化）', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_nocb_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('x' * 100));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final target = p.join(dir.path, 'z.bin');
      final r =
          await DataFileService().downloadFile(url: '$base/z', targetPath: target);
      expect(r.isOk, isTrue);
      expect(File(target).lengthSync(), equals(100));
    });

    test('downloadFiles 透传 onProgress', () async {
      final dir = await Directory.systemTemp.createTemp('dfs_batchcb_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('batch-body'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final seen = <int>[];
      final rs = await DataFileService().downloadFiles(
        urls: ['$base/a.txt', '$base/b.txt'],
        targetDir: dir.path,
        onProgress: (received, _) => seen.add(received),
      );
      expect(rs.length, equals(2));
      expect(rs.every((r) => r.isOk), isTrue);
      expect(seen, isNotEmpty, reason: '批量应透传进度回调');
    });
  });
}
