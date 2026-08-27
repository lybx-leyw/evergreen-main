/// 工作区文件「下载到固定目录」共享逻辑（Task 七 9.1 + 9.2 共用）。
///
/// - 9.1 抽屉「管理文件」批量下载：逐个 [downloadWorkspaceFile] 复制到固定目录
/// - 9.2 `show_file4u` 文件卡片的下载按钮：同一函数
///
/// 固定目录决策（spec 9.1）：**不支持自定义**，硬编码解析一次——桌面优先系统
/// 下载目录 `getDownloadsDirectory()`，Android 无系统下载目录时回退 app 支持
/// 目录下的 `downloads/`（先例：`classroom_viewer_screen.dart:112-118`）。
/// 同名冲突不覆盖：`planDownloadTargetPath` 净化 + 追加序号（`file_export_names.dart`）。
///
/// 目标路径规划是纯函数（`workspace_download_names.dart`），可独立单测；
/// 本文件依赖 path_provider / dart:io，仅能在真实 Flutter 环境运行。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'widgets/models.dart';
import 'workspace_download_names.dart';

// ═══════ 下载结果 ═══════

/// 单个文件下载结果。
class WorkspaceDownloadResult {
  final bool ok;
  final String? savedPath;
  final String? error;

  const WorkspaceDownloadResult.ok(String this.savedPath)
      : ok = true,
        error = null;

  const WorkspaceDownloadResult.fail(String this.error)
      : ok = false,
        savedPath = null;
}

// ═══════ 固定目录解析 ═══════

/// 固定下载目录：桌面优先系统下载目录，Android 回退 app 支持目录/downloads。
/// 目录不存在则创建（失败抛出，由调用方统一报错）。
Future<String> resolveFixedDownloadDir() async {
  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads.path;
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/downloads');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir.path;
}

// ═══════ 下载执行 ═══════

/// 将 [file] 复制到固定下载目录（同名自动追加序号，不覆盖）。
/// 返回 [WorkspaceDownloadResult]：成功携带完整落盘路径，失败携带错误信息。
Future<WorkspaceDownloadResult> downloadWorkspaceFile(WorkspaceFile file) async {
  try {
    final baseDir = await resolveFixedDownloadDir();
    final dir = Directory(baseDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final existing = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    final target = planDownloadTargetPath(
      baseDir: baseDir,
      sourceName: file.name,
      existingNames: existing,
    );
    await File(file.path).copy(target);
    return WorkspaceDownloadResult.ok(target);
  } catch (e) {
    return WorkspaceDownloadResult.fail('$e');
  }
}

// ═══════ 结果 UI（9.1 弹窗 + 复制；失败 SnackBar） ═══════

/// 下载成功弹窗：展示全部落盘路径 + 「一键复制」（复制所有路径，换行分隔）。
void showWorkspaceDownloadSuccessDialog(
  BuildContext context,
  List<String> savedPaths,
) {
  final theme = Theme.of(context);
  final joined = savedPaths.join('\n');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('下载完成',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('已保存 ${savedPaths.length} 个文件到固定下载目录：',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SelectableText(
              joined,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: joined));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('路径已复制'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('复制路径'),
        ),
      ],
    ),
  );
}

/// 下载失败 SnackBar（error 样式，先例 file_viewer.dart L171）。
void showWorkspaceDownloadErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('下载失败: $message'),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
