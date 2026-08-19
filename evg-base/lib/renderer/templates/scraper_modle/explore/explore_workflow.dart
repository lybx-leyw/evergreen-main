/// AI 探索模式工作流状态机（Phase 4 · D1-D9）。
///
/// 与定向抓取（[ScraperWorkflow]）**并列**的第二个状态机（D9：不同工作流 +
/// 不同 harness 约束）：
/// - 流程：idle → exploring → categorizing → confirming → building → registering → done/failed
/// - 守卫：GET-only、同域、授权范围（Scope）、页数/请求数上限、导航节流
///   （D7：20 页 / 50 请求 / 1s，可配置）、空转熔断（P1-1：连续 N 次导航
///   无新页面 → onStallDetected + 重复导航被拒，新页面自动恢复）
/// - 工具白名单：按阶段切换（D9 harness 约束，见 [exploreToolAllowedForPhase]）
///
/// 纯 Dart 无 Flutter 依赖，可独立单测（与 ScraperWorkflow 同规约）。
library explore_workflow;

import 'explore_scope.dart';

// ═══════ 探索阶段 ═══════

/// 探索模式的阶段。
enum ExplorePhase {
  /// 等待用户点击「开始探索」（提示先登录）。
  idle,

  /// AI 正在循环：枚举当前页链接 → GET 导航 → 读捕获日志。
  exploring,

  /// AI 正在把探索到的 GET 接口归类为候选数据源。
  categorizing,

  /// 候选数据源已呈现，等待用户多选确认（可改名）。
  confirming,

  /// 用户确认后，AI 逐源构建 data-{name} 插件。
  building,

  /// AI 批量注册 + orch.get 验证。
  registering,

  /// 批量注册完成。
  done,

  /// 无法继续（上限触达无产出 / 注册全失败等）。
  failed,
}

// ═══════ 候选数据源 ═══════

/// 候选字段（AI 归类产物，D3）。
class CandidateField {
  final String name;
  final String type; // string / number / boolean / date
  final String? description;

  /// 证据（P0-2）：来源请求日志 id（list_captured_requests 返回的证据 id）。
  final String? sourceLogId;

  /// 证据（P0-2）：响应 JSON 字段路径（如 `$.data[0].courseName`）。
  final String? sourceJsonPath;

  const CandidateField({
    required this.name,
    required this.type,
    this.description,
    this.sourceLogId,
    this.sourceJsonPath,
  });

