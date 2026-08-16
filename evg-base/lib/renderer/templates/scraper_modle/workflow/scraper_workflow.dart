/// 爬虫生成器工作流状态机（v2 工程化重构）。
///
/// 定义 crawling → analyzing → questioning → generating → running → debugging → done 的完整状态流转。
/// v2 新增（Phase 1 harness 一体化）：
/// - **阶段时间戳/耗时**：`phaseTimeline` 供可视化与 Trace 消费
/// - **验收门槛 G1-G4**：阶段转换带前置条件，violation 拒绝转换 + 原因
/// - **日志快照（A18）**：`confirmCaptureDone()` 冻结快照 + 锁 WebView；`restartCapture()` 重抓
/// - **guardFlags + G5 门禁（A5/A10）**：假数据 warning → markDone 弹窗 → 用户放行/拒绝
/// - **阶段级回退（A14）**：`rollbackTo()` + 回退轨迹；回退后前进重过验收
/// - **refining 循环（A16）**：done 非终态，`feedbackTriggered()` → debugging
/// - **调试轮次（A15）**：连续 3 轮失败 → warning（提示换策略），非 5 轮硬预算
/// - **awaitingUserConfirm 子状态**：弹窗期间事件流不丢
library scraper_workflow;

import 'dart:async';

// ═══════ 工作流状态 ═══════

/// 爬虫生成器的阶段。
enum ScraperPhase {
  /// 等待用户在 WebView 中操作。
  idle,

  /// 用户正在 WebView 中浏览目标网站，后台自动抓包。
  capturing,

  /// AI 正在分析捕获到的 HTTP 请求日志。
  analyzing,

  /// AI 正在向用户追问以明确需求。
  questioning,

  /// AI 正在生成 Python 爬虫代码。
  generating,

  /// 正在执行生成的 Python 爬虫。
  running,

  /// 执行失败，AI 正在分析错误并修改代码。
  debugging,

  /// 爬虫执行成功，等待导出。
  done,

  /// 无法继续，需要用户重新演示或决策。
  failed,
}

// ═══════ HTTP 请求记录 ═══════

/// 单个 HTTP 请求记录。
class HttpRequestLog {
  final DateTime timestamp;
  final String method; // GET / POST / PUT / DELETE / ...
  final String url;
  final Map<String, String>? headers;
  final String? body;

  /// 响应体（仅 CDP 主方案对 application/json 响应捕获，≤32KB）。
  /// 供 AI 推断 schema 时优先使用（样本更准）。
  final String? responseBody;

  const HttpRequestLog({
    required this.timestamp,
    required this.method,
    required this.url,
    this.headers,
    this.body,
    this.responseBody,
  });

