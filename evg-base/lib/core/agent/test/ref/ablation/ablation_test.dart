import 'package:evergreen_base/core/agent/ref/ablation/ablation.dart' as ablation;
import 'package:test/test.dart';

void main() {
  test('parse none', () {
    final s = ablation.parse('');
    expect(s.empty, isTrue);
    expect(s.arm(), 'full');
  });

  test('parse all and arm', () {
    final s = ablation.parse('all');
    expect(s.off(ablation.Module.evidence), isTrue);
    expect(s.arm(), startsWith('no-'));
    expect(s.toString(), isNot('none'));
  });

  test('parse known modules', () {
    final s = ablation.parse('evidence, planner');
    expect(s.off(ablation.Module.evidence), isTrue);
    expect(s.off(ablation.Module.planner), isTrue);
    expect(s.off(ablation.Module.compaction), isFalse);
  });
}
