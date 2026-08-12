/// zju classroom 模型 + service 单测（B3-classroom）。
///
/// 验证：
/// - 5 个模型：fromJson 映射 / toJson 往返 / aiContent 聚合
/// - ZjuClassroomService 6 个查询：正常路径 / 空列表 / 网页回退 / 去重 /
///   字幕毫秒换算 / 聚合 / 下载落盘（mock Dio，与 zdbk_test 同款 _MockAdapter）
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/classroom/services/classroom_service.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_classroom_course.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_classroom_video.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_course_content.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_ppt_slide.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('模型', () {
    test('ZjuClassroomCourse fromJson/toJson 往返', () {
      final c = ZjuClassroomCourse.fromJson(
          const {'id': '123', 'title': '数据结构', 'teacher': '张三'});
      expect(c.id, 123);
      expect(c.title, '数据结构');
      expect(c.teacher, '张三');
      final round = ZjuClassroomCourse.fromJson(c.toJson());
      expect(round.id, c.id);
      expect(round.title, c.title);
      expect(round.teacher, c.teacher);
    });

    test('ZjuClassroomCourse 缺省兜底（无 teacher / id 非数字）', () {
      final c = ZjuClassroomCourse.fromJson(const {'title': '高数'});
      expect(c.id, 0);
      expect(c.teacher, isNull);
      expect(c.toJson(), contains('title'));
    });

    test('ZjuClassroomCourse 值相等按 id（Dropdown value 匹配契约）', () {
      // 修复回归：DropdownButtonFormField 的 value 与 items 按 `==` 匹配。
      // 每次 fromJson 产生新实例，若按引用比较，选中项（旧实例）与 items
      // （新实例）不等 → 「There should be exactly one item with
      // [DropdownButton]'s value」崩溃。id 相同必须判定为同一门课。
      final a = ZjuClassroomCourse.fromJson(
          const {'id': '123', 'title': '数据结构', 'teacher': '张三'});
      final b = ZjuClassroomCourse.fromJson(
          const {'id': '123', 'title': '数据结构', 'teacher': '张三'});
      final c = ZjuClassroomCourse.fromJson(
          const {'id': '456', 'title': '数据结构', 'teacher': '张三'});
      expect(a == b, isTrue);
      expect(b == a, isTrue); // 对称
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
      // items.indexWhere 依赖：相同 id 的实例可被选中项命中
      final items = [c, b];
      expect(items.indexWhere((item) => item == a), 1);
    });

    test('ZjuClassroomVideo fromJson/toJson 往返（可空字段缺省不写）', () {
      final v = ZjuClassroomVideo.fromJson(const {
        'id': '1_2',
        'courseId': 1,
        'subId': 2,
        'title': '第1讲',
        'startAt': '2025-09-01 08:00',
        'videoUrl': 'https://cdn.example.com/v1.mp4',
      });
      expect(v.courseId, 1);
      expect(v.subId, 2);
      expect(v.videoUrl, 'https://cdn.example.com/v1.mp4');
      final json = v.toJson();
      expect(json['videoUrl'], 'https://cdn.example.com/v1.mp4');
      // 无 videoUrl → toJson 不写该字段（数据中枢缓存体积最小化）
      final v2 = ZjuClassroomVideo.fromJson(const {
        'id': '3_4',
        'courseId': 3,
        'subId': 4,
        'title': '第2讲',
      });
      expect(v2.videoUrl, isNull);
      expect(v2.toJson().containsKey('videoUrl'), isFalse);
    });

    test('ZjuPptSlide / ZjuSubtitle fromJson/toJson 往返', () {
      final s = ZjuPptSlide.fromJson(
          const {'page': 3, 'imageUrl': 'https://x/img3.png', 'text': '目录'});
      expect(s.page, 3);
      final round = ZjuPptSlide.fromJson(s.toJson());
      expect(round.page, 3);
      expect(round.imageUrl, s.imageUrl);
      expect(round.text, '目录');

      final sub = ZjuSubtitle.fromJson(
          const {'startMs': 125000, 'endMs': 0, 'text': '大家好'});
      expect(sub.startMs, 125000);
      final subRound = ZjuSubtitle.fromJson(sub.toJson());
      expect(subRound.startMs, 125000);
      expect(subRound.text, '大家好');
    });

    test('ZjuCourseContent 聚合 aiContent（PPT 文本 + 带时间戳字幕）', () {
      const content = ZjuCourseContent(
        slides: [
          ZjuPptSlide(page: 1, imageUrl: 'https://x/1.png', text: '引言'),
        ],
        subtitles: [
          ZjuSubtitle(startMs: 0, endMs: 0, text: '大家好'),
          ZjuSubtitle(startMs: 90000, endMs: 0, text: '今天讲树'),
        ],
      );
      final ai = content.aiContent;
      expect(ai, contains('## PPT 内容'));
      expect(ai, contains('引言'));
      expect(ai, contains('[1:30] 今天讲树'));
      // toJson/fromJson 往返
      final round = ZjuCourseContent.fromJson(content.toJson());
      expect(round.slides, hasLength(1));
      expect(round.subtitles, hasLength(2));
    });
  });

  group('ZjuClassroomService.listCourses（mock Dio）', () {
    const okBody =
        '{"params":{"result":{"data":'
        '[{"Id":"101","Title":"数据结构","Teacher":"张三"},'
        '{"Id":"102","Title":"操作系统","Teacher":"李四"}]}}}';

    test('正常路径：解析 params.result.data', () async {
      late Uri? lastUri;
      final dio = _dioWith((options) {
        lastUri = options.uri;
        return ResponseBody.fromString(okBody, 200);
      });
      final courses = await const ZjuClassroomService().listCourses(dio);
      expect(courses, hasLength(2));
      expect(courses.first.id, 101);
      expect(courses.first.title, '数据结构');
      expect(courses.first.teacher, '张三');
      expect(lastUri!.query, contains('force_mycourse=1'));
      expect(lastUri!.query, contains('per-page=100'));
    });

    test('空 data → 空列表（不抛）', () async {
      final dio = _dioWith(
          (options) => ResponseBody.fromString('{"params":{"result":{"data":[]}}}', 200));
      final courses = await const ZjuClassroomService().listCourses(dio);
      expect(courses, isEmpty);
    });

    test('返回网页（SSO 过期）→ 抛可读 StateError', () async {
      final dio = _dioWith(
          (options) => ResponseBody.fromString('<html>login</html>', 200));
      expect(
        () => const ZjuClassroomService().listCourses(dio),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('SSO'))),
      );
    });

    test('网络错误 → 抛可读 StateError', () async {
      final dio = _dioWith((options) {
        throw DioException.connectionError(
            requestOptions: options, reason: 'connection refused');
      });
      expect(
        () => const ZjuClassroomService().listCourses(dio),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('网络连接失败'))),
      );
    });
  });

  group('ZjuClassroomService.listVideos（mock Dio）', () {
    const okBody = '''
{"result":{"data":[
  {"sub_id":"1001","course_id":"7","status":"6",
   "title":"第1讲 绪论","start_at":"2025-09-01 08:00",
   "content":"{\\"playback\\":{\\"url\\":\\"https://cdn/v1.mp4\\"}}"},
  {"sub_id":"1002","course_id":"7","status":"5",
   "title":"第2讲 未发布","start_at":"2025-09-02 08:00",
   "content":"{\\"video_url\\":\\"https://cdn/v2.mp4\\"}"},
  {"sub_id":"1003","course_id":"7","status":"6",
   "title":"第3讲 无直链","start_at":"2025-09-03 08:00",
   "content":"not-json"}
]}}''';

    test('正常路径：仅保留 status=6，content 内嵌 JSON 解析 videoUrl', () async {
      late Uri? lastUri;
      final dio = _dioWith((options) {
        lastUri = options.uri;
        return ResponseBody.fromString(okBody, 200);
      });
      final videos = await const ZjuClassroomService().listVideos(dio, 7);
      expect(videos, hasLength(2), reason: 'status=5 必须被过滤');
      expect(lastUri!.query, contains('course_id=7'));
      // sub 1001：playback.url 直链
      expect(videos[0].subId, 1001);
      expect(videos[0].videoUrl, 'https://cdn/v1.mp4');
      // sub 1003：content 非 JSON → videoUrl 为 null
      expect(videos[1].subId, 1003);
      expect(videos[1].videoUrl, isNull);
    });

    test('空 data → 空列表', () async {
      final dio = _dioWith(
          (options) => ResponseBody.fromString('{"result":{"data":[]}}', 200));
      final videos = await const ZjuClassroomService().listVideos(dio, 7);
      expect(videos, isEmpty);
    });
  });

  group('ZjuClassroomService.fetchSlides（mock Dio）', () {
    test('正常路径：分页抓取 + 图片 URL 去重', () async {
      var page = 0;
      final dio = _dioWith((options) {
        page++;
        final items = List.generate(150, (i) {
          final url = 'https://cdn/slide_${(i % 2)}.png';
          return {
            'content':
                jsonEncode({'pptimgurl': url, 'text': '第${i + 1}页文本'})
          };
        });
        // 第二页仅 50 条（<100 → 触发停止翻页）
        return ResponseBody.fromString(
            jsonEncode({'list': items.take(page == 1 ? 100 : 50).toList()}),
            200);
      });
      final slides = await const ZjuClassroomService()
          .fetchSlides(dio, 7, 1001);
      // 150 条原始数据中 2 个不同 URL → 去重后 2 页
      expect(page, 2);
      expect(slides, hasLength(2));
      expect(slides[0].page, 1);
      expect(slides[0].imageUrl, 'https://cdn/slide_0.png');
      expect(slides[0].text, '第1页文本');
      expect(slides[1].page, 2);
    });

    test('空 list → 空列表', () async {
      final dio = _dioWith(
          (options) => ResponseBody.fromString('{"list":[]}', 200));
      final slides = await const ZjuClassroomService().fetchSlides(dio, 7, 1001);
      expect(slides, isEmpty);
    });
  });

  group('ZjuClassroomService.fetchSubtitles（mock Dio）', () {
    const okBody = '''
{"list":[
  {"all_content":[
     {"BeginSec":"0.5","Text":"大家好"},
     {"BeginSec":"90.0","Text":"今天讲树"},
     {"BeginSec":"120","Text":"  "}
  ]},
  {"all_content":"not-list"}
]}''';

    test('正常路径：BeginSec 秒 → 毫秒换算，空文本过滤', () async {
      late Uri? lastUri;
      final dio = _dioWith((options) {
        lastUri = options.uri;
        return ResponseBody.fromString(okBody, 200);
      });
      final subs = await const ZjuClassroomService()
          .fetchSubtitles(dio, 7, 1001);
      expect(subs, hasLength(2), reason: '空文本「  」必须过滤');
      expect(lastUri!.query, contains('sub_id=1001'));
      expect(subs[0].startMs, 500); // 0.5s → 500ms
      expect(subs[0].text, '大家好');
      expect(subs[1].startMs, 90000);
      expect(subs[1].text, '今天讲树');
    });

    test('非 JSON / 无 all_content → 空列表（不抛）', () async {
      final dio = _dioWith(
          (options) => ResponseBody.fromString('not json at all', 200));
      final subs = await const ZjuClassroomService()
          .fetchSubtitles(dio, 7, 1001);
      expect(subs, isEmpty);
    });
  });

  group('ZjuClassroomService.fetchCourseContent（mock Dio）', () {
    test('聚合 slides + subtitles', () async {
      final dio = _dioWith((options) {
        final path = options.uri.path;
        if (path.contains('search-ppt')) {
          return ResponseBody.fromString(
              jsonEncode({
                'list': [
                  {
                    'content': jsonEncode(
                        {'pptimgurl': 'https://cdn/s1.png', 'text': '引言'})
                  }
                ]
              }),
              200);
        }
        if (path.contains('search-trans-result')) {
          return ResponseBody.fromString(
              jsonEncode({
                'list': [
                  {
                    'all_content': [
                      {'BeginSec': '10.0', 'Text': '开场'}
                    ]
                  }
                ]
              }),
              200);
        }
        return ResponseBody.fromString('{}', 200);
      });
      final content = await const ZjuClassroomService()
          .fetchCourseContent(dio, 7, 1001);
      expect(content.slides, hasLength(1));
      expect(content.slides.first.text, '引言');
      expect(content.subtitles, hasLength(1));
      expect(content.subtitles.first.startMs, 10000);
    });
  });

  group('ZjuClassroomService.downloadSlides（mock Dio，写盘）', () {
    test('下载全部页到目标目录并返回路径', () async {
      final dio = _dioWith((options) {
        return ResponseBody.fromBytes(
            Uint8List.fromList([1, 2, 3, 4]), 200);
      });
      final dir = await Directory.systemTemp.createTemp('classroom_ppt_test');
      addTearDown(() => dir.delete(recursive: true));

      final slides = [
        const ZjuPptSlide(page: 1, imageUrl: 'https://cdn/s1.png'),
        const ZjuPptSlide(page: 2, imageUrl: 'https://cdn/s2.jpg'),
      ];
      final paths = await const ZjuClassroomService()
          .downloadSlides(dio, slides, dir.path);
      expect(paths, hasLength(2));
      expect(File(paths[0]).existsSync(), isTrue);
      expect(File(paths[1]).existsSync(), isTrue);
      expect(paths[0], endsWith('page_1.png'));
      expect(paths[1], endsWith('page_2.jpg'));
    });
  });
}

// ── mock 工具（与 zdbk_test / exams_test 同款）────────────────────────

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://classroom.zju.edu.cn'));
  dio.httpClientAdapter =
      _MockAdapter((options) => Future<ResponseBody>.sync(() => handler(options)));
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
