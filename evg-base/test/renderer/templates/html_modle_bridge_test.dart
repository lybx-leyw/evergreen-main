// 测试：html_modle bridge 的端口发现（CoreApiDiscovery）与健康探测。
//
// 覆盖点：
// 1. findProjectRoot 注入根目录
// 2. discover 端口文件读取 / 缺失降级 / 非法内容过滤
// 3. refresh 强制重读
// 4. probe 两级判定：health 200+ok → reachable；500 → degraded
// 5. probeAll 并行全量
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart';

void main() {
  // 关闭调试日志，保持测试输出干净。
  CoreApiDiscovery.verbose = false;

  late Directory tempDir;
  late CoreApiDiscovery discovery;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('evg_port_test_');
    discovery = CoreApiDiscovery(projectRootOverride: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String root() => tempDir.path;

  Future<File> writePortFile(String name, String content) async {
    final f = File('${root()}/$name');
    await f.writeAsString(content);
    return f;
  }

  group('CoreApiDiscovery.discover', () {
    test('读取全部合法端口文件', () async {
      await writePortFile('.agent_port', '12345\n');
      await writePortFile('.config_port', '23456');
      await writePortFile('.data_port', '34567');
      await writePortFile('.module_port', '45678');
      await writePortFile('.theme_port', '56789');
      await writePortFile('.core_port', '65535'); // 端口上限边界值合法

      final ports = discovery.discover();
      expect(ports, {
        'agent': 12345,
        'config': 23456,
        'data': 34567,
        'module': 45678,
        'theme': 56789,
        'core': 65535,
      });
    });

    test('缺失端口文件 → 该项不进入映射（服务不可用降级）', () async {
      await writePortFile('.agent_port', '12345');
      final ports = discovery.discover();
      expect(ports, {'agent': 12345});
    });

    test('非法内容（非数字/越界）被过滤', () async {
      await writePortFile('.agent_port', 'abc');
      await writePortFile('.config_port', '0');
      await writePortFile('.data_port', '70000');
      await writePortFile('.module_port', '-1');
      expect(discovery.discover(), isEmpty);
    });

    test('portOf 返回单端口 / 未发现为 null', () async {
      await writePortFile('.agent_port', '9999');
      expect(discovery.portOf(CoreService.agent), 9999);
      expect(discovery.portOf(CoreService.core), isNull);
    });

    test('refresh 强制重读端口变化', () async {
      await writePortFile('.agent_port', '10001');
      expect(discovery.portOf(CoreService.agent), 10001);

      await writePortFile('.agent_port', '20002');
      // discover 有缓存，端口文件变化不反映
      expect(discovery.portOf(CoreService.agent), 10001);
      // refresh 后反映新端口
      expect(discovery.refresh()['agent'], 20002);
    });
  });

  group('CoreApiDiscovery.probe', () {
    test('health 200 + ok → reachable', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'status': 'ok', 'tools': 3}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      await writePortFile('.agent_port', '${server.port}');

      final status = await discovery.probe(CoreService.agent);
      expect(status.reachability, ServiceReachability.reachable);
      expect(status.port, server.port);
    });

    test('health 500 → degraded（服务进程在但 HTTP 异常）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 500;
        req.response.write('{"error":"boom"}');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      await writePortFile('.agent_port', '${server.port}');

      final status = await discovery.probe(CoreService.agent);
      expect(status.reachability, ServiceReachability.degraded);
      expect(status.port, server.port);
    });

    test('端口文件缺失 → missing', () async {
      final status = await discovery.probe(CoreService.theme);
      expect(status.reachability, ServiceReachability.missing);
      expect(status.port, isNull);
    });

    test('端口文件内容非法 → invalidPort', () async {
      await writePortFile('.module_port', 'not-a-port');
      final status = await discovery.probe(CoreService.module);
      expect(status.reachability, ServiceReachability.invalidPort);
    });

    test('端口占用（无监听）→ degraded', () async {
      await writePortFile('.core_port', '1'); // 端口 1 通常不可连接
      final status = await discovery.probe(CoreService.core,
          timeout: const Duration(milliseconds: 300));
      expect(status.reachability, ServiceReachability.degraded);
    });

    test('probeAll 并行返回 6 组状态', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'status': 'ok'}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      await writePortFile('.agent_port', '${server.port}');
      // 其余 5 个缺失

      final statuses = await discovery.probeAll();
      expect(statuses, hasLength(6));
      expect(
        statuses.singleWhere((s) => s.service == CoreService.agent).reachability,
        ServiceReachability.reachable,
      );
      for (final s in statuses) {
        if (s.service != CoreService.agent) {
          expect(s.reachability, ServiceReachability.missing);
        }
      }
    });
  });
}