  factory CandidateField.fromJson(Map<String, dynamic> json) => CandidateField(
        name: (json['name'] as String? ?? '').trim(),
        type: json['type'] as String? ?? 'string',
        description: json['description'] as String?,
        sourceLogId: _trimToNull(json['sourceLogId'] as String?),
        sourceJsonPath: _trimToNull(json['sourceJsonPath'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (sourceLogId != null) 'sourceLogId': sourceLogId,
        if (sourceJsonPath != null) 'sourceJsonPath': sourceJsonPath,
      };
}

/// 空串归一为 null（证据字段可选：缺省/空串等价于未提供）。
String? _trimToNull(String? s) {
  final t = (s ?? '').trim();
  return t.isEmpty ? null : t;
}

/// 归一 method：AI 给定值透传（大写），空则默认 GET。
String _normalizeMethod(String? raw) {
  final t = (raw ?? '').trim();
  return t.isEmpty ? 'GET' : t.toUpperCase();
}

/// 危险 method 字样集合（编辑/删除等破坏性操作——提示 AI 避开）。
const Set<String> _dangerousMethodHints = {
  'DELETE', 'PUT', 'PATCH',
};

/// 校验 method 是否含危险操作字样。
///
/// 返回 null = 安全；否则为提示文案（不硬阻断，仅提示 AI 避开）。
String? dangerousMethodHint(String method) {
  final m = method.trim().toUpperCase();
  if (_dangerousMethodHints.contains(m)) {
    return 'method "$m" 属于编辑/删除类危险操作，'
        '探索模式只应呈现只读查询类数据源，请改用 GET 或只读查询接口';
  }
  // 含"编辑/删除/更新/删除"等中文危险字样也提示
  const cnDangerous = ['编辑', '删除', '更新', '写入', '修改', '提交'];
  for (final w in cnDangerous) {
    if (m.contains(w)) {
      return 'method "$m" 含危险操作字样「$w」，请改用只读查询类接口';
    }
  }
  return null;
}

/// 候选数据源（D3 归类产物；D4 用户多选；D8 每源一个 data-{name}）。
///
/// Phase 4 消费 Phase 3 定义的共享接口形态（§九 `CandidateDataSource`）。
class CandidateDataSource {
  final String name; // 英文标识 → 插件目录 data-{name}
  final String displayName; // 展示名（可被用户在确认弹窗中修改）
  final String category; // 细粒度归类（如 "课程列表"，由 AI 自主描述）
  final String url; // 数据 URL
  final String method; // 请求方法（AI 自主给定，默认 GET；不强制）
  final List<CandidateField> fields;

  /// 证据（P0-2）：url 对应的请求日志 id（可选，非强制）。
  final String? sourceLogId;

  const CandidateDataSource({
    required this.name,
    required this.displayName,
    required this.category,
    required this.url,
    this.method = 'GET',
    this.fields = const [],
    this.sourceLogId,
  });

  /// ⚠️ 改名复制时必须携带证据字段（用户在弹窗中改名后证据不丢失）。
  CandidateDataSource copyWith({String? name, String? displayName}) =>
      CandidateDataSource(
        name: name ?? this.name,
        displayName: displayName ?? this.displayName,
        category: category,
        url: url,
        method: method,
        fields: fields,
        sourceLogId: sourceLogId,
      );

  /// 从 AI 给出的 JSON 解析（method 透传 AI 给定值，默认 GET；字段过滤非法项）。
  factory CandidateDataSource.fromJson(Map<String, dynamic> json) =>
      CandidateDataSource(
        name: (json['name'] as String? ?? '').trim(),
        displayName: (json['displayName'] as String? ?? '').trim(),
        category: (json['category'] as String? ?? '').trim(),
        url: (json['url'] as String? ?? '').trim(),
        method: _normalizeMethod(json['method'] as String?),
        fields: (json['fields'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CandidateField.fromJson)
            .where((f) => f.name.isNotEmpty)
            .toList(),
        sourceLogId: _trimToNull(json['sourceLogId'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'category': category,
        'url': url,
        'method': method,
        'fields': fields.map((f) => f.toJson()).toList(),
        if (sourceLogId != null) 'sourceLogId': sourceLogId,
      };
}

// ═══════ 上限/节流配置 ═══════

/// 探索守卫上限（D7：同域 + 20 页 + 50 请求 + 1s 节流，全部可配置）。
///
/// P1-1 空转熔断：[stallThreshold] 为触发阈值（默认 3：连续 N 次导航无新
/// 页面即触发），[stallWindow] 为观察窗口大小（默认 6）。窗口须 ≥ 阈值，
/// 否则熔断永不触发（配置误用，文档注明）。
class ExploreLimits {
  final int maxPages;
  final int maxRequests;
  final Duration minNavigateInterval;
  final bool sameDomainOnly;

  /// 空转熔断阈值：观察窗口内导航数达到该值且全部无新页面 → 触发熔断。
  final int stallThreshold;

  /// 空转熔断观察窗口：最多回看最近 N 次导航的新页面产出。
  final int stallWindow;

  /// Phase 10：归类前最小探索页数（去重）。0 = 不设页数门槛。
  final int minPagesForCategorize;

  /// Phase 10：归类前最小探索请求数。0 = 不设请求门槛。
  final int minRequestsForCategorize;

  const ExploreLimits({
    this.maxPages = 20,
    this.maxRequests = 50,
    this.minNavigateInterval = const Duration(seconds: 1),
    this.sameDomainOnly = true,
    this.stallThreshold = 3,
    this.stallWindow = 6,
    this.minPagesForCategorize = 1,
    this.minRequestsForCategorize = 0,
  });
}

// ═══════ 守卫纯函数 ═══════

/// 校验探索导航 URL（D2 GET-only + D7 同域）。
///
/// 返回 null = 放行；否则为拒绝原因。
/// [baseHost] 为空时不校验域名（首次导航锁定域名）。
String? validateExploreUrl(String url, {String? baseHost}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return 'URL 为空';
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return 'URL 无法解析';
  final scheme = (uri.scheme.isEmpty ? 'http' : uri.scheme).toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return '仅允许 http/https（GET 探索）: "${uri.scheme}"';
  }
  if (uri.host.isEmpty) return 'URL 缺少主机名';
  if (baseHost != null && baseHost.isNotEmpty) {
    final host = uri.host.toLowerCase();
    final base = baseHost.toLowerCase();
    if (!_sameHost(host, base)) {
      return '非同域导航被拒（当前域: $base，目标: $host）';
    }
  }
  return null;
}

/// 同域判定：精确相等或互为子域（含跨端口）。
bool _sameHost(String a, String b) =>
    a == b || a.endsWith('.$b') || b.endsWith('.$a');

/// 校验数据源名称（→ 插件目录 data-{name}，D8）。
///
/// 返回 null = 合法；否则为拒绝原因。
String? sanitizeSourceName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '名称不能为空';
  final cleaned = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (cleaned != trimmed) {
    return '名称含非法字符（仅允许字母/数字/下划线/连字符）: "$trimmed"';
  }
  if (!RegExp(r'^[a-zA-Z]').hasMatch(cleaned)) return '名称必须以字母开头';
  if (cleaned.length > 32) return '名称过长（>32）';
  return null;
}

// ═══════ 工具白名单（D9：探索模式 harness 约束）══════

/// 探索模式全程禁用的定向抓取工具。
const Set<String> _bannedToolsInExplore = {
  'run_terminal_command',
  'save_credential',
  'run_python_scraper',
  'export_and_register_scraper',
  'get_request_logs',
  'read_request_snapshot',
  'read_existing_credential',
};

/// 探索模式各阶段恒可用的只读/交互工具。
const Set<String> _readToolsInExplore = {
  'ask',
  'guardian_review',
  'guard_override',
  'list_skills',
  'read_workspace_file',
  'list_captured_requests',
  'read_request_by_id',
  'list_python_capabilities',
};

/// 工具是否允许在探索模式的指定阶段使用（阶段切换白名单）。
bool exploreToolAllowedForPhase(String toolName, ExplorePhase phase) {
  if (_bannedToolsInExplore.contains(toolName)) return false;
  if (_readToolsInExplore.contains(toolName)) return true;
  switch (phase) {
    case ExplorePhase.idle:
      return false;
    case ExplorePhase.exploring:
      // present_data_sources 在 exploring 也放行：工具内部会先 startCategorizing()
      // 再 presentCandidates，让 AI 触达上限后能从 exploring 自然切换到归类/确认。
      return toolName == 'explore_page_links' ||
          toolName == 'navigate_get' ||
          toolName == 'explore_network_resources' ||
          toolName == 'present_data_sources';
    case ExplorePhase.categorizing:
    case ExplorePhase.confirming:
      // Phase 2：登录态验证在归类/确认阶段即可先跑通（构建前）
      return toolName == 'present_data_sources' ||
          toolName == 'verify_login_flow';
    case ExplorePhase.building:
      // register_batch 在 building 允许：工具内部先 startRegistering 再注册
      // Phase 2/3：登录验证与逐源执行验证在构建阶段可用
      return toolName == 'build_selected_source' ||
          toolName == 'register_batch' ||
          toolName == 'verify_login_flow' ||
          toolName == 'execute_built_source';
    case ExplorePhase.registering:
      return toolName == 'register_batch' ||
          toolName == 'build_selected_source' ||
          toolName == 'execute_built_source';
    case ExplorePhase.done:
    case ExplorePhase.failed:
      // 终态允许修复性重建/重注册/重新呈现
      return toolName == 'build_selected_source' ||
          toolName == 'register_batch' ||
          toolName == 'present_data_sources' ||
          toolName == 'verify_login_flow' ||
          toolName == 'execute_built_source';
  }
}

/// 生成探索白名单拒绝消息（回灌 AI）。
String blockedExploreToolMessage(String toolName, ExplorePhase phase) {
  return '[error: 探索模式守卫：工具 "$toolName" 在阶段 ${phase.name} 不可用。'
      '探索模式仅允许 GET-only 探索工具'
      '（explore_page_links / explore_network_resources / navigate_get / '
      'list_captured_requests / '
      'list_python_capabilities / present_data_sources / verify_login_flow / '
      'build_selected_source / execute_built_source / register_batch）'
      '与只读工具（ask / guardian_review / read_workspace_file / list_skills）。'
      'run_terminal_command / save_credential / run_python_scraper / '
      'export_and_register_scraper 在探索模式全程禁用]';
}

// ═══════ 探索工作流控制器 ═══════

/// 探索模式工作流控制器（纯 Dart，无 Flutter 依赖）。
class ExploreWorkflow {
  ExplorePhase _phase = ExplorePhase.idle;

  /// 探索守卫上限（Phase 1 可配置：授权弹窗用户输入后经 [configureLimits] 更新）。
  ExploreLimits _limits;

  /// 用户确认的授权范围（Scope Contract；探索开始前由 UI 层落盘并传入）。
  ///
  /// null = 未确认授权（导航仅受技术同域守卫，不锁语义范围）。
  ExploreScope? _scope;

  /// 候选数据源（AI 归类产物）。
  List<CandidateDataSource> _candidates = [];

  /// 用户确认选择的数据源。
  List<CandidateDataSource> _selected = [];

  /// 已访问 URL（去 fragment，用于页数计数与去重）。
  final Set<String> _visitedUrls = {};

  /// 锁定的探索域名（首次导航/开始探索时锁定；空 = 未锁）。
  String _baseHost = '';

  int _pagesVisited = 0;
  int _requestsCaptured = 0;
  bool _requestsLimitNotified = false;
  DateTime? _lastNavigateAt;
  String _errorMessage = '';

  /// P1-1 空转熔断观察窗口：最近 [ExploreLimits.stallWindow] 次导航是否产出
  /// 新页面（环形窗口，先进先出）。
  final List<bool> _stallWindow = [];

  /// 熔断是否已触发（触发后重复导航已探索页面会被拒绝；新页面导航自动恢复）。
  bool _stallDetected = false;

  /// 熔断提示文本（供 UI/AI 消费）。
  String _stallMessage = '';

  /// 可注入时钟（测试节流用）。
  final DateTime Function() clock;

  /// 状态变更回调——由 UI 层设置以触发 setState。
  void Function()? onChanged;

  /// 触达上限/节流提示回调（AI 应据此停止循环，A15 语义类比）。
  void Function(String message)? onLimitReached;

  /// 空转熔断触发回调（P1-1，reverse-skill R43 移植）：UI 层弹警告 + 回灌 AI。
  void Function(String message)? onStallDetected;

  ExploreWorkflow({
    ExploreLimits limits = const ExploreLimits(),
    DateTime Function()? clock,
  })  : _limits = limits,
        clock = clock ?? DateTime.now;

  // ── 属性 ──

  ExplorePhase get phase => _phase;

  /// 当前探索上限（Phase 1：可经 [configureLimits] 更新）。
  ExploreLimits get limits => _limits;
  List<CandidateDataSource> get candidates => List.unmodifiable(_candidates);
  List<CandidateDataSource> get selected => List.unmodifiable(_selected);
  String get baseHost => _baseHost;
  ExploreScope? get scope => _scope;
  int get pagesVisited => _pagesVisited;
  int get requestsCaptured => _requestsCaptured;
  int get uniquePages => _visitedUrls.length;
  String get errorMessage => _errorMessage;
  bool get pagesExhausted => uniquePages >= limits.maxPages;
  bool get requestsExhausted => _requestsCaptured >= limits.maxRequests;

  /// Phase 10：探索是否达到归类最小量（页数或请求数门槛）。
  ///
  /// 用于 present_data_sources 守卫：杜绝 AI 在 0 导航时过早归类。
  ///
  /// 门槛语义：值为 0 表示「不设该门槛」；页数与请求数门槛**均需满足**才充分
  /// （默认 minRequestsForCategorize=0，故仅页数门槛生效——0 导航时
  /// uniquePages=0 < 1 → 不充分）。
  bool get explorationSufficient {
    final minPages = limits.minPagesForCategorize;
    final minReqs = limits.minRequestsForCategorize;
    final pagesOk = minPages == 0 || uniquePages >= minPages;
    final reqsOk = minReqs == 0 || _requestsCaptured >= minReqs;
    return pagesOk && reqsOk;
  }

  /// P1-1：空转熔断是否已触发（UI 弹警告；重复导航被拒）。
  bool get stallDetected => _stallDetected;

  /// P1-1：熔断提示文本。
  String get stallMessage => _stallMessage;

  /// 当前阶段是否允许用户交互（选择弹窗）。
  bool get isUserInteractive => _phase == ExplorePhase.idle ||
      _phase == ExplorePhase.confirming;

  void _notify() => onChanged?.call();

  /// Phase 1：更新探索守卫上限（授权弹窗用户配置后调用）。
  ///
  /// 页数/请求上限、节流、空转熔断、最小探索量均可被覆盖；
  /// 未提供的字段保留旧值（不会意外重置为默认）。
  void configureLimits(ExploreLimits limits) {
    _limits = limits;
    _notify();
  }

  void _enter(ExplorePhase phase, {String? note}) {
    _phase = phase;
    _notify();
  }

  // ── 序列化（断点续作：重启后回到上次探索状态） ──

  /// 快照当前探索状态（候选/选中/已访问/计数/熔断）。
  Map<String, dynamic> toJson() => {
        'phase': _phase.name,
        'baseHost': _baseHost,
        'candidates': _candidates.map((c) => c.toJson()).toList(),
        'selected': _selected.map((c) => c.toJson()).toList(),
        'visitedUrls': _visitedUrls.toList(),
        'pagesVisited': _pagesVisited,
        'requestsCaptured': _requestsCaptured,
        'stallDetected': _stallDetected,
        'stallMessage': _stallMessage,
        'errorMessage': _errorMessage,
      };

  /// 从快照恢复探索状态。失败静默保持当前（新）状态。
  void restoreFromJson(Map<String, dynamic> json) {
    try {
      _phase =
          ExplorePhase.values.asNameMap()[json['phase']] ?? ExplorePhase.idle;
      _baseHost = json['baseHost'] as String? ?? '';
      _candidates = (json['candidates'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CandidateDataSource.fromJson)
          .toList();
      _selected = (json['selected'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CandidateDataSource.fromJson)
          .toList();
      _visitedUrls
        ..clear()
        ..addAll((json['visitedUrls'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _pagesVisited = (json['pagesVisited'] as num?)?.toInt() ?? 0;
      _requestsCaptured =
          (json['requestsCaptured'] as num?)?.toInt() ?? 0;
      _stallDetected = json['stallDetected'] as bool? ?? false;
      _stallMessage = json['stallMessage'] as String? ?? '';
      _errorMessage = json['errorMessage'] as String? ?? '';
      _notify();
    } catch (e) {
      // 恢复失败：保持新状态
    }
  }

  // ── 阶段转换 ──

  /// idle → exploring（D1：用户点「开始探索」）。
  ///
  /// [startUrl] 非空时锁定其域名（同域守卫即刻生效）。
  ///
  /// [scope] 为持久化授权范围（Scope Contract）：非空时立即校验 startUrl
  /// 是否落在授权内，并在导航守卫（[recordNavigation]）中追加授权校验。
  /// 探索开始后可通过 [scope] getter 读取，供 Guardian prompt 注入。
  bool startExploring({String? startUrl, ExploreScope? scope}) {
    if (_phase != ExplorePhase.idle) return false;
    _scope = scope;
    if (startUrl != null && startUrl.trim().isNotEmpty) {
      final err = validateExploreUrl(startUrl);
      if (err != null) {
        _errorMessage = err;
        return false;
      }
      // 授权边界：startUrl 若超出 scope，探索应 fail-closed
      final scopeErr = scope?.validateUrl(startUrl);
      if (scopeErr != null) {
        _errorMessage = '开始探索被拒：$scopeErr';
        return false;
      }
      _baseHost = Uri.parse(startUrl.trim()).host.toLowerCase();
    }
    _enter(ExplorePhase.exploring, note: '开始探索');
    return true;
  }

  /// exploring → categorizing（AI 归类开始）。
  bool startCategorizing() {
    if (_phase != ExplorePhase.exploring && _phase != ExplorePhase.failed) {
      return false;
    }
    _enter(ExplorePhase.categorizing);
    return true;
  }

  /// categorizing/confirming → confirming（AI 呈现候选数据源，D3/D4）。
  ///
  /// 替换候选列表；重新呈现（用户要求重新归类）同样走此方法。
  bool presentCandidates(List<CandidateDataSource> candidates) {
    if (_phase != ExplorePhase.categorizing && _phase != ExplorePhase.confirming) {
      return false;
    }
    _candidates = List.of(candidates);
    _enter(ExplorePhase.confirming);
    return true;
  }

  /// confirming → building（用户多选确认，D4/D5）。
  bool confirmSelection(List<CandidateDataSource> selected) {
    if (_phase != ExplorePhase.confirming) return false;
    if (selected.isEmpty) return false;
    _selected = List.of(selected);
    _enter(ExplorePhase.building);
    return true;
  }

  /// building → registering（开始批量注册，D6）。
  bool startRegistering() {
    if (_phase != ExplorePhase.building && _phase != ExplorePhase.done &&
        _phase != ExplorePhase.failed) {
      return false;
    }
    _enter(ExplorePhase.registering);
    return true;
  }

  /// → done（批量注册 + 验证通过）。
  bool markDone() {
    if (_phase == ExplorePhase.done) return false;
    _enter(ExplorePhase.done);
    return true;
  }

  /// → failed（记录原因）。
  void markFailed(String reason) {
    _errorMessage = reason;
    _enter(ExplorePhase.failed, note: reason);
  }

  /// 回到 exploring（重新探索：清空候选/选择，保留域名与计数）。
  void restartExploring() {
    _candidates = [];
    _selected = [];
    _resetStall();
    _enter(ExplorePhase.exploring, note: '重新探索');
  }

  /// 重置整个探索工作流。
  void reset() {
    _phase = ExplorePhase.idle;
    _candidates = [];
    _selected = [];
    _visitedUrls.clear();
    _baseHost = '';
    _scope = null;
    _pagesVisited = 0;
    _requestsCaptured = 0;
    _requestsLimitNotified = false;
    _lastNavigateAt = null;
    _errorMessage = '';
    _resetStall();
    _notify();
  }

  /// 清空熔断状态（重新探索/重置时）。
  void _resetStall() {
    _stallWindow.clear();
    _stallDetected = false;
    _stallMessage = '';
  }

  // ── 守卫计数（navigate_get 工具消费）──

  /// 守卫并记录一次 GET 导航。
  ///
  /// 返回 null = 放行；否则为拒绝原因（URL 非法 / 非同域 / 阶段不符 /
  /// 节流 / 页数上限）。
  String? recordNavigation(String url) {
    final err = validateExploreUrl(url, baseHost: baseHost);
    if (err != null) return err;
    // 授权边界（Scope Contract）：超出用户确认范围 → 拒绝导航
    final scope = _scope;
    if (scope != null) {
      final scopeErr = scope.validateUrl(url);
      if (scopeErr != null) {
        return '超出授权范围: $scopeErr';
      }
    }
    if (_phase != ExplorePhase.exploring) return '仅探索阶段允许导航（当前: ${_phase.name}）';

    final now = clock();
    final last = _lastNavigateAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < limits.minNavigateInterval) {
        return '节流中：距上次导航 ${elapsed.inMilliseconds}ms，'
            '需 ≥${limits.minNavigateInterval.inMilliseconds}ms（D7 1s 节流）';
      }
    }

    // 首次导航锁定域名（startExploring 未提供 URL 时）
    if (_baseHost.isEmpty) {
      _baseHost = Uri.parse(url.trim()).host.toLowerCase();
    }

    final key = _urlKey(url);
    final isNew = !_visitedUrls.contains(key);

    // P1-1 空转熔断：已触发期间重复访问已探索页面 → 拒绝（AI 无法继续空转）；
    // 访问新页面自动恢复（换策略出口）。
    if (_stallDetected && !isNew) {
      return '空转熔断已触发：$_stallMessage。请切换策略（换入口链接 / 结束探索进入归类）';
    }

    if (isNew && _visitedUrls.length >= limits.maxPages) {
      final msg = '已触达页数上限（${limits.maxPages} 页），探索应结束';
      onLimitReached?.call(msg);
      return msg;
    }
    if (isNew) _visitedUrls.add(key);
    _pagesVisited++;
    _lastNavigateAt = now;
    // P1-1 空转熔断：探索首导航（pagesVisited 由 0→1）视为探索起点本身，
    // 不计入"新页面产出"，否则连续访问同页时首导航的 isNew=true 会污染
    // 观察窗口导致熔断永不触发（测试期望"连续 N 次访问同页"全算无新页面）。
    _recordStall(isNew && _pagesVisited > 1);
    recordRequest();
    _notify();
    return null;
  }

  /// 更新空转观察窗口并判定熔断（P1-1，reverse-skill R43 移植）。
  ///
  /// 窗口内导航次数 ≥ [ExploreLimits.stallThreshold] 且全部无新页面 → 触发；
  /// 新页面产出 → 自动恢复。
  void _recordStall(bool isNew) {
    _stallWindow.add(isNew);
    if (_stallWindow.length > limits.stallWindow) {
      _stallWindow.removeAt(0);
    }
    if (isNew && _stallDetected) {
      // 探索重新产出：熔断自动恢复
      _stallDetected = false;
      _stallMessage = '';
    }
    if (!_stallDetected &&
        limits.stallThreshold > 0 &&
        _stallWindow.length >= limits.stallThreshold &&
        !_stallWindow.any((e) => e)) {
      _stallDetected = true;
      _stallMessage = '连续 ${limits.stallThreshold} 次导航无新页面，'
          '探索疑似空转，重复导航将被拒绝';
      onStallDetected?.call(_stallMessage);
    }
  }

  /// 记录一次探索触发的 GET 请求（含导航本身）。
  ///
  /// 达到请求上限时通过 [onLimitReached] 提示一次（不硬阻断——提示后
  /// 由 AI 停止循环；navigate 受节流与页数守卫硬约束）。
  void recordRequest() {
    _requestsCaptured++;
    if (_requestsCaptured >= limits.maxRequests && !_requestsLimitNotified) {
      _requestsLimitNotified = true;
      onLimitReached?.call('已触达请求数上限（${limits.maxRequests} 请求）');
    }
    _notify();
  }

  /// URL 去重键：去 fragment、host 小写。
  static String _urlKey(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.replace(fragment: '').toString().toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// 释放回调引用。
  void dispose() {
    onChanged = null;
    onLimitReached = null;
    onStallDetected = null;
  }
}
