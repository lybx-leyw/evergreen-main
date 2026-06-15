/// Agent Provider — Riverpod 桥接层。
///
/// 将 Agent Runtime 的 Controller 注入到 Flutter Widget 树。
/// 将 Flutter Provider 数据桥接到 Agent 的 ZJU 工具。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/config/app_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/services/ocr_pipeline.dart';
import '../../../core/agent/agent.dart' as agent;
import '../../../core/agent/memory/facade.dart';
import '../../../core/agent/memory/router.dart';
import '../../../core/agent/memory/file_memory_store.dart';
import '../../../core/agent/tool.dart';
import '../../../core/agent/tools/zju_data_source.dart';
import '../../../core/agent/tools/zju_courses.dart';
import '../../../core/agent/tools/zju_scores.dart';
import '../../../core/agent/tools/zju_classroom.dart';
import '../../../core/agent/tools/zju_ecard.dart';
import '../../../core/agent/tools/zju_todos.dart';
import '../../../core/agent/tools/zju_exams.dart';
import '../../../core/agent/tools/zju_timetable.dart';
import '../../../core/agent/tools/zju_notifications.dart';
import '../../../core/agent/tools/semester_info.dart';
import '../../../core/agent/tools/user_info.dart';
import '../../../core/agent/tools/read_global_memory.dart';
import '../../../core/agent/tools/write_global_memory.dart';
import '../../../core/agent/tools/run_skill.dart';
import '../../../core/agent/skill/skill.dart';
import '../../teachers/tools/search_teacher.dart';
import '../../../core/agent/tools/web_search.dart';
import '../../../core/models/course_offering.dart';
import '../../../core/models/timetable_session.dart';
import '../../zdbk/providers/zdbk_provider.dart';
import '../../zdbk/providers/zdbk_notifications_provider.dart';
import '../../zdbk/tools/zju_course_offerings.dart';
import '../../zdbk/tools/search_course_offerings.dart';
import '../../zdbk/tools/get_training_plan.dart';
import '../../../core/models/training_plan.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classroom/providers/classroom_provider.dart';
import '../../classroom/services/classroom_crawler.dart';
import '../../ecard/providers/ecard_provider.dart';
import '../../todo/providers/todo_provider.dart';
import '../../exams/providers/exams_provider.dart';
import '../services/session_store.dart';

// ─── ZJU Data Source ──────────────────────────────────────

class FlutterZjuDataSource implements ZjuDataSource, CourseOfferingDataSource, CourseOfferingSearchDataSource, TrainingPlanDataSource {
  final Ref _ref;
  FlutterZjuDataSource(this._ref);

  @override
  Future<List<ZjuCourse>> getCourses() async {
    // 从教务网课表读取（替代原有的 courses.zju.edu.cn）
    final result = await _ref.read(zdbkTimetableProvider.future);
    final sessions = result.fold((s) => s, (_) => <TimetableSession>[]);
    // 按课程名去重：同一门课每周有多条 timetable session
    final unique = <String, ZjuCourse>{};
    for (final s in sessions) {
      if (!unique.containsKey(s.courseName)) {
        unique[s.courseName] = ZjuCourse(
          id: _stableCourseId(s.courseName, s.courseId),
          name: s.courseName,
          teacher: s.teacher,
          isActive: !s.isEnded,
        );
      }
    }
    return unique.values.toList();
  }

  /// 从课程名和选课课号生成稳定正整数 ID。
  static int _stableCourseId(String name, String? courseId) {
    final seed = courseId ?? name;
    int hash = 0;
    for (int i = 0; i < seed.length; i++) {
      hash = 31 * hash + seed.codeUnitAt(i);
    }
    return hash.abs();
  }

  @override
  Future<ZjuScoreResult?> getScores() async {
    final result = await _ref.read(zdbkEverythingProvider.future);
    return result.fold(
      (data) => ZjuScoreResult(
        fivePointGpa: data.domesticGpa.fivePoint,
        fourPointThreeGpa: data.domesticGpa.fourPoint,
        fourPointGpa: data.domesticGpa.fourPointLegacy,
        hundredPointGpa: data.domesticGpa.hundredPoint,
        totalCredits: data.domesticGpa.earnedCredits,
        courseCount: data.grades.length,
      ),
      (_) => null,
    );
  }

  @override
  Future<List<ZjuClassroomCourse>> getClassroomCourses() async {
    final result = await _ref.read(classroomCoursesProvider.future);
    final courses = result.fold((c) => c, (_) => <ClassroomCourse>[]);
    return courses
        .map((c) => ZjuClassroomCourse(id: c.id, title: c.title))
        .toList();
  }

