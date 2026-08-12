/// courses feature 单测（B3 首接入）：
/// - ZjuCourse 模型 fromJson/toJson 往返
/// - CoursesApiService：mock Dio（正常 JSON / 网页响应 / 网络错误三种路径）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:evergreen_base/renderer/templates/zju_modle/courses/models/course.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/courses/services/courses_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZjuCourse 模型', () {
    test('fromJson 全字段解析', () {
      final c = ZjuCourse.fromJson({
        'id': 1001,
        'name': '数据结构',
        'course_code': 'CS101',
        'class_name': '1班',
        'teacher_name': '张三',
        'teaching_place': '紫金港-东1A-201',
        'course_type_name': '专业必修',
        'is_started': true,
        'is_closed': false,
        'credits': 3.5,
      });
      expect(c.id, 1001);
      expect(c.name, '数据结构');
      expect(c.courseCode, 'CS101');
      expect(c.teacherName, '张三');
      expect(c.courseTypeName, '专业必修');
      expect(c.isStarted, isTrue);
      expect(c.isClosed, isFalse);
      expect(c.credits, 3.5);
      expect(c.statusLabel, '进行中');
    });

    test('fromJson 兼容后端旧字段（course_name / instructors 列表）', () {
      final c = ZjuCourse.fromJson({
        'course_id': 7,
        'course_name': '高等数学',
        'instructors': [
          {'name': '李四'}
        ],
        'is_started': 1,
        'credits': 4,
      });
      expect(c.id, 7);
      expect(c.name, '高等数学');
      expect(c.teacherName, '李四');
      expect(c.isStarted, isTrue);
      expect(c.credits, 4.0);
    });

    test('toJson → fromJson 往返一致', () {
      const src = ZjuCourse(
        id: 1,
        name: '软件工程',
        courseCode: 'SE201',
        teacherName: '王五',
        courseTypeName: '专业选修',
        isStarted: true,
        credits: 2.0,
      );
      final round = ZjuCourse.fromJson(src.toJson());
      expect(round.id, src.id);
      expect(round.name, src.name);
      expect(round.courseCode, src.courseCode);
      expect(round.teacherName, src.teacherName);
      expect(round.credits, src.credits);
    });

    test('状态标签：未开始 / 已结束', () {
      expect(const ZjuCourse(id: 1, name: 'a').statusLabel, '未开始');
      expect(
        const ZjuCourse(id: 1, name: 'a', isStarted: true, isClosed: true)
            .statusLabel,
        '已结束',
      );
    });
  });

  group('CoursesApiService（mock Dio）', () {
    late Dio dio;

    test('getMyCourses 正常解析', () async {
      dio = _dioWith((options) => _jsonResponse({
            'courses': [
              {'id': 1, 'name': '课程A', 'teacher_name': '赵六', 'credits': 3},
              {'id': 2, 'name': '课程B', 'is_started': true},
            ],
          }));
      final service = CoursesApiService(dio);
      final list = await service.getMyCourses();
      expect(list, hasLength(2));
      expect(list.first.name, '课程A');
      expect(list.first.teacherName, '赵六');
      expect(list[1].statusLabel, '进行中');
    });

    test('getMyCourses 空列表', () async {
      dio = _dioWith((options) => _jsonResponse({'courses': []}));
      final list = await CoursesApiService(dio).getMyCourses();
      expect(list, isEmpty);
    });

    test('getMyCourses 返回网页（未登录）→ 抛可读异常', () async {
      dio = _dioWith((options) =>
          ResponseBody.fromString('<html>统一身份认证</html>', 200));
      expect(
        () => CoursesApiService(dio).getMyCourses(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('返回了网页'))),
      );
    });

    test('getMyCourses 连接错误 → 抛可读异常', () async {
      dio = _dioWith(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      );
      expect(
        () => CoursesApiService(dio).getMyCourses(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('无法连接'))),
      );
    });
  });
}

// ── mock 工具 ──────────────────────────────────────────────────────────

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(jsonEncode(body), 200,
      headers: {'content-type': ['application/json']});
}

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://courses.zju.edu.cn'));
  dio.httpClientAdapter = _MockAdapter(
      (options) => Future<ResponseBody>.sync(() => handler(options)));
  return dio;
}

class _MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  _MockAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
