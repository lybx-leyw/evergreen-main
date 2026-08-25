/// HTML 插件导出服务 —— 单目标原子导出。
///
/// 导出到 `{pluginsRoot}/{pluginId}/module/`（运行期插件目录），路径统一由
/// [resolvePluginsRoot] 解析——与主题插件 `ThemeExporter`（`resolvePluginsRoot()`
/// + `plugins/<id>/theme/theme.json`）同源，平台正确（桌面=项目 `plugins/`，
/// 安卓=应用私有 `.greenix/plugins`）。
///
/// 不变式：`assets/plugins_bundle/` 是 `plugins/` 的纯镜像，**仅由
/// `tool/bundle_plugins.dart` 生成**——本服务不再直写 bundle（旧版双写曾把
/// 用户画布泄漏进 APK bundle、且未注入 pubspec 导致安卓「导出后找不到」，
/// 见 docs/2026-08-25-general-pluginization-plan.md §2 RC-2）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/path_sandbox.dart';
import 'package:path/path.dart' as p;

import '../models/html_project.dart';

/// 插件 ID 合法模式：小写字母开头，后跟小写字母/数字，段间以单个 `-` 连接。
///
/// 比旧 `^[a-z0-9]+(?:-[a-z0-9]+)*$` 更严：**拒绝纯数字**（如 "5"，O5——
/// 用户画布导出的 "5" 曾泄漏进 bundle）、大写、空格与路径分隔符（防路径穿越）。
const String kHtmlPluginIdPattern = r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$';

/// 插件 ID 校验（手动导出 + AI 导出 + 工具钩子共用单一规则）。
///
/// 返回 `null` = 合法；否则返回**用户可展示**的错误信息（含 `plugin_id 非法`
/// 前缀，保持与旧钩子/测试文案兼容）。
String? htmlPluginIdError(String pluginId) {
  if (pluginId.isEmpty) {
    return 'plugin_id 非法: 不能为空';
  }
  if (pluginId.length > 64) {
    return 'plugin_id 非法: 过长（${pluginId.length} 字符，上限 64）';
  }
  if (!RegExp(kHtmlPluginIdPattern).hasMatch(pluginId)) {
    return 'plugin_id 非法: "$pluginId"——仅允许小写字母开头 + 小写字母/数字/'
        '连字符（如 my-dashboard），禁止纯数字/大写/空格/路径分隔符';
  }
  return null;
}

