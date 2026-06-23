import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/capture/context_capturer.dart';

void main() {
  group('ContextCapturer', () {
    test('从路由推断 Feature', () {
      final capturer = ContextCapturer();

      final agentCtx = capturer.capture(const CapturerInput(
        currentRoute: '/agent',
        recentActions: ['输入问题'],
        triggerSource: '对话中触发',
      ));
      expect(agentCtx.activeFeature, 'agent');

      final coursesCtx = capturer.capture(const CapturerInput(
        currentRoute: '/courses',
      ));
      expect(coursesCtx.activeFeature, 'courses');

      final scoresCtx = capturer.capture(const CapturerInput(
        currentRoute: '/scores',
      ));
      expect(scoresCtx.activeFeature, 'scores');
    });

    test('全空输入 → empty', () {
      final capturer = ContextCapturer();
      final ctx = capturer.capture(const CapturerInput());

      expect(ctx.isEmpty, isTrue);
      expect(ctx.activeFeature, isNull);
      expect(ctx.activeTask, isNull);
    });

    test('recentActions 截断到 5 条', () {
      final capturer = ContextCapturer();
      final ctx = capturer.capture(CapturerInput(
        currentRoute: '/agent',
        recentActions: List.generate(10, (i) => '操作 $i'),
      ));

      expect(ctx.recentActions.length, 5);
      expect(ctx.recentActions.first, '操作 0');
      expect(ctx.recentActions.last, '操作 4');
    });

    test('带待办和路由', () {
      final capturer = ContextCapturer();
      final ctx = capturer.capture(CapturerInput(
        currentRoute: '/todo',
        activeTodo: '完成数学作业',
        recentActions: ['打开待办', '标记完成'],
        triggerSource: '完成任务触发',
      ));

      expect(ctx.activeFeature, 'todo');
      expect(ctx.activeTask, '完成数学作业');
      expect(ctx.triggerSource, '完成任务触发');
    });
  });
}
