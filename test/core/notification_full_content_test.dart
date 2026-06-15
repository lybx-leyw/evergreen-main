import 'package:flutter_test/flutter_test.dart';

/// 0.4.2 — Agent 通知工具不再截断 500 字符，完整返回正文。
import 'package:evergreen_multi_tools/core/agent/tools/zju_notifications.dart';
import 'package:evergreen_multi_tools/core/agent/tools/zju_data_source.dart';

class _FakeDataSource implements ZjuDataSource {
  @override
  Future<List<ZjuNotification>> getNotifications() async {
    final longContent = 'A' * 600;
    return [ZjuNotification(id: '1', title: '测试', content: longContent)];
  }

  @override dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('Notifications — full content', () {
    test('超 500 字正文完整返回', () async {
      final tool = ZjuNotificationsTool(_FakeDataSource());
      final result = await tool.execute({});
      expect(result, contains('A' * 600));
      expect(result, isNot(contains('...')));
    });
  });
}
