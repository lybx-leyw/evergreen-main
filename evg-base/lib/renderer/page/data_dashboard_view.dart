/// 数据中枢看板——**纯 UI 看板**（只读轮询，实时反映数据调度状态）。
///
/// 设计契约（移除一切用户手动拉取/重试入口）：
/// - **只读**：本看板只消费 [DataOrchestrator] 的公开只读 API（[DataOrchestrator.allStatuses] /
///   [DataOrchestrator.dataChangeEvents] / 计数），**绝不调用** get / refresh / testConnectivity
///   等任何会触发拉取的入口，也不展示「拉取/重试」按钮。
/// - **时时**：[Timer.periodic] 每 [_pollInterval] 轮询一次状态快照；同时订阅
///   [DataOrchestrator.dataChangeEvents]——后台刷新内容变化时立即刷新，无需等轮询周期。
/// - **可信**：展示的拉取时间一律来自 [DataSourceStatus.lastFetchedAt] /
///   [DataSourceStatus.relativeTime]（真实时间戳，不伪造、不缓存展示时间）。
/// - **失败仅警告**：数据源 connected=false 时，若已有拉取历史（[DataSourceStatus.lastFetchedAt]
///   非空，即有缓存/历史数据可用）则显示**警告级**（琥珀色徽标 + [DataSourceStatus.lastError]），
///   绝不显示红色错误卡或空态错误页；只有「从未拉取成功且无数据」才显示中性空态。
/// - **不阻塞**：加载/刷新全程同步读状态快照，永不 await 拉取结果（用户永不等数据）。
/// - **调度快照（可选）**：若 core 提供了调度快照 getter（如 `schedulingSnapshot`），以防御式
///   方式读取并展示「当前调度」区（后台串行重试 / 待重试队列 / 并行拉取 / 最近后台刷新 /
///   下次自动刷新 / 串行重试策略）；core 未提供时优雅降级为仅用 allStatuses，省略该区
///   （绝不因此报错）。
/// - **拉取轨迹（可选）**：若 core 提供 `fetchPathOf(name)` / `fetchPaths`（阶段追踪
///   契约，core 子代理并行交付中），防御式读取并在每个数据源卡片底部渲染「轨迹式
///   阶段条」——固定骨架 + 轨迹填充、当前阶段脉冲高亮、失败标红、重试次数徽标；
///   core 未交付 / 该源无轨迹数据时优雅降级（不显示轨迹条，其余看板照常）。
/// - **整体调度总览泳道（可选增强）**：在汇总条下方新增泳道区——所有数据源按状态
///   分组（拉取中/重试中 · 新鲜 · 过期/警告 · 从未拉取），每源一条横向迷你轨迹泳道，
///   顶部「调度状态横幅」呈现并行拉取（由 fetchPaths 推导：isActive 且当前阶段为
///   fetching 的源计数，多源同存即并行）与后台串行重试（schedulingSnapshot.isRetrying
///   + pendingRetryNames）路径及下次自动刷新时刻（nextRefreshAt）；源数 >6 时默认
///   折叠，极窄屏（<320dp）自动仅显示横幅 + 活跃源泳道，任何宽度无水平溢出。
///   core 字段缺失时优雅降级（横幅省略相应行 / 泳道行仅显示名称与状态）。
library;

import 'dart:async';

import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 看板轮询间隔（任务契约 3–5 秒，取 4 秒）。状态变更（拉取失败/连通变化）不产生
/// [DataChangeEvent]，靠本定时器兜底；内容变更由事件订阅即时刷新。
const Duration _pollInterval = Duration(seconds: 4);

class DataDashboardView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  const DataDashboardView({super.key, required this.descriptor});

  @override
  ConsumerState<DataDashboardView> createState() => _DataDashboardViewState();
}

