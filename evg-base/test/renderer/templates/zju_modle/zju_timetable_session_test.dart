/// ZjuTimetableSession 模型单测（B3-ui，课表周视图数据模型）。
///
/// 覆盖：
/// - `fromZdbkJson`：ZDBK 原始条目（kcb HTML / djj / skcd / dsz / xkkh）解析，
///   含学期位掩码推断（春=1,夏=2,短①=4,秋=8,冬=16,短②=32,暑=64）与 zwf 截取；
/// - `fromJson`/`toJson`：中枢缓存 JSON 双向桥接（semester/course_year 必须还原）。
library;

import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_timetable_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// ZDBK 课表 API 新格式（2026 年）：kcb 为 HTML 含全部信息，djj+skcd 表示节次。
const validTimetableJson = {
  'xkkh': '(2026-2027-2)-CS101-001',
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
  'xkkh': '(2026-2027-2)-PHY101-001',
  'kcb': '大学物理<br>春夏{第1-16周|2节/周}<br>李四<br>紫金港西2-205zwf2026年06月20日(14:00-16:00)zwf紫金港东2-301',
  'xqj': '2',
  'djj': '3',
  'skcd': '2',
  'dsz': '1-16',
  'xf': '3.0',
};

void main() {
  group('ZjuTimetableSession.fromZdbkJson', () {
    test('合法 JSON → 从 kcb HTML 正确解析字段 + 学期位掩码', () {
      final t = ZjuTimetableSession.fromZdbkJson(validTimetableJson);
      expect(t.courseName, '数据结构基础');
      expect(t.teacher, '张三');
      expect(t.location, '紫金港东1A-301');
      expect(t.dayOfWeek, 3);
      expect(t.periods, [1, 2]); // djj=1, skcd=2 → [1, 2]
      expect(t.weekRange, '1-16');
      expect(t.semester, 24); // 秋冬 → 秋(8) | 冬(16)
      expect(t.courseYear, 2026); // (2026-2027-2)-... → 2026
      expect(t.isEnded, false);
      expect(t.credit, 4.0);
      expect(t.courseId, '(2026-2027-2)-CS101-001');
    });

    test('含 zwf 后缀 → 地点正确截取', () {
      final t = ZjuTimetableSession.fromZdbkJson(kcbWithZwfSuffix);
      expect(t.courseName, '大学物理');
      expect(t.teacher, '李四');
      expect(t.location, '紫金港西2-205');
      expect(t.periods, [3, 4]); // djj=3, skcd=2 → [3, 4]
      expect(t.semester, 3); // 春夏 → 春(1) | 夏(2)
    });

    test('空 {} → 不抛异常，默认值', () {
      final t = ZjuTimetableSession.fromZdbkJson(emptyJson);
      expect(t.courseName, ''); // kcb 空 → courseName 空（参考实现同款）
      expect(t.dayOfWeek, 1);
      expect(t.periods, isEmpty);
      expect(t.isEnded, false);
      expect(t.credit, 0.0);
      expect(t.semester, 0);
      expect(t.courseYear, isNull);
    });

    test('kcb 只有课程名 → teacher/location 为空', () {
      final t = ZjuTimetableSession.fromZdbkJson({
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

    test('sfyjskc=1（已结束课程）→ isEnded true', () {
      final t = ZjuTimetableSession.fromZdbkJson({
        ...validTimetableJson,
        'sfyjskc': '1',
      });
      expect(t.isEnded, true);
    });
  });

  group('ZjuTimetableSession JSON 桥接（数据中枢缓存契约）', () {
    test('fromJson/toJson 双向还原全部字段', () {
      final src = ZjuTimetableSession.fromZdbkJson(validTimetableJson);
      final restored = ZjuTimetableSession.fromJson(src.toJson());
      expect(restored.courseName, src.courseName);
      expect(restored.teacher, src.teacher);
      expect(restored.location, src.location);
      expect(restored.dayOfWeek, 3);
      expect(restored.periods, [1, 2]);
      expect(restored.weekRange, '1-16');
      expect(restored.semester, 24); // 学期位掩码必须还原（UI 过滤依赖）
      expect(restored.courseYear, 2026);
      expect(restored.isEnded, false);
      expect(restored.credit, 4.0);
      expect(restored.courseId, src.courseId);
    });

    test('semester=0 → fromJson 还原为 null（未推断出学期）', () {
      final restored = ZjuTimetableSession.fromJson({
        'course_id': null,
        'course_name': '实验课',
        'teacher': null,
        'location': null,
        'day_of_week': 5,
        'periods': [1],
        'week_range': null,
        'semester': 0,
        'course_year': null,
        'is_ended': false,
        'credit': 1.0,
      });
      expect(restored.semester, isNull);
      expect(restored.courseName, '实验课');
      expect(restored.dayOfWeek, 5);
      expect(restored.periods, [1]);
    });
  });
}
