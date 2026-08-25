/// zju 数据源注册——9+ 个 DataType + Dart fetcher 进数据中枢。
///
/// B2（2026-08-12）：删除 data-zdbk 插件后，教务数据由本文件以「内置 Dart fetcher」
/// 形式注册进 [DataOrchestrator]。数据链路：
///
/// `renderer UI → resolveDataSource(orch://zju_*) → DataOrchestrator → Dart fetcher`
///
/// 缓存/状态/刷新/连通性由数据中枢统一管理（web_cache JSON + TTL + 状态面板）。
/// fetcher 返回必须 JSON 兼容（orchestrator 会 jsonEncode 落盘缓存），
/// 模型 `toJson()` 产出、renderer `fromJson()` 还原。
///
/// 注：std 版裁剪（§5.1）在 B5 随 full/std 双版生成落地——本文件直接 import
/// 会编进 std，届时把注册调用收进生成物/开关。
library;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/session_provider.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/log.dart';

import 'classroom/services/classroom_service.dart';
import 'courses/services/courses_api_service.dart';
import 'shared/models/zju_classroom_course.dart';
import 'shared/models/zju_course_offering.dart';
import 'shared/models/zju_exam.dart';
import 'shared/models/zju_timetable_session.dart';
import 'shared/models/zju_training_plan.dart';
import 'shared/models/zju_zdbk_notification.dart';
import 'shared/utils/zju_gpa_calculator.dart';
import 'teachers/services/chalaoshi_service.dart';
import 'zdbk/services/zdbk_service.dart';
import 'zju_auth/zju_session.dart';

/// 注册 zju 全部数据源进 [orch]。
///
/// [prefs] 用于 fetcher 读取凭证（SSO 复用 getSetting，B3 移植 service 后接入）。
///
/// B2 阶段：先注册 zdbk 6 类型（教务），fetcher 为占位实现（抛「未接入」，
/// 保证注册契约与状态面板可用），B3 逐个 feature 移植 service 后替换真实 fetcher。
void registerZjuDataSources(DataOrchestrator orch, SharedPreferences prefs) {
  _zjuPrefs = prefs; // fetcher 懒加载共享会话时读取凭证

  // T9：注册 zju 会话 provider + 接入数据中枢会话协调器。
  // 拉取失败且错误被判「会话失效」时，DataOrchestrator 经 SessionCoordinator
  // 单点重登后重拉（登录锁防「登录挤占」）。注册点放在数据源注册处（而非
  // app_bootstrap），使 zju 会话中心与 12 类型同生命周期、不越 renderer 管辖。
  SessionCoordinator.instance.registerSessionProvider(
    'zju',
    ZjuSessionProvider(prefs: prefs),
  );
  orch.sessionCoordinator = SessionCoordinator.instance;

  // ── courses（教务，B3 首接入真实 fetcher）────────────────────────────
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_courses',
      category: '教务',
      displayName: '我的课程',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_courses',
      sessionProviderId: 'zju',
    ),
    _fetchZjuCourses,
  );

  // ── scores（教务，B3 第二接入真实 fetcher：成绩 + 双策略 GPA）─────────
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_scores',
      category: '教务',
      displayName: '成绩与 GPA',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_scores',
      sessionProviderId: 'zju',
    ),
    _fetchZjuScores,
  );

  // ── exams（教务，B3 第三接入真实 fetcher：考试安排 ZDBK + courses 回退）────
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_exams',
      category: '教务',
      displayName: '考试安排',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_exams',
      sessionProviderId: 'zju',
    ),
    _fetchZjuExams,
  );

  // ── zdbk（教务，6 类型，B3-zdbk 全部接真实 fetcher）────────────────────
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_zdbk_transcript',
      category: '教务',
      displayName: '成绩单',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_zdbk_transcript',
      sessionProviderId: 'zju',
    ),
    _fetchZjuZdbkTranscript,
  );
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_zdbk_major_grade',
      category: '教务',
      displayName: '主修成绩',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_zdbk_major_grade',
      sessionProviderId: 'zju',
    ),
    _fetchZjuZdbkMajorGrade,
  );
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_zdbk_practice_scores',
      category: '教务',
      displayName: '实践成绩',
      ttl: Duration(minutes: 10),
      persistentKey: 'zju_zdbk_practice_scores',
      sessionProviderId: 'zju',
    ),
    _fetchZjuZdbkPracticeScores,
  );
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_course_offerings',
      category: '教务',
      displayName: '开课情况',
      ttl: Duration(hours: 6),
      persistentKey: 'zju_course_offerings',
      sessionProviderId: 'zju',
    ),
    _fetchZjuCourseOfferings,
  );
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_training_plans',
      category: '教务',
      displayName: '培养方案',
      ttl: Duration(hours: 6),
      persistentKey: 'zju_training_plans',
      sessionProviderId: 'zju',
    ),
    _fetchZjuTrainingPlans,
  );
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_notifications',
      category: '教务',
      displayName: '教务通知',
      ttl: Duration(minutes: 30),
      persistentKey: 'zju_notifications',
      sessionProviderId: 'zju',
    ),
    _fetchZjuNotifications,
  );

  // ── timetable（教务，B3-ui：课表周视图，当前学年整个学年数据）────────
  // 注：ZDBK 忽略 xqm 参数返回整个学年的课，UI 按 semester 位掩码过滤学期，
  // 学期切换零网络；历史学年切换由 UI 直连 service（classroom 同款模式）。
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_timetable',
      category: '教务',
      displayName: '课表',
      ttl: Duration(hours: 6),
      persistentKey: 'zju_timetable',
      sessionProviderId: 'zju',
    ),
    _fetchZjuTimetable,
  );

  // ── classroom（校园，B3-classroom：智云课堂课程元数据）──────────────
  // 注：视频/PPT/字幕为二进制流 → 不进中枢（JSON 缓存装不下），UI 侧
  // 经 ZjuClassroomService 直连；本类型仅缓存课程元数据列表。
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_classroom_courses',
      category: '校园',
      displayName: '智云课堂',
      ttl: Duration(minutes: 30),
      persistentKey: 'zju_classroom_courses',
      sessionProviderId: 'zju',
    ),
    _fetchZjuClassroomCourses,
  );

  // ── teachers（校园，B3-teachers：查老师数据集统计）────────────────
  // 注：搜索为交互式（在线优先 + 本地秒回），结果不进中枢缓存；完整
  // 1.5MB 数据集作为 asset 内置 + 文档目录增量缓存。本类型仅缓存
  // 「数据集就绪统计」，供状态面板展示查老师数据源可用性。
  orch.register(
    const DataType<Map<String, dynamic>>(
      name: 'zju_teachers',
      category: '校园',
      displayName: '查老师',
      ttl: Duration(hours: 24),
      persistentKey: 'zju_teachers',
      sessionProviderId: 'zju',
    ),
    _fetchZjuTeachers,
  );

  Log().info(
      '[zju] registerZjuDataSources 完成（B3：courses 1 + scores 1 + exams 1 + zdbk 6 + classroom 1 + teachers 1 + timetable 1 = 12 类型全部真实接入）');
}

