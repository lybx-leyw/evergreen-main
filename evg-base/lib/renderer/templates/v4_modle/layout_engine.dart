/// 布局引擎 — v4_modle 的 5 种布局范式纯函数实现。
///
/// 从 [composite_view.dart] 中抽取，供 [SlotTreeRenderer] 和 [SlotDispatch]
/// 共用。无状态、纯函数，仅依赖 Flutter Widget 树。
///
/// 支持的布局范式：
/// - grid：多列等行高网格，纵向可滚动
/// - flex：弹性布局（Row/Column/Wrap），不可滚动，双向自适应
/// - fullscreen：单组件撑满
/// - absolute：绝对定位（Stack + Positioned）
/// - dock：停靠布局（top/bottom/left/right/center）
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';

/// 布局引擎——根据 [type] 分派到 5 种布局范式。
///
/// [children] 为子 slot 的 key→描述符映射。
/// [slotBuilder] 为单个 slot 的渲染回调，由调用方注入（CompositeView 或 SlotTreeRenderer）。
class LayoutEngine {
  /// 根据 [type] 和 [preset] 构建子 slot 排布。
  ///
  /// [entries] 为有序的 slot 条目列表。
  /// [slotBuilder] 是调用方提供的 slot→Widget 构建函数，用于递归渲染。
  static Widget build({
    required String type,
    required LayoutPreset preset,
    required Map<String, SlotDescriptor> slots,
    required String pageId,
    required ModuleDescriptor moduleDescriptor,
    required PageEventBus? bus,
    required Widget Function(MapEntry<String, SlotDescriptor> entry, String pageId, PageEventBus? bus) slotBuilder,
  }) {
    final entries = slots.entries.toList();
    if (entries.isEmpty) return const Center(child: Text('无内容'));

    return switch (type) {
      'grid'       => GridLayout(
          preset: preset,
          entries: entries,
          pageId: pageId,
          moduleDescriptor: moduleDescriptor,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
      'flex'       => FlexLayout(
          preset: preset,
          entries: entries,
          pageId: pageId,
          moduleDescriptor: moduleDescriptor,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
      'fullscreen' => FullscreenLayout(
          entries: entries,
          pageId: pageId,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
      'absolute'   => AbsoluteLayout(
          preset: preset,
          entries: entries,
          pageId: pageId,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
      'dock'       => DockLayout(
          preset: preset,
          entries: entries,
          pageId: pageId,
          moduleDescriptor: moduleDescriptor,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
      _            => FlexLayout(
          preset: const LayoutPreset(direction: 'column'),
          entries: entries,
          pageId: pageId,
          moduleDescriptor: moduleDescriptor,
          bus: bus,
          slotBuilder: slotBuilder,
        ),
    };
  }

  // ═══════ 辅助 ═══════

  static MainAxisAlignment mainAlign(String? v) => switch (v) {
    'end'     => MainAxisAlignment.end,
    'center'  => MainAxisAlignment.center,
    'between' => MainAxisAlignment.spaceBetween,
    'around'  => MainAxisAlignment.spaceAround,
    'evenly'  => MainAxisAlignment.spaceEvenly,
    _         => MainAxisAlignment.start,
  };

  static CrossAxisAlignment crossAlign(String? v) => switch (v) {
    'end'     => CrossAxisAlignment.end,
    'center'  => CrossAxisAlignment.center,
    'stretch' => CrossAxisAlignment.stretch,
    _         => CrossAxisAlignment.start,
  };

  static double? styleDouble(StyleDescriptor style, String key) {
    final v = switch (key) {
      'width' => style.width,
      'height' => style.height,
      'top' => style.top,
      'bottom' => style.bottom,
      'left' => style.left,
      'right' => style.right,
      _ => null,
    };
    return v is num ? v.toDouble() : null;
  }

  static double regionHeight(Map<String, dynamic>? regions, String key) {
    if (regions == null) return 0;
    final r = regions[key];
    if (r is Map) return (r['height'] as num?)?.toDouble() ?? 0;
    return 0;
  }

  static double regionWidth(Map<String, dynamic>? regions, String key) {
    if (regions == null) return 0;
    final r = regions[key];
    if (r is Map) return (r['width'] as num?)?.toDouble() ?? 0;
    return 0;
  }
}

// ═══════ Grid 布局 ═══════

class GridLayout extends StatelessWidget {
  final LayoutPreset preset;
  final List<MapEntry<String, SlotDescriptor>> entries;
  final String pageId;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? bus;
  final Widget Function(MapEntry<String, SlotDescriptor>, String, PageEventBus?) slotBuilder;

  const GridLayout({
    super.key,
    required this.preset,
    required this.entries,
    required this.pageId,
    required this.moduleDescriptor,
    required this.bus,
    required this.slotBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final columns = (preset.columns ?? 1).clamp(1, 12);
    final gap = (preset.gap ?? 16.0).toDouble();

    final rows = <List<MapEntry<String, SlotDescriptor>>>[];
    for (var i = 0; i < entries.length; i += columns) {
      final end = (i + columns < entries.length) ? i + columns : entries.length;
      rows.add(entries.sublist(i, end));
    }

    // 在 build 阶段预构建所有 slot 内容（不在 LayoutBuilder builder 内调用
    // slotBuilder）：builder 在 performLayout 阶段执行，若其中挂载含
    // Scrollable 的组件，ScrollPosition 初始化会 markNeedsLayout 重入，
    // 触发 '_debugDoingThisLayout' 断言（黑屏根因）。
    final slotWidgets = <MapEntry<String, SlotDescriptor>, Widget>{
      for (final e in entries) e: slotBuilder(e, pageId, bus),
    };

    // 2026-08-01: 单列单条目 → 跳过 SCSV，直接用全高填充（如数据中枢）。
    // SCSV 丢弃父级有界约束 → 子卡片 _buildSlotCardBody 走 UNBOUNDED 路径 →
    // Column(min) 而非 Column(max)+Expanded → 内容高度不够。
    if (columns == 1 && entries.length == 1) {
      final content = slotWidgets[entries.first]!;
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          debugPrint('[GRID_1x1] W=${maxW.isFinite ? maxW.toStringAsFixed(1) : "Inf"} '
              'H=${maxH.isFinite ? maxH.toStringAsFixed(1) : "Inf"} '
              '→ ${maxH.isFinite ? "FULL_HEIGHT" : "FALLBACK_600"}');
          final h = maxH.isFinite ? maxH : 600.0;
          return SizedBox(
            width: maxW.isFinite ? maxW : double.infinity,
            height: h,
            child: content,
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.all(gap),
      // SingleChildScrollView 在 LayoutBuilder 外层：在 builder 内创建
      // Scrollable 会在 performLayout 阶段挂载并重入 markNeedsLayout，
      // 触发 '_debugDoingThisLayout' 断言（黑屏根因）。
      child: SingleChildScrollView(
        child: LayoutBuilder(builder: (context, constraints) {
          final colWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
          // 滚动容器内纵向约束无限 → 行高取固定最小值（内容超高时滚动）。
          const minRowH = 220.0;
          final rowHeight = minRowH;

        final gridRows = Column(
          mainAxisSize: MainAxisSize.min,
          children: rows.map((row) => SizedBox(
            height: rowHeight,
            child: Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(columns, (i) {
                  if (i >= row.length) return SizedBox(width: colWidth);
                  final entry = row[i];
                  Widget content = slotWidgets[entry]!;
                  content = ScaledSlot(
                    slotWidth: colWidth,
                    slotHeight: rowHeight,
                    scrollableV: true,
                    scrollableH: false,
                    child: content,
                  );
                  return SizedBox(
                    width: colWidth,
                    child: Padding(
                      padding: EdgeInsets.only(right: i < columns - 1 ? gap : 0),
                      child: content,
                    ),
                  );
                }),
              ),
            ),
          )).toList(),
        );

        return gridRows;
        }),
      ),
    );
  }
}

// ═══════ Flex 布局 ═══════

class FlexLayout extends StatelessWidget {
  final LayoutPreset preset;
  final List<MapEntry<String, SlotDescriptor>> entries;
  final String pageId;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? bus;
  final Widget Function(MapEntry<String, SlotDescriptor>, String, PageEventBus?) slotBuilder;

  const FlexLayout({
    super.key,
    required this.preset,
    required this.entries,
    required this.pageId,
    required this.moduleDescriptor,
    required this.bus,
    required this.slotBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final direction = preset.direction ?? 'column';
    final gap = (preset.gap ?? 16.0).toDouble();
    final wrap = preset.wrap ?? false;
    final justify = LayoutEngine.mainAlign(preset.justify);
    final align = LayoutEngine.crossAlign(preset.align);

    // 预构建 slot 内容（见 GridLayout 注释：避免在 performLayout 阶段挂载）
    final slotWidgets = <MapEntry<String, SlotDescriptor>, Widget>{
      for (final e in entries) e: slotBuilder(e, pageId, bus),
    };

    if (wrap) {
      return Padding(
        padding: EdgeInsets.all(gap),
        child: LayoutBuilder(builder: (context, constraints) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: entries.map((e) => ScaledSlot(
              slotWidth: constraints.maxWidth,
              slotHeight: constraints.maxHeight,
              scrollableH: false,
              scrollableV: false,
              child: slotWidgets[e]!,
            )).toList(),
          );
        }),
      );
    }

    final slotCount = entries.length;
    return Padding(
      padding: EdgeInsets.all(gap),
      child: LayoutBuilder(builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight.isFinite ? constraints.maxHeight : 400.0;

        final children = <Widget>[];
        for (var i = 0; i < entries.length; i++) {
          if (i > 0) {
            children.add(SizedBox(
              width: direction == 'row' ? gap : 0,
              height: direction == 'column' ? gap : 0,
            ));
          }
          final e = entries[i];
          Widget slotWidget = slotWidgets[e]!;

          slotWidget = ScaledSlot(
            slotWidth: direction == 'row'
                ? (availW - gap * (slotCount - 1)) / slotCount
                : availW,
            slotHeight: direction == 'column'
                ? (availH - gap * (slotCount - 1)) / slotCount
                : availH,
            scrollableH: false,
            scrollableV: false,
            child: slotWidget,
          );
          children.add(Expanded(child: slotWidget));
        }

        return direction == 'row'
            ? Row(crossAxisAlignment: align, mainAxisAlignment: justify, children: children)
            : Column(crossAxisAlignment: align, mainAxisAlignment: justify, children: children);
      }),
    );
  }
}

// ═══════ Fullscreen 布局 ═══════

class FullscreenLayout extends StatelessWidget {
  final List<MapEntry<String, SlotDescriptor>> entries;
  final String pageId;
  final PageEventBus? bus;
  final Widget Function(MapEntry<String, SlotDescriptor>, String, PageEventBus?) slotBuilder;

  const FullscreenLayout({
    super.key,
    required this.entries,
    required this.pageId,
    required this.bus,
    required this.slotBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // 预构建 slot 内容（避免在 performLayout 阶段挂载，见 GridLayout 注释）
    final slotWidget = slotBuilder(entries.first, pageId, bus);
    // LayoutBuilder 获取父级真实有界约束（TabBarView → PageView → 本 Widget），
    // 再将 bounded width/height 注入子组件。若使用 SizedBox.expand，子组件
    // 会收到 infinity 约束，而 _buildSlotCardBody 的 Column(min) 不收缩其高度，
    // 导致内部 Expanded（如 ScraperGeneratorView 的 Column+Expanded）被分配
    // 0 高度 → 内容不可见 → 黑屏。
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        debugPrint('[FULLSCREEN] W=${maxW.isFinite ? maxW.toStringAsFixed(1) : "Inf"} '
            'H=${maxH.isFinite ? maxH.toStringAsFixed(1) : "Inf"} '
            '→ ${(maxW.isFinite && maxH.isFinite) ? "BOUNDED(SizedBox)" : "UNBOUNDED(fallback)"}');
        if (maxW.isFinite && maxH.isFinite) {
          return SizedBox(width: maxW, height: maxH, child: slotWidget);
        }
        // 退化：父级无界约束时直接渲染（极少发生，仅在测量/松约束阶段）
        debugPrint('[FULLSCREEN] WARNING: unbounded constraints — slot may collapse to 0 height');
        return slotWidget;
      },
    );
  }
}

// ═══════ Absolute 布局 ═══════

class AbsoluteLayout extends StatelessWidget {
  final LayoutPreset preset;
  final List<MapEntry<String, SlotDescriptor>> entries;
  final String pageId;
  final PageEventBus? bus;
  final Widget Function(MapEntry<String, SlotDescriptor>, String, PageEventBus?) slotBuilder;

  const AbsoluteLayout({
    super.key,
    required this.preset,
    required this.entries,
    required this.pageId,
    required this.bus,
    required this.slotBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // 预构建 slot 内容（避免在 performLayout 阶段挂载，见 GridLayout 注释）
    final slotWidgets = <MapEntry<String, SlotDescriptor>, Widget>{
      for (final e in entries) e: slotBuilder(e, pageId, bus),
    };
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: entries.map((e) {
          final style = e.value.style;
          final topF = LayoutEngine.styleDouble(style, 'top');
          final bottomF = LayoutEngine.styleDouble(style, 'bottom');
          final leftF = LayoutEngine.styleDouble(style, 'left');
          final rightF = LayoutEngine.styleDouble(style, 'right');
          final wF = LayoutEngine.styleDouble(style, 'width');
          final hF = LayoutEngine.styleDouble(style, 'height');
          double? toPxW(double? fraction) => fraction == null ? null : fraction * constraints.maxWidth;
          double? toPxH(double? fraction) => fraction == null ? null : fraction * constraints.maxHeight;
          final top = toPxH(topF);
          final bottom = toPxH(bottomF);
          final left = toPxW(leftF);
          final right = toPxW(rightF);
          final wD = (wF != null)
              ? wF * constraints.maxWidth
              : (left != null && right != null) ? constraints.maxWidth - left - right! : constraints.maxWidth;
          final hD = (hF != null)
              ? hF * constraints.maxHeight
              : (top != null && bottom != null) ? constraints.maxHeight - top - bottom! : constraints.maxHeight;
          return Positioned(
            top: top, bottom: bottom, left: left, right: right,
            width: wD, height: hD,
            child: ScaledSlot(
              slotWidth: wD, slotHeight: hD,
              scrollableH: false, scrollableV: false,
              constrain: true,
              child: slotWidgets[e]!,
            ),
          );
        }).toList(),
      );
    });
  }
}

