/// SidecarStatusClient 解析层测试（M5 起步 · 纯逻辑）。
import 'package:test/test.dart';

import '../runtime.dart';
import '../sidecar_status_client.dart';
import '../sidecar/sidecar_controller.dart';

void main() {
  group('parseSidecarsResponse', () {
    test('解析含 sidecar 的响应', () {
      const body = '''
      {
        "sidecars": [
          {
            "id": "sc1",
            "name": "Sidecar One",
            "sidecar": {
              "kind": "node",
              "entry": "s.js",
              "port": 9100,
              "healthy": true,
              "capabilities": {"fs.scope": "plugin-dir"}
            }
          }
        ],
        "count": 1
      }
      ''';
      final list = parseSidecarsResponse(body);
      expect(list, hasLength(1));
      final s = list.first;
      expect(s.id, 'sc1');
      expect(s.name, 'Sidecar One');
      expect(s.kind, RuntimeKind.node);
      expect(s.entry, 's.js');
      expect(s.port, 9100);
      expect(s.healthy, isTrue);
      expect(s.capabilities['fs.scope'], 'plugin-dir');
    });

    test('空 sidecars → 空列表', () {
      const body = '{"sidecars": [], "count": 0}';
      expect(parseSidecarsResponse(body), isEmpty);
    });

    test('缺 sidecar 字段的条目 → 默认 node/非健康', () {
      const body = '{"sidecars": [{"id": "x", "name": "X"}]}';
      final s = parseSidecarsResponse(body).first;
      expect(s.kind, RuntimeKind.node);
      expect(s.healthy, isFalse);
      expect(s.port, isNull);
    });
  });
}
