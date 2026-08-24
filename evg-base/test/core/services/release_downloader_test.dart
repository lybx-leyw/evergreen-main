/// release 下载器测试（M6 · 补 5 增强）。
///
/// 验证 [downloadRelease] 的 asset 选择与解压：
/// - `包含词!排除词` 语法：`windows_amd64!srv` 精确选客户端、排除服务端。
/// - 归一化匹配：`windows-amd64` 能匹配 `windows_amd64`。
/// - `.tar.gz` 正确解压（gzip → tar），而非当单文件落盘。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/services/release_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻 release_downloader 的平台判定（与实现保持一致，使下述用例在任意桌面
/// 平台都能通过，不写死 Windows）。CI runner 为 Linux 时同样成立。
String _expectedPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'darwin';
  return 'linux';
}

String _expectedArch() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm') || v.contains('aarch')) return 'arm64';
  }
  return 'amd64';
}

/// 当前平台的标准标识（用于 platforms 白名单比对）。
String _expectedCurrentPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

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

ResponseBody _bytes(int status, List<int> body) =>
    ResponseBody.fromBytes(body, status);

/// 构造一个包含 [files]（文件名 -> 内容）的 tar.gz 字节流。
List<int> _tarGz(Map<String, String> files) {
  final tar = TarEncoder();
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value.codeUnits));
  }
  final tarBytes = tar.encode(archive)!;
  final gz = GZipEncoder().encode(tarBytes)!;
  return gz;
}

/// 模拟 latest release 响应，返回指定 asset 列表。
Map<String, dynamic> _release(String tag, List<String> assetNames) => {
      'tag_name': tag,
      'assets': [
        for (final name in assetNames)
          {
            'name': name,
            'browser_download_url': 'https://example.com/$name',
          },
      ],
    };

GithubSource _src() => GithubSource(owner: 'cxz66666', repo: 'zju-ical');

void main() {
  test('windows_amd64!srv 精确选客户端并解压 tar.gz', () async {
    final tarGz = _tarGz({'zjuical/zjuical.exe': 'fake-binary'});
    final dio = _dioWith((options) async {
      if (options.path.endsWith('/releases/latest')) {
        return _json(200, _release('v1.0.0-rc7', [
          'zjuicalsrv_1.0.0-rc7_windows_amd64.tar.gz', // 服务端，应被排除
          'zjuical_1.0.0-rc7_windows_amd64.tar.gz', // 客户端，应被选中
        ]));
      }
      return _bytes(200, tarGz);
    });

    final tmp = Directory.systemTemp.createTempSync('release_').path;
    final r = await downloadRelease(
      _src(),
      tmp,
      assetPattern: 'windows_amd64!srv',
      dio: dio,
    );

    expect(r.success, isTrue, reason: r.error);
    expect(r.assetName, 'zjuical_1.0.0-rc7_windows_amd64.tar.gz');
    // 解压后应出现 zjuical/zjuical.exe，而非残留 .tar.gz 单文件。
    expect(File('$tmp/zjuical/zjuical.exe').existsSync(), isTrue);
    expect(
      Directory(tmp).listSync().whereType<File>().any((f) => f.path.endsWith('.tar.gz')),
      isFalse,
      reason: 'tar.gz 应被解压，不应作为单文件残留',
    );
    Directory(tmp).deleteSync(recursive: true);
  });

  test('归一化：连字符 pattern 也能匹配下划线 asset 名', () async {
    final tarGz = _tarGz({'zjuical.exe': 'bin'});
    final dio = _dioWith((options) async {
      if (options.path.endsWith('/releases/latest')) {
        return _json(200, _release('v1.0.0-rc7', [
          'zjuical_1.0.0-rc7_windows_amd64.tar.gz',
        ]));
      }
      return _bytes(200, tarGz);
    });

    final tmp = Directory.systemTemp.createTempSync('release2_').path;
    final r = await downloadRelease(
      _src(),
      tmp,
      assetPattern: 'windows-amd64', // 连字符，旧配置
      dio: dio,
    );

    expect(r.success, isTrue, reason: r.error);
    expect(r.assetName, 'zjuical_1.0.0-rc7_windows_amd64.tar.gz');
    Directory(tmp).deleteSync(recursive: true);
  });

  test('无匹配 asset → 返回失败且不抛异常', () async {
    final dio = _dioWith((options) async {
      if (options.path.endsWith('/releases/latest')) {
        return _json(200, _release('v1.0.0-rc7', [
          'zjuical_1.0.0-rc7_darwin_amd64.tar.gz', // 只有 mac
        ]));
      }
      return _bytes(200, []);
    });

    final r = await downloadRelease(
      _src(),
      Directory.systemTemp.createTempSync('release3_').path,
      assetPattern: 'windows_amd64',
      dio: dio,
    );

    expect(r.success, isFalse);
    expect(r.error, contains('未找到匹配'));
  });

  test('平台占位符：{platform}/{arch} 运行时替换后匹配正确 asset', () async {
    final tarGz = _tarGz({'zjuical.exe': 'bin'});
    final platform = _expectedPlatform();
    final arch = _expectedArch();
    final dio = _dioWith((options) async {
      if (options.path.endsWith('/releases/latest')) {
        return _json(200, _release('v1.0.0-rc7', [
          'zjuicalsrv_1.0.0-rc7_${platform}_$arch.tar.gz', // 服务端，排除
          'zjuical_1.0.0-rc7_${platform}_$arch.tar.gz', // 客户端，选中
          'zjuical_1.0.0-rc7_darwin_amd64.tar.gz', // 其它平台
        ]));
      }
      return _bytes(200, tarGz);
    });

    final tmp = Directory.systemTemp.createTempSync('release4_').path;
    final r = await downloadRelease(
      _src(),
      tmp,
      assetPattern: 'zjuical {platform}_{arch}!srv',
      dio: dio,
    );

    // {platform}/{arch} 按当前平台展开（空格分隔让 zjuical 与平台片段独立匹配，
    // 中间隔版本号也能命中）。Windows→windows_amd64，Linux→linux_amd64，
    // macOS→darwin_amd64/arm64，平台无关。
    expect(r.success, isTrue, reason: r.error);
    expect(r.assetName, 'zjuical_1.0.0-rc7_${platform}_$arch.tar.gz');
    Directory(tmp).deleteSync(recursive: true);
  });

  test('platforms 白名单：当前平台不受支持 → 直接报错且不发起请求', () async {
    var requestCount = 0;
    final dio = _dioWith((options) async {
      requestCount++;
      return _json(200, _release('v1.0.0-rc7', []));
    });

    // 白名单排除当前平台（平台无关：所有桌面平台里剔除当前运行的那个）。
    // 例：Windows 上白名单为 [macos, linux]；Linux 上为 [windows, macos]。
    final allPlatforms = ['windows', 'macos', 'linux'];
    final current = _expectedCurrentPlatform();
    final whitelist = allPlatforms.where((p) => p != current).toList();
    // 仅当当前平台是已知桌面平台时才验证白名单拦截；否则无法构造「不支持」场景。
    if (!allPlatforms.contains(current)) return;

    final r = await downloadRelease(
      _src(),
      Directory.systemTemp.createTempSync('release5_').path,
      assetPattern: 'zjuical {platform}_{arch}!srv',
      platforms: whitelist,
      dio: dio,
    );

    expect(r.success, isFalse);
    expect(r.error, contains('不支持当前平台'));
    expect(requestCount, 0, reason: '平台不支持时应直接报错，不发起网络请求');
  });
}
