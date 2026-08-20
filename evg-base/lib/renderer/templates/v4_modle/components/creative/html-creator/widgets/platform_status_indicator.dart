/// 平台服务状态指示器 —— 6 组 core 服务（Agent/Config/Data/Module/Theme/Core）
/// 的端口可达性体检入口（规划 B6）。
///
/// ## 设计
/// - 复用 A1 端口发现模块 [CoreApiDiscovery]（读 projectRoot 下 `.xxx_port` 文件）。
/// - 两级探测：端口文件存在性 → HTTP health（`GET /health` / `GET /xxx/health`）。
/// - 三态：绿(可达) / 灰(文件缺失，未启动) / 红(文件在但 HTTP 不通)。
/// - 紧凑形态：工具栏右侧一个状态徽章，点击弹出详情对话框（逐服务三态 + 手动重扫）。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart';

/// 服务中文名（UI 展示）。
const Map<CoreService, String> _serviceLabels = {
  CoreService.agent: 'Agent',
  CoreService.config: 'Config',
  CoreService.data: 'Data',
  CoreService.module: 'Module',
  CoreService.theme: 'Theme',
  CoreService.core: 'Core',
};

/// 状态 → (颜色, 文案, 图标)。
(Color, String, IconData) _stateStyle(ServiceReachability r) => switch (r) {
      ServiceReachability.reachable => (
          const Color(0xFF2E7D32), '可达', Icons.check_circle_outline),
      ServiceReachability.missing => (
          Colors.grey, '未启动', Icons.radio_button_unchecked),
      ServiceReachability.invalidPort => (
          Colors.orange, '端口文件异常', Icons.warning_amber_rounded),
      ServiceReachability.degraded => (
          Colors.red, 'HTTP 不通', Icons.error_outline),
    };

class PlatformStatusIndicator extends StatefulWidget {
  const PlatformStatusIndicator({super.key});

  @override
  State<PlatformStatusIndicator> createState() => _PlatformStatusIndicatorState();
}

class _PlatformStatusIndicatorState extends State<PlatformStatusIndicator> {
  List<CoreServiceStatus>? _statuses; // null = 未探测完成
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() => _probing = true);
    final results = await coreApiDiscovery.probeAll();
    if (!mounted) return;
    setState(() {
      _statuses = results;
      _probing = false;
    });
    debugPrint('[PlatformStatus] 探测完成: '
        '${results.map((s) => '${s.service.id}=${s.reachability.name}').join(', ')}');
  }

  /// 汇总态：红(有 degraded) > 绿(全 reachable) > 灰(其余)。
  ServiceReachability get _summary {
    final st = _statuses;
    if (st == null) return ServiceReachability.missing;
    if (st.any((s) => s.reachability == ServiceReachability.degraded)) {
      return ServiceReachability.degraded;
    }
    if (st.every((s) => s.reachability == ServiceReachability.reachable)) {
      return ServiceReachability.reachable;
    }
    return ServiceReachability.missing;
  }

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _stateStyle(_summary);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '平台服务状态：${_statuses == null ? "探测中…" : label}'
          '（点击查看 6 组 core 服务体检）',
      child: OutlinedButton.icon(
        onPressed: () => _showDialog(context),
        icon: _probing
            ? const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5))
            : Icon(icon, size: 14, color: color),
        label: Text(
          _probing ? '探测中' : label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
      ),
    );
  }

  Future<void> _showDialog(BuildContext context) async {
    // 打开对话框时重扫一次，保证看到的即是最新状态。
    await _probe();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.dns_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('平台服务状态', style: TextStyle(fontSize: 16)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {});
                _probe();
              },
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重扫', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        content: ConstrainedBox(
          // 自适应宽度：宽屏 420 封顶，窄屏（安卓手机 ~360dp 减对话框边距）
          // 自动收缩，避免固定 420 在窄屏上横向超格；纵向超出时整体可滚动，
          // 长错误文本 / 多条目不再裁剪。
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: _statuses == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summaryStrip(),
                      const Divider(height: 12),
                      for (final s in _statuses!) _serviceRow(s),
                      const SizedBox(height: 8),
                      _legendRow(),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 汇总条：共 X 项 · 可达 Y · 异常 Z · 未启动 W。
  Widget _summaryStrip() {
    final st = _statuses!;
    final reach = st.where((s) => s.reachability == ServiceReachability.reachable).length;
    final degrade = st.where((s) => s.reachability == ServiceReachability.degraded).length;
    final missing = st.length - reach - degrade;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '共 ${st.length} 项 · 可达 $reach · 异常 $degrade · 未启动 $missing',
        style: TextStyle(
          fontSize: 12,
          color: _summary == ServiceReachability.degraded
              ? Colors.red
              : _summary == ServiceReachability.reachable
                  ? const Color(0xFF2E7D32)
                  : Colors.grey.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 单个服务行：状态点 + 服务名 + 端口 + 状态文案。
  Widget _serviceRow(CoreServiceStatus s) {
    final (color, label, icon) = _stateStyle(s.reachability);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              _serviceLabels[s.service]!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.port != null ? '端口 ${s.port}' : '—',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              s.error != null && s.reachability != ServiceReachability.missing
                  ? '$label · ${s.error}'
                  : label,
              style: TextStyle(fontSize: 11, color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// 图例。
  Widget _legendRow() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _legendDot(const Color(0xFF2E7D32), '可达'),
        const SizedBox(width: 12),
        _legendDot(Colors.grey, '未启动'),
        const SizedBox(width: 12),
        _legendDot(Colors.orange, '端口文件异常'),
        const SizedBox(width: 12),
        _legendDot(Colors.red, 'HTTP 不通'),
        const SizedBox(width: 12),
        // 端口文件路径可能很长（安卓 app 私有目录）——必须 Expanded 包裹 +
        // 省略号截断，否则长路径会把整行 Row 撑出容器（横向超格）。
        Expanded(
          child: Text(
            '端口文件: ${coreApiDiscovery.projectRoot}',
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
