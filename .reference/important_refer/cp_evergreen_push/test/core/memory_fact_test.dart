import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/fact.dart';

void main() {
  group('MemoryFact', () {
    test('toJson / fromJson 往返', () {
      final f = MemoryFact(
        fact: '用户是大三学生', timeAnchor: '2026年6月',
        confidence: 0.95, recordedAt: DateTime(2026, 6, 12),
        source: '用户说：我是大三CS',
      );
      final j = f.toJson();
      final r = MemoryFact.fromJson(j);
      expect(r.fact, '用户是大三学生');
      expect(r.timeAnchor, '2026年6月');
      expect(r.confidence, 0.95);
      expect(r.isStyleFact, false);
      expect(r.source, '用户说：我是大三CS');
    });

    test('toPrompt 格式带时间锚定', () {
      final f = MemoryFact(
        fact: '用户就读于浙江大学', timeAnchor: '2026年6月',
        confidence: 0.9, recordedAt: DateTime(2026, 6, 12),
      );
      expect(f.toPrompt(), '[2026年6月] 用户就读于浙江大学');
    });

    test('fromJson 容错：缺少字段用默认值', () {
      final r = MemoryFact.fromJson({});
      expect(r.fact, '');
      expect(r.timeAnchor, '');
      expect(r.confidence, 0.5);
      expect(r.isStyleFact, false);
    });

    test('fromJson 容错：类型错误不崩溃', () {
      final r = MemoryFact.fromJson({
        'fact': 123,
        'confidence': 'not_a_number',
        'is_style': 'not_bool',
      });
      // 不抛异常即通过
      expect(r.fact, isNotNull);
    });

    test('isStyleFact 标记', () {
      final style = MemoryFact(
        fact: '用户偏好简洁回答', timeAnchor: '2026年6月',
        confidence: 0.8, isStyleFact: true, recordedAt: DateTime(2026, 6, 12),
      );
      expect(style.isStyleFact, true);
      expect(style.toPrompt(), contains('用户偏好简洁回答'));
    });
  });

  group('MemoryFact — 冲突检测', () {
    test('年级变化 → 冲突', () {
      final old_ = MemoryFact(
        fact: '用户是大二学生', timeAnchor: '2025年6月',
        confidence: 0.9, recordedAt: DateTime(2025),
      );
      final new_ = MemoryFact(
        fact: '用户是大三学生', timeAnchor: '2026年6月',
        confidence: 0.95, recordedAt: DateTime(2026),
      );
      expect(old_.contradicts(new_), true);
    });

    test('大二→大三 conflict', () {
      final a = MemoryFact(fact: '用户是大二学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是大三学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('大三→大四 conflict', () {
      final a = MemoryFact(fact: '用户是大三学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是大四学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('本科生→研究生 conflict', () {
      final a = MemoryFact(fact: '用户是本科生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是研究生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('硕士→博士 conflict', () {
      final a = MemoryFact(fact: '用户是硕士', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是博士', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('专业变化 → 冲突', () {
      final a = MemoryFact(fact: '用户主修计算机科学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户主修数学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), true);
    });

    test('相同事实 → 不冲突', () {
      final a = MemoryFact(fact: '用户是大三学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户是大三学生', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), false);
    });

    test('无关事实 → 不冲突', () {
      final a = MemoryFact(fact: '用户就读于浙江大学', timeAnchor: '', confidence: 1, recordedAt: DateTime(2025));
      final b = MemoryFact(fact: '用户偏好简洁回答', timeAnchor: '', confidence: 1, recordedAt: DateTime(2026));
      expect(a.contradicts(b), false);
    });
  });

  group('TraitLevel', () {
    test('枚举值完整', () {
      expect(TraitLevel.values.length, 4);
      expect(TraitLevel.cardinal.name, 'cardinal');
      expect(TraitLevel.central.name, 'central');
      expect(TraitLevel.secondary.name, 'secondary');
      expect(TraitLevel.keyFact.name, 'keyFact');
    });

    test('values 按声明顺序', () {
      expect(TraitLevel.values[0], TraitLevel.cardinal);
      expect(TraitLevel.values[1], TraitLevel.central);
      expect(TraitLevel.values[2], TraitLevel.secondary);
      expect(TraitLevel.values[3], TraitLevel.keyFact);
    });
  });
}