  @override
  Future<ZjuEcardResult?> getEcardBalance() async {
    try {
      final data = await _ref.read(ecardBalanceProvider.future);
      if (data == null) return null;
      final balance = (data['balance'] ?? data['card_balance'] ?? data['amount']);
      return ZjuEcardResult(
        balance: (balance is num) ? balance.toDouble() : 0.0,
        cardNumber: data['card_no']?.toString(),
      );
    } catch (_) { return null; }
  }

  @override
  Future<List<ZjuTodo>> getTodos() async {
    final todos = await _ref.read(todoListProvider.future);
    return todos.map((t) => ZjuTodo(id: t.id, title: t.title, deadline: t.deadline, type: t.type)).toList();
  }

  @override
  Future<List<ZjuExam>> getExams() async {
    final exams = await _ref.read(examsListProvider.future);
    return exams.map((e) => ZjuExam(name: e.name, startTime: e.startTime, location: e.location)).toList();
  }

  @override
  Future<List<ZjuTimetableEntry>> getTimetable() async {
    final result = await _ref.read(zdbkTimetableProvider.future);
    final sessions = result.fold((s) => s, (_) => <TimetableSession>[]);
    return sessions.map((s) => ZjuTimetableEntry(
      courseName: s.courseName,
      teacher: s.teacher,
      location: s.location,
      dayOfWeek: s.dayOfWeek,
      periods: s.periods,
      weekRange: s.weekRange,
      semesterLabel: semesterBitsToLabel(s.semester, s.courseYear),
    )).toList();
  }

  @override
  Future<List<ZjuNotification>> getNotifications() async {
    final result = await _ref.read(zdbkNotificationsProvider.future);
    return result.fold(
      (list) => list.map((n) => ZjuNotification(
        id: n.id,
        title: n.title,
        publisher: n.publisher,
        publishDate: n.publishDate,
        content: n.content,
      )).toList(),
      (_) => <ZjuNotification>[],
    );
  }

  // ── CourseOfferingDataSource ──────────────────────────────

  @override
  Future<List<CourseOffering>> getCourseOfferings({int year = 2024, int semester = 12}) async {
    final result = await _ref.read(courseOfferingsProvider((year: year, semester: semester)).future);
    return result.fold((data) => data, (_) => <CourseOffering>[]);
  }

  @override
  Future<List<CourseOffering>> searchCourseOfferings({required String query, int year = 2025, int semester = 12}) async {
    final service = await _ref.read(zdbkServiceInstanceProvider.future);
    final auth = _ref.read(authProvider);
    final httpClient = _ref.read(httpClientProvider);
    if (!service.isLoggedIn) await service.login(httpClient, auth.ssoCookie!);
    final result = await service.searchCourseOfferings(httpClient, query: query, year: year, semester: semester);
    return result.fold((data) => data, (_) => <CourseOffering>[]);
  }

  // ── TrainingPlanDataSource ───────────────────────────────

  @override
  Future<Result<List<TrainingPlan>>> getTrainingPlans(int grade) async {
    final result = await _ref.read(trainingPlansProvider(grade).future);
    return result;
  }

  @override
  Future<Result<String>> getPlanOcrText(String planNo) async {
    try {
      final service = await _ref.read(zdbkServiceInstanceProvider.future);
      final httpClient = _ref.read(httpClientProvider);
      final auth = _ref.read(authProvider);
      if (!service.isLoggedIn && auth.ssoCookie != null) {
        await service.login(httpClient, auth.ssoCookie!);
      }

      // 1. 下载 PDF
      final pdfResult = await service.downloadPlanPdf(httpClient, planNo);
      if (pdfResult.isErr) return Err((pdfResult as Err).error);
      final pdfPath = (pdfResult as Ok<String>).value;

      // 2. 两级 OCR：DeepSeek → Tesseract（PDF 拆分 + 逐页 OCR 由 Pipeline 处理）
      final dio = _ref.read(dioClientProvider);
      final text = await OcrPipeline(dio).recognizeFile(pdfPath);

      // 3. 清理临时 PDF
      try { await File(pdfPath).delete(); } catch (_) {}

      if (text == null || text.isEmpty) {
        return Err(AppError.fileError('ocr', 'read', osError: 'OCR 未识别到文字'));
      }
      return Ok(text);
    } catch (e) {
      return Err(AppError.unknown(e));
    }
  }
}

// ─── Agent Controller Provider ────────────────────────────

