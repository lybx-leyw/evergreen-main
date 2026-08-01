/// StatTile 槽位——从 [ComponentDescriptor.config] 读取数据渲染 KPI 卡片。
/// 支持 M2 dataSource 注入：拉取到的数据合并进 config（Map 逐项覆盖；标量写入 value）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/dashboard_card.dart';

/// StatTile 组件——读取 config 中的 title/value/subtitle/trend/trendUp。
class StatTileSlot extends DataSourceSlot {
  const StatTileSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定 — 标量值注入 value
  @override
  DataMapping get dataMapping => const DataMapping(targetKey: 'value');

  @override
  DataSourceSlotState<StatTileSlot> createState() => _StatTileSlotState();
}

class _StatTileSlotState extends DataSourceSlotState<StatTileSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final title = cfg['title'] as String? ?? '';
    final value = cfg['value']?.toString() ?? '';
    final subtitle = cfg['subtitle'] as String?;
    final trend = cfg['trend'] as String? ?? '';
    final trendUp = cfg['trendUp'] as bool? ?? false;

    // 将 trendUp 映射为 DashboardCard 可识别的趋势文本
    final trendKey = trendUp
        ? 'up'
        : (cfg['trendDown'] as bool? ?? false)
            ? 'down'
            : (trend.isEmpty ? 'neutral' : trend);

    return DashboardCard(
      title: title,
      value: value.isEmpty ? '--' : value,
      trend: trendKey,
      subtitle: subtitle,
      cardTheme: _themeFromTitle(title),
    );
  }

  static DashboardCardTheme _themeFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('组件') || t.contains('模块')) return DashboardCardTheme.blue;
    if (t.contains('http') || t.contains('server') || t.contains('端点')) {
      return DashboardCardTheme.green;
    }
    if (t.contains('服务') || t.contains('runtime')) {
      return DashboardCardTheme.orange;
    }
    if (t.contains('用户') || t.contains('session')) {
      return DashboardCardTheme.purple;
    }
    return DashboardCardTheme.teal;
  }
}