// ═══════ Dock 布局 ═══════

class DockLayout extends StatelessWidget {
  final LayoutPreset preset;
  final List<MapEntry<String, SlotDescriptor>> entries;
  final String pageId;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? bus;
  final Widget Function(MapEntry<String, SlotDescriptor>, String, PageEventBus?) slotBuilder;

  const DockLayout({
    super.key,
    required this.preset,
    required this.entries,
    required this.pageId,
    required this.moduleDescriptor,
    required this.bus,
    required this.slotBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final regions = preset.regions;
    final topH = LayoutEngine.regionHeight(regions, 'top');
    final bottomH = LayoutEngine.regionHeight(regions, 'bottom');
    final leftW = LayoutEngine.regionWidth(regions, 'left');
    final rightW = LayoutEngine.regionWidth(regions, 'right');

    // 预构建 slot 内容（避免在 performLayout 阶段挂载，见 GridLayout 注释）
    final slotWidgets = <MapEntry<String, SlotDescriptor>, Widget>{
      for (final e in entries) e: slotBuilder(e, pageId, bus),
    };

    return LayoutBuilder(builder: (context, constraints) {
      final cw = constraints.maxWidth - leftW - rightW;
      final ch = constraints.maxHeight - topH - bottomH;

      MapEntry<String, SlotDescriptor>? findIn(String key) {
        final idx = entries.indexWhere((e) => e.key == key);
        return idx >= 0 ? entries[idx] : null;
      }

      Widget? top = findIn('top') != null
          ? SizedBox(width: constraints.maxWidth, height: topH,
              child: ScaledSlot(slotWidth: constraints.maxWidth, slotHeight: topH,
                  scrollableH: false, scrollableV: false,
                  child: slotWidgets[findIn('top')]!))
          : null;

      Widget? bottom = findIn('bottom') != null
          ? SizedBox(width: constraints.maxWidth, height: bottomH,
              child: ScaledSlot(slotWidth: constraints.maxWidth, slotHeight: bottomH,
                  scrollableH: false, scrollableV: false,
                  child: slotWidgets[findIn('bottom')]!))
          : null;

      Widget? left = findIn('left') != null
          ? SizedBox(width: leftW,
              child: ScaledSlot(slotWidth: leftW, slotHeight: ch,
                  scrollableH: false, scrollableV: false,
                  child: slotWidgets[findIn('left')]!))
          : null;

      Widget? right = findIn('right') != null
          ? SizedBox(width: rightW,
              child: ScaledSlot(slotWidth: rightW, slotHeight: ch,
                  scrollableH: false, scrollableV: false,
                  child: slotWidgets[findIn('right')]!))
          : null;

      final centerEntry = findIn('center') ?? findIn('fill') ?? findIn('middle') ??
          entries.where((e) => !['top','bottom','left','right'].contains(e.key)).firstOrNull ??
          entries.first;

      final center = ScaledSlot(
        slotWidth: cw, slotHeight: ch,
        scrollableH: false, scrollableV: false,
        child: slotWidgets[centerEntry]!,
      );

      return Column(children: [
        if (top != null) top,
        Expanded(child: Row(children: [
          if (left != null) left,
          Expanded(child: center),
          if (right != null) right,
        ])),
        if (bottom != null) bottom,
      ]);
    });
  }
}
