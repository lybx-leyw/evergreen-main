// Evergreen 启动入口冒烟——不实例化 App（启动依赖 HttpServer/插件目录，测试环境无法完整初始化），
// 改为验证 AppBootstrap 步骤定义契约：步骤数、id 唯一性、致命步骤标记。
import 'package:evergreen_base/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppBootstrap 步骤契约完整', () {
    final b = AppBootstrap(
      projectRoot: '.',
      pluginsDir: '.',
      ports: <String, int>{},
    );
    final steps = b.stepsForTest;
    expect(steps.length, greaterThanOrEqualTo(20));
    final ids = steps.map((s) => s.id).toSet();
    expect(ids.length, steps.length, reason: '步骤 id 必须唯一');
    expect(
      steps.where((s) => s.fatal).map((s) => s.id),
      ['greenix-paths'],
      reason: '仅 greenix-paths 为致命步骤',
    );
    // 关键时序约束：window-show 必须最后
    expect(steps.last.id, 'window-show');
    expect(steps.first.id, 'window-init');
  });
}
