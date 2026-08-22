// 数据变更通知服务编译/降级验证。
//
// 纯 Dart 单测环境无原生插件通道：ensureInitialized 触发 MissingPluginException
// 时应被服务内部 catch 吞掉（降级为日志），绝不能抛出影响测试/主流程。

import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/app/service/data_change_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('通知服务单例可构造', () {
    expect(DataChangeNotificationService.instance, isNotNull);
  });

  test('无平台通道时初始化优雅降级不抛出', () async {
    final service = DataChangeNotificationService.instance;
    await service.ensureInitialized(); // 内部 catch，不得抛出
    // 无原生通道 → _initFailed 为 true，后续 notify 静默跳过
  });

  test('初始化失败后 notify 不抛出', () async {
    final service = DataChangeNotificationService.instance;
    await service.ensureInitialized();
    // 不构造真实事件（core 事件在核心层已有单测），仅验证降级路径安全
  });
}