/// Agent 运行时状态（Controller + 事件流）。
class AgentRuntime {
  final agent.Controller controller;
  final agent.StreamEventSink eventSink;
  final agent.Session session;

  AgentRuntime({
    required this.controller,
    required this.eventSink,
    required this.session,
  });

  Stream<agent.AgentEvent> get events => eventSink.stream;
}

/// 全局唯一的 Agent Runtime。
final agentRuntimeProvider = Provider<AgentRuntime>((ref) {
  final dio = ref.read(dioClientProvider);
  final apiKey = AppConfig.deepseekApiKey ?? '';
  final model = AppConfig.deepseekModel ?? 'deepseek-v4-flash';

  debugPrint('[AgentInit:D] creating AgentRuntime apiKey=${apiKey.isNotEmpty ? "✅ ${apiKey.substring(0, 8)}..." : "❌ empty"} model=$model');

  final provider = agent.DeepSeekProvider(dio: dio, apiKey: apiKey, model: model);
  final dataSource = FlutterZjuDataSource(ref);

  // 记忆系统：global → 文件存储
  final globalStore = FileMemoryStore('.greenix/memories');

  // Skill 系统：首次运行时从打包 assets 提取预置 skill 到文件系统
  const skillDir = '.greenix/skills';
  const bundledSkills = ['acceptance.md'];
  Directory(skillDir).createSync(recursive: true);
  for (final name in bundledSkills) {
    final target = File('$skillDir/$name');
    if (!target.existsSync()) {
      rootBundle.loadString('$skillDir/$name').then((content) {
        target.writeAsStringSync(content);
      }).catchError((_) {}); // 开发模式无 asset bundle → 静默跳过
    }
  }

  final skillIndex = SkillIndex();
  final loader = SkillLoader([skillDir]);
  skillIndex.addAll(loader.loadAll());
  BuiltinSkills.loadInto(skillIndex);
  if (skillIndex.all().isNotEmpty) {
    debugPrint('[AgentInit:D] loaded ${skillIndex.all().length} skills');
  }

  // 注册工具
  final registry = Registry();
  registry.registerAll([
    ZjuCoursesTool(dataSource),
    ZjuScoresTool(dataSource),
    ZjuClassroomTool(dataSource),
    ZjuEcardTool(dataSource),
    ZjuTodosTool(dataSource),
    ZjuExamsTool(dataSource),
    ZjuTimetableTool(dataSource),
    ZjuNotificationsTool(dataSource),
    ZjuCourseOfferingsTool(dataSource),
    SearchCourseOfferingsTool(dataSource),
    GetCurrentSemesterTool(),
    GetUserInfoTool(),
    GetTrainingPlanTool(dataSource),
    SearchTeacherTool(dio),
    WebSearchTool(dio),   // 默认启用，但模型只会在 system prompt 提示时使用
    WebFetchTool(dio),    // 同上
    ReadGlobalMemoryTool(globalStore),
    WriteGlobalMemoryTool(globalStore),
    RunSkillTool(loader, skillIndex, provider, registry),
    ListSkillsTool(loader, skillIndex),
  ]);
  // 默认禁用联网搜索（由用户开关控制）
  registry.disable('web_search');
  registry.disable('web_fetch');
  debugPrint('[AgentInit:D] registered ${registry.enabled().length} tools (web tools disabled by default)');
  for (final t in registry.enabled()) {
    debugPrint('[AgentInit:D]   tool: ${t.name} readOnly=${t.readOnly}');
  }

  // 事件流 + 会话
  final eventSink = agent.StreamEventSink();
  final session = agent.Session();

  // 记忆门面（globalStore 已在上面创建）
  final memoryRouter = MemoryRouter(global: globalStore);
  final memory = MemoryFacade(memoryRouter);

  // Controller
  final controller = agent.Controller(
    provider: provider,
    registry: registry,
    sink: eventSink,
    session: session,
    memory: memory,
    skillIndexText: skillIndex.indexText(),
  );

  // 监听联网搜索开关，动态启用/禁用 web 工具
  ref.listen<bool>(webSearchEnabledProvider, (prev, enabled) {
    if (enabled) {
      registry.enable('web_search');
      registry.enable('web_fetch');
      debugPrint('[AgentInit:D] web search tools ENABLED');
    } else {
      registry.disable('web_search');
      registry.disable('web_fetch');
      debugPrint('[AgentInit:D] web search tools DISABLED');
    }
  });

  // 监听深度思考开关
  ref.listen<bool>(deepThinkingEnabledProvider, (prev, enabled) {
    if (enabled) {
      provider.setThinking('enabled');
      provider.setReasoningEffort('max');
      debugPrint('[AgentInit:D] thinking=DEEP (thinking=enabled reasoning_effort=max)');
    } else {
      provider.setThinking('enabled');
      provider.setReasoningEffort('low');
      debugPrint('[AgentInit:D] thinking=DEFAULT (thinking=enabled reasoning_effort=low)');
    }
  });

  // 确保 Provider 销毁时释放 Controller
  ref.onDispose(() {
    controller.dispose();
    debugPrint('[AgentInit:D] Controller disposed');
  });

  debugPrint('[AgentInit:D] AgentRuntime ready');
  return AgentRuntime(controller: controller, eventSink: eventSink, session: session);
});

