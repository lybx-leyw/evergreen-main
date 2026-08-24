/// sidecar 纯逻辑测试（M1-1~M1-9）。
///
/// 覆盖端口分配、优雅停机阈值、工厂映射、健康检查退避、命令拼装、能力 env。
/// 不含真实子进程（[SidecarRuntime] 用替身注入）。
import 'package:test/test.dart';

import '../lattice.dart';
import '../runtime.dart';
import '../module_descriptor.dart';
import '../resolved_plugin.dart';
import '../sidecar/health.dart';
import '../sidecar/command.dart';
import '../sidecar/sidecar_controller.dart';
import '../sidecar/sidecar_factory.dart';
import '../sidecar/node_sidecar.dart';
import '../sidecar/python_sidecar.dart';
import '../sidecar/deno_sidecar.dart';

/// [SidecarRuntime] 测试替身：不启动真实进程，记录最后一次命令。
class _FakeRuntime implements SidecarRuntime {
  List<String>? lastArgv;
  String? lastCwd;
  Map<String, String>? lastEnv;

  /// 注入给假进程的 stdout 内容（按行）。
  List<String> stdoutLines = const [];

  @override
  Future<SidecarProcess> startProcess(
    List<String> command,
    String workingDirectory, {
    Map<String, String> environment = const {},
  }) async {
    lastArgv = command;
    lastCwd = workingDirectory;
    lastEnv = environment;
    return _FakeProcess(stdoutLines);
  }
}

class _FakeProcess implements SidecarProcess {
  @override
  int pid = 9999;
  @override
  Stream<List<int>> stdout;
  @override
  Stream<List<int>> stderr = const Stream.empty();
  @override
  Future<int> kill([String signal = 'SIGTERM']) async => 0;
  @override
  Future<int> exitCode = Future.value(0);

  _FakeProcess(List<String> stdoutLines)
      : stdout = stdoutLines.isEmpty
            ? const Stream.empty()
            : Stream.fromIterable(
                stdoutLines.map((l) => l.codeUnits),
              );
}

RuntimeDescriptor _rt(RuntimeKind kind, {int port = 0}) => RuntimeDescriptor(
      kind: kind,
      entry: 's.js',
      port: port,
    );

