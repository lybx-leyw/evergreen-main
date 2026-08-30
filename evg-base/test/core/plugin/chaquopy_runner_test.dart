/// Android 原生桥（Chaquopy）纯 Dart 测试 —— 规划 §3.2 P1b。
///
/// 测试 ChaquopyRunner（MethodChannel 'evergreen/python' 的 runScript /
/// startLongServer / stopLongServer）和 ChaquopyLongProcess（EventChannel
/// 'evergreen/python_stream' 包装为 Process 接口），验证：
///
/// 1. ChaquopyLongProcess stdout/stderr/exit 事件正确路由
/// 2. kill() → stopLongServer + 幂等防重
/// 3. ChaquopyRunner.runOnce/startLong 参数映射
///
/// 全在 Windows dart test 环境下运行，不依赖 Android 真机。
/// 仅验证 Dart 侧 JS bridge 逻辑，不测原生 Kotlin 实现。
library;

import 'dart:convert';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编程的 MockStreamHandler：测试通过 [emit] 控制事件序列。
///
/// 订阅前的事件（emit / emitError / endStream）缓存到内存 buffer；
/// onListen 时一次性 flush 到 [MockStreamHandlerEventSink]，与原生的
/// `streamBuffer` 行为一致。
class _TestStreamHandler extends MockStreamHandler {
  MockStreamHandlerEventSink? _sink;
  // 订阅前的事件缓存（非广播，用 List 简单积累）
  final List<Map<String, dynamic>> _buffer = [];
  bool _errorBuffered = false;
  bool _closeBuffered = false;

  void emit(Map<String, dynamic> event) {
    if (_sink != null) {
      _sink!.success(event);
    } else {
      _buffer.add(event);
    }
  }

  void emitError() {
    if (_sink != null) {
      _sink!.error(code: 'TEST_ERROR', message: 'test error');
    } else {
      _errorBuffered = true;
    }
  }

  void endStream() {
    if (_sink != null) {
      _sink!.endOfStream();
    } else {
      _closeBuffered = true;
    }
  }

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    _sink = events;
    // Flush 缓存（原生侧 subscribe 后一次性 flush streamBuffer）
    for (final event in _buffer) {
      events.success(event);
    }
    _buffer.clear();
    if (_errorBuffered) {
      events.error(code: 'TEST_ERROR', message: 'test error');
      _errorBuffered = false;
    }
    if (_closeBuffered) {
      events.endOfStream();
      _closeBuffered = false;
    }
  }

  @override
  void onCancel(Object? arguments) {
    _sink = null;
  }
}

/// 为每个测试安装 Flutter test binding + 重置 mock 状态。
///
/// 因为多个 group 共享同一 MethodChannel/EventChannel mock，
/// 在 setUp 中重新注册以保证测试隔离。
class _MockEnv {

  _MockEnv() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // 安装 EventChannel mock（MockStreamHandler API）
    messenger.setMockStreamHandler(
      const EventChannel('evergreen/python_stream'),
      streamHandler,
    );