/// 将 [files]（module 内相对路径 → 内容）**原子**写入 `{pluginsRoot}/{pluginId}/module/`。
///
/// 原子性：先把旧 `module/` 复制到同目录临时目录（保留附加资产如 icon/数据文件），
/// 写入新文件后整体 rename 替换（旧目录转备份，成功后删备份；失败回滚）——
/// 读取方（模块扫描 / html_modle HTTP 服务）永远看不到半成品目录。
///
/// 安全：pluginId 先经 [htmlPluginIdError] 校验，落盘路径再经 [PathSandbox]
/// confine（防越界，双保险）。返回 module 目录绝对路径；失败抛异常
/// （[PathSandboxException] / [FileSystemException]，信息可展示）。
Future<String> writeHtmlPluginModule({
  required String pluginsRoot,
  required String pluginId,
  required Map<String, String> files,
}) async {
  final idErr = htmlPluginIdError(pluginId);
  if (idErr != null) {
    throw PathSandboxException(idErr);
  }

  final moduleRel = p.join(pluginId, 'module');
  final sandbox = PathSandbox(pluginsRoot);
  final confined = sandbox.confine(moduleRel);
  final expectedAbs =
      p.normalize(Directory(p.join(pluginsRoot, moduleRel)).absolute.path);
  if (confined == null || p.normalize(confined) != expectedAbs) {
    throw PathSandboxException('plugin_id 非法: 导出路径越界（$moduleRel）');
  }

  final moduleDir = Directory(confined);
  final pluginDir = Directory(p.dirname(moduleDir.path));
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final tmpDir = Directory(p.join(pluginDir.path, '.module_tmp_$stamp'));
  final bakDir = Directory(p.join(pluginDir.path, '.module_bak_$stamp'));

  try {
    // 1. 临时目录 = 旧 module/ 的复制（保留附加资产）或空目录
    if (moduleDir.existsSync()) {
      _copyDirSync(moduleDir, tmpDir);
    } else {
      tmpDir.createSync(recursive: true);
    }

    // 2. 写入新文件（manifest.json / index.html …）
    for (final entry in files.entries) {
      final target = File(p.join(tmpDir.path, entry.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(entry.value, flush: true);
    }

    // 3. 原子替换：module → bak；tmp → module；删 bak
    if (moduleDir.existsSync()) {
      await moduleDir.rename(bakDir.path);
    }
    await tmpDir.rename(moduleDir.path);
    if (bakDir.existsSync()) {
      try {
        await bakDir.delete(recursive: true);
      } catch (_) {
        // 备份清理失败不阻塞导出（下次导出覆盖时复用）
      }
    }
    return moduleDir.path;
  } catch (e) {
    // 回滚：清 tmp；若已替换则恢复 bak
    if (tmpDir.existsSync()) {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
    if (bakDir.existsSync()) {
      try {
        if (moduleDir.existsSync()) {
          await moduleDir.delete(recursive: true);
        }
        await bakDir.rename(moduleDir.path);
      } catch (_) {}
    }
    rethrow;
  }
}

void _copyDirSync(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync()) {
    final name = p.basename(entity.path);
    final target = p.join(dst.path, name);
    if (entity is Directory) {
      _copyDirSync(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// 导出结果。
class ExportResult {
  final bool success;
  final String message;
  final List<String> createdFiles;

  const ExportResult({
    required this.success,
    required this.message,
    this.createdFiles = const [],
  });
}

/// 将 [HtmlProject] 导出为完整的 HTML 模板插件（单目标）。
///
/// 落盘：`{resolvePluginsRoot()}/{pluginId}/module/{manifest.json,index.html}`。
/// 与主题插件（`plugins/<id>/theme/theme.json`）同根，安卓/桌面行为一致。
class HtmlExportService {
  /// 插件根目录覆盖（测试注入用）；缺省时使用 [resolvePluginsRoot]
  /// （core/utils 的单一真理来源，平台正确）。
  final String? pluginsDirOverride;

  const HtmlExportService({this.pluginsDirOverride});

  /// 导出项目到磁盘（原子写入）。
  Future<ExportResult> export(HtmlProject project) async {
    final pluginsRoot = pluginsDirOverride ?? resolvePluginsRoot();
    final files = <String, String>{
      'manifest.json':
          const JsonEncoder.withIndent('  ').convert(_buildManifest(project)),
      'index.html': project.htmlContent,
    };

    try {
      final moduleDir = await writeHtmlPluginModule(
        pluginsRoot: pluginsRoot,
        pluginId: project.pluginId,
        files: files,
      );
      Log().info('[HtmlExport] ✅ 已导出: $moduleDir（root=$pluginsRoot）');
      return ExportResult(
        success: true,
        message: '已导出到 plugins/${project.pluginId}/module/（插件视图侧边栏可见）',
        createdFiles: ['$moduleDir/manifest.json', '$moduleDir/index.html'],
      );
    } catch (e) {
      Log().error('[HtmlExport] ❌ 导出失败', error: e);
      return ExportResult(
        success: false,
        message: '导出失败: ${_friendly(e)}',
      );
    }
  }

  /// 把 `PathSandboxException: xxx` 这类前缀剥掉，保留用户可读信息。
  static String _friendly(Object e) => e.toString().replaceFirst(
      RegExp(
          r'^(PathSandboxException|FileSystemException|ArgumentError|FormatException): '),
      '');

  Map<String, dynamic> _buildManifest(HtmlProject project) => {
        'schemaVersion': '2.0',
        'type': 'module',
        'id': project.pluginId,
        'name': project.pluginName,
        if (project.description != null) 'description': project.description,
        if (project.icon != null) 'icon': project.icon,
        'template': 'html',
        'version': '1.0.0',
        'route': '/${project.pluginId}',
        'nav': {
          'sidebar': {
            'section': project.navSection,
            'sectionOrder': 99,
            'order': 99,
          },
        },
      };
}
