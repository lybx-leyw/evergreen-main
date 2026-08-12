/// zju 数据源注册契约测试（B2 骨架 + B3 全部 12 类型真实 fetcher）。
///
/// 验证 [registerZjuDataSources]：
/// - 全部类型注册进 DataOrchestrator（name/category/displayName/ttl/persistentKey）
/// - 重复调用幂等（覆盖注册不抛）
/// - 真实 fetcher 未配置凭证：refresh 返回 null（fetcher 抛 StateError → 中枢捕获
///   置 connected=false + lastError 含「未配置」引导），不污染缓存
library;

import 'dart:io';

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_auth/cookie_store.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zju_data_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataOrchestrator orch;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 隔离本机真实 `.greenix/zju_cookies.json`：真实运行 app 后该文件写入
    // 了 SSO cookie，「未配置凭证」测试会读到它而跳过凭证检查直接走网络
    // （DioException 400）而非期望的「未配置」StateError。
    tmp = await Directory.systemTemp.createTemp('zju_ds_cookie_test');
    CookieStore.setInstanceForTesting(
      await CookieStore.createForTesting('${tmp.path}/zju_cookies.json'),
    );
    orch = DataOrchestrator();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> register() async {
    final prefs = await SharedPreferences.getInstance();
    registerZjuDataSources(orch, prefs);
  }

  test('全部类型注册，元数据正确（B3: courses 1 + scores 1 + exams 1 + zdbk 6 + classroom 1 + teachers 1 + timetable 1）',
      () async {
    await register();
    expect(orch.registeredTypes, hasLength(12));

    // B3 courses 首接入
    final courses = orch.typeByName('zju_courses');
    expect(courses, isNotNull);
    expect(courses!.category, '教务');
    expect(courses.displayName, '我的课程');
    expect(courses.ttl, const Duration(minutes: 10));
    expect(courses.persistentKey, 'zju_courses');

    // B3 scores 第二接入
    final scores = orch.typeByName('zju_scores');
    expect(scores, isNotNull);
    expect(scores!.category, '教务');
    expect(scores.displayName, '成绩与 GPA');
    expect(scores.ttl, const Duration(minutes: 10));
    expect(scores.persistentKey, 'zju_scores');

    // B3 exams 第三接入
    final exams = orch.typeByName('zju_exams');
    expect(exams, isNotNull);
    expect(exams!.category, '教务');
    expect(exams.displayName, '考试安排');
    expect(exams.ttl, const Duration(minutes: 10));
    expect(exams.persistentKey, 'zju_exams');

    final transcript = orch.typeByName('zju_zdbk_transcript');
    expect(transcript, isNotNull);
    expect(transcript!.category, '教务');
    expect(transcript.displayName, '成绩单');
    expect(transcript.ttl, const Duration(minutes: 10));
    expect(transcript.persistentKey, 'zju_zdbk_transcript');

    final offerings = orch.typeByName('zju_course_offerings');
    expect(offerings!.ttl, const Duration(hours: 6));
    expect(offerings.persistentKey, 'zju_course_offerings');

    // B3 timetable（教务第 10 接入：课表周视图）
    final timetable = orch.typeByName('zju_timetable');
    expect(timetable, isNotNull);
    expect(timetable!.category, '教务');
    expect(timetable.displayName, '课表');
    expect(timetable.ttl, const Duration(hours: 6));
    expect(timetable.persistentKey, 'zju_timetable');

    // B3 classroom（校园分类首接入）
    final classroom = orch.typeByName('zju_classroom_courses');
    expect(classroom, isNotNull);
    expect(classroom!.category, '校园');
    expect(classroom.displayName, '智云课堂');
    expect(classroom.ttl, const Duration(minutes: 30));
    expect(classroom.persistentKey, 'zju_classroom_courses');

    // B3 teachers（校园分类第二接入：查老师数据集统计）
    final teachers = orch.typeByName('zju_teachers');
    expect(teachers, isNotNull);
    expect(teachers!.category, '校园');
    expect(teachers.displayName, '查老师');
    expect(teachers.ttl, const Duration(hours: 24));
    expect(teachers.persistentKey, 'zju_teachers');

    // 分类：教务（10）→ 校园（classroom + teachers 2），供状态面板按分类分组。
    expect(orch.categories, ['教务', '校园']);
  });

  test('注册集合与规划数据源类型表一致（courses 1 + scores 1 + exams 1 + zdbk 6 + classroom 1 + teachers 1 + timetable 1）',
      () async {
    await register();
    final names = orch.registeredTypes.toSet();
    expect(
      names,
      {
        'zju_courses',
        'zju_scores',
        'zju_exams',
        'zju_zdbk_transcript',
        'zju_zdbk_major_grade',
        'zju_zdbk_practice_scores',
        'zju_course_offerings',
        'zju_training_plans',
        'zju_notifications',
        'zju_timetable',
        'zju_classroom_courses',
        'zju_teachers',
      },
    );
  });

  test('真实 fetcher 未配置凭证：refresh 返回 null 且状态记录可读错误（不崩溃不写缓存）',
      () async {
    await register();
    final result = await orch.refreshByName('zju_zdbk_transcript');
    expect(result, isNull);

    final s = orch.status('zju_zdbk_transcript')!;
    expect(s.connected, isFalse);
    expect(s.lastError, contains('未配置'));
  });

  test('重复注册幂等（覆盖不抛，类型数不增长）', () async {
    await register();
    await register();
    expect(orch.registeredTypes, hasLength(12));
  });
}
