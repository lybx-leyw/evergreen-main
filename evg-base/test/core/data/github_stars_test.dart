/// GitHub star 数据中枢接入测试。
///
/// 验证 [registerGithubStars] 与 [DataOrchestrator] 的契约：
/// - 成功：orchestrator.get 返回 `owner/repo -> stars`，且标记 connected。
/// - 网络失败（fetchStarsBatch 全失败）→ fetcher 抛异常，orchestrator
///   返回 null 并记录 lastError（「失败返回空 + 失败信息」约定）。
/// - 部分失败：只返回成功的那部分。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/services/github_stars.dart';
import 'package:flutter_test/flutter_test.dart';

Dio _dioWith(Future<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _MockAdapter(handler);
  return dio;
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {HttpHeaders.contentTypeHeader: ['application/json']},
    );

void main() {
  group('registerGithubStars（数据中枢接入）', () {
    test('成功 → get 返回 owner/repo -> stars 且标记 connected', () async {
      final dio = _dioWith((options) async {
        final path = options.path; // /repos/cubicYYY/ZJUCrawler
        if (path.endsWith('ZJUCrawler')) {
          return _json(200, {'stargazers_count': 128});
        }
        return _json(200, {'stargazers_count': 42});
      });

      final orch = DataOrchestrator();
      registerGithubStars(orch, repoUrls: [
        'https://github.com/cubicYYY/ZJUCrawler',
        'https://github.com/cxz66666/zju-ical',
      ], dio: dio);

      final stars = await orch.get(githubStarsType());

      expect(stars, isNotNull);
      expect(stars!['cubicYYY/ZJUCrawler'], 128);
      expect(stars['cxz66666/zju-ical'], 42);
      expect(orch.status('github-stars')!.connected, isTrue);
    });

    test('网络失败 → get 返回 null 且记录 lastError（不抛到调用方）', () async {
      // 模拟连接错误：Dio 抛 DioException（connectionError）。
      final dio = _dioWith((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'connection refused',
        );
      });

      final orch = DataOrchestrator();
      registerGithubStars(
        orch,
        repoUrls: ['https://github.com/cubicYYY/ZJUCrawler'],
        dio: dio,
      );

      final stars = await orch.get(githubStarsType());

      expect(stars, isNull); // 失败返回空
      final status = orch.status('github-stars')!;
      expect(status.connected, isFalse);
      expect(status.lastError, isNotNull); // 记录了失败信息
      expect(status.lastError, contains('GithubStarsFetchException'));
    });

    test('部分失败 → 只返回成功的那部分（不整体判失败）', () async {
      final dio = _dioWith((options) async {
        final path = options.path;
        if (path.endsWith('ZJUCrawler')) {
          return _json(200, {'stargazers_count': 100});
        }
        // 另一个仓库 404 → fetchGithubStars 返回 null（该条失败）
        return _json(404, {'message': 'Not Found'});
      });

      final orch = DataOrchestrator();
      registerGithubStars(orch, repoUrls: [
        'https://github.com/cubicYYY/ZJUCrawler',
        'https://github.com/nonexistent/repo',
      ], dio: dio);

      final stars = await orch.get(githubStarsType());

      expect(stars, isNotNull);
      expect(stars!['cubicYYY/ZJUCrawler'], 100);
      // 失败的仓库不出现在映射里（消费方逐仓库回退静态值）。
      expect(stars.containsKey('nonexistent/repo'), isFalse);
    });
  });
}
