/// exams feature 单测（B3 第三接入，B4-fix 适配 HttpClient 版 service）：
/// - ZjuExam 模型 fromZdbk（中文时间格式）/ fromCourses / fromJson 往返 / urgency
/// - ZjuZdbkService.parseItems：静态解析考试项（service 网络逻辑已改 HttpClient，不再 mock）
/// - CoursesApiService.getAllExams：mock Dio（正常 / 返回网页抛可读错误）
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:evergreen_base/renderer/templates/zju_modle/courses/services/courses_api_service.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_exam.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/services/zdbk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZjuExam 模型', () {
    test('fromZdbk 解析中文时间格式（jssj="null" 回退 kssj 区间）', () {
      final e = ZjuExam.fromZdbk({
        'xkkh': '(2024-2025-1)-CS101-001',
        'kcmc': '数据结构',
        'cdmc': '东1A-101',
        'kssj': '2025年08月23日(14:00-16:40)',
        'jssj': 'null',
        'zwh': '12',
      });
      expect(e.id, '(2024-2025-1)-CS101-001');
      expect(e.name, '数据结构');
      expect(e.location, '东1A-101');
      expect(e.seatNumber, '12');
      expect(e.source, 'zdbk');
      expect(e.startTime, DateTime(2025, 8, 23, 14, 0));
      // jssj 为字面 "null" → 结束时间从 kssj 区间提取
      expect(e.endTime, DateTime(2025, 8, 23, 16, 40));
    });

    test('fromZdbk 无时间字段 → 时间可空', () {
      final e = ZjuExam.fromZdbk({
        'xkkh': 'x1',
        'kcmc': '未安排考试',
        'kssj': '',
        'jssj': 'null',
      });
      expect(e.startTime, isNull);
      expect(e.endTime, isNull);
      expect(e.name, '未安排考试');
    });

    test('fromCourses 解析 start_at', () {
      final e = ZjuExam.fromCourses({
        'id': '42',
        'title': '高数（乙）',
        'location': '紫金港西1-206',
        'start_at': '2025-09-01T09:00:00.000Z',
        'end_at': '2025-09-01T11:00:00.000Z',
      });
      expect(e.id, '42');
      expect(e.name, '高数（乙）');
      expect(e.source, 'courses');
      expect(e.startTime, DateTime.parse('2025-09-01T09:00:00.000Z'));
      expect(e.endTime, DateTime.parse('2025-09-01T11:00:00.000Z'));
    });

    test('toJson → fromJson 往返一致（含空时间）', () {
      final src = ZjuExam(
        id: '(2024-2025-1)-CS101-001',
        name: '数据结构',
        location: '东1A-101',
        startTime: DateTime(2025, 8, 23, 14, 0),
        endTime: DateTime(2025, 8, 23, 16, 40),
        seatNumber: '12',
        source: 'zdbk',
      );
      final round = ZjuExam.fromJson(src.toJson());
      expect(round.id, src.id);
      expect(round.name, src.name);
      expect(round.location, src.location);
      expect(round.startTime, src.startTime);
      expect(round.endTime, src.endTime);
      expect(round.seatNumber, src.seatNumber);
      expect(round.source, src.source);

      const empty = ZjuExam(
        id: 'x2',
        name: '无时间',
        source: 'courses',
      );
      final round2 = ZjuExam.fromJson(empty.toJson());
      expect(round2.startTime, isNull);
      expect(round2.endTime, isNull);
      expect(round2.location, isNull);
    });

    test('urgency 分级：已结束 / 7 天内 / 30 天内 / 更远', () {
      final now = DateTime.now();
      // 注意：Duration.inDays 向下截断，`now.add(8天)` 减去微秒后 inDays 可能变 7，
      // 故未来边界加 hours 余量保证整天（照抄参考 daysUntil 的语义）。
      ZjuExam exam(int days, {int extraHours = 0}) => ZjuExam(
            id: 'x',
            name: 'n',
            startTime: now.add(Duration(days: days, hours: extraHours)),
            source: 'zdbk',
          );
      expect(exam(-1, extraHours: -1).urgency, ZjuExamUrgency.past);
      expect(exam(0).urgency, ZjuExamUrgency.critical);
      expect(exam(7).urgency, ZjuExamUrgency.critical);
      expect(exam(8, extraHours: 12).urgency, ZjuExamUrgency.soon);
      expect(exam(30, extraHours: 12).urgency, ZjuExamUrgency.soon);
      expect(exam(31, extraHours: 12).urgency, ZjuExamUrgency.future);
      // 无时间 → daysUntil 999 → future
      expect(
        const ZjuExam(id: 'x', name: 'n', source: 'zdbk').urgency,
        ZjuExamUrgency.future,
      );
    });
  });

  group('ZjuZdbkService.parseItems（考试安排静态解析）', () {
    // 正常考试响应（JSON items，走 ZdbkPatterns.itemsWithTotalResult）
    const okBody =
        '{"items":[{"xkkh":"(2024-2025-1)-CS101-001","kcmc":"数据结构",'
        '"cdmc":"东1A-101","kssj":"2025年08月23日(14:00-16:40)",'
        '"jssj":"null","zwh":"12"},{"xkkh":"(2024-2025-1)-CS102-001",'
        '"kcmc":"高数","cdmc":"西1-206","kssj":"2025年08月25日(09:00-11:00)",'
        '"jssj":"null","zwh":"3"}],"totalResult":2}';

    test('正常路径：解析考试项列表', () {
      final items = ZjuZdbkService.parseItems(okBody, what: '考试安排');
      expect(items, hasLength(2));
      expect(items.first['kcmc'], '数据结构');
      expect(items.first['cdmc'], '东1A-101');
      expect(items[1]['zwh'], '3');
    });

    test('解析为空 → 抛可读 StateError（提示页面结构变更）', () {
      expect(
        () => ZjuZdbkService.parseItems('{}', what: '考试安排'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('解析为空'))),
      );
    });
  });

  group('CoursesApiService.getAllExams（mock Dio）', () {
    test('正常路径：解析 exams 数组', () async {
      final dio = _dioWith((options) {
        return ResponseBody.fromString(
          '{"exams":[{"id":"42","title":"高数（乙）",'
          '"location":"西1-206","start_at":"2025-09-01T09:00:00Z",'
          '"end_at":"2025-09-01T11:00:00Z"}]}',
          200,
        );
      });
      final items = await CoursesApiService(dio).getAllExams();
      expect(items, hasLength(1));
      expect(items.first['title'], '高数（乙）');
    });

    test('返回网页（未登录）→ 抛可读 StateError', () async {
      final dio = _dioWith((options) {
        return ResponseBody.fromString('<html>login</html>', 200);
      });
      expect(
        () => CoursesApiService(dio).getAllExams(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('SSO 会话可能已过期'))),
      );
    });
  });
}

// ── mock 工具（与 scores_test 同款）────────────────────────────────────

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://zdbk.zju.edu.cn'));
  dio.httpClientAdapter = _MockAdapter(
      (options) => Future<ResponseBody>.sync(() => handler(options)));
  return dio;
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
