/// 数据预览服务 —— 从 DataOrchestrator 加载数据源列表和缓存内容。
library;

import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';

class DataPreviewService {
  final DataOrchestrator orch;

  DataPreviewService(this.orch);

  /// 获取所有已注册数据源的预览列表（不含缓存数据）。
  List<DataSourcePreview> listSources() {
    return orch.allStatuses
        .map((s) => DataSourcePreview(
              name: s.name,
              displayName: s.displayName ?? s.name,
              freshnessLabel: s.freshnessLabel,
              connected: s.connected,
            ))
        .toList();
  }

  /// 获取指定数据源的缓存内容。
  /// 返回 null 表示未注册或无缓存。
  Future<dynamic> fetchPreview(String name) async {
    final dt = orch.typeByName(name);
    if (dt == null) return null;
    try {
      return await orch.fastRead(dt) ?? await orch.get(dt);
    } catch (_) {
      return null;
    }
  }
}