  /// 从 JS 注入捕获的 JSON 反序列化。
  factory HttpRequestLog.fromJson(Map<String, dynamic> json) {
    return HttpRequestLog(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      url: json['url'] as String? ?? '',
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      body: json['body'] as String?,
      responseBody: json['responseBody'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'method': method,
        'url': url,
        if (headers != null) 'headers': headers,
        if (body != null) 'body': body,
        if (responseBody != null) 'responseBody': responseBody,
      };

  /// 格式化为 AI 可读的日志行。
  String toLogLine() {
    final buf = StringBuffer();
    buf.writeln(
        '[${timestamp.toString().substring(0, 19)}] $method  $url');
    if (headers != null && headers!.isNotEmpty) {
      buf.writeln('  Headers: $headers');
    }
    if (body != null && body!.isNotEmpty) {
      buf.writeln('  Body: $body');
    }
    if (responseBody != null && responseBody!.isNotEmpty) {
      buf.writeln('  ResponseBody (${responseBody!.length} chars): '
          '${responseBody!.length > 512 ? '${responseBody!.substring(0, 512)}…' : responseBody}');
    }
    return buf.toString();
  }

  /// 生成 LLM 友好的日志摘要（响应体优先，提升 AI 推断字段准确率）。
  String toAiSummary() {
    final ts = timestamp.toString().substring(0, 19);
    final h = headers?.entries
            .where((e) =>
                ['authorization', 'cookie', 'x-api-key', 'content-type']
                    .contains(e.key.toLowerCase()))
            .map((e) => '  ${e.key}: ${e.value}')
            .join('\n') ??
        '';
    final b = body != null && body!.isNotEmpty
        ? '\n  RequestBody (${body!.length} chars): ${body!.length > 1024 ? '${body!.substring(0, 1024)}…' : body}'
        : '';
    final rb = responseBody != null && responseBody!.isNotEmpty
        ? '\n  ResponseBody (${responseBody!.length} chars): ${responseBody!.length > 2048 ? '${responseBody!.substring(0, 2048)}…' : responseBody}'
        : '';
    return '[$ts] $method $url\n$h$b$rb';
  }
}

// ═══════ 阶段时间线条目 ═══════

/// 一次阶段转换的时间线记录（供 Stepper 可视化与 Trace 消费）。
class PhaseTimelineEntry {
  final ScraperPhase phase;
  final DateTime enteredAt;
  final Duration elapsed; // 该阶段停留时长
  final String? note; // 转换说明（如验收拒绝原因）

  const PhaseTimelineEntry({
    required this.phase,
    required this.enteredAt,
    this.elapsed = Duration.zero,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'enteredAt': enteredAt.toIso8601String(),
        'elapsedMs': elapsed.inMilliseconds,
        if (note != null) 'note': note,
      };
}

// ═══════ 守卫标记 ═══════

/// guardFlags 的键。
class GuardFlags {
  /// 疑似硬编码假数据（lintScraperCode warning 命中）。
  static const suspectedFakeData = 'suspectedFakeData';
}

/// 无参回调（纯 Dart，避免依赖 Flutter 的 VoidCallback）。
typedef WorkflowCallback = void Function();

// ═══════ 工作流控制器 ═══════

/// 爬虫生成器工作流控制器（纯 Dart，无 Flutter 依赖）。
///
/// 管理阶段转换、请求日志累积、调试计数、快照、守卫标记与 Python 输出。
/// 通过 [onChanged] 回调通知 UI 层重建（由父 Widget 在 initState 中设置）。
class ScraperWorkflow {
  ScraperPhase _phase = ScraperPhase.idle;
  final List<HttpRequestLog> _logs = [];
  int _debugCount = 0;

  /// refining 迭代轮次（A19：不设硬上限，仅展示轮次）。
  int _refineCount = 0;

  /// 连续失败计数（A15：连续 3 轮失败 → warning）。
  int _consecutiveFailures = 0;
  bool _warningSent3 = false;

  /// 阶段时间线。
  final List<PhaseTimelineEntry> _timeline = [];
  DateTime? _phaseEnteredAt;

  /// 回退历史（A14：UI 可见回退轨迹）。
  final List<ScraperPhase> _rollbackHistory = [];

  /// 守卫标记集合（A5：suspectedFakeData 等）。
  final Set<String> _guardFlags = {};

  /// 是否处于等待用户确认子状态（弹窗期间）。
  bool _awaitingUserConfirm = false;

  // ── 日志快照（A18）──
  final List<HttpRequestLog> _snapshot = [];
  bool _snapshotFrozen = false;

  /// 旧版 5 轮预算常量（保留兼容；v2 实际防自循环机制是 [debugWarningThreshold]）。
  static const int maxDebugRounds = 5;

  /// v2 调试轮次阈值（A15）：连续失败达到此数 → warning 提示换策略。
  static const int debugWarningThreshold = 3;

  String _pythonCode = '';
  String _pythonOutput = '';
  String _errorMessage = '';

  /// 终端待执行的命令（AI 通过 run_terminal_command 工具设置）。
  String _pendingTerminalCommand = '';

  /// 终端命令执行后的输出（回传给 AI 的下一次对话）。
  String _terminalResult = '';

  /// 是否有待执行的终端命令。
  bool get hasPendingTerminalCommand => _pendingTerminalCommand.isNotEmpty;

  /// 获取并清除待执行的终端命令。
  String consumeTerminalCommand() {
    final cmd = _pendingTerminalCommand;
    _pendingTerminalCommand = '';
    return cmd;
  }

  /// 设置终端命令（由 AI Tool 调用）。
  void setTerminalCommand(String cmd) {
    _pendingTerminalCommand = cmd;
    _log('📟 终端命令已入队: $cmd');
    _notify();
  }

  /// 设置终端执行结果（回传给 AI）。
  void setTerminalResult(String result) {
    _terminalResult = result;
    _log('📟 终端结果已设置 (${result.length} chars)');
    _notify();
  }

  /// 获取并清除终端结果。
  String consumeTerminalResult() {
    final r = _terminalResult;
    _terminalResult = '';
    return r;
  }

  /// 状态变更回调——由 UI 层设置以触发 [setState]。
  void Function()? onChanged;

  /// **G5 门禁弹窗回调（A10）**：返回用户是否放行。
  /// 参数：守卫原因、AI 澄清文本。
  Future<bool> Function(String reason, String aiClarification)?
      onUserConfirmRequest;

  /// **WebView 锁定回调（A18）**：快照冻结后由 UI 层锁定 WebView。
  WorkflowCallback? onWebViewLock;

  /// **重抓确认回调（A18）**：用户确认后由 UI 层回首页并重启抓取。
  WorkflowCallback? onRestartCapture;

  /// **3 轮 warning 回调（A15）**：提示 AI 换策略。
  void Function(String warning)? onWarning;

  final List<void Function()> _listeners = [];

  /// 添加状态变化监听器（不覆盖 [onChanged]）。
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 移除监听器。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  // ── 属性 ──

  ScraperPhase get phase => _phase;
  List<HttpRequestLog> get logs => List.unmodifiable(_logs);
  List<HttpRequestLog> get snapshot => List.unmodifiable(_snapshot);
  bool get snapshotFrozen => _snapshotFrozen;
  int get debugCount => _debugCount;
  int get refineCount => _refineCount;
  int get consecutiveFailures => _consecutiveFailures;
  bool get warningSent3 => _warningSent3;
  bool get awaitingUserConfirm => _awaitingUserConfirm;

  /// 兼容旧 UI：5 轮预算剩余（v2 不再硬性触发 failed，仅展示）。
  int get debugRemaining => maxDebugRounds - _debugCount;
  bool get canDebug => true; // v2：不再用 5 轮硬上限阻断调试

  String get pythonCode => _pythonCode;
  String get pythonOutput => _pythonOutput;
  String get errorMessage => _errorMessage;

  List<PhaseTimelineEntry> get timeline => List.unmodifiable(_timeline);
  List<ScraperPhase> get rollbackHistory =>
      List.unmodifiable(_rollbackHistory);

  /// 守卫标记只读视图。
  Set<String> get guardFlags => Set.unmodifiable(_guardFlags);

  /// 是否有疑似假数据标记（G5 门禁判断用）。
  bool get suspectedFakeData =>
      _guardFlags.contains(GuardFlags.suspectedFakeData);

  /// 是否有请求日志可供分析（G1 门槛）。
  bool get hasLogs => _logs.isNotEmpty;

  /// 是否有已冻结快照。
  bool get hasSnapshot => _snapshot.isNotEmpty;

  /// 当前阶段是否允许用户交互。
  bool get isUserInteractive =>
      _phase == ScraperPhase.idle || _phase == ScraperPhase.capturing;

  /// 当前阶段是否允许 AI 交互。
  bool get isAiInteractive =>
      _phase == ScraperPhase.questioning ||
      _phase == ScraperPhase.done ||
      _phase == ScraperPhase.failed;

  // ── 内部通知 ──

  void _notify() {
    onChanged?.call();
    for (final l in _listeners) {
      l();
    }
  }

  /// 记录阶段进入时间（时间线）。
  void _enterPhase(ScraperPhase phase, {String? note}) {
    final now = DateTime.now();
    final prev = _phaseEnteredAt;
    if (prev != null && _timeline.isNotEmpty) {
      final last = _timeline.removeLast();
      _timeline.add(PhaseTimelineEntry(
        phase: last.phase,
        enteredAt: last.enteredAt,
        elapsed: now.difference(last.enteredAt),
        note: last.note,
      ));
    }
    _phase = phase;
    _phaseEnteredAt = now;
    _timeline.add(PhaseTimelineEntry(
      phase: phase,
      enteredAt: now,
      note: note,
    ));
    _log('▶️ → $phase${note != null ? ' ($note)' : ''}');
  }

  // ── 守卫标记 ──

  /// 设置守卫标记（lint warning 等）。
  void setGuardFlag(String flag) {
    _guardFlags.add(flag);
    _notify();
  }

  /// 清除守卫标记（用户放行 / AI 修正后）。
  void clearGuardFlag(String flag) {
    _guardFlags.remove(flag);
    _notify();
  }

  // ── 阶段转换（带验收门槛 G1-G4）──

  /// G1：开始抓包。
  bool startCapturing() {
    if (_phase != ScraperPhase.idle) {
      _log('⚠ 非 idle 状态下忽略 startCapturing');
      return false;
    }
    _enterPhase(ScraperPhase.capturing);
    _notify();
    return true;
  }

  /// G1：开始分析。门槛：已有日志或快照。
  bool startAnalyzing() {
    if (_phase != ScraperPhase.capturing &&
        _phase != ScraperPhase.questioning) {
      _log('⚠ 非 capturing/questioning 状态下忽略 startAnalyzing');
      return false;
    }
    if (!hasLogs && !hasSnapshot) {
      _log('⚠ G1 门槛：无请求日志，拒绝 analyzing');
      return false;
    }
    _enterPhase(ScraperPhase.analyzing);
    _notify();
    return true;
  }

  /// G2：开始生成。门槛：analyzing 已完成（或直接授权）。
  bool startGenerating() {
    if (_phase != ScraperPhase.analyzing &&
        _phase != ScraperPhase.questioning &&
        _phase != ScraperPhase.debugging) {
      _log('⚠ 非 analyzing/questioning/debugging 状态下忽略 startGenerating');
      return false;
    }
    _enterPhase(ScraperPhase.generating);
    _notify();
    return true;
  }

  /// G3：开始运行。门槛：已生成代码。
  bool startRunning() {
    if (_phase != ScraperPhase.generating &&
        _phase != ScraperPhase.debugging) {
      _log('⚠ 非 generating/debugging 状态下忽略 startRunning');
      return false;
    }
    _enterPhase(ScraperPhase.running);
    _notify();
    return true;
  }

  /// G4：进入追问（AI 信息缺失时主动询问）。
  void startQuestioning() {
    _enterPhase(ScraperPhase.questioning);
    _notify();
  }

  /// 进入调试（R1/R2/R3 汇聚点；A15 连续 3 轮 warning）。
  void startDebugging() {
    _debugCount++;
    _consecutiveFailures++;
    if (_consecutiveFailures >= debugWarningThreshold && !_warningSent3) {
      _warningSent3 = true;
      final warn = '连续 ${debugWarningThreshold} 轮调试仍失败。'
          '请换策略：使用网页探索能力探索用户未暴露的相关接口，'
          '或向用户询问目标数据的具体形态，避免在同一方案上自循环。';
      _log('⚠️ $warn');
      onWarning?.call(warn);
    }
    _enterPhase(ScraperPhase.debugging,
        note: '第 $_debugCount 轮（连续失败 $_consecutiveFailures）');
    _notify();
  }

  /// 调试成功 → 重置连续失败计数。
  void resetDebugLoop() {
    _consecutiveFailures = 0;
    _warningSent3 = false;
    _notify();
  }

  /// **G5 门禁（A5/A10）**：请求完成。若存在假数据标记 → 弹窗用户裁决。
  ///
  /// [aiClarification]：AI 澄清文本（如"该站是静态 JSON 页，无 API 日志"）。
  /// 返回是否已进入 done（可能因弹窗异步而先返回 false，裁决后回调通知）。
  Future<bool> requestDone({String aiClarification = ''}) async {
    if (suspectedFakeData) {
      _awaitingUserConfirm = true;
      _notify();
      final reason = '检测到疑似硬编码假数据：'
          '（无网络请求却输出数据 / 数据为字面量直出 / URL 与捕获日志无交集 / 含占位符数据）。'
          '请确认 AI 的澄清说明是否可信。';
      final approved = await onUserConfirmRequest?.call(reason, aiClarification) ??
          false; // 无回调时默认拒绝（fail-closed）
      _awaitingUserConfirm = false;
      if (approved) {
        clearGuardFlag(GuardFlags.suspectedFakeData);
        _completeDone();
        return true;
      }
      // 用户拒绝 → 转 debugging，AI 必须修正为真实抓取
      _log('⚠ G5 用户拒绝放行 → debugging');
      startDebugging();
      return false;
    }
    _completeDone();
    return true;
  }

  /// 无门禁直接完成（内部）。
  void _completeDone() {
    if (_phase == ScraperPhase.done) return;
    _debugCount = 0;
    _consecutiveFailures = 0;
    _warningSent3 = false;
    _enterPhase(ScraperPhase.done);
    _notify();
  }

  /// 兼容旧调用：无门禁直接 done（旧代码路径；新路径请用 [requestDone]）。
  void markDone() {
    _completeDone();
  }

  /// 标记失败（无法继续）。
  void markFailed(String reason) {
    _enterPhase(ScraperPhase.failed, note: reason);
    _errorMessage = reason;
    _notify();
  }

  /// **阶段级回退（A14）**：AI 自主回退到之前已完成阶段。
  ///
  /// 回退后记录轨迹；重新前进时必须重过该阶段验收门槛。
  bool rollbackTo(ScraperPhase target) {
    final order = ScraperPhase.values;
    final curIdx = order.indexOf(_phase);
    final tgtIdx = order.indexOf(target);
    if (tgtIdx < 0 || tgtIdx >= curIdx) {
      _log('⚠ 回退目标 $target 非已完成阶段');
      return false;
    }
    _rollbackHistory.add(_phase);
    _enterPhase(target, note: '回退（来自 $curIdx → $tgtIdx）');
    _notify();
    return true;
  }

  /// **refining 循环（A16）**：done 后收到用户反馈 → 进入 debugging 处理反馈。
  ///
  /// 每次反馈迭代 [refineCount] +1（A19：不设硬上限，仅展示轮次）。
  void feedbackTriggered() {
    if (_phase != ScraperPhase.done) {
      _log('⚠ 非 done 状态忽略 feedbackTriggered');
      return;
    }
    _refineCount++;
    _log('🔄 用户反馈 → refining（第 $_refineCount 轮，debugging 路线，不重新抓包）');
    _enterPhase(ScraperPhase.debugging,
        note: 'refining 第 $_refineCount 轮（反馈驱动，保留快照与产物）');
    _notify();
  }

  /// **日志快照（A18）**：用户点击「确认操作完毕」→ 冻结快照 + 锁 WebView。
  void confirmCaptureDone() {
    if (_snapshotFrozen) return;
    _snapshot
      ..clear()
      ..addAll(_logs);
    _snapshotFrozen = true;
    _log('📸 日志快照已冻结（${_snapshot.length} 条）');
    onWebViewLock?.call();
    _notify();
  }

  /// **重抓（A18）**：AI ask 需重新走一遍 → 确认框 → 同意后回首页重启抓取。
  ///
  /// 由 UI 层在确认后调用；清空日志/快照、回到 capturing。
  void restartCapture() {
    _logs.clear();
    _snapshot.clear();
    _snapshotFrozen = false;
    _guardFlags.clear();
    _rollbackHistory.clear();
    _debugCount = 0;
    _refineCount = 0;
    _consecutiveFailures = 0;
    _warningSent3 = false;
    _enterPhase(ScraperPhase.capturing, note: '重启抓取');
    onRestartCapture?.call();
    _notify();
  }

  /// 重置整个工作流（用户手动重置 / 新会话）。
  void reset() {
    _logs.clear();
    _snapshot.clear();
    _snapshotFrozen = false;
    _debugCount = 0;
    _refineCount = 0;
    _consecutiveFailures = 0;
    _warningSent3 = false;
    _pythonCode = '';
    _pythonOutput = '';
    _errorMessage = '';
    _pendingTerminalCommand = '';
    _terminalResult = '';
    _guardFlags.clear();
    _rollbackHistory.clear();
    _timeline.clear();
    _phaseEnteredAt = null;
    _awaitingUserConfirm = false;
    _enterPhase(ScraperPhase.idle, note: '重置');
    _notify();
  }

  // ── 日志操作 ──

  /// 添加一条 HTTP 请求日志（快照冻结后不再追加到快照，但保留活动日志）。
  void addLog(HttpRequestLog log) {
    _logs.add(log);
    _log('📋 #${_logs.length} $log');
    _notify();
  }

  /// 批量添加日志。
  void addLogs(List<HttpRequestLog> logs) {
    _logs.addAll(logs);
    _log('📋 批量添加 ${logs.length} 条日志（总计 ${_logs.length}）');
    _notify();
  }

  /// 清空日志（重抓前）。
  void clearLogs() {
    _logs.clear();
    _snapshot.clear();
    _snapshotFrozen = false;
    _log('🗑 日志已清空');
    _notify();
  }

  /// 获取所有日志的 AI 友好摘要（快照优先：AI 读冻结快照，A18）。
  String requestLogsSummary() {
    final src = _snapshotFrozen ? _snapshot : _logs;
    if (src.isEmpty) return '(暂无请求日志)';
    final buf = StringBuffer();
    buf.writeln('## 用户操作捕获的 HTTP 请求日志（${src.length} 条'
        '${_snapshotFrozen ? ' · 已冻结快照' : ''}）\n');
    for (var i = 0; i < src.length; i++) {
      buf.writeln('### 请求 #${i + 1}');
      buf.writeln(src[i].toAiSummary());
      buf.writeln();
    }
    return buf.toString();
  }

  // ── Python 代码 ──

  void setPythonCode(String code) {
    _pythonCode = code;
    _log('🐍 Python 代码已更新 (${code.length} chars)');
    _notify();
  }

  void setPythonOutput(String output) {
    _pythonOutput = output;
    final preview = output.length > 300 ? '${output.substring(0, 300)}...' : output;
    _log('📤 Python 输出: $preview');
    _notify();
  }

  void appendPythonOutput(String chunk) {
    _pythonOutput += chunk;
    _notify();
  }

  /// 将最新的错误信息写入调试上下文。
  void setLastError(String error) {
    _errorMessage = error;
    _log('⚠ 错误: $error');
    _notify();
  }

  // ── 序列化 ──

  Map<String, dynamic> toJson() => {
        'phase': _phase.name,
        'debugCount': _debugCount,
        'refineCount': _refineCount,
        'consecutiveFailures': _consecutiveFailures,
        'snapshotFrozen': _snapshotFrozen,
        'guardFlags': _guardFlags.toList(),
        'logs': _logs.map((l) => l.toJson()).toList(),
        'snapshot': _snapshot.map((l) => l.toJson()).toList(),
        'timeline': _timeline.map((t) => t.toJson()).toList(),
        'rollbackHistory': _rollbackHistory.map((p) => p.name).toList(),
        'pythonCode': _pythonCode,
        'errorMessage': _errorMessage,
      };

  /// 释放资源——清空回调引用。
  void dispose() {
    _log('dispose');
    onChanged = null;
    onUserConfirmRequest = null;
    onWebViewLock = null;
    onRestartCapture = null;
    onWarning = null;
  }
}

// ── 调试日志（仅在 debug 模式下输出，release 自动消除） ──
void _log(String msg) {
  assert(() {
    print('[ScraperWorkflow] $msg');
    return true;
  }());
}