void main() {
  group('resolveSidecarPort', () {
    test('显式端口且未占用 → 原样返回', () {
      expect(resolveSidecarPort(8080, {}), 8080);
    });
    test('显式端口被占用 → 抛', () {
      expect(() => resolveSidecarPort(8080, {8080}), throwsStateError);
    });
    test('port=0 → 自动分配首个未占用（≥16384）', () {
      final p = resolveSidecarPort(0, {16384, 16385});
      expect(p, 16386);
    });
    test('端口池耗尽 → 抛', () {
      final occupied = {for (var i = 16384; i < 65535; i++) i};
      expect(() => resolveSidecarPort(0, occupied), throwsStateError);
    });
  });

  group('gracefulKillTimeoutMs', () {
    test('低于下限 1000 → 兜底 1000', () {
      expect(gracefulKillTimeoutMs(0), 1000);
      expect(gracefulKillTimeoutMs(500), 1000);
    });
    test('正常配置 → 原样', () {
      expect(gracefulKillTimeoutMs(8000), 8000);
    });
  });

  group('sidecarFactoryFor', () {
    test('node → NodeSidecarController', () {
      final f = sidecarFactoryFor(RuntimeKind.node);
      expect(f(_rt(RuntimeKind.node), _FakeRuntime()),
          isA<NodeSidecarController>());
    });
    test('python → PythonSidecarController', () {
      final f = sidecarFactoryFor(RuntimeKind.python);
      expect(f(_rt(RuntimeKind.python), _FakeRuntime()),
          isA<PythonSidecarController>());
    });
    test('deno → DenoSidecarController', () {
      final f = sidecarFactoryFor(RuntimeKind.deno);
      expect(f(_rt(RuntimeKind.deno), _FakeRuntime()),
          isA<DenoSidecarController>());
    });
  });

  group('SidecarHealthPolicy', () {
    test('退避序列：base * factor^i 封顶', () {
      const p = SidecarHealthPolicy(
        maxRetries: 3,
        baseDelayMs: 1000,
        backoffFactor: 2,
        maxDelayMs: 8000,
      );
      expect(p.retryDelays, [1000, 2000, 4000]);
    });
    test('退避封顶 maxDelayMs', () {
      const p = SidecarHealthPolicy(
        maxRetries: 5,
        baseDelayMs: 1000,
        backoffFactor: 2,
        maxDelayMs: 3000,
      );
      // 1000, 2000, 4000→3000, 8000→3000, 16000→3000
      expect(p.retryDelays, [1000, 2000, 3000, 3000, 3000]);
    });
    test('attempt 越界 → -1', () {
      const p = SidecarHealthPolicy();
      expect(p.delayForRetry(3), -1); // == maxRetries
    });
  });

  group('judgeHealth', () {
    test('200 → healthy', () {
      expect(
        judgeHealth(attempt: 1, statusCode: 200, maxRetries: 3),
        HealthVerdict.healthy,
      );
    });
    test('非 200 且可重试 → unhealthy', () {
      expect(
        judgeHealth(attempt: 1, statusCode: 503, maxRetries: 3),
        HealthVerdict.unhealthy,
      );
    });
    test('连接失败耗尽重试 → dead', () {
      // 第 4 次（maxRetries+1）仍不健康 → dead
      expect(
        judgeHealth(attempt: 4, statusCode: null, maxRetries: 3),
        HealthVerdict.dead,
      );
    });
  });

  group('buildCapabilityEnv (M1-9)', () {
    test('deny-all → DENY_ALL=1 且白名单空', () {
      final env = buildCapabilityEnv(const RuntimeCapabilities(), 8080);
      expect(env['EVERGREEN_DENY_ALL'], '1');
      expect(env['EVERGREEN_NET_ALLOW'], '');
      expect(env['EVERGREEN_SPAWN_ALLOW'], '');
      expect(env['EVERGREEN_SIDECAR_PORT'], '8080');
    });
    test('带能力 → 注入白名单', () {
      const caps = RuntimeCapabilities(
        fsScope: FileScope.pluginDir,
        netAllow: ['api.zju.edu.cn'],
        spawnAllow: ['node'],
      );
      final env = buildCapabilityEnv(caps, 9000);
      expect(env['EVERGREEN_FS_SCOPE'], 'pluginDir');
      expect(env['EVERGREEN_NET_ALLOW'], 'api.zju.edu.cn');
      expect(env['EVERGREEN_SPAWN_ALLOW'], 'node');
      expect(env['EVERGREEN_DENY_ALL'], '0');
    });
  });

  group('命令拼装', () {
    test('node: node <entry> --port <p>', () {
      final c = buildNodeCommand(_rt(RuntimeKind.node, port: 9000), '/wd', 9000);
      expect(c.argv, ['node', 's.js', '--port', '9000']);
      expect(c.workingDirectory, '/wd');
    });
    test('python: <py> <entry> --port <p>', () {
      final c = buildPythonCommand(
        _rt(RuntimeKind.python, port: 9001),
        '/wd',
        9001,
        pythonExe: '/usr/bin/python3',
      );
      expect(c.argv, ['/usr/bin/python3', 's.js', '--port', '9001']);
    });
    test('python 缺解释器 → fail-closed', () {
      expect(
        () => buildPythonCommand(_rt(RuntimeKind.python), '/wd', 1),
        throwsStateError,
      );
    });
    test('deno: 按 capabilities 收窄 --allow-*', () {
      const caps = RuntimeCapabilities(
        fsScope: FileScope.pluginDir,
        netAllow: ['api.zju.edu.cn'],
        spawnAllow: ['node'],
      );
      final d = RuntimeDescriptor(
        kind: RuntimeKind.deno,
        entry: 's.ts',
        capabilities: caps,
      );
      final c = buildDenoCommand(d, '/wd', 9002, denoExe: 'deno');
      expect(
        c.argv,
        [
          'deno',
          'run',
          '--allow-net=api.zju.edu.cn',
          '--allow-read',
          '--allow-run=node',
          's.ts',
          '--port',
          '9002',
        ],
      );
    });
    test('deno deny-all → 无任何 --allow', () {
      final d = _rt(RuntimeKind.deno, port: 9003);
      final c = buildDenoCommand(d, '/wd', 9003, denoExe: 'deno');
      expect(c.argv, ['deno', 'run', 's.js', '--port', '9003']);
    });
  });

  group('控制器 start（fake runtime）', () {
    test('NodeSidecarController.start 读 PORT 行 + 探测 → healthy', () async {
      final rt = _FakeRuntime()..stdoutLines = ['booting...', 'PORT:9100'];
      final ctrl = NodeSidecarController(
        _rt(RuntimeKind.node, port: 9100),
        rt,
        healthProbe: (_) async => true,
      );
      await ctrl.start();
      expect(ctrl.port, 9100);
      expect(ctrl.isHealthy, isTrue);
      expect(rt.lastArgv, ['node', 's.js', '--port', '9100']);
      expect(rt.lastEnv!['EVERGREEN_SIDECAR_PORT'], '9100');
      await ctrl.stop();
      expect(ctrl.isHealthy, isFalse);
      expect(ctrl.port, isNull);
    });

    test('stdout 无 PORT 行 → 超时判失败 + kill', () async {
      final rt = _FakeRuntime()..stdoutLines = ['no port here'];
      final ctrl = NodeSidecarController(
        _rt(RuntimeKind.node, port: 9102),
        rt,
        healthProbe: (_) async => true,
      );
      await ctrl.start();
      expect(ctrl.isHealthy, isFalse);
      expect(ctrl.port, isNull);
    });

    test('PORT 解析出但探测失败 → 判失败', () async {
      final rt = _FakeRuntime()..stdoutLines = ['PORT:9103'];
      final ctrl = NodeSidecarController(
        _rt(RuntimeKind.node, port: 9103),
        rt,
        healthProbe: (_) async => false,
      );
      await ctrl.start();
      expect(ctrl.port, 9103);
      expect(ctrl.isHealthy, isFalse);
    });

    test('DenoSidecarController 缺 deno → start 抛', () async {
      final ctrl =
          DenoSidecarController(_rt(RuntimeKind.deno, port: 9101), _FakeRuntime());
      expect(() => ctrl.start(), throwsStateError);
    });

    test('toMeta 序列化 kind/entry/port/healthy', () {
      final rt = _FakeRuntime()..stdoutLines = ['PORT:9104'];
      final ctrl = NodeSidecarController(
        _rt(RuntimeKind.node, port: 9104),
        rt,
        healthProbe: (_) async => true,
      );
      // 不真正 start，手动填字段验证 sidecarMetaOf
      ctrl.port = 9104;
      ctrl.isHealthy = true;
      final meta = sidecarMetaOf(ctrl);
      expect(meta.kind, RuntimeKind.node);
      expect(meta.entry, 's.js');
      expect(meta.port, 9104);
      expect(meta.healthy, isTrue);
      expect(meta.toJson()['kind'], 'node');
    });
  });

  group('lattice→kind 集成（M0+M1 衔接）', () {
    test('sidecar 格 + node runtime → 工厂产出 Node 控制器', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 's',
        'name': 'S',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      });
      final resolved = ResolvedPlugin.fromDescriptor(d);
      expect(resolved.isSidecar, isTrue);
      final f = sidecarFactoryFor(resolved.runtime!.kind);
      expect(f(resolved.runtime!, _FakeRuntime()), isA<NodeSidecarController>());
    });

    test('ModuleLoader 路由判定：isSidecar && runtime!=null → 走控制器',
        () {
      // 等价于 ModuleLoader.start() 的分支条件（M1-7）。
      // 因 module_loader.dart 依赖 package:evergreen_base（子包不可解析），
      // 此处直接验证分支谓词，避免引入子包外依赖。
      final sidecarD = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 's7',
        'name': 'S7',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      });
      final r1 = ResolvedPlugin.fromDescriptor(sidecarD);
      expect(r1.isSidecar && r1.runtime != null, isTrue);

      final staticD = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 's8',
        'name': 'S8',
        'lattice': 'static-web',
      });
      final r2 = ResolvedPlugin.fromDescriptor(staticD);
      expect(r2.isSidecar && r2.runtime != null, isFalse);
    });
  });
}
