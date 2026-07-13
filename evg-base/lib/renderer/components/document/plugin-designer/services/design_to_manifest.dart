/// 设计 → Manifest 编译器 —— DesignDocument → 标准 manifest.json。
///
/// 比 [PreviewSyncService] 更精细的编译器，支持分页/分组/依赖注入。
library;

import 'dart:convert';

import '../models/design_document.dart';
import '../models/design_page.dart';

/// 设计文档 → manifest.json 编译器。
class DesignToManifest {
  /// 编译设计文档为 manifest JSON 字符串。
  static String compileToJson(DesignDocument doc) {
    return const JsonEncoder.withIndent('  ').convert(compile(doc));
  }

  /// 编译设计文档为 manifest Map。
  static Map<String, dynamic> compile(DesignDocument doc) {
    final pages = <Map<String, dynamic>>[];
    for (final designPage in doc.pages) {
      pages.add(_compilePage(doc, designPage));
    }

    return <String, dynamic>{
      'schemaVersion': '2.0',
      'id': doc.pluginId,
      'name': doc.pluginName,
      if (doc.icon != null) 'icon': doc.icon,
      if (doc.description != null) 'description': doc.description,
      if (doc.route != null) 'route': doc.route,
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
      'layout': <String, dynamic>{
        'type': page.layoutPreset.name,
        'slots': slots,
      },
    };
  }
}