// ═══════════════════════════════════════════════════════════════════════
// 共享 ZJU 会话（CAS 并发节流：9+ fetcher 共用同一 Dio）
// ═══════════════════════════════════════════════════════════════════════

SharedPreferences? _zjuPrefs;
Future<Dio>? _zjuDioFuture;

/// 懒加载共享 Dio（首次调用触发 SSO 登录/恢复，之后复用）。
Future<Dio> _ensureZjuDio() {
  return _zjuDioFuture ??= ensureZjuSession(prefs: _zjuPrefs!);
}

// ═══════════════════════════════════════════════════════════════════════
// courses fetcher（B3 首接入）
// ═══════════════════════════════════════════════════════════════════════

/// 拉取我的课程 → JSON（数据中枢缓存）。
Future<Map<String, dynamic>> _fetchZjuCourses() async {
  final dio = await _ensureZjuDio();
  final courses = await CoursesApiService(dio).getMyCourses();
  return {'courses': courses.map((c) => c.toJson()).toList()};
}

/// 拉取教务成绩单 → 成绩列表 + 双策略 GPA（保研首次/出国最高）→ JSON。
///
/// 数据形态（renderer `ZjuGrade.fromJson` / `ZjuGpaResult.fromJson` 还原）：
/// ```json
/// {
///   "grades": [{"xkkh":..,"kcmc":..,"xf":..,"cj":..,"jd":..,"major":..}],
///   "domestic_gpa": {"five_point":..,"four_point":..,"four_point_legacy":..,
///                    "hundred_point":..,"earned_credits":..},
///   "abroad_gpa": {...}
/// }
/// ```
Future<Map<String, dynamic>> _fetchZjuScores() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final grades = await service.getTranscript(service.httpClient!);
  final domesticGpa = ZjuGpaCalculator.calculateGpa(
      ZjuGpaCalculator.pickFirstAttempt(grades));
  final abroadGpa = ZjuGpaCalculator.calculateGpa(
      ZjuGpaCalculator.pickHighestAttempt(grades));
  Log().info('[zju-scores] 成绩单 + GPA 就绪',
      data: {'grades': grades.length, 'domestic': domesticGpa.toString()});
  return {
    'grades': grades.map((g) => g.toJson()).toList(),
    'domestic_gpa': domesticGpa.toJson(),
    'abroad_gpa': abroadGpa.toJson(),
  };
}

