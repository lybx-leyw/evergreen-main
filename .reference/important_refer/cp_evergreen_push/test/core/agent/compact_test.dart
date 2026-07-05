import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/compact/compact.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';
import 'package:evergreen_multi_tools/core/agent/agent/session.dart';
import 'package:evergreen_multi_tools/core/agent/provider.dart';

/// Mock LLM that returns a fixed summary.
class _MockSummaryLlm extends Provider {
  @override String get name => 'mock-compact';

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.content('对话涉及课程查询和成绩分析。');
    yield ProviderEvent.done();
  }
}

void main() {
  group('Compactor — AI 驱动', () {
    late Compactor compactor;
    late _MockSummaryLlm mockLlm;

    setUp(() {
      mockLlm = _MockSummaryLlm();
      compactor = Compactor(
        llm: mockLlm,
        contextWindow: 128000,
      );
    });

    test('enabled when contextWindow > 0', () {
      expect(compactor.enabled, true);
    });

    test('disabled when contextWindow == 0', () {
      final c = Compactor(llm: _MockSummaryLlm(), contextWindow: 0);
      expect(c.enabled, false);
    });

    test('default thresholds 递增', () {
      expect(compactor.softRatio, 0.5);
      expect(compactor.compactRatio, 0.7);
      expect(compactor.forceRatio, 0.8);
    });

    test('check — 低于阈值不触发', () {
      final s = Session();
      s.add(Message.user('hi'));
      s.add(Message.assistant('hello'));
      final (should, trigger, _) = compactor.check(s);
      expect(should, false);
    });
  });

  group('contextRatioDescription', () {
    test('正常格式化', () {
      final desc = contextRatioDescription(64000, 128000);
      expect(desc, '50% (64000 / 128000 tok)');
    });

    test('窗口为0时禁用', () {
      expect(contextRatioDescription(100, 0), '压缩已禁用');
    });
  });
}
