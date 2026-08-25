/// DataFileService 测试（T8a）—— 本地临时 HTTP 服务验证：成功 / 404 不重试 /
/// 5xx 重试 / 超时 / headers 透传 / 沙箱拒绝越界路径。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../services/data_file_service.dart';
import '../errors.dart';

/// 启动一个本地 HTTP 服务，返回 (server, baseUrl)。[handler] 抛错被吞掉，
/// 避免「客户端已超时断开后服务端再写」的 Connection closed 噪音。
Future<(HttpServer, String)> startServer(
    Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    handler(req).catchError((_) {});
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

Future<Directory> tempDir(String prefix) async =>
    Directory.systemTemp.createTemp(prefix);

void main() {
  group('downloadFile', () {
    test('成功：下载字节并写入 targetPath，返回 Ok(本地路径)', () async {
      final dir = await tempDir('df_success_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('hello-evergreen'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService();
      final target = p.join(dir.path, 'out.bin');
      final result =
          await svc.downloadFile(url: '$base/file', targetPath: target);

      expect(result.isOk, isTrue);
      final path = result.unwrapOr('');
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), 'hello-evergreen');
    });

    test('404：确定性客户端错误，不重试（服务端仅被命中一次）', () async {
      final dir = await tempDir('df_404_');
      addTearDown(() => dir.deleteSync(recursive: true));
      var hits = 0;
      final (server, base) = await startServer((req) async {
        hits++;
        req.response.statusCode = 404;
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc =
          DataFileService(retryBackoff: const [Duration(milliseconds: 1)]);
      final result = await svc.downloadFile(
        url: '$base/missing',
        targetPath: p.join(dir.path, 'x.bin'),
        maxRetries: 3,
      );

      expect(result.isErr, isTrue);
      final err = result.fold<AppError>((v) => fail('expected err'), (e) => e);
      expect(err, isA<NetworkError>());
      expect((err as NetworkError).statusCode, 404);
      expect(hits, 1);
      expect(File(p.join(dir.path, 'x.bin')).existsSync(), isFalse);
    });

    test('5xx 瞬态错误：重试后成功（服务端命中 2 次）', () async {
      final dir = await tempDir('df_retry_');
      addTearDown(() => dir.deleteSync(recursive: true));
      var hits = 0;
      final (server, base) = await startServer((req) async {
        hits++;
        if (hits == 1) {
          req.response.statusCode = 503;
          await req.response.close();
        } else {
          req.response.statusCode = 200;
          req.response.add(utf8.encode('recovered'));
          await req.response.close();
        }
      });
      addTearDown(() => server.close(force: true));

      final svc =
          DataFileService(retryBackoff: const [Duration(milliseconds: 1)]);
      final result = await svc.downloadFile(
        url: '$base/flaky',
        targetPath: p.join(dir.path, 'ok.bin'),
        maxRetries: 2,
      );

      expect(result.isOk, isTrue);
      expect(File(result.unwrapOr('')).readAsStringSync(), 'recovered');
      expect(hits, 2);
    });

    test('超时：超出 timeout 返回 Err(TimeoutError)', () async {
      final dir = await tempDir('df_timeout_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        req.response.statusCode = 200;
        req.response.add(utf8.encode('late'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService(
        timeout: const Duration(milliseconds: 100),
        retryBackoff: const [Duration(milliseconds: 1)],
      );
      final result = await svc.downloadFile(
        url: '$base/slow',
        targetPath: p.join(dir.path, 't.bin'),
        maxRetries: 1,
      );

      expect(result.isErr, isTrue);
      final err = result.fold<AppError>((v) => fail('expected err'), (e) => e);
      expect(err, isA<TimeoutError>());
    });

    test('headers 透传：自定义凭据头到达服务端', () async {
      final dir = await tempDir('df_headers_');
      addTearDown(() => dir.deleteSync(recursive: true));
      String? seenToken;
      String? seenCookie;
      final (server, base) = await startServer((req) async {
        seenToken = req.headers.value('x-custom-token');
        seenCookie = req.headers.value('cookie');
        req.response.statusCode = 200;
        req.response.add(utf8.encode('ok'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService();
      final result = await svc.downloadFile(
        url: '$base/secure',
        targetPath: p.join(dir.path, 'h.bin'),
        headers: {'x-custom-token': 'secret-token', 'cookie': 'session=abc'},
      );

      expect(result.isOk, isTrue);
      expect(seenToken, 'secret-token');
      expect(seenCookie, 'session=abc');
    });

    test('沙箱：越界 targetPath 拒绝写入（Err + 无文件产生）', () async {
      final root = await tempDir('df_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('should-not-write'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService(sandboxRoot: root.path);
      final escapePath = p.join(root.path, '..', 'escape.bin');
      final result = await svc.downloadFile(
        url: '$base/file',
        targetPath: escapePath,
      );

      expect(result.isErr, isTrue);
      final err = result.fold<AppError>((v) => fail('expected err'), (e) => e);
      expect(err, isA<ValidationError>());
      expect(File(escapePath).existsSync(), isFalse);
    });

    test('沙箱：根内目标正常写入', () async {
      final root = await tempDir('df_ok_');
      addTearDown(() => root.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('inside'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService(sandboxRoot: root.path);
      final result = await svc.downloadFile(
        url: '$base/file',
        targetPath: p.join(root.path, 'sub', 'in.bin'),
      );

      expect(result.isOk, isTrue);
      expect(File(result.unwrapOr('')).readAsStringSync(), 'inside');
    });

    test('非法 URL：快速失败（ValidationError，不发起请求）', () async {
      final dir = await tempDir('df_badurl_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svc = DataFileService();
      final result = await svc.downloadFile(
        url: 'not-a-url',
        targetPath: p.join(dir.path, 'x.bin'),
      );
      expect(result.isErr, isTrue);
      final err = result.fold<AppError>((v) => fail('expected err'), (e) => e);
      expect(err, isA<ValidationError>());
    });
  });

  group('downloadFiles', () {
    test('串行批量：逐项返回结果，文件名自 URL 末段派生', () async {
      final dir = await tempDir('df_batch_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (server, base) = await startServer((req) async {
        final name = req.uri.pathSegments.last;
        req.response.statusCode = 200;
        req.response.add(utf8.encode('content-of-$name'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final svc = DataFileService();
      final results = await svc.downloadFiles(
        urls: ['$base/a.txt', '$base/b.txt'],
        targetDir: dir.path,
      );

      expect(results, hasLength(2));
      expect(results.every((r) => r.isOk), isTrue);
      expect(File(p.join(dir.path, 'a.txt')).readAsStringSync(),
          'content-of-a.txt');
      expect(File(p.join(dir.path, 'b.txt')).readAsStringSync(),
          'content-of-b.txt');
    });
  });
}