/// 拉取考试安排 → ZjuExam JSON 列表（ZDBK 主源 + courses 回退，抄参考 provider）。
///
/// 数据形态（renderer `ZjuExam.fromJson` 还原）：
/// ```json
/// {"exams": [{"id":..,"name":..,"location":..,"startTime":..,"endTime":..,
///            "seatNumber":..,"source":"zdbk|courses"}]}
/// ```
/// 按开考时间升序排列（无时间字段排末尾，与参考 `examsListProvider` 一致）。
Future<Map<String, dynamic>> _fetchZjuExams() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final exams = <ZjuExam>[];

  // 1. ZDBK（教务网，主源）
  try {
    final items = await service.getExams(service.httpClient!);
    exams.addAll(items.map(ZjuExam.fromZdbk));
    Log().info('[zju-exams] ZDBK 考试就绪', data: {'count': exams.length});
  } catch (e) {
    Log().warn('[zju-exams] ZDBK 考试不可用，尝试 courses 回退',
        data: {'error': e.toString()});
  }

  // 2. 学在浙大回退（ZDBK 失败或为空时）
  if (exams.isEmpty) {
    try {
      final dio = await _ensureZjuDio();
      final items = await CoursesApiService(dio).getAllExams();
      exams.addAll(items.map(ZjuExam.fromCourses));
      Log().info('[zju-exams] courses 考试回退成功', data: {'count': exams.length});
    } catch (e) {
      Log().warn('[zju-exams] 全部考试源不可用', data: {'error': e.toString()});
      throw StateError('考试安排获取失败：教务（zdbk）与学在浙大（courses）均不可用');
    }
  }

  // 按考试时间升序，无时间排末尾（与参考 provider 排序一致）
  exams.sort((a, b) {
    if (a.startTime == null && b.startTime == null) return 0;
    if (a.startTime == null) return 1;
    if (b.startTime == null) return -1;
    return a.startTime!.compareTo(b.startTime!);
  });

  return {'exams': exams.map((e) => e.toJson()).toList()};
}

// ═══════════════════════════════════════════════════════════════════════
// zdbk fetcher（B3-zdbk：6 个占位全部替换为真实拉取）
// ═══════════════════════════════════════════════════════════════════════

/// 读取学号（实践成绩/教务通知的 `su` 参数；未配置时抛可读错误）。
String _zjuUsername() {
  final u = getSetting(_zjuPrefs!, 'ZJU_USERNAME');
  if (u.isEmpty) {
    throw StateError('未配置浙大学号——请先在「设置」中填写 ZJU_USERNAME');
  }
  return u;
}

/// 当前学年 + 学期码（秋冬 3 / 春夏 12，参考 `_currentSemester`）。
({int year, int semester}) _currentZjuSemester() {
  final now = DateTime.now();
  final isAutumnWinter = now.month >= 9 || now.month <= 2;
  return (
    year: isAutumnWinter ? now.year : now.year - 1,
    semester: isAutumnWinter ? 3 : 12,
  );
}

/// 拉取成绩单（旧 zdbk 兼容）→ JSON。
///
/// 数据形态（renderer `ZjuGrade.fromJson` 还原）：
/// ```json
/// {"grades": [{"xkkh":..,"kcmc":..,"xf":..,"cj":..,"jd":..,"major":..}]}
/// ```
Future<Map<String, dynamic>> _fetchZjuZdbkTranscript() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final grades = await service.getTranscript(service.httpClient!);
  return {'grades': grades.map((g) => g.toJson()).toList()};
}

/// 拉取主修成绩 → 成绩列表 + 保研 GPA（与 scores 同款首考策略）。
///
/// 数据形态：`{"grades": [...], "gpa": {...}}`（ZjuGpaResult.toJson）。
Future<Map<String, dynamic>> _fetchZjuZdbkMajorGrade() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final grades = await service.getMajorGrades(service.httpClient!);
  final gpa = ZjuGpaCalculator.calculateGpa(
      ZjuGpaCalculator.pickFirstAttempt(grades));
  Log().info('[zju-zdbk] 主修成绩 + GPA 就绪',
      data: {'grades': grades.length, 'gpa': gpa.toString()});
  return {
    'grades': grades.map((g) => g.toJson()).toList(),
    'gpa': gpa.toJson(),
  };
}

/// 拉取实践成绩（第二/三/四课堂）→ JSON。
///
/// 数据形态：`{"scores": {"pt2":..,"pt3":..,"pt4":..}}`。
Future<Map<String, dynamic>> _fetchZjuZdbkPracticeScores() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final scores =
      await service.getPracticeScores(service.httpClient!, _zjuUsername());
  return {'scores': scores};
}

