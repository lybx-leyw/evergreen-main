/// 展示类 slot 的数据源注入基类——M2 组件级接入的统一骨架。
///
/// 职责（遵循 M2 规则 R2/R4/R5/R7）：
/// - 转为 ConsumerState，可直接 [ref.read(dataOrchestratorProvider) 取用数据中枢；
/// - Future 记忆化：在 [initState] 创建一次，避免父级重建导致重复拉取；
/// - 拉取到的数据经 [mergeData] 合并进静态 config，再交给 [buildStatic] 渲染；
/// - 优雅降级：拉取失败 / 返回 null 时保留静态 config（绝不白屏/崩溃）；
/// - 无 `dataSource` 时直接走静态渲染（向后兼容 R4）。
///
/// 子类只需：构造透传 config、实现 [buildStatic]，必要时覆写 [mergeData]
/// （不同组件拉取数据落入的 config 字段不同，如 chart→`data`、card-list→`cards`）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/data/data_source_resolver.dart';

abstract class DataSourceSlot extends ConsumerStatefulWidget {
  final ComponentDescriptor config;

  const DataSourceSlot({super.key, required this.config});
}

abstract class DataSourceSlotState<T extends DataSourceSlot>
    extends ConsumerState<T> {
  Future<dynamic>? _future;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final ds = widget.config.dataSource;
    if (ds == null) return; // 无 dataSource → 直接静态渲染
    _future = resolveDataSource(
      ds: ds,
      orch: ref.read(dataOrchestratorProvider),
    );
    _startAutoRefresh(ds);
  }

  /// 按 [DataSourceDescriptor.refreshInterval]（秒）周期性重新拉取并刷新 UI。
  /// 0 / 负数 = 不刷新。离开页面由 [dispose] 释放 Timer（R5 无泄漏）。
  void _startAutoRefresh(DataSourceDescriptor ds) {
    final secs = ds.refreshInterval;
    if (secs <= 0) return;
    _timer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted) return;
      setState(() {
        _future = resolveDataSource(
          ds: ds,
          orch: ref.read(dataOrchestratorProvider),
          forceRefresh: true,
        );
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// 将拉取到的数据合并进静态 config。
  ///
  /// 默认：Map → 逐项覆盖；其余（标量/List）→ 原样返回 base，由子类覆写处理特定字段。
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    final merged = <String, dynamic>{...base};
    if (resolved is Map<String, dynamic>) merged.addAll(resolved);
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.dataSource == null) {
      return buildStatic(widget.config.config);
    }
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (ctx, snap) {
        final merged = mergeData(widget.config.config, snap.data);
        return buildStatic(merged);
      },
    );
  }

  /// 用（可能已注入数据的）config 渲染静态视图。
  Widget buildStatic(Map<String, dynamic> cfg);
}
