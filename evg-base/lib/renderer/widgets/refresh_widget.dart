/// 下拉刷新包装器——根据 [RefreshDescriptor] 配置刷新行为。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 下拉刷新 + 自动刷新包装器。
///
/// 读取 [RefreshDescriptor] 配置：
/// - [RefreshDescriptor.enabled] — 是否启用刷新
/// - [RefreshDescriptor.pullToRefresh] — 是否启用下拉刷新
/// - [RefreshDescriptor.autoInterval] — 自动刷新间隔（秒），0 = 不自动
class RefreshWidget extends StatefulWidget {
  final RefreshDescriptor? refreshConfig;
  final Future<void> Function()? onRefresh;
  final Widget child;

  const RefreshWidget({
    super.key,
    this.refreshConfig,
    this.onRefresh,
    required this.child,
  });

  @override
  State<RefreshWidget> createState() => _RefreshWidgetState();
}

class _RefreshWidgetState extends State<RefreshWidget> {
  Timer? _autoTimer;

  bool get _enabled => widget.refreshConfig?.enabled ?? false;
  bool get _pullToRefresh => widget.refreshConfig?.pullToRefresh ?? true;
  int get _autoInterval => widget.refreshConfig?.autoInterval ?? 0;

  @override
  void initState() {
    super.initState();
    _setupAutoRefresh();
  }

  @override
  void didUpdateWidget(covariant RefreshWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshConfig?.autoInterval !=
        widget.refreshConfig?.autoInterval) {
      _setupAutoRefresh();
    }
  }

  void _setupAutoRefresh() {
    _autoTimer?.cancel();
    if (_autoInterval > 0 && _enabled) {
      _autoTimer = Timer.periodic(
        Duration(seconds: _autoInterval),
        (_) => widget.onRefresh?.call(),
      );
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    if (!_pullToRefresh) return widget.child;

    return RefreshIndicator(
      onRefresh: () => widget.onRefresh?.call() ?? Future.value(),
      child: widget.child,
    );
  }
}