/// 拉取开课情况（自动检测当前学年学期）→ JSON。
///
/// 数据形态（renderer `ZjuCourseOffering.fromJson` 还原）：
/// ```json
/// {"offerings": [{"kcdm":..,"kcmc":..,"jsxm":..,"skdd":..,"sksj":..,..}],
///  "year":2026,"semester":3}
/// ```
Future<Map<String, dynamic>> _fetchZjuCourseOfferings() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final sem = _currentZjuSemester();
  final offerings = await service.getCourseOfferings(
    service.httpClient!,
    year: sem.year,
    semester: sem.semester,
  );
  Log().info('[zju-zdbk] 开课情况就绪',
      data: {'count': offerings.length, 'year': sem.year, 'semester': sem.semester});
  return {
    'offerings': offerings.map((o) => o.toJson()).toList(),
    'year': sem.year,
    'semester': sem.semester,
  };
}

/// 拉取培养方案 → JSON。
///
/// 数据形态（renderer `ZjuTrainingPlan.fromJson` 还原）：
/// ```json
/// {"plans": [{"jxjhh":..,"pyfamc":..,"zymc":..,"synj":..,..}]}
/// ```
Future<Map<String, dynamic>> _fetchZjuTrainingPlans() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final plans = await service.getTrainingPlans(service.httpClient!);
  return {'plans': plans.map((p) => p.toJson()).toList()};
}

/// 拉取教务通知 → JSON。
///
/// 数据形态（renderer `ZjuZdbkNotification.fromJson` 还原）：
/// ```json
/// {"notifications": [{"id":..,"title":..,"publisher":..,"publishDate":..,
///                     "viewCount":..,"content":..}]}
/// ```
Future<Map<String, dynamic>> _fetchZjuNotifications() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final notifications =
      await service.getNotifications(service.httpClient!, _zjuUsername());
  return {
    'notifications': notifications.map((n) => n.toJson()).toList(),
  };
}

// ═══════════════════════════════════════════════════════════════════════
// timetable fetcher（B3-ui：课表周视图）
// ═══════════════════════════════════════════════════════════════════════

/// 拉取课表（当前学年整个学年数据）→ JSON。
///
/// 数据形态（renderer `ZjuTimetableSession.fromJson` 还原）：
/// ```json
/// {"sessions": [{"course_id":..,"course_name":..,"teacher":..,"location":..,
///                "day_of_week":..,"periods":[..],"week_range":..,
///                "semester":..,"course_year":..,"is_ended":..,"credit":..}],
///  "year":2026}
/// ```
/// 注意 ZDBK 忽略 xqm 参数返回整个学年的课，UI 按 `semester` 位掩码过滤
/// 展示学期（春=1, 夏=2, 短①=4, 秋=8, 冬=16, 短②=32, 暑=64）。
Future<Map<String, dynamic>> _fetchZjuTimetable() async {
  final service = await ensureZdbkSession(prefs: _zjuPrefs!);
  final sem = _currentZjuSemester();
  final sessions = await service.getTimetable(
    service.httpClient!,
    year: sem.year,
    semester: sem.semester,
  );
  Log().info('[zju] 课表就绪',
      data: {'count': sessions.length, 'year': sem.year, 'semester': sem.semester});
  return {
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'year': sem.year,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// classroom fetcher（B3-classroom：智云课堂课程元数据）
// ═══════════════════════════════════════════════════════════════════════

/// 拉取智云课堂课程列表 → JSON。
///
/// 数据形态（renderer `ZjuClassroomCourse.fromJson` 还原）：
/// ```json
/// {"courses": [{"id":..,"title":..,"teacher":..}]}
/// ```
Future<Map<String, dynamic>> _fetchZjuClassroomCourses() async {
  final dio = await _ensureZjuDio();
  final courses = await ZjuClassroomService().listCourses(dio);
  Log().info('[zju/classroom] 课程列表就绪', data: {'count': courses.length});
  return {'courses': courses.map((c) => c.toJson()).toList()};
}

// ═══════════════════════════════════════════════════════════════════════
// teachers fetcher（B3-teachers：查老师数据集统计）
// ═══════════════════════════════════════════════════════════════════════

/// 加载查老师内置数据集并返回统计 → JSON（数据中枢缓存）。
///
/// 完整数据集作为 asset 内置 + 文档目录增量缓存，不进 JSON 缓存；
/// 仅缓存统计供状态面板展示。asset 缺失时抛可读 StateError
/// （中枢捕获后置 connected=false + lastError 引导）。
///
/// 数据形态（renderer 无需还原，仅状态面板展示）：
/// ```json
/// {"loaded": true, "teachers": 1234, "colleges": 40}
/// ```
Future<Map<String, dynamic>> _fetchZjuTeachers() async {
  final dataset = await ZjuChalaoshiService(Dio()).loadDataset();
  Log().info('[zju/teachers] 数据集就绪',
      data: {'teachers': dataset.teachers.length, 'colleges': dataset.colleges.length});
  return dataset.toStatsJson();
}
