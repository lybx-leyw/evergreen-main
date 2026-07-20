/// 设计 → Manifest 编译器 —— DesignDocument → 标准 manifest.json。
///
/// 比 [PreviewSyncService] 更精细的编译器，支持分页/分组/依赖注入。
library;

import 'dart:convert';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';

/// 设计文档 → manifest.json 编译器。
class DesignToManifest {
  /// 编译设计文档为 manifest JSON 字符串。
  static String compileToJson(DesignDocument doc) {
    return const JsonEncoder.withIndent('  ').convert(compile(doc));
  }

  /// 编译设计文档为 manifest Map。
  ///
  /// 输出严格对齐真实 manifest V2（见 plugins/showcase-v3/module/manifest.json），
  /// 并能被 [ModuleDescriptor.fromJson] 正确解析。
  static Map<String, dynamic> compile(DesignDocument doc) {
    final pages = <Map<String, dynamic>>[];
    for (final designPage in doc.pages) {
      pages.add(_compilePage(doc, designPage));
    }

    return <String, dynamic>{
      'schemaVersion': '2.0',
      'renderMode': 'dart',
      'type': 'module',
      'id': doc.pluginId,
      'name': doc.pluginName,
      if (doc.icon != null) 'icon': doc.icon,
      if (doc.description != null) 'description': doc.description,
      if (doc.route != null) 'route': doc.route,
      'ui': 'composite',
      'version': doc.version,
      'dependencies': doc.dependencies,
      'nav': <String, dynamic>{
        'sidebar': <String, dynamic>{
          'section': doc.nav.section,
          'sectionOrder': doc.nav.sectionOrder,
          'order': doc.nav.order,
          'badge': doc.nav.badge,
        },
      },
      'process':
          doc.process.map((p) => p.toJson()).toList(),
      'pages': pages,
      if (doc.metadata.isNotEmpty) 'metadata': doc.metadata,
    };
  }

  static Map<String, dynamic> _compilePage(
      DesignDocument doc, DesignPage page) {
    final slots = <String, Map<String, dynamic>>{};
    for (final slot in page.slots) {
      slots[slot.id] = <String, dynamic>{
        if (slot.label.isNotEmpty) 'label': slot.label,
        'region': slot.region.name,
        if (page.layoutPreset == DesignPageLayout.absolute) ..._compileAbsolutePosition(slot),
        if (slot.component != null)
          'component': <String, dynamic>{
            'type': slot.component!.type,
            if (slot.component!.config.isNotEmpty)
              'config': slot.component!.config,
          },
      };
    }

    return <String, dynamic>{
      'id': page.id,
      'label': page.label,
      'default': page.isDefault,
      'hideTab': page.hideTab,
      'layout': <String, dynamic>{
        'type': page.layoutPreset.name,
        'preset': _compilePreset(page),
        'slots': slots,
      },
    };
  }

  /// 编译布局预设超参数。
  static Map<String, dynamic> _compilePreset(DesignPage page) {
    return switch (page.layoutPreset) {
      DesignPageLayout.grid => {
          'columns': page.gridColumns.clamp(1, 12),
          'gap': page.gridGap,
        },
      DesignPageLayout.flex => {
          'direction': page.flexDirection,
          'gap': page.flexGap,
          'justify': page.flexJustify,
          'align': page.flexAlign,
          if (page.flexWrap) 'wrap': true,
        },
      DesignPageLayout.dock => {
          if (page.dockRegions != null) 'regions': page.dockRegions,
        },
      DesignPageLayout.absolute => <String, dynamic>{},
      DesignPageLayout.fullscreen => <String, dynamic>{},
    };
  }

  /// 编译绝对定位坐标（仅 absolute 布局时写入 slot）。
  ///
  /// 坐标语义：rect 内部为 **百分比 (0-100)**，写入 manifest 时转成
  /// **fraction (0-1)** —— 与 Flutter `Positioned` / `Stack` 的 fraction 约定一致，
  /// 也方便下游消费者（其他渲染器、CSS）直接使用。
  static Map<String, dynamic> _compileAbsolutePosition(DesignSlot slot) {
    // rect: [x%, y%, width%, height%] — 0-100 区间
    final r = slot.rect;
    return {
      'style': {
        'position': 'absolute',
        // 转 0-1 fraction
        'left': r[0] / 100.0,
        'top': r[1] / 100.0,
        'width': r[2] / 100.0,
        'height': r[3] / 100.0,
      },
    };
  }
}
