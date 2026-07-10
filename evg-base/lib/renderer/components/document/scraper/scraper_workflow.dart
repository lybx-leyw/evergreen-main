/// 爬虫生成器工作流状态机。
///
/// 定义 crawling → analyzing → questioning → generating → running → debugging → done 的完整状态流转。
/// 最多 5 轮自动调试，超限后返回 failed 请求用户重新演示。
library scraper_workflow;

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

  /// 超过 5 轮调试上限，需要用户重新演示。
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

  const HttpRequestLog({
    required this.timestamp,
    required this.method,
    required this.url,
    this.headers,
    this.body,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'method': method,
        'url': url,
        if (headers != null) 'headers': headers,
        if (body != null) 'body': body,
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
    return buf.toString();
  }

  /// 生成 LLM 友好的日志摘要。
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
        ? '\n  Body (${body!.length} chars): $body'
        : '';
    return '[$ts] $method $url\n$h$b';
  }
}

// ═══════ 工作流控制器 ═══════

/// 爬虫生成器工作流控制器（纯 Dart，无 Flutter 依赖）。
///
/// 管理阶段转换、请求日志累积、调试计数和 Python 输出。
/// 通过 [onChanged] 回调通知 UI 层重建（由父 Widget 在 initState 中设置）。
class ScraperWorkflow {
  ScraperPhase _phase = ScraperPhase.idle;
  final List<HttpRequestLog> _logs = [];
  int _debugCount = 0;
  static const int maxDebugRounds = 5;

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
  int get debugCount => _debugCount;
  int get debugRemaining => maxDebugRounds - _debugCount;
  bool get canDebug => _debugCount < maxDebugRounds;

  String get pythonCode => _pythonCode;
  String get pythonOutput => _pythonOutput;
  String get errorMessage => _errorMessage;

  /// 是否有请求日志可供分析。
  bool get hasLogs => _logs.isNotEmpty;

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

  // ── 阶段转换 ──

  void startCapturing() {
    if (_phase != ScraperPhase.idle) {
      _log('⚠ 非 idle 状态下忽略 startCapturing');
      return;
    }
    _phase = ScraperPhase.capturing;
    _log('▶️ idle → capturing');
    _notify();
  }

  void startAnalyzing() {
    if (_phase != ScraperPhase.capturing) {
      _log('⚠ 非 capturing 状态下忽略 startAnalyzing');
      return;
    }
    _phase = ScraperPhase.analyzing;
    _log('▶️ capturing → analyzing');
    _notify();
  }

  void startQuestioning() {
    _phase = ScraperPhase.questioning;
    _log('▶️ → questioning');
    _notify();
  }

  void startGenerating() {
    _phase = ScraperPhase.generating;
    _log('▶️ → generating');
    _notify();
  }

  void startRunning() {
    _phase = ScraperPhase.running;
    _log('▶️ → running');
    _notify();
  }

  void startDebugging() {
    _debugCount++;
    if (_debugCount > maxDebugRounds) {
      _phase = ScraperPhase.failed;
      _errorMessage = '自动调试已达上限 ($maxDebugRounds 轮)，请重新演示操作流程。';
      _log('❌ 超过 $maxDebugRounds 轮调试上限 → failed');
      _notify();
    } else {
      _phase = ScraperPhase.debugging;
      _log('🔄 → debugging (第 $_debugCount/$maxDebugRounds 轮)');
      _notify();
    }
  }

  void markDone() {
    _phase = ScraperPhase.done;
    _debugCount = 0;
    _log('✅ → done');
    _notify();
  }

  void markFailed(String reason) {
    _phase = ScraperPhase.failed;
    _errorMessage = reason;
    _log('❌ → failed: $reason');
    _notify();
  }

  void reset() {
    _phase = ScraperPhase.idle;
    _logs.clear();
    _debugCount = 0;
    _pythonCode = '';
    _pythonOutput = '';
    _errorMessage = '';
    _pendingTerminalCommand = '';
    _terminalResult = '';
    _log('🔄 重置 → idle');
    _notify();
  }

  // ── 日志操作 ──

  /// 添加一条 HTTP 请求日志。
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

  /// 清空日志。
  void clearLogs() {
    _logs.clear();
    _log('🗑 日志已清空');
    _notify();
  }

  /// 获取所有日志的 AI 友好摘要。
  String requestLogsSummary() {
    if (_logs.isEmpty) return '(暂无请求日志)';
    final buf = StringBuffer();
    buf.writeln('## 用户操作捕获的 HTTP 请求日志（${_logs.length} 条）\n');
    for (var i = 0; i < _logs.length; i++) {
      buf.writeln('### 请求 #${i + 1}');
      buf.writeln(_logs[i].toAiSummary());
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
        'logs': _logs.map((l) => l.toJson()).toList(),
        'pythonCode': _pythonCode,
        'errorMessage': _errorMessage,
      };

  /// 释放资源——清空回调引用。
  void dispose() {
    _log('dispose');
    onChanged = null;
  }
}

// ── 调试日志（仅在 debug 模式下输出，release 自动消除） ──
void _log(String msg) {
  assert(() {
    print('[ScraperWorkflow] $msg');
    return true;
  }());
}
