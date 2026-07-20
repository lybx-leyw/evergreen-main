/// 教室模板测试——模型解析 + orch 数据绑定 + 渲染冒烟。
///
/// classroom 已提升为独立 modle（classroom_modle），数据经 manifest 模块级
/// `dataSource`（orch://）拉取，不再内嵌 static config。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/classroom_modle/classroom_view.dart';
import 'package:evergreen_base/renderer/templates/classroom_modle/classroom_models.dart';

/// 假数据中枢：返回整份预置文档（与真实 orch://<type> 的 fetcher 返回形态一致，
/// 即 {courses:[...]} 这类带顶层键的文档），绕过注册/拉取。
class _FakeOrch extends DataOrchestrator {
  final Map<String, dynamic> _data;
  _FakeOrch(this._data);

  @override
  Future<T?> get<T>(DataType<T> type) async => _data as T?;

  @override
  Future<T?> refresh<T>(DataType<T> type) async => _data as T?;
}

void main() {
  // ── 模型冒烟 ──
  group('Classroom models', () {
    test('PptSlide fromJson/toJson', () {
      final s = PptSlide.fromJson(
          {'page': 1, 'imageUrl': 'img.png', 'text': '标题'});
      expect(s.page, 1);
      expect(s.imageUrl, 'img.png');
      expect(s.text, '标题');

      final json = s.toJson();
      final s2 = PptSlide.fromJson(json);
      expect(s2.page, 1);
      expect(s2.imageUrl, 'img.png');
    });

    test('Subtitle fromJson/toJson', () {
      final s = Subtitle.fromJson(
          {'startMs': 5000, 'endMs': 8000, 'text': '你好'});
      expect(s.startMs, 5000);
      expect(s.endMs, 8000);
      expect(s.text, '你好');
    });

    test('ClassroomVideo fromJson/toJson', () {
      final v = ClassroomVideo.fromJson({
        'subId': 1,
        'title': '第一讲',
        'videoUrl': 'v.mp4',
        'slides': [
          {'page': 1, 'imageUrl': 's1.png'}
        ],
        'subtitles': [
          {'startMs': 0, 'endMs': 0, 'text': 'Hi'}
        ],
      });
      expect(v.subId, 1);
      expect(v.title, '第一讲');
      expect(v.slides.length, 1);
      expect(v.subtitles.length, 1);

      final json = v.toJson();
      expect(json['subId'], 1);
      expect((json['slides'] as List).length, 1);
    });

    test('ClassroomCourse fromJson', () {
      final c = ClassroomCourse.fromJson({
        'id': '101',
        'title': '微积分',
        'teachers': ['张老师', '李老师'],
        'videos': [
          {
            'subId': 1,
            'title': 'V1',
            'slides': [],
            'subtitles': []
          }
        ],
      });
      expect(c.id, '101');
      expect(c.title, '微积分');
      expect(c.teachers, ['张老师', '李老师']);
      expect(c.videos.length, 1);
      expect(c.videos[0].subId, 1);
    });

    test('ClassroomCourse empty teachers', () {
      final c = ClassroomCourse.fromJson({'id': 1});
      expect(c.teachers, []);
      expect(c.videos, []);
    });

    test('CourseContent.aiContent 不为空', () {
      final content = CourseContent(
        slides: [
          PptSlide(page: 1, imageUrl: 'a.png', text: '因式分解'),
        ],
        subtitles: [
          Subtitle(startMs: 0, text: '今天学习数学'),
        ],
      );
      final ai = content.aiContent;
      expect(ai, contains('因式分解'));
      expect(ai, contains('今天学习数学'));
      expect(content.isEmpty, isFalse);
    });

    test('CourseContent.aiContent 为空', () {
      final content = CourseContent();
      expect(content.isEmpty, isTrue);
      expect(content.aiContent, '');
    });
  });

  // ── 数据绑定 + 渲染 ──
  group('ClassroomView', () {
    testWidgets('无 dataSource → 显示空态', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ClassroomView(
                moduleId: 'test',
                pluginsDir: r'C:\fake\plugins',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('缺少课程数据'), findsOneWidget);
    });

    testWidgets('orch 返回 courses → 渲染课程选择', (tester) async {
      final orch = _FakeOrch({
        'courses': [
          {
            'id': '1',
            'title': '测试课程',
            'teachers': ['A'],
            'videos': [
              {'subId': 1, 'title': '视频1', 'slides': [], 'subtitles': []}
            ],
          }
        ]
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
            dataOrchestratorProvider.overrideWithValue(orch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: ClassroomView(
                  dataSource:
                      const DataSourceDescriptor(endpoint: 'orch://courses'),
                  moduleId: 'test',
                  pluginsDir: r'C:\fake\plugins',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 应该显示课程标题
      expect(find.text('测试课程'), findsOneWidget);
      // 没有 videoUrl → 显示"无视频"
      expect(find.text('无视频'), findsOneWidget);
    });

    testWidgets('有 videoUrl 时显示视频播放器折叠条', (tester) async {
      final orch = _FakeOrch({
        'courses': [
          {
            'id': '1',
            'title': '有视频课',
            'teachers': [],
            'videos': [
              {
                'subId': 1,
                'title': 'V1',
                'videoUrl': 'test.mp4',
                'slides': [],
                'subtitles': []
              }
            ],
          }
        ]
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
            dataOrchestratorProvider.overrideWithValue(orch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: ClassroomView(
                  dataSource:
                      const DataSourceDescriptor(endpoint: 'orch://courses'),
                  moduleId: 'test',
                  pluginsDir: r'C:\fake\plugins',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('播放录播'), findsOneWidget);
    });

    testWidgets('自定义 bindings 键路径驱动提取（非标准数据形状）', (tester) async {
      // 数据形状与默认绑定完全不同：lessonList[].{code,name,instructors,clips[].{...}}
      final orch = _FakeOrch({
        'lessonList': [
          {
            'code': 'MATH101',
            'name': '数学分析',
            'instructors': ['王教授'],
            'clips': [
              {
                'clipId': 7,
                'label': '第一讲',
                'url': 'http://x/v.mp4',
                'pages': [
                  {'no': 2, 'img': 'p2.png', 'cap': '泰勒展开'}
                ],
                'subs': [
                  {'from': 0, 'to': 3000, 'line': '今天我们讲极限'}
                ],
              },
              {
                'clipId': 8,
                'label': '第二讲',
                'url': 'http://x/v2.mp4',
                'pages': [],
                'subs': []
              }
            ]
          }
        ]
      });
      // 自定义绑定：把每个语义键映射到上述形状的真实键路径
      const customBindings = DataSourceDescriptor(
        endpoint: 'orch://courses',
        bindings: {
          'courses': 'lessonList',
          'course.id': 'code',
          'course.title': 'name',
          'course.teachers': 'instructors',
          'course.videos': 'clips',
          'video.id': 'clipId',
          'video.title': 'label',
          'video.videoUrl': 'url',
          'video.slides': 'pages',
          'video.subtitles': 'subs',
          'slide.page': 'no',
          'slide.imageUrl': 'img',
          'slide.text': 'cap',
          'subtitle.startMs': 'from',
          'subtitle.endMs': 'to',
          'subtitle.text': 'line',
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
            dataOrchestratorProvider.overrideWithValue(orch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: ClassroomView(
                  dataSource: customBindings,
                  moduleId: 'test',
                  pluginsDir: r'C:\fake\plugins',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 证明：course.title 走绑定 'name' → 显示 '数学分析'
      expect(find.text('数学分析'), findsOneWidget);
      // 证明：video.title 走绑定 'label' → 显示 '第一讲'
      expect(find.text('第一讲'), findsOneWidget);
      // 证明：video.videoUrl 走绑定 'url' → 视频面板出现
      expect(find.text('播放录播'), findsOneWidget);
      // 证明：slide.text 走绑定 'cap' → PPT 文本出现
      expect(find.text('泰勒展开'), findsOneWidget);
      // 证明：subtitle.text 走绑定 'line' → 字幕出现
      expect(find.text('今天我们讲极限'), findsOneWidget);
    });

    testWidgets('视频选择（PopupMenuButton）可点开并展示选项', (tester) async {
      // 单课程 + 2 个视频 → 顶栏应出现「视频下拉框」（videos.length>1）
      final orch = _FakeOrch({
        'courses': [
          {
            'id': '1',
            'title': '单课程',
            'teachers': [],
            'videos': [
              {'subId': 1, 'title': 'V1', 'slides': [], 'subtitles': []},
              {'subId': 2, 'title': 'V2', 'slides': [], 'subtitles': []},
            ],
          }
        ]
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginsDirProvider.overrideWithValue(r'C:\fake\plugins'),
            dataOrchestratorProvider.overrideWithValue(orch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: ClassroomView(
                  dataSource:
                      const DataSourceDescriptor(endpoint: 'orch://courses'),
                  moduleId: 'test',
                  pluginsDir: r'C:\fake\plugins',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 视频选择（PopupMenuButton）应存在
      final videoDropdown = find.byType(PopupMenuButton<ClassroomVideo>);
      expect(videoDropdown, findsOneWidget);

      // 未打开时，未选中的第二项标题不应出现在树中
      expect(find.text('V2'), findsNothing);

      // 点开选择菜单
      await tester.tap(videoDropdown);
      await tester.pumpAndSettle();

      // 打开后，菜单中出现第二项选项
      expect(find.text('V2'), findsWidgets);
    });
  });
}
