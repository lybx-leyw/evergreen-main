/// 主题导出服务——校验草稿 → 写 `plugins/<id>/theme/theme.json` → 热注册。
///
/// 输出与平台 `scanThemes` 契约一致（扁平 8 色模型，见 docs/plugin-theme.md）：
/// 导出的主题无需重启即可经 [ThemeStore.register] 出现在设置页主题下拉。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/theme/theme_store.dart';

import '../models/theme_draft.dart';

/// 导出结果。
class ThemeExportResult {
  final bool success;
  final String message;
  final String? themePath;

  const ThemeExportResult({
    required this.success,
    required this.message,
    this.themePath,
  });
}

/// 主题导出器。
class ThemeExporter {
  /// 插件根目录（如 resolvePluginsRoot() 或注入以便测试）。
  final String pluginsDir;

  ThemeExporter(this.pluginsDir);

  /// 校验草稿并导出为主题插件。
  ///
  /// 校验失败返回失败结果（含具体原因），不写盘。
  ThemeExportResult export(ThemeDraft draft) {
    if (!draft.idValid) {
      return const ThemeExportResult(
        success: false,
        message: 'id 不合法：需 snake_case（小写字母/数字/下划线），'
            '且不能与内置主题（dark/light/default/evergreen）冲突',
      );
    }
    if (!draft.hasAllColors) {
      return const ThemeExportResult(
        success: false,
        message: '8 个语义色未填全（background/surface/border/text/'
            'textSecondary/accent/error/others）',
      );
    }
    if (!draft.allColorsValid) {
      return const ThemeExportResult(
        success: false,
        message: '存在非法 hex 颜色（需 #RGB / #RRGGBB / #AARRGGBB）',
      );
    }

    try {
      final themeDir = Directory(p.join(pluginsDir, draft.id, 'theme'));
      themeDir.createSync(recursive: true);
      final file = File(p.join(themeDir.path, 'theme.json'));
      file.writeAsStringSync(
        jsonEncode({
          'type': 'theme',
          'id': draft.id,
          'name': draft.name,
          'colors': draft.colors,
        }),
        flush: true,
      );
      return ThemeExportResult(
        success: true,
        message: '已导出到 plugins/${draft.id}/theme/theme.json',
        themePath: file.path,
      );
    } catch (e) {
      return ThemeExportResult(success: false, message: '导出失败: $e');
    }
  }

  /// 导出 + 热注册（同 id 覆盖，设置页主题下拉立即可见）。
  ThemeExportResult exportAndRegister(ThemeDraft draft, ThemeStore store) {
    final r = export(draft);
    if (r.success) {
      store.register(draft.toDescriptor());
    }
    return r;
  }
}