/// Controller 运行状态——可被 Widget 监听。
final controllerStateProvider = StateProvider<agent.ControllerState>((ref) {
  return agent.ControllerState.idle;
});

/// 联网搜索开关。
final webSearchEnabledProvider = StateProvider<bool>((ref) => false);

/// 深度思考开关。
final deepThinkingEnabledProvider = StateProvider<bool>((ref) => false);

/// 对话消息历史。
final chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
  return ChatMessagesNotifier();
});

/// 扩展消息类型：携带额外元数据用于 UI 渲染。
/// 继承 agent.Message 的所有字段，增加 isToolCall/isToolResultCard 标记。
class ChatMessage extends agent.Message {
  final bool isToolCall;
  final bool isToolResultCard;

  const ChatMessage({
    required super.role,
    super.content = '',
    super.reasoningContent = '',
    super.toolCalls,
    this.isToolCall = false,
    this.isToolResultCard = false,
  });
}

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  ChatMessagesNotifier() : super([]);

  void addUser(String text) {
    state = [...state, ChatMessage(role: agent.Role.user, content: text)];
  }

  void addAssistant(String text, {String reasoning = ''}) {
    state = [...state, ChatMessage(
      role: agent.Role.assistant,
      content: text,
      reasoningContent: reasoning,
    )];
  }

  /// 添加系统通知消息（如 🧠 记忆提取结果）。
  void addNotice(String text) {
    state = [...state, ChatMessage(role: agent.Role.system, content: text)];
  }

  void updateLastAssistant(String text, {String reasoning = ''}) {
    if (state.isEmpty || state.last.role != agent.Role.assistant ||
        state.last.isToolCall || state.last.isToolResultCard) {
      state = [...state, ChatMessage(
        role: agent.Role.assistant,
        content: text,
        reasoningContent: reasoning,
      )];
      return;
    }
    final updated = [...state];
    final last = updated.last;
    final newReasoning = reasoning.isNotEmpty ? reasoning : last.reasoningContent;
    updated[updated.length - 1] = ChatMessage(
      role: agent.Role.assistant,
      content: last.content + text,
      reasoningContent: newReasoning,
    );
    state = updated;
  }

  /// 替换最后一条 AI 消息（用于流式合并场景，不追加）。
  void replaceLastAssistant(String text) {
    if (state.isNotEmpty && state.last.role == agent.Role.assistant &&
        !state.last.isToolCall && !state.last.isToolResultCard) {
      final updated = [...state];
      updated[updated.length - 1] = ChatMessage(
        role: agent.Role.assistant,
        content: text,
      );
      state = updated;
    } else {
      state = [...state, ChatMessage(
        role: agent.Role.assistant,
        content: text,
      )];
    }
  }

  void addToolCall(String name) {
    state = [...state, ChatMessage(
      role: agent.Role.assistant,
      content: name,
      isToolCall: true,
    )];
  }

  void addToolResult(String name, String output) {
    state = [...state, ChatMessage(
      role: agent.Role.assistant,
      content: '[$name]\n$output',
      isToolResultCard: true,
    )];
  }

  void clear() => state = [];
}

// ═══════════════════════════════════════════════════════════════════
// Session 管理
// ═══════════════════════════════════════════════════════════════════

/// SessionStore 单例 Provider。
final sessionStoreProvider = FutureProvider<SessionStore>((ref) async {
  return SessionStore.create();
});

/// 当前活动会话 ID。
final activeSessionIdProvider = StateProvider<String?>((ref) => null);

/// 会话列表（按更新时间倒序）。
final sessionListProvider = FutureProvider<List<agent.Session>>((ref) async {
  final store = await ref.watch(sessionStoreProvider.future);
  return store.listAll();
});