    // 安装 MethodChannel mock：记录调用并返回预设结果。
    messenger.setMockMethodCallHandler(
      const MethodChannel('evergreen/python'),
      (MethodCall call) {
        _methodCalls.add(call);
        return Future.value(_methodResult);
      },
    );
  }
  final _TestStreamHandler streamHandler = _TestStreamHandler();
  final _methodCalls = <MethodCall>[];
  dynamic _methodResult;

  /// 设置下一个 runScript 的返回值。
  void setRunScriptResult(Map<String, dynamic> result) {
    _methodResult = result;
  }

  MethodCall? get lastMethodCall =>
      _methodCalls.isEmpty ? null : _methodCalls.last;

  int get methodCallCount => _methodCalls.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChaquopyLongProcess（进程内 Python 线程 → Process 接口包装）', () {
    late _MockEnv env;

    setUp(() {
      // 重置跨测试存活的全局流分发器：否则残留订阅会让本测试新装的
      // mock stream handler 收不到 onListen，emit 的事件滞留缓存丢失。
      ChaquopyLongProcess.resetStreamHubForTesting();
      env = _MockEnv();
    });

    test('pid 返回 -1（占位）', () {
      final proc = ChaquopyLongProcess('test.py');
      expect(proc.pid, -1);
    });

    test('stdin write → 触发 writeStdin MethodChannel（stdin 双向流）', () async {
      final proc = ChaquopyLongProcess('test.py');
      // stdin 不再抛异常，而是返回可写 sink。
      proc.stdin.write('status\n');
      // 等待异步 MethodChannel 调用发出。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(env.lastMethodCall?.method, 'writeStdin');
      final args = env.lastMethodCall?.arguments as Map<dynamic, dynamic>?;
      expect(args?['entry'], 'test.py');
      expect(args?['data'], 'status\n');
    });

    test('stdout 流 → EventChannel type=stdout 事件正确路由', () async {
      final proc = ChaquopyLongProcess('test.py');

      // 先订阅，模拟 DataSourceLoader._listenStdout() 行为
      final lines = <String>[];
      final sub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);

      // 模拟原生侧发送 stdout 行
      env.streamHandler.emit({'type': 'stdout', 'line': 'PORT:8080'});
      env.streamHandler.emit({'type': 'stdout', 'line': 'Server started'});

      // 给 Stream 一点时间传播
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lines, contains('PORT:8080'));
      expect(lines, contains('Server started'));

      await sub.cancel();
    });

    test('stderr 流 → EventChannel type=stderr 事件正确路由', () async {
      final proc = ChaquopyLongProcess('test.py');
      final lines = <String>[];
      final sub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);

      env.streamHandler.emit({'type': 'stderr', 'line': 'WARNING: deprecated'});

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(lines, contains('WARNING: deprecated'));

      await sub.cancel();
    });

    test('EventChannel type=exit → exitCode 完成 + 流关闭', () async {
      final proc = ChaquopyLongProcess('test.py');
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final outSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stdoutLines.add);
      final errSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      env.streamHandler.emit({'type': 'stdout', 'line': 'ok'});
      env.streamHandler.emit({'type': 'exit', 'code': 42});

      final code = await proc.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -999,
      );
      expect(code, 42);

      // 流应在 exit 后被关闭，不再接受新事件
      env.streamHandler.emit({'type': 'stdout', 'line': 'too late'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 流已关闭，不会接收新行
      expect(stdoutLines.length, 1);

      await outSub.cancel();
      await errSub.cancel();
    });

    test('EventChannel onError → exitCode=1 + 流关闭', () async {
      final proc = ChaquopyLongProcess('test.py');

      env.streamHandler.emitError();

      final code = await proc.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -999,
      );
      expect(code, 1);
    });

    test('EventChannel onDone → exitCode=0 + 流关闭', () async {
      final proc = ChaquopyLongProcess('test.py');

      env.streamHandler.endStream();

      final code = await proc.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -999,
      );
      expect(code, 0);
    });

    test('kill() 首次返回 true → 调用 stopLongServer → 二次 kill 返回 false',
        () async {
      final proc = ChaquopyLongProcess('test.py');

      final ok = proc.kill();
      expect(ok, isTrue);
      // 验证 MethodChannel('evergreen/python') 收到 stopLongServer 调用
      expect(env.methodCallCount, 1);
      expect(env.lastMethodCall?.method, 'stopLongServer');

      // 再次 kill → 幂等返回 false
      final ok2 = proc.kill();
      expect(ok2, isFalse);
      // 不应再次发出 stopLongServer
      expect(env.methodCallCount, 1);

      // kill 后 exitCode 立即完成
      final code = await proc.exitCode;
      expect(code, 0);
    });

    test('stdout/stderr 流中不包含 type=exit 行', () async {
      final proc = ChaquopyLongProcess('test.py');
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final outSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stdoutLines.add);
      final errSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      env.streamHandler.emit({'type': 'stdout', 'line': 'line1'});
      env.streamHandler.emit({'type': 'stderr', 'line': 'err1'});
      env.streamHandler.emit({'type': 'exit', 'code': 0});

      await proc.exitCode;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(stdoutLines, equals(['line1']));
      expect(stderrLines, equals(['err1']));

      await outSub.cancel();
      await errSub.cancel();
    });

    test('未知 type 事件被静默忽略（不崩溃、不污染 stdio）', () async {
      final proc = ChaquopyLongProcess('test.py');
      final stdoutLines = <String>[];
      final outSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stdoutLines.add);

      env.streamHandler.emit({'type': 'unknown', 'line': 'ignored'});
      env.streamHandler.emit({'type': 'stdout', 'line': 'real line'});

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stdoutLines, equals(['real line']));

      await outSub.cancel();
    });

    test('exit 之前产生的事件全部被 stdout 消费（顺序保证）', () async {
      final proc = ChaquopyLongProcess('test.py');
      final lines = <String>[];
      final sub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add);

      env.streamHandler.emit({'type': 'stdout', 'line': 'A'});
      env.streamHandler.emit({'type': 'stdout', 'line': 'B'});
      env.streamHandler.emit({'type': 'stdout', 'line': 'C'});
      env.streamHandler.emit({'type': 'exit', 'code': 0});

      await proc.exitCode;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A, B, C 都应在 exit 前到达
      expect(lines, equals(['A', 'B', 'C']));

      await sub.cancel();
    });
  });

  group('ChaquopyRunner.runOnce（一次性 Python 执行）', () {
    late _MockEnv env;

    setUp(() {
      // 重置全局流分发器，避免残留订阅干扰本组 mock（见上组注释）。
      ChaquopyLongProcess.resetStreamHubForTesting();
      env = _MockEnv();
    });

    test('runScript 参数完整映射到 MethodChannel', () async {
      env.setRunScriptResult({
        'stdout': 'hello world',
        'stderr': '',
        'exitCode': 0,
      });

      const runner = ChaquopyRunner();
      final result = await runner.runOnce(
        '/data/plugins/data-courses/data/scraper.py',
        ['--type', 'courses', '--project-root', '/data/data/com.example/files'],
        stdinJson: {'cmd': 'fetch'},
        workingDirectory: '/data/plugins/data-courses/data',
        runtime: 'python',
      );

      // 验证返回值
      expect(result.stdout, 'hello world');
      expect(result.stderr, '');
      expect(result.exitCode, 0);

      // 验证 MethodChannel 参数
      final call = env.lastMethodCall;
      expect(call?.method, 'runScript');
      final args = call?.arguments as Map<dynamic, dynamic>?;
      expect(
          args?['entry'], '/data/plugins/data-courses/data/scraper.py');
      expect(args?['args'],
          ['--type', 'courses', '--project-root', '/data/data/com.example/files']);
      expect(args?['stdinJson'], {'cmd': 'fetch'});
      expect(args?['workingDirectory'], '/data/plugins/data-courses/data');
      expect(args?['runtime'], 'python');
    });

    test('null 响应字段 fallback 为空串 / -1', () async {
      env.setRunScriptResult({}); // 完全空响应

      const runner = ChaquopyRunner();
      final result = await runner.runOnce('test.py', []);

      expect(result.stdout, '');
      expect(result.stderr, '');
      expect(result.exitCode, -1);
    });

    test('部分 null 字段 fallback', () async {
      env.setRunScriptResult({
        'stdout': 'output only',
        // stderr 缺失
        // exitCode 缺失
      });

      const runner = ChaquopyRunner();
      final result = await runner.runOnce('test.py', []);

      expect(result.stdout, 'output only');
      expect(result.stderr, '');
      expect(result.exitCode, -1);
    });

    test('exitCode 为 0 正确传递', () async {
      env.setRunScriptResult({
        'stdout': '',
        'stderr': '',
        'exitCode': 0,
      });

      const runner = ChaquopyRunner();
      final result = await runner.runOnce('test.py', []);

      expect(result.exitCode, 0);
    });

    test('exitCode 非零正确传递', () async {
      env.setRunScriptResult({
        'stdout': '',
        'stderr': 'ImportError: No module named foo',
        'exitCode': 1,
      });

      const runner = ChaquopyRunner();
      final result = await runner.runOnce('test.py', []);

      expect(result.exitCode, 1);
      expect(result.stderr, 'ImportError: No module named foo');
    });
  });

  group('ChaquopyRunner.startLong（长驻 HTTP server）', () {
    late _MockEnv env;

    setUp(() {
      // startLong 会构造 ChaquopyLongProcess 注册进 hub，同样需要先重置。
      ChaquopyLongProcess.resetStreamHubForTesting();
      env = _MockEnv();
    });

    test('startLongServer 参数完整映射', () async {
      const runner = ChaquopyRunner();
      final proc = await runner.startLong(
        '/data/plugins/data-courses/data/server.py',
        ['--project-root', '/data/data/com.example/files'],
        workingDirectory: '/data/plugins/data-courses/data',
        preferredPort: 8765,
        runtime: 'python',
      );

      // 应返回 ChaquopyLongProcess
      expect(proc, isA<ChaquopyLongProcess>());

      // 验证 MethodChannel 参数
      final call = env.lastMethodCall;
      expect(call?.method, 'startLongServer');
      final args = call?.arguments as Map<dynamic, dynamic>?;
      expect(
          args?['entry'], '/data/plugins/data-courses/data/server.py');
      expect(args?['args'],
          ['--project-root', '/data/data/com.example/files']);
      expect(args?['workingDirectory'], '/data/plugins/data-courses/data');
      expect(args?['preferredPort'], 8765);
      expect(args?['runtime'], 'python');
    });

    test('startLong 返回的 Process 可被正常 kill', () async {
      const runner = ChaquopyRunner();
      final proc = await runner.startLong('server.py', []);

      final killed = proc.kill();
      expect(killed, isTrue);
      // kill 应发出 stopLongServer
      expect(env.lastMethodCall?.method, 'stopLongServer');
    });

    test('preferredPort=0 时参数原样传递', () async {
      const runner = ChaquopyRunner();
      await runner.startLong('server.py', [], preferredPort: 0);

      final args = env.lastMethodCall?.arguments as Map<dynamic, dynamic>?;
      expect(args?['preferredPort'], 0);
    });
  });
}
