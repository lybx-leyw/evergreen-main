/// 全局记忆——Allport 特质理论分组的回归测试（纯函数，秒级运行，绝不挂死）。
///
/// 回归点：全局记忆页面此前按 [MemoryType]（用户身份/反馈指导/项目上下文/
/// 外部引用）分组，私自撤销了 core/agent 里奥尔波特特质理论的设计。
/// 修复后分组必须按记忆的 [Memory.priority] 维度：
///   cardinal / central / secondary / requirement / key_fact。
///
/// 本测试直接验证领域层纯函数 [groupMemoriesByAllport]，不挂载任何 Widget，
/// 因此不触发 SharedPreferences / MarkdownRenderer / Riverpod，编译与运行都很快。
///
/// 运行：cd evg-base && flutter test test/global_memory_allport_test.dart
import 'package:evergreen_base/core/agent/memory/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groupMemoriesByAllport 按 Allport priority 分组，而非 MemoryType', () {
    final memories = [
      Memory(name: 'cardinal-1', title: '完美主义者', type: MemoryType.user, priority: 'cardinal'),
      Memory(name: 'central-1', title: '严谨', type: MemoryType.user, priority: 'central'),
      Memory(name: 'central-2', title: '勤奋', type: MemoryType.user, priority: 'central'),
      Memory(name: 'secondary-1', title: '偏好简洁代码', type: MemoryType.user, priority: 'secondary'),
      Memory(name: 'requirement-1', title: '用中文回答', type: MemoryType.user, priority: 'requirement'),
      Memory(name: 'fact-1', title: '主修计算机科学', type: MemoryType.user, priority: 'high'),
      // 故意混入旧的 MemoryType 维度（feedback）——验证它不影响 Allport 分组
      Memory(name: 'feedback-1', title: '旧的反馈指导', type: MemoryType.feedback, priority: 'medium'),
    ];

    final groups = groupMemoriesByAllport(memories);

    // 五个 Allport 分组都存在且数量正确
    expect(groups.containsKey('cardinal'), isTrue);
    expect(groups.containsKey('central'), isTrue);
    expect(groups.containsKey('secondary'), isTrue);
    expect(groups.containsKey('requirement'), isTrue);
    expect(groups.containsKey('key_fact'), isTrue);

    expect(groups['cardinal']!.length, 1);
    expect(groups['central']!.map((m) => m.title).toList(),
        containsAll(['严谨', '勤奋']));
    expect(groups['secondary']!.length, 1);
    expect(groups['requirement']!.length, 1);

    // 非 Allport priority（high/medium 等）一律归入 key_fact
    expect(groups['key_fact']!.map((m) => m.name).toList(),
        containsAll(['fact-1', 'feedback-1']));

    // 关键回归断言：MemoryType=feedback 的记忆仍按 priority 归入 key_fact，
    // 而不是被错误的 MemoryType 分组逻辑单独拎出来。
    expect(groups['key_fact']!.any((m) => m.type == MemoryType.feedback), isTrue);
  });

  test('groupMemoriesByAllport 空列表返回五个空分组', () {
    final groups = groupMemoriesByAllport([]);
    for (final key in ['cardinal', 'central', 'secondary', 'requirement', 'key_fact']) {
      expect(groups[key], isEmpty);
    }
  });
}