/// 当前活动会话实例。
final activeSessionProvider = FutureProvider<agent.Session?>((ref) async {
  final id = ref.watch(activeSessionIdProvider);
  if (id == null) return null;
  final store = await ref.watch(sessionStoreProvider.future);
  return store.load(id);
});

/// 新建会话，返回 session ID。
final createSessionProvider = Provider<void Function(String? title)>((ref) {
  return (String? title) async {
    // 保存当前会话
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null) {
      await ref.read(saveCurrentSessionProvider)(currentId);
    }
    // 创建新 session
    final session = agent.Session(title: title ?? '新对话');
    final id = session.id;
    // 重置 runtime session
    final runtime = ref.read(agentRuntimeProvider);
    runtime.session.messages.clear();
    runtime.session.id = id;
    runtime.session.title = title ?? '新对话';
    // 更新 UI
    ref.read(activeSessionIdProvider.notifier).state = id;
    ref.read(chatMessagesProvider.notifier).clear();
    // 持久化
    final store = await ref.read(sessionStoreProvider.future);
    await store.save(session);
    ref.invalidate(sessionListProvider);
  };
});

/// 切换活动会话。
final switchSessionProvider = Provider<void Function(String id)>((ref) {
  return (String id) async {
    // 保存当前会话
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null) {
      await ref.read(saveCurrentSessionProvider)(currentId);
    }
    // 加载目标会话
    final store = await ref.read(sessionStoreProvider.future);
    final target = store.load(id);
    ref.read(activeSessionIdProvider.notifier).state = id;

    // 同步到 AgentRuntime.session + ChatMessages
    final runtime = ref.read(agentRuntimeProvider);
    final messagesNotifier = ref.read(chatMessagesProvider.notifier);
    messagesNotifier.clear();
    if (target != null) {
      // 替换 runtime 中的 session 消息
      runtime.session.messages.clear();
      runtime.session.messages.addAll(target.messages);
      runtime.session.id = target.id;
      runtime.session.title = target.title;
      // 加载到 ChatMessages（跳过空内容消息，避免渲染空框）
      for (final m in target.messages) {
        final text = m.content.trim();
        if (text.isEmpty) continue;
        if (m.role == agent.Role.user) {
          messagesNotifier.addUser(text);
        } else if (m.role == agent.Role.assistant) {
          messagesNotifier.addAssistant(text, reasoning: m.reasoningContent);
        }
      }
    }
  };
});

/// 保存当前会话（从 AgentRuntime 的 session 同步消息）。
final saveCurrentSessionProvider = Provider<Future<void> Function(String id)>((ref) {
  return (String id) async {
    try {
      final runtime = ref.read(agentRuntimeProvider);
      // 自动设置标题（取第一条用户消息的前 30 字）
      if (runtime.session.title.isEmpty || runtime.session.title == '新对话') {
        final firstUser = runtime.session.messages
            .where((m) => m.role == agent.Role.user)
            .firstOrNull;
        if (firstUser != null && firstUser.content.isNotEmpty) {
          final t = firstUser.content.replaceAll('\n', ' ').trim();
          runtime.session.title = t.length > 30 ? '${t.substring(0, 30)}...' : t;
        }
      }
      final store = await ref.read(sessionStoreProvider.future);
      await store.save(runtime.session);
      ref.invalidate(sessionListProvider);
    } catch (e) {
      // ignore
    }
  };
});

/// 删除会话。
final deleteSessionProvider = Provider<void Function(String id)>((ref) {
  return (String id) async {
    // 同步清空 UI 状态（失败也不影响用户体验）
    if (ref.read(activeSessionIdProvider) == id) {
      ref.read(activeSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).clear();
    }
    // 异步持久化
    final store = await ref.read(sessionStoreProvider.future);
    await store.delete(id);
    ref.invalidate(sessionListProvider);
  };
});

/// 重命名会话。
final renameSessionProvider = Provider<void Function(String id, String newTitle)>((ref) {
  return (String id, String newTitle) async {
    final store = await ref.read(sessionStoreProvider.future);
    final session = store.load(id);
    if (session != null) {
      session.title = newTitle;
      await store.save(session);
      ref.invalidate(sessionListProvider);
    }
  };
});

/// 当前活动会话标题（给 AppBar 用）。
final activeSessionTitleProvider = Provider<String>((ref) {
  final id = ref.watch(activeSessionIdProvider);
  if (id == null) return 'AI 助手';
  final sessions = ref.watch(sessionListProvider).valueOrNull ?? [];
  final active = sessions.where((s) => s.id == id).firstOrNull;
  return active?.title ?? 'AI 助手';
});
