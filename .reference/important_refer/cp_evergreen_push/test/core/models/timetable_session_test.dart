import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/timetable_session.dart';

/// ZDBK 课表 API 新格式（2026 年）：kcb 为 HTML 含全部信息，djj+skcd 表示节次
const validTimetableJson = {
  'xkkh': '(2024-2025-2)-CS101-001',
  'kcb': '数据结构基础<br>秋冬{第1-16周|3节/周}<br>张三<br>紫金港东1A-301',
  'xqj': '3',
  'djj': '1',
  'skcd': '2',
  'dsz': '1-16',
  'sfyjskc': '0',
  'xf': '4.0',
};

const emptyJson = <String, dynamic>{};

const kcbWithZwfSuffix = {
  'xkkh': '(2025-2026-2)-PHY101-001',
  'kcb': '大学物理<br>春夏{第1-16周|2节/周}<br>李四<br>紫金港西2-205zwf2026年06月20日(14:00-16:00)zwf紫金港东2-301',
  'xqj': '2',
  'djj': '3',
  'skcd': '2',
  'dsz': '1-16',
  'xf': '3.0',
};

void main() {
  group('TimetableSession.fromZdbkJson', () {
    test('合法 JSON → 从 kcb HTML 正确解析字段', () {
      final t = TimetableSession.fromZdbkJson(validTimetableJson);
      expect(t.courseName, '数据结构基础');
      expect(t.teacher, '张三');
      expect(t.location, '紫金港东1A-301');
      expect(t.dayOfWeek, 3);
      expect(t.periods, [1, 2]); // djj=1, skcd=2 → [1, 2]
      expect(t.weekRange, '1-16');
      expect(t.isEnded, false);
      expect(t.credit, 4.0);
    });

    test('含 zwf 后缀 → 地点正确截取', () {
      final t = TimetableSession.fromZdbkJson(kcbWithZwfSuffix);
      expect(t.courseName, '大学物理');
      expect(t.teacher, '李四');
      expect(t.location, '紫金港西2-205');
      expect(t.periods, [3, 4]); // djj=3, skcd=2 → [3, 4]
    });

    test('空 {} → 不抛异常，默认值', () {
      final t = TimetableSession.fromZdbkJson(emptyJson);
      expect(t.courseName, ''); // kcb 空 → courseName 空
      expect(t.dayOfWeek, 1);
      expect(t.periods, isEmpty);
      expect(t.isEnded, false);
      expect(t.credit, 0.0);
    });

    test('kcb 只有课程名 → teacher/location 为空', () {
      final t = TimetableSession.fromZdbkJson({
        'kcb': '操作系统',
        'xqj': '1',
        'djj': '5',
        'skcd': '3',
      });
      expect(t.courseName, '操作系统');
      expect(t.teacher, '');
      expect(t.location, '');
      expect(t.periods, [5, 6, 7]);
    });
  });
}
