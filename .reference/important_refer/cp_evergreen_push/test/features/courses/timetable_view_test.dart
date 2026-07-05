import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/timetable_session.dart';

List<TimetableSession> _mockSessions() {
  const base = {
    'xkkh': '(2025-2026-2)-CS101-001',
    'sfyjskc': '0',
    'xf': '3.0',
  };
  return [
    TimetableSession.fromZdbkJson({...base, 'kcb': '数据结构<br><br>张老师<br>东1A-201', 'xqj': '1', 'djj': '1', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '数据结构<br><br>张老师<br>东1A-201', 'xqj': '3', 'djj': '1', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '高等数学<br><br>李老师<br>西2-101', 'xqj': '2', 'djj': '3', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '高等数学<br><br>李老师<br>西2-101', 'xqj': '4', 'djj': '3', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '大学物理<br><br>王老师<br>东2-205', 'xqj': '5', 'djj': '1', 'skcd': '3'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '大学物理实验<br><br>刘老师<br>实B-301', 'xqj': '7', 'djj': '5', 'skcd': '3'}),
  ];
}

void main() {
  group('课表数据解析', () {
    test('djj+skcd → 正确展开节次列表', () {
      final s = TimetableSession.fromZdbkJson({
        'kcb': '测试课', 'xqj': '1', 'djj': '2', 'skcd': '3',
      });
      expect(s.periods, [2, 3, 4]);
    });

    test('只有 djj 无 skcd → 单节次', () {
      final s = TimetableSession.fromZdbkJson({
        'kcb': '测试课', 'xqj': '1', 'djj': '5',
      });
      expect(s.periods, [5]);
    });

    test('kcb 解析：教师和地点', () {
      final s = TimetableSession.fromZdbkJson({
        'kcb': '线性代数<br>秋冬{第1-8周|1节/周}<br>汪国军<br>紫金港东2-304zwf2026年01月11日(08:00-10:00)',
        'xqj': '1',
        'djj': '1', 'skcd': '2',
      });
      expect(s.courseName, '线性代数');
      expect(s.teacher, '汪国军');
      expect(s.location, '紫金港东2-304');
    });

    test('空 JSON → 默认值不抛异常', () {
      final s = TimetableSession.fromZdbkJson({});
      expect(s.courseName, '');
      expect(s.dayOfWeek, 1);
      expect(s.periods, isEmpty);
    });

    test('6 条 mock sessions → 数据正确', () {
      final sessions = _mockSessions();
      expect(sessions.length, 6);
      expect(sessions[0].courseName, '数据结构');
      expect(sessions[0].periods, [1, 2]);
      expect(sessions[0].dayOfWeek, 1);
      expect(sessions[2].courseName, '高等数学');
      expect(sessions[2].periods, [3, 4]);
      expect(sessions[2].dayOfWeek, 2);
    });
  });
}
