/// GitHub 源克隆器安卓路径测试（zipball 下载 + 解压，无 git 二进制平台兜底）。
///
/// 验证 [cloneGithubViaZipball]：
/// - 成功下载并剥离 zipball 顶层目录落盘（与 git clone 目录语义一致）。
/// - ref 编码进 URL（分支/tag/commit），空 ref 走默认分支端点。
/// - 404/401 → notFound/authRequired 错误类型（与桌面 git clone 映射对齐）。
/// - 空 zip 与路径穿越条目防御。
/// - [cloneGithub] 幂等：targetDir 非空直接成功，不触发任何网络/子进程。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/services/github_clone.dart';
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

ResponseBody _zip(int status, List<int> body) =>
    ResponseBody.fromBytes(body, status);

/// 构造 GitHub zipball 形态的 zip：所有条目共享 `{repo}-{ref}/` 顶层目录。
List<int> _zipball(String topLevel, Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(
        ArchiveFile('$topLevel/${e.key}', e.value.length, e.value.codeUnits));
  }
  return ZipEncoder().encode(archive)!;
}

GithubSource _src({String? ref}) =>
    GithubSource(owner: 'cxz66666', repo: 'zju-ical', ref: ref);

void main() {
  test('成功下载并剥离 zipball 顶层目录', () async {
    final zip = _zipball('zju-ical-main', {
      'manifest.json': '{"id":"zju-ical"}',
      'module/index.html': '<html/>',
    });
    final dio = _dioWith((options) async => _zip(200, zip));

    final tmp = Directory.systemTemp.createTempSync('ghzip_').path;
    final r = await cloneGithubViaZipball(_src(), tmp, dio: dio);

    expect(r.success, isTrue, reason: r.error);
    expect(r.errorType, isNull);
    // 剥离顶层目录：文件直接落在 targetDir 下。
    expect(File('$tmp/manifest.json').existsSync(), isTrue);
    expect(File('$tmp/module/index.html').existsSync(), isTrue);
    // 不应残留顶层目录。
    expect(Directory('$tmp/zju-ical-main').existsSync(), isFalse);
    Directory(tmp).deleteSync(recursive: true);
  });

  test('ref 非空 → URL 含编码后的 /zipball/<ref>', () async {
    final zip = _zipball('zju-ical-feature%2Ffoo', {'manifest.json': '{}'});
    final dio = _dioWith((options) async {
      expect(options.uri.toString(), contains('/zipball/feature%2Ffoo'));
      return _zip(200, zip);
    });

    final tmp = Directory.systemTemp.createTempSync('ghzip2_').path;
    final r =
        await cloneGithubViaZipball(_src(ref: 'feature/foo'), tmp, dio: dio);
    expect(r.success, isTrue, reason: r.error);
    Directory(tmp).deleteSync(recursive: true);
  });

  test('ref 为空 → URL 以 /zipball 结尾（默认分支）', () async {
    final zip = _zipball('zju-ical-main', {'manifest.json': '{}'});
    final dio = _dioWith((options) async {
      expect(options.uri.toString(), endsWith('/zipball'));
      expect(options.uri.toString(), isNot(contains('/zipball/')));
      return _zip(200, zip);
    });

    final tmp = Directory.systemTemp.createTempSync('ghzip3_').path;
    final r = await cloneGithubViaZipball(_src(), tmp, dio: dio);
    expect(r.success, isTrue, reason: r.error);
    Directory(tmp).deleteSync(recursive: true);
  });

  test('404 → notFound（与桌面 git clone 映射对齐）', () async {
    final dio = _dioWith((options) async => _zip(404, []));
    final r = await cloneGithubViaZipball(
        _src(), Directory.systemTemp.createTempSync('ghzip4_').path,
        dio: dio);
    expect(r.success, isFalse);
    expect(r.errorType, CloneErrorType.notFound);
  });

  test('401 → authRequired（私有仓库）', () async {
    final dio = _dioWith((options) async => _zip(401, []));
    final r = await cloneGithubViaZipball(
        _src(), Directory.systemTemp.createTempSync('ghzip5_').path,
        dio: dio);
    expect(r.success, isFalse);
    expect(r.errorType, CloneErrorType.authRequired);
  });

  test('空 zip → 失败（zipball 内容为空）', () async {
    final dio = _dioWith((options) async => _zip(200, []));
    final r = await cloneGithubViaZipball(
        _src(), Directory.systemTemp.createTempSync('ghzip6_').path,
        dio: dio);
    expect(r.success, isFalse);
    expect(r.error, contains('内容为空'));
  });

  test('路径穿越条目被跳过，正常条目仍落盘', () async {
    final zip = _zipball('zju-ical-main', {
      'manifest.json': 'ok',
      '../evil.txt': 'evil',
    });
    final dio = _dioWith((options) async => _zip(200, zip));

    final tmp = Directory.systemTemp.createTempSync('ghzip7_').path;
    final r = await cloneGithubViaZipball(_src(), tmp, dio: dio);
    expect(r.success, isTrue, reason: r.error);
    expect(File('$tmp/manifest.json').existsSync(), isTrue);
    expect(File('$tmp/evil.txt').existsSync(), isFalse);
    Directory(tmp).deleteSync(recursive: true);
  });

  test('cloneGithub 幂等：targetDir 非空直接成功（不触发下载/子进程）', () async {
    final tmp = Directory.systemTemp.createTempSync('ghzip8_').path;
    File('$tmp/exists.txt').writeAsStringSync('x');
    // 幂等短路保证不会走到 git 子进程 / 网络下载。
    final r =
        await cloneGithub(_src(), tmp, timeout: const Duration(seconds: 5));
    expect(r.success, isTrue, reason: r.error);
    Directory(tmp).deleteSync(recursive: true);
  });
}
