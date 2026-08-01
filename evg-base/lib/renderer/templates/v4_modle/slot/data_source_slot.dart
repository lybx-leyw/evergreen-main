/// 展示类 slot 的数据源注入基类——v5P Phase 2 升级版：三步骤管道。
///
/// 职责：
/// - 转为 ConsumerState，可直接 [ref.read(dataOrchestratorProvider)] 取用数据中枢；
/// - Future 记忆化：在 [initState] 创建一次，避免父级重建导致重复拉取；
/// - **管道三步骤**：归一化 → 字段映射 → 注入 config → 交给 [buildStatic] 渲染；
/// - 优雅降级：拉取失败 / 返回 null 时保留静态 config（绝不白屏/崩溃）；
/// - 无 `dataSource` 时直接走静态渲染（向后兼容 R4）。
///
/// # Phase 2 升级：管道前置
///
/// 原先子类覆写 [mergeData] 各自处理数据格式差异。
/// Phase 2 改为统一管道：
/// 1. [DataNormalizer.normalize] — 格式归一化（CSV/XML/JSON → NormalizedData）
/// 2. [DataMapping.applyFieldMap] — 字段映射（外部字段名 → 内部字段名）
/// 3. 注入 targetKey → [buildStatic]
///
/// 子类只需覆写 [buildStatic] 和声明式 [dataMapping] / [expectedShape]。
library;

export 'package:evergreen_base/renderer/templates/v4_modle/data/data_mapping.dart' show DataMapping;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/data/normalized_data.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/data/data_normalizer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/data/data_mapping.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/data/component_shape.dart';

abstract class DataSourceSlot extends ConsumerStatefulWidget {
  final ComponentDescriptor config;

  const DataSourceSlot({super.key, required this.config});

  /// 声明式字段映射（Phase 2 新增）。
  /// 覆写此方法替代旧的 [mergeData]。
  DataMapping get dataMapping => const DataMapping();

  /// 组件期望的数据形状（Phase 2 新增）。
  /// 用于 DataNormalizer 优化推断策略。
  DataShape get expectedShape => DataShape.simpleList;
}

abstract class DataSourceSlotState<T extends DataSourceSlot> extends ConsumerState<T> {
  Future<dynamic>? _future;
  Timer? _timer;

  bool get _hasDataSource {
    final ds = widget.config.dataSource;
    return ds != null && ds.endpoint != null && ds.endpoint!.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (!_hasDataSource) return; // 无数据端点 → 直接静态渲染
    _future = resolveDataSource(
      ds: widget.config.dataSource!,
      orch: ref.read(dataOrchestratorProvider),
    );
    _startAutoRefresh(widget.config.dataSource!);
  }

  /// 按 [DataSourceDescriptor.refreshInterval]（秒）周期性重新拉取并刷新 UI。
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

  // ═══════ Phase 2 管道 ═══════

  /// 应用管道三步骤：归一化 → 字段映射 → 注入 config。
  ///
  /// 步骤说明：
  /// 1. [DataNormalizer.normalize] — 格式归一化（CSV/XML/API → [NormalizedData]）
  /// 2. [DataMapping.applyFieldMap] — 字段映射（外部字段名 → 内部字段名）
  /// 3. 注入 [DataMapping.targetKey] → 基础 config
  ///
  /// 如果组件单独覆写了 [mergeData]（旧路径），优先使用旧逻辑（deprecated 兼容期）。
  Map<String, dynamic> _applyPipeline(Map<String, dynamic> base, dynamic raw) {
    if (raw == null) return base;

    // 步骤 1：归一化
    final normalized = DataNormalizer.normalize(raw);

    // 步骤 2：字段映射 + 目标形状转换
    final mapping = widget.dataMapping;

    // 从 normalized.payload 中按 sourcePath 取值
    dynamic resolved = DataMapping.resolvePath(normalized.payload, mapping.sourcePath);

    // 如果 resolved 为 null 且 skipIfNull → 保留静态 config
    if (resolved == null && mapping.skipIfNull) return base;

    // 字段映射：仅对 simpleList 形状生效
    if (normalized.shape == DataShape.simpleList && mapping.fieldMap.isNotEmpty && resolved is List) {
      resolved = mapping.applyFieldMap(List<Map<String, dynamic>>.from(resolved));
    }

    // 步骤 3：注入 targetKey
    final merged = <String, dynamic>{...base};
    merged[mapping.targetKey] = resolved ?? base[mapping.targetKey];
    return merged;
  }

  // ═══════ 旧的 mergeData（保留兼容） ═══════

  /// [@Deprecated] 使用 [dataMapping] 替代。将在 v4_modle v2 移除。
  ///
  /// 如果子类覆写了此方法，管道跳过，直接使用此方法的返回值。
  /// 未覆写的子类走新管道。
  @Deprecated('Use dataMapping instead.')
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    return base;
  }

  // ═══════ build ═══════

  @override
  Widget build(BuildContext context) {
    if (!_hasDataSource) {
      return buildStatic(widget.config.config);
    }
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (ctx, snap) {
        // Phase 2: 统一管道
        final merged = _applyPipeline(widget.config.config, snap.data);
        return buildStatic(merged);
      },
    );
  }

  /// 用（可能已注入数据的）config 渲染静态视图。
  Widget buildStatic(Map<String, dynamic> cfg);
}
