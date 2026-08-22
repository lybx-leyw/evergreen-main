/// GitHub Issue 发布器测试。
///
/// 用 mock HttpClientAdapter 验证：
/// - 成功路径返回 html_url
/// - 401（无权限 token）→ failure
/// - 连接错误 → failure（不抛）
/// - 请求体含正确 title/body，且截图 base64 内嵌进 body
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/feedback/feedback_writer.dart'
    show buildFeedbackBody, buildIssueTitle;
import 'package:evergreen_base/core/feedback/github_issue_publisher.dart'
    show publishGithubIssue, IssueSuccess, IssueFailure, IssueFailureKind, kFeedbackRepo;
import 'package:flutter_test/flutter_test.dart';

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio();
  dio.httpClientAdapter =
      _MockAdapter((options) => Future<ResponseBody>.sync(() => handler(options)));
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

ResponseBody _json(int status, Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {HttpHeaders.contentTypeHeader: ['application/json']},
    );

void main() {
  group('publishGithubIssue', () {
    test('成功 → 返回 html_url', () async {
      late RequestOptions captured;
      final dio = _dioWith((options) {
        captured = options;
        return _json(201, {
          'html_url': 'https://github.com/$kFeedbackRepo/issues/42',
        });
      });

      final result = await publishGithubIssue(
        token: 'ghp_test123',
        title: '[Bug] 崩溃',
        body: 'desc',
        dio: dio,
      );

      expect(result, isA<IssueSuccess>());
      final url = (result as IssueSuccess).htmlUrl;
      expect(url, contains('/issues/42'));

      // endpoint + 请求体
      expect(captured.path, contains('/repos/$kFeedbackRepo/issues'));
      final sent = jsonDecode(captured.data as String) as Map;
      expect(sent['title'], '[Bug] 崩溃');
      expect(sent['body'], 'desc');
    });

    test('401 无权限 → failure(auth) + 透出原文', () async {
      final dio = _dioWith((_) => _json(401, {
            'message': 'Bad credentials',
          }));
      final result = await publishGithubIssue(
        token: 'bad', title: 't', body: 'b', dio: dio,
      );
      expect(result, isA<IssueFailure>());
      final f = result as IssueFailure;
      expect(f.kind, IssueFailureKind.auth);
      expect(f.statusCode, 401);
      expect(f.rawMessage, 'Bad credentials');
      expect(f.reason, contains('Bad credentials'));
    });

    test('连接错误 → failure(network) 不抛', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        );
      });
      final result = await publishGithubIssue(
        token: 't', title: 't', body: 'b', dio: dio,
      );
      expect(result, isA<IssueFailure>());
      expect((result as IssueFailure).kind, IssueFailureKind.network);
    });

    test('超时 → failure(timeout) 不抛', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.sendTimeout,
        );
      });
      final result = await publishGithubIssue(
        token: 't', title: 't', body: 'b', dio: dio,
      );
      expect(result, isA<IssueFailure>());
      expect((result as IssueFailure).kind, IssueFailureKind.timeout);
    });

    test('空 token → 直接 failure(noToken)', () async {
      final result = await publishGithubIssue(
        token: '', title: 't', body: 'b',
      );
      expect(result, isA<IssueFailure>());
      final f = result as IssueFailure;
      expect(f.kind, IssueFailureKind.noToken);
      expect(f.reason, contains('未填写'));
    });

    test('超长 body 自动剥离截图段，不触发 422', () async {
      // 构造一个超长 body（含截图段）
      final hugeB64 = 'A' * 200000;
      final longBody = '描述\n\n### 📸 截图\n\n![screenshot](data:image/png;base64,$hugeB64)\n';
      late RequestOptions captured;
      final dio = _dioWith((options) {
        captured = options;
        return _json(201, {
          'html_url': 'https://github.com/$kFeedbackRepo/issues/99',
        });
      });
      final result = await publishGithubIssue(
        token: 'ghp_x', title: 't', body: longBody, dio: dio,
      );
      expect(result, isA<IssueSuccess>());
      final sent = jsonDecode(captured.data as String) as Map;
      final sentBody = sent['body'] as String;
      // 截图段被剥离、长度受控
      expect(sentBody.length, lessThan(65000));
      expect(sentBody, isNot(contains('data:image/png;base64,$hugeB64')));
      expect(sentBody, contains('截图过大已省略'));
    });
  });

  group('buildFeedbackBody / buildIssueTitle', () {
    test('正文含元信息表与描述', () {
      final body = buildFeedbackBody(
        timestampUs: 1700000000000000,
        route: '/courses',
        tag: '🐛 Bug',
        description: '点击按钮崩溃',
      );
      expect(body, contains('| **触发路由** | `/courses` |'));
      expect(body, contains('点击按钮崩溃'));
      expect(body, contains('Bug'));
    });

    test('截图路径内嵌 base64 data-uri', () {
      // 构造一个临时 png
      final tmp = File('${Directory.systemTemp.path}/fb_test.png');
      tmp.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final body = buildFeedbackBody(
        timestampUs: 1,
        route: '/',
        tag: '💡 建议',
        description: '加个功能',
        screenshotPath: tmp.path,
      );
      expect(body, contains('data:image/png;base64,'));
      tmp.deleteSync();
    });

    test('标题前缀映射', () {
      expect(buildIssueTitle(tag: '🐛 Bug', description: 'app 崩溃了'), '[Bug] app 崩溃了');
      expect(buildIssueTitle(tag: '💡 建议', description: 'Line1\nLine2'), '[建议] Line1');
    });
  });
}