class _DataDashboardViewState extends ConsumerState<DataDashboardView>
    with SingleTickerProviderStateMixin {
  DataOrchestrator? _orch;
  List<DataSourceStatus> _statuses = const [];
  _SchedulingInfo? _scheduling;
  Timer? _pollTimer;
  StreamSubscription<DataChangeEvent>? _eventSub;

  /// 看板自身最后一次轮询时间（仅用于展示轮询健康度，明确标注为「看板轮询时间」，
  /// 与数据源真实拉取时间 [DataSourceStatus.lastFetchedAt] 严格区分，不伪造）。
  DateTime? _lastPollAt;

  /// 各数据源拉取轨迹（core 阶段追踪契约，防御式读取；未交付/缺失时为空 Map，
  /// 卡片不渲染轨迹条，其余看板照常）。
  Map<String, _FetchPathInfo> _paths = const {};

  /// 泳道区展开偏好（仅内存记忆，不持久化；切换入口见 [_setSwimlaneExpanded]）。
  ///
  /// 默认：源数 ≤ [_kSwimlaneCollapseThreshold] 时展开，否则折叠为「调度状态横幅 +
  /// 活跃组 + 其余组计数」。[_swimlaneTouched] 标记用户是否显式切换过——从未切换时，
  /// 极窄屏（< [_kSwimlaneUltraNarrow]）自动按折叠渲染（只显示横幅 + 活跃源泳道），
  /// 用户显式展开后尊重其选择（展开时每行迷你轨迹同样无水平溢出）。
  bool _swimlaneExpanded = true;
  bool _swimlaneTouched = false;

  /// 轨迹「进行中节点」呼吸脉冲动画（轻量：仅在有源处于拉取/重试中时运行，
  /// 全部空闲即停止并归位；单控制器驱动全部卡片，避免每卡一个 ticker）。
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    final orch = ref.read(dataOrchestratorProvider);
    _orch = orch;
    _statuses = orch.allStatuses;
    _swimlaneExpanded = _statuses.length <= _kSwimlaneCollapseThreshold;
    _scheduling = _tryReadSchedulingSnapshot(orch);
    _paths = _readFetchPaths(orch, [for (final s in _statuses) s.name]);
    _lastPollAt = DateTime.now();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _syncPulseTicker();
    // 事件驱动：后台刷新内容变化时立即刷新（时时反映，不等轮询周期）。
    _eventSub = orch.dataChangeEvents.listen((_) => _refreshStatuses());
    // 定时兜底：状态变更（如拉取失败）不产生变更事件，靠轮询兜底。
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshStatuses());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _eventSub?.cancel();
    _eventSub = null;
    _pulse.dispose();
    _orch = null;
    super.dispose();
  }

  /// 纯读状态刷新——只读取 [DataOrchestrator.allStatuses]（及可选调度快照），
  /// **不触发任何拉取/重试**。定时轮询与事件订阅共用。
  void _refreshStatuses() {
    if (!mounted) return;
    final orch = _orch;
    if (orch == null) return;
    setState(() {
      _statuses = orch.allStatuses;
      _scheduling = _tryReadSchedulingSnapshot(orch);
      _paths = _readFetchPaths(orch, [for (final s in _statuses) s.name]);
      _lastPollAt = DateTime.now();
    });
    _syncPulseTicker();
  }

  /// 轨迹脉冲联动：任一数据源处于拉取/重试中（isActive）时运行呼吸动画，
  /// 全部空闲时停止并归位（轻量，避免常驻 ticker 空转）。
  void _syncPulseTicker() {
    final anyActive = _paths.values.any((p) => p.isActive);
    if (anyActive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!anyActive && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  /// 设置泳道区展开/收起（用户显式操作）。首次切换后置位 [_swimlaneTouched]，
  /// 此后极窄屏不再自动强制折叠，尊重用户选择。
  void _setSwimlaneExpanded(bool expanded) {
    setState(() {
      _swimlaneTouched = true;
      _swimlaneExpanded = expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orch = _orch;
    final statuses = _statuses;
    if (orch == null || statuses.isEmpty) {
      return _buildEmpty(theme);
    }

    // 按 category 分组（空分类归入「其他」，与既有语义一致）。
    final grouped = <String, List<DataSourceStatus>>{};
    for (final s in statuses) {
      final cat = s.category.isNotEmpty ? s.category : '其他';
      grouped.putIfAbsent(cat, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 12),
        _buildSummary(theme, orch),
        const SizedBox(height: 16),
        _SwimlaneSection(
          statuses: statuses,
          paths: _paths,
          scheduling: _scheduling,
          pulse: _pulse,
          expanded: _swimlaneExpanded,
          touched: _swimlaneTouched,
          onSetExpanded: _setSwimlaneExpanded,
        ),
        if (_scheduling != null) ...[
          const SizedBox(height: 16),
          _SchedulingCard(info: _scheduling!),
        ],
        const SizedBox(height: 8),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Row(
              children: [
                Text(entry.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary)),
                const Spacer(),
                Text('${entry.value.length} 个',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          ...entry.value.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child:
                    _SourceCard(status: s, path: _paths[s.name], pulse: _pulse),
              )),
        ],
      ],
    );
  }

  /// 顶部标题行：展示自动轮询健康度（看板轮询时间，非数据源拉取时间）。
  Widget _buildHeader(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.dashboard_outlined,
            size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('数据中枢',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        Icon(Icons.sync_rounded, size: 14, color: muted),
        const SizedBox(width: 4),
        Text(
          '自动轮询 ${_pollInterval.inSeconds} 秒 · 上次 '
          '${_lastPollAt != null ? _formatClock(_lastPollAt!) : '--'}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  /// 汇总条：total / connected / fresh（来自 core 公开计数，实时一致）。
  Widget _buildSummary(ThemeData theme, DataOrchestrator orch) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.storage_rounded,
              label: '数据源',
              value: '${orch.totalCount}',
              color: theme.colorScheme.primary,
            ),
          ),
          Container(width: 1, height: 36, color: theme.dividerColor),
          Expanded(
            child: _StatTile(
              icon: Icons.check_circle_rounded,
              label: '连通',
              value: '${orch.connectedCount}',
              color: _green(theme),
            ),
          ),
          Container(width: 1, height: 36, color: theme.dividerColor),
          Expanded(
            child: _StatTile(
              icon: Icons.new_releases_rounded,
              label: '新鲜',
              value: '${orch.freshCount}',
              color: _green(theme),
            ),
          ),
        ],
      ),
    );
  }

  /// 中性空态：仅当无任何注册数据源时展示（不是错误页）。
  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('暂无注册数据源', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text('data 插件将在启动时自动注册；看板自动轮询最新状态',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 汇总统计块。
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// 单个数据源状态卡——纯只读展示，无任何点击拉取/重试入口。
///
/// 状态着色规则（契约 ⑤：有缓存/历史数据时失败仅警告，绝不显示红色错误卡）：
/// - connected=true 且新鲜 → 绿色「连通」；
/// - connected=true 但过期 → 橙色「连通 · 过期」；
/// - connected=false 但已有拉取历史（lastFetchedAt 非空）→ 琥珀色警告
///   「失败 · 缓存可用」+ lastError 文案（警告级提示）；
/// - connected=false 且从未拉取 → 中性灰「从未拉取」（中性空态，无红色错误展示）。
/// - 拉取轨迹（可选）：core 提供 fetchPathOf/fetchPaths 时在卡片底部渲染轨迹式阶段条
///   （固定骨架 + 轨迹填充、当前阶段脉冲、失败标红、重试次数徽标；契约⑤：有历史
///   数据时失败徽标为琥珀警告而非红色）。
class _SourceCard extends StatelessWidget {
  final DataSourceStatus status;

  /// 该源的拉取轨迹（core 阶段追踪契约；core 未交付 / 从未拉取时为 null →
  /// 不渲染轨迹条，其余卡片内容照常）。
  final _FetchPathInfo? path;

  /// 共享呼吸脉冲动画（看板持有并驱动，卡片侧只消费；进行中节点高亮用）。
  final Animation<double> pulse;

  const _SourceCard({
    required this.status,
    this.path,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final never = status.lastFetchedAt == null;
    final hasHistory = !never;

    final state = _sourceStateOf(status, theme);
    final dotColor = state.color;
    final stateLabel = state.label;
    final stateColor = state.color;

    // 真实拉取时间：lastFetchedAt 原始时间戳 + relativeTime（均来自 core，不伪造）。
    final timeText = never
        ? '从未拉取 · 无历史数据'
        : '${status.freshnessLabel} · ${_formatDateTime(status.lastFetchedAt!)}（${status.relativeTime}）';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      // 跟随主题：卡片面板底色（surfaceContainerHighest = 主题 surface/bgSecondary）。
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: dotColor.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: dotColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(status.displayName,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (status.completed) ...[
                            const SizedBox(width: 6),
                            _TinyBadge(text: '流式已完结', color: muted),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${status.name} · ${status.category.isNotEmpty ? status.category : '未分类'}',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StateChip(text: stateLabel, color: stateColor),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(timeText,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11)),
                ),
              ],
            ),
            // 失败提示：有缓存/历史数据 → 警告级（琥珀色）；无数据 → 中性灰提示。
            // 两者都不是红色错误卡。
            if (status.lastError != null && !status.connected) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                        hasHistory
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                        size: 14,
                        color: stateColor),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(status.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, height: 1.4, color: stateColor)),
                  ),
                ],
              ),
            ],
            // 拉取轨迹条：core 阶段追踪契约交付后自动生效；未交付/无轨迹数据 →
            // path 为 null，不渲染（防御降级，其余看板照常）。
            if (path != null) ...[
              const SizedBox(height: 10),
              Divider(
                  height: 1,
                  thickness: 0.5,
                  color: theme.dividerColor.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              _FetchTrajectoryBar(
                path: path!,
                hasHistory: hasHistory,
                connected: status.connected,
                lastError: status.lastError,
                pulse: pulse,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 小型状态徽标（如「流式已完结」）。
class _TinyBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _TinyBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// 圆角状态胶囊（连通 / 失败 · 缓存可用 / 从未拉取）。
class _StateChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StateChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 整体调度总览泳道——所有数据源按状态分组，每源一条横向泳道，一屏看清并行/串行调度全貌
//
// 数据来源：与看板其余部分同源（_statuses / _paths / _scheduling，同一份快照，
// 随 _refreshStatuses() 一起刷新，不重复请求）；全部经既有防御式解析
// （_readFetchPaths / _SchedulingInfo），core 字段缺失时优雅降级：
// - 无轨迹数据（path 为 null）→ 泳道行只显示名称 + 状态胶囊，轨迹列显示占位符；
// - 调度快照缺失 → 横幅仅展示由 fetchPaths 推导的「并行拉取中」，串行/下次刷新行省略；
// - fetchPaths 整体缺失 → 横幅省略「并行拉取中」，泳道区退化为纯状态分组视图。
// ═══════════════════════════════════════════════════════════════════════════

/// 泳道区极窄屏阈值：可用宽度 < 该值（如 <320dp）时，用户未显式展开则自动只显示
/// 「调度状态横幅 + 活跃源泳道」，完整泳道需展开（展开时每行迷你轨迹同样无溢出）。
const double _kSwimlaneUltraNarrow = 320;

/// 泳道区默认折叠阈值：数据源数 > 该值时默认折叠为「横幅 + 活跃组 + 其余组计数」。
const int _kSwimlaneCollapseThreshold = 6;

/// 数据源状态 → 展示用（颜色, 标签）二元组（[_SourceCard] 与泳道行共用，
/// 保证状态胶囊/圆点着色语义一致）。
///
/// 着色规则（契约⑤：有缓存/历史数据时失败仅警告，绝不红色错误展示）：
/// - connected=true 且新鲜 → 绿「连通」；
/// - connected=true 但过期 → 橙「连通 · 过期」；
/// - connected=false 但已有拉取历史（lastFetchedAt 非空）→ 琥珀「失败 · 缓存可用」；
/// - connected=false 且从未拉取 → 中性「从未拉取」。
({Color color, String label}) _sourceStateOf(
    DataSourceStatus status, ThemeData theme) {
  if (status.connected) {
    return status.isFresh
        ? (color: _green(theme), label: '连通')
        : (color: _stale(theme), label: '连通 · 过期');
  }
  if (status.lastFetchedAt != null) {
    return (color: _warn(theme), label: '失败 · 缓存可用');
  }
  return (color: theme.colorScheme.onSurfaceVariant, label: '从未拉取');
}

/// 泳道区渲染模型（纯数据，由 [_buildSwimlaneModel] 一次性计算，每源仅归入一组）。
class _SwimlaneModel {
  const _SwimlaneModel({
    required this.active,
    required this.fresh,
    required this.stale,
    required this.never,
    required this.fetchingNames,
    required this.retryInProgress,
    required this.pendingRetryNames,
    required this.nextRefreshKnown,
    this.nextRefreshAt,
  });

  /// 分组 A「拉取中 / 重试中」：isActive=true 或 schedulingSnapshot.pendingRetryNames 成员。
  final List<DataSourceStatus> active;

  /// 分组 B「新鲜」：isFresh && connected。
  final List<DataSourceStatus> fresh;

  /// 分组 C「过期 / 警告」：非新鲜但已有拉取历史（连通过期 / 失败缓存可用）。
  final List<DataSourceStatus> stale;

  /// 分组 D「从未拉取」：lastFetchedAt == null。
  final List<DataSourceStatus> never;

  /// 并行拉取中：由 fetchPaths 推导——isActive 且最后一个未完成 step 为 fetching
  /// 的源（多源同存即并行）。
  final List<String> fetchingNames;

  /// 后台串行重试进行中（schedulingSnapshot.isRetrying）。
  final bool retryInProgress;

  /// 待重试队列（schedulingSnapshot.pendingRetryNames，防御式解析）。
  final List<String> pendingRetryNames;

  /// 下次自动刷新时刻字段是否已知（core 未提供该字段时不渲染该行）。
  final bool nextRefreshKnown;
  final DateTime? nextRefreshAt;

  /// 调度状态横幅是否有内容（任一活跃路径或已知的下次刷新时刻）。
  bool get hasBanner =>
      fetchingNames.isNotEmpty ||
      retryInProgress ||
      (nextRefreshKnown && nextRefreshAt != null);

  int get total => active.length + fresh.length + stale.length + never.length;
}

/// 计算泳道分组与调度横幅信息（纯读，随 _refreshStatuses() 的数据快照一起刷新）。
///
/// 分组规则（优先级从上到下，每源仅入一组）：
/// 1. 拉取中/重试中：isActive=true，或 schedulingSnapshot.pendingRetryNames 成员；
/// 2. 从未拉取：lastFetchedAt == null；
/// 3. 新鲜：isFresh && connected；
/// 4. 其余有历史者（连通过期 / 失败缓存可用）→ 过期 / 警告。
/// 组内按名称排序（忽略大小写）。
_SwimlaneModel _buildSwimlaneModel(List<DataSourceStatus> statuses,
    Map<String, _FetchPathInfo> paths, _SchedulingInfo? scheduling) {
  final active = <DataSourceStatus>[];
  final fresh = <DataSourceStatus>[];
  final stale = <DataSourceStatus>[];
  final never = <DataSourceStatus>[];
  final fetching = <String>[];

  final retryQueue = scheduling?.retryQueue ?? const <String>[];
  final retryInProgress = scheduling?.retryInProgress ?? false;

  for (final s in statuses) {
    final p = paths[s.name];
    // 「并行拉取中」推导：isActive 且最后一个未完成 step 的 phase 为 fetching。
    final isFetching =
        p != null && p.isActive && p.currentStep?.phase == 'fetching';
    if (isFetching) fetching.add(s.name);
    if ((p?.isActive ?? false) || retryQueue.contains(s.name)) {
      active.add(s);
    } else if (s.lastFetchedAt == null) {
      never.add(s);
    } else if (s.isFresh && s.connected) {
      fresh.add(s);
    } else {
      stale.add(s);
    }
  }

  int byName(DataSourceStatus a, DataSourceStatus b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  active.sort(byName);
  fresh.sort(byName);
  stale.sort(byName);
  never.sort(byName);
  fetching.sort();

  return _SwimlaneModel(
    active: active,
    fresh: fresh,
    stale: stale,
    never: never,
    fetchingNames: fetching,
    retryInProgress: retryInProgress,
    pendingRetryNames: retryQueue,
    nextRefreshKnown: scheduling?.nextRefreshKnown ?? false,
    nextRefreshAt: scheduling?.nextRefreshAt,
  );
}

/// 「整体调度总览泳道」区——所有数据源按状态分组、每源一条横向泳道。
///
/// - 顶部「调度状态横幅」（[_SwimlaneBanner]）：并行拉取中 N 项（fetchPaths 推导）·
///   后台串行重试中（isRetrying + pendingRetryNames）· 下次自动刷新 HH:MM；
/// - 分组 A/B/C/D（拉取中/新鲜/过期/从未拉取），组内按名称排序；
/// - 可折叠：源数 > [_kSwimlaneCollapseThreshold] 默认折叠为「横幅 + 活跃组 +
///   其余组计数」，展开/收起状态仅记忆于 State 字段（[_SwimlaneSection] 内计算有效
///   展开状态：用户显式切换后尊重其选择；从未切换时极窄屏自动按折叠渲染）；
/// - 响应式：LayoutBuilder 计算名称列/胶囊宽度，迷你轨迹按剩余宽度等比缩放节点，
///   任何宽度无水平溢出。
class _SwimlaneSection extends StatelessWidget {
  const _SwimlaneSection({
    required this.statuses,
    required this.paths,
    this.scheduling,
    required this.pulse,
    required this.expanded,
    required this.touched,
    required this.onSetExpanded,
  });

  final List<DataSourceStatus> statuses;
  final Map<String, _FetchPathInfo> paths;
  final _SchedulingInfo? scheduling;

  /// 共享呼吸脉冲动画（看板持有；泳道行活跃节点消费，空闲自动停）。
  final Animation<double> pulse;

  /// 用户展开偏好（默认：源数 ≤ [_kSwimlaneCollapseThreshold] 时展开）。
  final bool expanded;

  /// 用户是否显式切换过展开状态（未切换时极窄屏自动按折叠渲染）。
  final bool touched;

  /// 展开/收起回调（携带目标状态，由看板 State 记忆）。
  final ValueChanged<bool> onSetExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = _buildSwimlaneModel(statuses, paths, scheduling);
    return LayoutBuilder(builder: (context, cons) {
      final maxW = cons.maxWidth;
      final ultraNarrow = maxW.isFinite && maxW < _kSwimlaneUltraNarrow;
      // 有效展开：用户显式切换后尊重其选择；从未切换时，极窄屏自动只显示
      // 「调度状态横幅 + 活跃源泳道」（完整泳道需展开，展开时每行无溢出）。
      final showAll = touched ? expanded : (expanded && !ultraNarrow);
      // 名称列 / 状态胶囊宽度随可用宽度自适应（防水平溢出）。
      final nameW = (maxW * (ultraNarrow ? 0.34 : 0.38)).clamp(84.0, 148.0);
      final chipMaxW = ultraNarrow ? 0.0 : (maxW * 0.24).clamp(68.0, 104.0);

      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme, model, showAll),
              if (model.hasBanner) ...[
                const SizedBox(height: 8),
                _SwimlaneBanner(model: model),
              ],
              const SizedBox(height: 4),
              if (showAll) ...[
                _buildGroup(theme, '拉取中 / 重试中', model.active,
                    theme.colorScheme.primary, nameW, chipMaxW, ultraNarrow),
                _buildGroup(theme, '新鲜', model.fresh, _green(theme), nameW,
                    chipMaxW, ultraNarrow),
                _buildGroup(theme, '过期 / 警告', model.stale, _stale(theme), nameW,
                    chipMaxW, ultraNarrow),
                _buildGroup(
                    theme,
                    '从未拉取',
                    model.never,
                    theme.colorScheme.onSurfaceVariant,
                    nameW,
                    chipMaxW,
                    ultraNarrow),
              ] else ...[
                _buildGroup(theme, '拉取中 / 重试中', model.active,
                    theme.colorScheme.primary, nameW, chipMaxW, ultraNarrow),
                _buildCollapsedCounts(theme, model),
              ],
            ],
          ),
        ),
      );
    });
  }

  /// 泳道区标题行：标题 + 源总数 + 展开/收起切换。
  Widget _buildHeader(ThemeData theme, _SwimlaneModel model, bool showAll) {
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.linear_scale_rounded, size: 16, color: primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text('整体调度总览',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text('${model.total} 源',
            style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        const Spacer(),
        InkWell(
          onTap: () => onSetExpanded(!showAll),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(showAll ? '收起' : '展开',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                Icon(showAll ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 分组标题行（● 标签 N）+ 组内泳道行（组空则不渲染）。
  Widget _buildGroup(
      ThemeData theme,
      String label,
      List<DataSourceStatus> group,
      Color color,
      double nameW,
      double chipMaxW,
      bool ultraNarrow) {
    if (group.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$label ${group.length}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        for (final s in group)
          _SwimlaneRow(
            status: s,
            path: paths[s.name],
            pulse: pulse,
            nameWidth: nameW,
            chipMaxWidth: chipMaxW,
            ultraCompact: ultraNarrow,
          ),
      ],
    );
  }

  /// 折叠视图：其余分组的计数摘要（如「新鲜 5 · 过期 2 · 从未拉取 1」）。
  Widget _buildCollapsedCounts(ThemeData theme, _SwimlaneModel model) {
    final parts = <String>[
      if (model.fresh.isNotEmpty) '新鲜 ${model.fresh.length}',
      if (model.stale.isNotEmpty) '过期 ${model.stale.length}',
      if (model.never.isNotEmpty) '从未拉取 ${model.never.length}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(parts.join(' · '),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// 调度状态横幅：泳道区顶部一行式呈现并行/串行调度路径 + 下次自动刷新时刻。
///
/// - 「并行拉取中 N 项」：由 fetchPaths 推导（isActive 且当前阶段 fetching 的源数，
///   多源同存即并行；core 未交付 fetchPaths 时自动省略该行）；
/// - 「后台串行重试中」：schedulingSnapshot.isRetrying（来源 pendingRetryNames）；
/// - 「下次自动刷新 HH:MM」：schedulingSnapshot.nextRefreshAt（复用 _SchedulingInfo
///   的 nextRefreshKnown 语义；字段缺失/未开启时不渲染）。
class _SwimlaneBanner extends StatelessWidget {
  const _SwimlaneBanner({required this.model});

  final _SwimlaneModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    if (model.fetchingNames.isNotEmpty) {
      rows.add(_SchedulingRow(
        icon: Icons.bolt_rounded,
        color: theme.colorScheme.primary,
        title: '并行拉取中 ${model.fetchingNames.length} 项',
        detail: model.fetchingNames.join(' · '),
      ));
    }
    if (model.retryInProgress) {
      rows.add(_SchedulingRow(
        icon: Icons.sync_rounded,
        color: _warn(theme),
        title: '后台串行重试中',
        detail: model.pendingRetryNames.isNotEmpty
            ? model.pendingRetryNames.join(' · ')
            : null,
        trailing: const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (model.nextRefreshKnown && model.nextRefreshAt != null) {
      rows.add(_SchedulingRow(
        icon: Icons.event_available_rounded,
        color: theme.colorScheme.primary,
        title: '下次自动刷新 ${_formatClockHM(model.nextRefreshAt!)}',
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

/// 单条泳道行（每源一条横向轨道）：左侧源名 + 状态胶囊，右侧横向迷你轨迹。
///
/// 行高控制在 ~40–48dp：名称两行小字 + 迷你轨迹单行圆点；名称列宽度随可用宽度
/// 自适应（[nameWidth]），极窄屏下状态胶囊退化为纯色圆点（[chipMaxWidth] == 0）。
class _SwimlaneRow extends StatelessWidget {
  const _SwimlaneRow({
    required this.status,
    this.path,
    required this.pulse,
    required this.nameWidth,
    required this.chipMaxWidth,
    required this.ultraCompact,
  });

  final DataSourceStatus status;

  /// 该源拉取轨迹（core 未交付 / 该源无轨迹数据时为 null → 轨迹列显示占位符，
  /// 其余看板照常）。
  final _FetchPathInfo? path;

  final Animation<double> pulse;
  final double nameWidth;
  final double chipMaxWidth;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = _sourceStateOf(status, theme);
    final showChip = chipMaxWidth > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: nameWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(status.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                const SizedBox(height: 1),
                Text(
                  '$status.name · ${status.category.isNotEmpty ? status.category : '未分类'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, fontSize: 10.5, height: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (showChip) ...[
            _MiniStateChip(
                text: state.label, color: state.color, maxWidth: chipMaxWidth),
            const SizedBox(width: 8),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: state.color),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _MiniTrajectoryBar(
              path: path,
              connected: status.connected,
              lastError: status.lastError,
              pulse: pulse,
              ultraCompact: ultraCompact,
            ),
          ),
        ],
      ),
    );
  }
}

/// 泳道行状态胶囊（[_StateChip] 的简化版）：单行省略，防水平溢出。
class _MiniStateChip extends StatelessWidget {
  const _MiniStateChip({
    required this.text,
    required this.color,
    required this.maxWidth,
  });

  final String text;
  final Color color;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// 泳道行横向迷你轨迹：复用 [_FetchTrajectoryBar] 的节点骨架/填充/配色语义
/// （[_composeTrajectoryNodes] / [_trajectoryDot] / [_trajectorySegmentColor]），
/// 但压缩为紧凑单行：节点更小（6–8dp）、无节点下方标签，仅尾部以文字徽标呈现
/// 当前/失败阶段（或重试次数），避免行高膨胀。
///
/// 响应式：LayoutBuilder 按剩余宽度等比缩放节点/连线，任何宽度无水平溢出；
/// [ultraCompact]（极窄屏）进一步压缩节点并隐藏尾部文字徽标。
class _MiniTrajectoryBar extends StatelessWidget {
  const _MiniTrajectoryBar({
    this.path,
    required this.connected,
    this.lastError,
    required this.pulse,
    required this.ultraCompact,
  });

  /// 该源拉取轨迹（core 未交付 / 无轨迹数据时为 null → 显示占位符）。
  final _FetchPathInfo? path;

  final bool connected;
  final String? lastError;

  /// 共享呼吸脉冲动画（看板持有；仅进行中节点消费）。
  final Animation<double> pulse;

  /// 极窄屏压缩模式：更小节点、隐藏尾部文字徽标。
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = path;
    if (p == null) {
      return Text('暂无轨迹',
          style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 10));
    }
    final nodes = _composeTrajectoryNodes(p, connected, lastError);
    if (nodes.isEmpty) return const SizedBox.shrink();
    final dotBase = ultraCompact ? 6.0 : 8.0;
    final connBase = ultraCompact ? 3.0 : 5.0;
    final needed = nodes.length * dotBase + (nodes.length - 1) * connBase;
    final currentIdx = nodes.indexWhere((n) => n.isCurrent);
    final failedIdx = nodes.indexWhere((n) => n.isFailed);
    return LayoutBuilder(builder: (context, cons) {
      final avail = cons.maxWidth;
      var dot = dotBase;
      var conn = connBase;
      if (avail.isFinite && needed > avail) {
        final scale = needed > 0 ? avail / needed : 1.0;
        dot = dotBase * scale;
        conn = connBase * scale;
      }
      // 尾部状态徽标：仅当前/失败节点（或重试次数）显示，且有富余宽度时呈现；
      // 极窄屏一律隐藏，避免挤压轨迹。
      final tag = _buildTag(theme, p, nodes, currentIdx, failedIdx);
      final showTag = tag != null &&
          !ultraCompact &&
          (!avail.isFinite || avail >= needed + 44);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            _trajectoryDot(context, theme, nodes[i], size: dot, pulse: pulse),
            if (i < nodes.length - 1)
              Container(
                width: conn,
                height: 2,
                color: _trajectorySegmentColor(theme, nodes[i + 1]),
              ),
          ],
          if (showTag) tag,
        ],
      );
    });
  }

  /// 尾部状态徽标文案（优先级：重试次数 > 失败 > 当前阶段）。
  Widget? _buildTag(ThemeData theme, _FetchPathInfo p,
      List<_TrajectoryNode> nodes, int currentIdx, int failedIdx) {
    if (p.isActive && p.retryCount > 0) {
      return _tag(theme, '重试 ${p.retryCount}', _warn(theme));
    }
    if (failedIdx >= 0) {
      return _tag(theme, '失败', _red(theme));
    }
    if (currentIdx >= 0) {
      return _tag(theme, _phaseLabel(nodes[currentIdx].phase),
          theme.colorScheme.primary);
    }
    return null;
  }

  Widget _tag(ThemeData theme, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        maxLines: 1,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 拉取轨迹（轨迹式阶段条）——core 阶段追踪契约的防御式消费
//
// core 子代理正在并行实现阶段追踪契约（`DataFetchPhase` 枚举 / `DataSourceFetchStep`
// / `DataSourceFetchPath` / `DataOrchestrator.fetchPathOf(name)` + `fetchPaths`）。
// 本看板只消费、不触碰 core/。消费方式与 [_SchedulingInfo] 同款：全部经 dynamic 读取
// + try/catch，core 未交付或字段缺失时优雅降级——不渲染轨迹条，其余看板照常；
// core 交付后无需改本文件即可生效。
// ═══════════════════════════════════════════════════════════════════════════

/// 固定 6 阶段骨架（按拉取顺序）——已发生部分按实际 steps 填充，未发生阶段作空心背景。
const List<String> _kSkeletonPhases = [
  'queued',
  'cacheLookup',
  'fetching',
  'validating',
  'caching',
  'done',
];

const Map<String, String> _kPhaseLabels = {
  'queued': '排队',
  'cacheLookup': '查缓存',
  'fetching': '拉取',
  'validating': '校验',
  'caching': '写缓存',
  'done': '完成',
  'failed': '失败',
};

/// 横向/纵向切换阈值：卡片可用宽度 ≥ 该值走横向步骤条，否则自动切纵向（小屏无溢出）。
const double _kTrajectoryBreakpoint = 360;

/// 横向每节点最小宽度（含标签）；不足时强制退回纵向，防水平溢出。
const double _kMinNodeLabelWidth = 30;

/// 横向节点间连线宽度。
const double _kConnectorWidth = 10;

String _phaseLabel(String phase) => _kPhaseLabels[phase] ?? phase;

/// 拉取路径信息（渲染用只读模型，由 [_parseFetchPath] 防御式解析而来）。
class _FetchPathInfo {
  const _FetchPathInfo({
    required this.steps,
    required this.isActive,
    this.retryCount = 0,
  });

  final List<_FetchStepInfo> steps;

  /// 是否正在拉取/重试中。
  final bool isActive;

  /// 累计重试次数。
  final int retryCount;

  /// 当前进行中阶段 = 最后一个未完成的 step（仅 isActive 时有意义）。
  _FetchStepInfo? get currentStep {
    for (var i = steps.length - 1; i >= 0; i--) {
      if (!steps[i].completed) return steps[i];
    }
    return null;
  }
}

/// 单阶段轨迹信息。
class _FetchStepInfo {
  const _FetchStepInfo({
    required this.phase,
    required this.completed,
    this.at,
  });

  final String phase;
  final bool completed;
  final DateTime? at;
}

/// 轨迹节点（骨架阶段 / 已发生填充 / 进行中 / 失败的展示模型）。
class _TrajectoryNode {
  const _TrajectoryNode({
    required this.phase,
    this.step,
    this.isCurrent = false,
    this.isFailed = false,
  });

  final String phase;
  final _FetchStepInfo? step;

  /// 进行中高亮（脉冲）。
  final bool isCurrent;

  /// 失败节点（红色 + ✗）。
  final bool isFailed;
}

/// 防御式读取全部数据源的拉取轨迹（core 阶段追踪契约；getter 缺失 → 返回空 Map）。
///
/// 优先读 `fetchPaths`（`Map<name, DataSourceFetchPath>` 形态）；缺失/非 Map 时逐源
/// 回退 `fetchPathOf(name)`。任何异常均静默降级为空 Map（不渲染轨迹条，不报错）。
Map<String, _FetchPathInfo> _readFetchPaths(
    DataOrchestrator orch, List<String> names) {
  dynamic raw;
  try {
    raw = (orch as dynamic).fetchPaths;
  } catch (_) {
    raw = null;
  }
  if (raw is Map) {
    final result = <String, _FetchPathInfo>{};
    try {
      for (final entry in raw.entries) {
        final info = _parseFetchPath(entry.value);
        if (info != null) result['${entry.key}'] = info;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }
  // fetchPaths 缺失/非 Map → 逐源回退 fetchPathOf(name)。
  final result = <String, _FetchPathInfo>{};
  for (final name in names) {
    try {
      final info = _parseFetchPath((orch as dynamic).fetchPathOf(name));
      if (info != null) result[name] = info;
    } catch (_) {
      // 单源失败不影响其他源。
    }
  }
  return result;
}

/// 解析单条拉取路径（兼容对象形态 / Map 形态 / toJson 形态；异常 → null）。
_FetchPathInfo? _parseFetchPath(dynamic p) {
  if (p == null) return null;
  final map = _asMap(p);
  if (map == null) {
    // 对象形态且无 toJson → 动态 getter 逐字段。
    return _FetchPathInfo(
      steps: _parseSteps(_fetchPathMember(p, 'steps')),
      isActive: _asBool(_fetchPathMember(p, 'isActive') ??
              _fetchPathMember(p, 'active')) ??
          false,
      retryCount: _asInt(_fetchPathMember(p, 'retryCount') ??
              _fetchPathMember(p, 'retries')) ??
          0,
    );
  }
  return _FetchPathInfo(
    steps: _parseSteps(map['steps']),
    isActive: _asBool(map['isActive'] ?? map['active']) ?? false,
    retryCount: _asInt(map['retryCount'] ?? map['retries']) ?? 0,
  );
}

/// 统一为 Map 形态：Map 直接用；对象形态优先经 toJson() 转 Map（失败返回 null，
/// 调用方退回动态 getter）。
Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map) return v.cast<String, dynamic>();
  try {
    final json = (v as dynamic).toJson();
    if (json is Map) return json.cast<String, dynamic>();
  } catch (_) {
    // 无 toJson 或非 Map → 调用方退回动态 getter。
  }
  return null;
}

List<_FetchStepInfo> _parseSteps(dynamic raw) {
  if (raw is! List) return const [];
  final out = <_FetchStepInfo>[];
  for (final e in raw) {
    final step = _parseStep(e);
    if (step != null) out.add(step);
  }
  return out;
}

_FetchStepInfo? _parseStep(dynamic e) {
  if (e == null) return null;
  final map = _asMap(e);
  if (map != null) {
    final phase = _normalizePhase(map['phase']);
    if (phase.isEmpty) return null;
    return _FetchStepInfo(
      phase: phase,
      completed: _asBool(map['completed'] ?? map['done']) ?? false,
      at: _asDateTime(map['at'] ?? map['timestamp']),
    );
  }
  // 对象形态且无 toJson → 动态 getter。
  final phase = _normalizePhase(_fetchPathMember(e, 'phase'));
  if (phase.isEmpty) return null;
  return _FetchStepInfo(
    phase: phase,
    completed: _asBool(
            _fetchPathMember(e, 'completed') ?? _fetchPathMember(e, 'done')) ??
        false,
    at: _asDateTime(
        _fetchPathMember(e, 'at') ?? _fetchPathMember(e, 'timestamp')),
  );
}

/// 归一化阶段名：兼容枚举实例（`DataFetchPhase.fetching`）与字符串
/// （`"fetching"` / `"DataFetchPhase.fetching"`）→ 统一小写短名。
String _normalizePhase(dynamic v) {
  if (v == null) return '';
  final s = v is String ? v : v.toString();
  final dot = s.lastIndexOf('.');
  return (dot >= 0 ? s.substring(dot + 1) : s).trim().toLowerCase();
}

/// 对象形态的 getter 访问（缺字段抛 NoSuchMethodError → 返回 null）。
Object? _fetchPathMember(dynamic obj, String member) {
  try {
    return switch (member) {
      'steps' => obj.steps,
      'isActive' => obj.isActive,
      'active' => obj.active,
      'retryCount' => obj.retryCount,
      'retries' => obj.retries,
      'phase' => obj.phase,
      'completed' => obj.completed,
      'done' => obj.done,
      'at' => obj.at,
      'timestamp' => obj.timestamp,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// 组装轨迹展示节点序列：固定 6 阶段骨架 →（steps 中骨架外的未知阶段）→ 失败节点。
///
/// 由 [_FetchTrajectoryBar]（每源卡片轨迹条）与 [_MiniTrajectoryBar]（泳道迷你轨迹）
/// 共用，保证两处节点骨架/填充语义完全一致。
List<_TrajectoryNode> _composeTrajectoryNodes(
    _FetchPathInfo path, bool connected, String? lastError) {
  final byPhase = <String, _FetchStepInfo>{
    for (final s in path.steps) s.phase: s
  };
  final current = path.isActive ? path.currentStep : null;
  final doneCompleted = byPhase['done']?.completed ?? false;
  // 失败节点：steps 含 failed 阶段，或（未 done 完成但 lastError 存在且未连通）。
  final showFailed = byPhase.containsKey('failed') ||
      (lastError != null &&
          lastError.isNotEmpty &&
          !connected &&
          !doneCompleted);
  final nodes = <_TrajectoryNode>[];
  for (final phase in _kSkeletonPhases) {
    final step = byPhase[phase];
    nodes.add(_TrajectoryNode(
      phase: phase,
      step: step,
      isCurrent: current != null && current.phase == phase,
    ));
  }
  for (final s in path.steps) {
    if (!_kSkeletonPhases.contains(s.phase) && s.phase != 'failed') {
      nodes.add(_TrajectoryNode(
        phase: s.phase,
        step: s,
        isCurrent: current != null && current.phase == s.phase,
      ));
    }
  }
  if (showFailed) {
    nodes.add(_TrajectoryNode(
        phase: 'failed', step: byPhase['failed'], isFailed: true));
  }
  return nodes;
}

/// 轨迹节点间连线颜色（[_FetchTrajectoryBar] 与 [_MiniTrajectoryBar] 共用）：
/// 连向失败 → 红；连向进行中 → 主色；连向已完成 → 绿；否则灰。
Color _trajectorySegmentColor(ThemeData theme, _TrajectoryNode next) {
  if (next.isFailed) return _red(theme);
  if (next.isCurrent) return theme.colorScheme.primary;
  if (next.step != null && next.step!.completed) return _green(theme);
  return theme.colorScheme.outlineVariant;
}

/// 轨迹节点圆点（大小可参数化：大轨迹条 10dp，泳道迷你轨迹 6–8dp；颜色语义全派生
/// 自主题，[_FetchTrajectoryBar] 与 [_MiniTrajectoryBar] 共用）：失败红✗ / 已完成
/// 绿✓ / 进行中主色脉冲 / 已发生未完成主色描边 / 未发生空心灰。
Widget _trajectoryDot(
    BuildContext context, ThemeData theme, _TrajectoryNode node,
    {double size = 10, Animation<double>? pulse}) {
  final double borderWidth = (size * 0.15).clamp(1.0, 1.5).toDouble();
  if (node.isFailed) {
    final red = _red(theme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: red),
      alignment: Alignment.center,
      child: Icon(Icons.close_rounded, size: size * 0.75, color: _onColor(red)),
    );
  }
  if (node.step == null) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(
            color: theme.colorScheme.outlineVariant, width: borderWidth),
      ),
    );
  }
  if (node.step!.completed) {
    final green = _green(theme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: green),
      alignment: Alignment.center,
      child:
          Icon(Icons.check_rounded, size: size * 0.8, color: _onColor(green)),
    );
  }
  if (!node.isCurrent) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        border:
            Border.all(color: theme.colorScheme.primary, width: borderWidth),
      ),
    );
  }
  final anim = pulse;
  if (anim == null) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: theme.colorScheme.primary),
    );
  }
  // 进行中：轻量呼吸/脉冲（随共享 pulse 缩放 + 辉光，避免炫技）。
  return AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final t = 0.94 + 0.14 * anim.value;
      return Transform.scale(
        scale: t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary
                    .withValues(alpha: 0.25 + 0.35 * anim.value),
                blurRadius: 3 + 3 * anim.value,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 轨迹式阶段条：固定骨架 + 轨迹填充；横向（宽屏）/纵向（窄屏）随可用宽度自适应。
class _FetchTrajectoryBar extends StatelessWidget {
  const _FetchTrajectoryBar({
    required this.path,
    required this.hasHistory,
    required this.connected,
    this.lastError,
    required this.pulse,
  });

  final _FetchPathInfo path;

  /// 是否有历史数据（契约⑤：有缓存/历史时失败仅琥珀警告，绝不红色错误卡）。
  final bool hasHistory;

  final bool connected;
  final String? lastError;

  /// 共享呼吸脉冲动画（看板持有；仅进行中节点消费）。
  final Animation<double> pulse;

  /// 组装展示节点序列（与泳道迷你轨迹共用 [_composeTrajectoryNodes]，骨架/填充语义
  /// 完全一致）。
  List<_TrajectoryNode> _composeNodes() =>
      _composeTrajectoryNodes(path, connected, lastError);

  /// 节点间连线颜色（与泳道迷你轨迹共用 [_trajectorySegmentColor]，语义一致）：
  /// 连向失败 → 红；连向进行中 → 主色；连向已完成 → 绿；否则灰。
  Color _segmentColor(ThemeData theme, _TrajectoryNode next) =>
      _trajectorySegmentColor(theme, next);

  /// 节点圆点（颜色语义全派生自主题；与泳道迷你轨迹共用 [_trajectoryDot]）：
  /// 失败红✗ / 已完成绿✓ / 进行中主色脉冲 / 已发生未完成主色描边 / 未发生空心灰。
  Widget _nodeDot(
          BuildContext context, ThemeData theme, _TrajectoryNode node) =>
      _trajectoryDot(context, theme, node, pulse: pulse);

  /// 底部徽标行：重试次数（琥珀）与失败徽标 + lastError（契约⑤ 着色）。
  Widget? _buildFooter(ThemeData theme, List<_TrajectoryNode> nodes) {
    final rows = <Widget>[];
    if (path.isActive && path.retryCount > 0) {
      rows.add(Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 10,
          height: 10,
          child:
              CircularProgressIndicator(strokeWidth: 1.5, color: _warn(theme)),
        ),
        const SizedBox(width: 5),
        _TinyBadge(text: '重试 ${path.retryCount} 次', color: _warn(theme)),
      ]));
    }
    final failed = nodes.any((n) => n.isFailed);
    if (failed && !path.isActive) {
      // 契约⑤：有历史数据 → 琥珀警告；仅「从未拉取且失败」才允许红色。
      final color = hasHistory ? _warn(theme) : _red(theme);
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TinyBadge(text: '拉取失败', color: color),
          if (lastError != null && lastError!.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  lastError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.3, color: color),
                ),
              ),
            ),
          ],
        ],
      ));
    }
    if (rows.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: r),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = _composeNodes();
    final footer = _buildFooter(theme, nodes);
    return LayoutBuilder(builder: (context, cons) {
      final maxW = cons.maxWidth;
      var horizontal = maxW.isFinite && maxW >= _kTrajectoryBreakpoint;
      double nodeW = 0;
      if (horizontal) {
        nodeW = (maxW - _kConnectorWidth * (nodes.length - 1)) / nodes.length;
        // 节点标签放不下 → 强制退回纵向（小屏验收：任何宽度下无水平溢出）。
        if (nodeW < _kMinNodeLabelWidth) horizontal = false;
      }
      if (horizontal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < nodes.length; i++) ...[
                  _nodeCell(context, theme, nodes[i], nodeW),
                  if (i < nodes.length - 1)
                    Container(
                      width: _kConnectorWidth,
                      height: 2,
                      color: _segmentColor(theme, nodes[i + 1]),
                    ),
                ],
              ],
            ),
            if (footer != null) footer,
          ],
        );
      }
      // 纵向步骤条（stepper 形态）：节点垂直排列，连线从上到下。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 10,
                  child: Column(
                    children: [
                      _nodeDot(context, theme, nodes[i]),
                      if (i < nodes.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Container(
                            width: 2,
                            height: 8,
                            color: _segmentColor(theme, nodes[i + 1]),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      _phaseLabel(nodes[i].phase),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: nodes[i].isFailed
                            ? _red(theme)
                            : (nodes[i].isCurrent
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant),
                        fontWeight: (nodes[i].isCurrent || nodes[i].isFailed)
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (footer != null) footer,
        ],
      );
    });
  }

  /// 横向节点单元：节点 + 下方阶段名（字号随可用宽度缩放，标签超宽自动省略）。
  Widget _nodeCell(BuildContext context, ThemeData theme, _TrajectoryNode node,
      double width) {
    final showLabel = width >= _kMinNodeLabelWidth;
    final fontSize = width >= 36 ? 10.0 : 8.5;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _nodeDot(context, theme, node),
          if (showLabel) ...[
            const SizedBox(height: 3),
            Text(
              _phaseLabel(node.phase),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.0,
                color: node.isFailed
                    ? _red(theme)
                    : (node.isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant),
                fontWeight: (node.isCurrent || node.isFailed)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「当前调度」区——仅在 core 提供调度快照时展示（防御式，见 [_tryReadSchedulingSnapshot]）。
///
/// 反映串行（后台串行重试 / 待重试队列）与并行（并行拉取中）两条调度路径，以及
/// 最近后台刷新 / 下次自动刷新 / 串行重试策略；快照存在但无任务时展示中性「无任务」。
class _SchedulingCard extends StatelessWidget {
  final _SchedulingInfo info;
  const _SchedulingCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final rows = <Widget>[];
    if (info.retryInProgress) {
      rows.add(_SchedulingRow(
        icon: Icons.sync_rounded,
        color: _warn(theme),
        title: '后台串行重试中',
        trailing: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (info.retryQueue.isNotEmpty) {
      rows.add(_SchedulingRow(
        icon: Icons.hourglass_top_rounded,
        color: _warn(theme),
        title: '待重试 ${info.retryQueue.length} 项',
        detail: info.retryQueue.join(' · '),
      ));
    }
    if (info.inFlight.isNotEmpty) {
      rows.add(_SchedulingRow(
        icon: Icons.bolt_rounded,
        color: theme.colorScheme.primary,
        title: '并行拉取中 ${info.inFlight.length} 项',
        detail: info.inFlight.join(' · '),
      ));
    }
    if (info.lastBackgroundRefreshAt != null) {
      rows.add(_SchedulingRow(
        icon: Icons.history_rounded,
        color: muted,
        title: '最近后台刷新 ${_formatDateTime(info.lastBackgroundRefreshAt!)}',
      ));
    }
    // 下次自动刷新时刻（core 快照 `nextRefreshAt`）：字段缺失（core 尚未交付）不渲染；
    // 字段存在但为 null（startAutoRefresh 未开启）显示「自动刷新未开启」。
    if (info.nextRefreshKnown) {
      final next = info.nextRefreshAt;
      rows.add(_SchedulingRow(
        icon: Icons.event_available_rounded,
        color: next != null ? theme.colorScheme.primary : muted,
        title: next != null ? '下次自动刷新：${_formatClockHM(next)}' : '自动刷新未开启',
      ));
    }
    if (rows.isEmpty) {
      rows.add(_SchedulingRow(
        icon: Icons.check_circle_outline_rounded,
        color: muted,
        title: '当前无后台调度任务',
      ));
    }
    // 串行重试策略参数（core 快照只读回显，供看板展示）。
    final retryDelay = info.domainRetryDelay;
    final maxAttempts = info.domainRetryMaxAttempts;
    if (retryDelay != null || maxAttempts != null) {
      final parts = <String>[
        if (retryDelay != null) '延迟 ${_formatDuration(retryDelay)}',
        if (maxAttempts != null) '最多 $maxAttempts 次',
      ];
      rows.add(_SchedulingRow(
        icon: Icons.tune_rounded,
        color: theme.colorScheme.primary,
        title: '串行重试策略：${parts.join(' · ')}',
      ));
    }
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_rounded,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('当前调度',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// 调度区单行条目。
class _SchedulingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final Widget? trailing;
  const _SchedulingRow({
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// core 调度快照（只读展示用）。core 未提供该快照时，[_tryReadSchedulingSnapshot]
/// 返回 null，看板优雅降级并省略「当前调度」区。
class _SchedulingInfo {
  final bool retryInProgress;
  final List<String> retryQueue;
  final List<String> inFlight;
  final DateTime? lastBackgroundRefreshAt;

  /// 串行重试策略参数（core `DataSourceSchedulingSnapshot` 只读回显，供看板展示）。
  final Duration? domainRetryDelay;
  final int? domainRetryMaxAttempts;

  /// 下一次时钟对齐自动刷新 tick 时刻（core 快照 `nextRefreshAt`）。
  /// [nextRefreshKnown] 区分「字段缺失（core 尚未交付）」与「字段为 null
  /// （startAutoRefresh 未开启）」：缺失时不渲染该行，null 时渲染「自动刷新未开启」。
  final bool nextRefreshKnown;
  final DateTime? nextRefreshAt;
  const _SchedulingInfo({
    required this.retryInProgress,
    required this.retryQueue,
    required this.inFlight,
    this.lastBackgroundRefreshAt,
    this.domainRetryDelay,
    this.domainRetryMaxAttempts,
    this.nextRefreshKnown = false,
    this.nextRefreshAt,
  });
}

/// 防御式读取 core 的调度快照（core 子代理可能新增，确切名字未知）。
///
/// 候选 getter 名：`schedulingSnapshot` / `domainRetrySnapshot`。getter 不存在时
/// 抛 [NoSuchMethodError]，捕获后优雅降级（仅用 allStatuses）；值无法解析时同样
/// 返回 null。**绝不因快照缺失/异常而报错。**
_SchedulingInfo? _tryReadSchedulingSnapshot(DataOrchestrator orch) {
  dynamic snap;
  try {
    snap = (orch as dynamic).schedulingSnapshot;
  } catch (_) {
    try {
      snap = (orch as dynamic).domainRetrySnapshot;
    } catch (_) {
      return null;
    }
  }
  return _parseSchedulingSnapshot(snap);
}

/// 解析调度快照（兼容 Map 形态与对象形态；任何字段缺失/异常均取默认值）。
///
/// 解析策略：Map 直接用；对象形态**优先经 `toJson()` 转为 Map** 统一解析（core
/// `DataSourceSchedulingSnapshot` 含 toJson），无 toJson 时退回动态 getter 逐字段。
/// 当前 core 实际字段：`isRetrying` / `pendingRetryNames` / `lastBackgroundRefreshAt` /
/// `domainRetryDelay` / `domainRetryMaxAttempts`，并预留 `nextRefreshAt`（core 子代理
/// 正在追加：下一次时钟对齐自动刷新 tick 时刻）；同义字段名（retryInProgress /
/// retryQueue 等）为兼容未来改名/Map 形态保留。
_SchedulingInfo? _parseSchedulingSnapshot(dynamic snap) {
  if (snap == null) return null;

  // 统一为 Map 形态：Map 直接用；对象形态经 toJson() 转 Map（失败则走动态 getter）。
  Map<String, dynamic> map = <String, dynamic>{};
  var mapShape = false;
  if (snap is Map) {
    map = snap.cast<String, dynamic>();
    mapShape = true;
  } else {
    try {
      final json = (snap as dynamic).toJson();
      if (json is Map) {
        map = json.cast<String, dynamic>();
        mapShape = true;
      }
    } catch (_) {
      mapShape = false;
    }
  }

  Object? field(String name) => mapShape ? map[name] : _tryMember(snap, name);
  // 字段存在性（区分「core 未提供该字段」与「字段为 null」）。
  bool has(String name) =>
      mapShape ? map.containsKey(name) : _hasMember(snap, name);

  final retryInProgress = _asBool(field('isRetrying') ??
          field('retryInProgress') ??
          field('retrying') ??
          field('backgroundRetryRunning') ??
          field('domainRetryRunning')) ??
      false;
  final queueRaw = field('pendingRetryNames') ??
      field('retryQueue') ??
      field('pendingRetries') ??
      field('queue');
  final inFlightRaw =
      field('inFlight') ?? field('activeFetches') ?? field('parallelFetches');
  final lastBg = field('lastBackgroundRefreshAt') ?? field('lastRefreshAt');
  final nextRefreshKnown = has('nextRefreshAt') ||
      has('nextAutoRefreshAt') ||
      has('nextRefreshTime');
  final nextRefresh = _asDateTime(field('nextRefreshAt') ??
      field('nextAutoRefreshAt') ??
      field('nextRefreshTime'));
  return _SchedulingInfo(
    retryInProgress: retryInProgress,
    retryQueue: _namesFrom(queueRaw),
    inFlight: _namesFrom(inFlightRaw),
    lastBackgroundRefreshAt: _asDateTime(lastBg),
    domainRetryDelay:
        _asDuration(field('domainRetryDelay') ?? field('domainRetryDelayMs')),
    domainRetryMaxAttempts: _asInt(field('domainRetryMaxAttempts')),
    nextRefreshKnown: nextRefreshKnown,
    nextRefreshAt: nextRefresh,
  );
}

/// 对象形态快照的 getter 访问（动态分发，缺字段抛 NoSuchMethodError 时返回 null）。
Object? _tryMember(dynamic obj, String member) {
  try {
    return switch (member) {
      'isRetrying' => obj.isRetrying,
      'retryInProgress' => obj.retryInProgress,
      'retrying' => obj.retrying,
      'backgroundRetryRunning' => obj.backgroundRetryRunning,
      'domainRetryRunning' => obj.domainRetryRunning,
      'pendingRetryNames' => obj.pendingRetryNames,
      'retryQueue' => obj.retryQueue,
      'pendingRetries' => obj.pendingRetries,
      'queue' => obj.queue,
      'inFlight' => obj.inFlight,
      'activeFetches' => obj.activeFetches,
      'parallelFetches' => obj.parallelFetches,
      'lastBackgroundRefreshAt' => obj.lastBackgroundRefreshAt,
      'lastRefreshAt' => obj.lastRefreshAt,
      'domainRetryDelay' => obj.domainRetryDelay,
      'domainRetryDelayMs' => obj.domainRetryDelayMs,
      'domainRetryMaxAttempts' => obj.domainRetryMaxAttempts,
      'nextRefreshAt' => obj.nextRefreshAt,
      'nextAutoRefreshAt' => obj.nextAutoRefreshAt,
      'nextRefreshTime' => obj.nextRefreshTime,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// 对象形态快照字段是否存在（动态 getter：缺失抛 NoSuchMethodError → false；
/// 存在（含 null 值）→ true）。仅用于区分「core 未提供该字段」与「字段为 null」。
bool _hasMember(dynamic obj, String member) {
  try {
    final probe = switch (member) {
      'nextRefreshAt' => obj.nextRefreshAt,
      'nextAutoRefreshAt' => obj.nextAutoRefreshAt,
      'nextRefreshTime' => obj.nextRefreshTime,
      _ => _missingField,
    };
    return probe != _missingField;
  } catch (_) {
    return false;
  }
}

/// 字段缺失哨兵（见 [_hasMember]）。
const Object _missingField = Object();

/// 从快照字段解析数据源 name 列表（兼容 String / List<String> / List<Map> 形态）。
List<String> _namesFrom(dynamic raw) {
  if (raw == null) return const [];
  if (raw is String) return [raw];
  if (raw is List) {
    return raw.map((e) {
      if (e is String) return e;
      if (e is Map) {
        final name = e['name'] ?? e['displayName'] ?? e['sourceName'];
        return name?.toString() ?? '(未知)';
      }
      return e?.toString() ?? '(未知)';
    }).toList();
  }
  return const [];
}

bool? _asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
  }
  return null;
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// 解析串行重试延迟（兼容 Duration 对象 / 毫秒整数两种形态）。
Duration? _asDuration(dynamic v) {
  if (v == null) return null;
  if (v is Duration) return v;
  if (v is int) return Duration(milliseconds: v);
  if (v is num) return Duration(milliseconds: v.round());
  return null;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString().trim());
}

// ═══════════════════════════════════════════════════════════════════════════
// 主题派生色（明暗主题兼容）与时间格式化工具
// ═══════════════════════════════════════════════════════════════════════════

Color _green(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.green.shade300
    : Colors.green.shade600;

Color _stale(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.orange.shade300
    : Colors.orange.shade700;

Color _warn(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.amber.shade300
    : Colors.amber.shade800;

/// 失败红（仅轨迹节点与「从未拉取且失败」徽标使用；契约⑤：有历史数据时失败为琥珀警告）。
Color _red(ThemeData theme) => theme.brightness == Brightness.dark
    ? Colors.red.shade300
    : Colors.red.shade600;

/// 节点填充色上的图标对比色（亮色填充用深色图标，暗色填充用白色图标）。
Color _onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : Colors.black87;

String _two(int v) => v.toString().padLeft(2, '0');

/// 真实时间戳格式化（来自 DataSourceStatus.lastFetchedAt，不伪造）。
String _formatDateTime(DateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// 仅时分秒（看板轮询时间用）。
String _formatClock(DateTime dt) =>
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// 仅时分（下次自动刷新时刻用，HH:MM）。
String _formatClockHM(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';

/// 人性化时长（串行重试延迟用）。
String _formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} 秒';
  if (d.inMinutes < 60) return '${d.inMinutes} 分';
  return '${d.inHours} 时';
}
