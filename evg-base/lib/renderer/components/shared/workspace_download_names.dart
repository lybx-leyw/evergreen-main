/// 工作区文件「下载到固定目录」——纯函数：目标路径规划（零依赖，可独立单测）。
///
/// Task 七 9.1/9.2 共用：9.1 抽屉「管理文件」批量下载、9.2 文件卡片下载按钮
/// 都经 [planDownloadTargetPath] 确定落盘路径（固定目录 + 净化 + 同名去重），
/// 复用 T8b 资产 `file_export_names.dart` 的 [sanitizeFileName] / [uniqueFileName]。
///
/// 本文件刻意零依赖（不 import path_provider / path / Flutter），
/// 与 `file_export_names.dart` 同模式，可在 renderer 子包 `dart test` 独立验证。
library;

import 'file_export_names.dart';

/// 规划下载目标路径（纯函数）：净化文件名 + 同名不覆盖、追加序号。
///
/// - [baseDir]：固定下载目录（系统下载目录或回退目录，见 `workspace_file_download.dart`）
/// - [sourceName]：源文件名（可带路径，仅取末段净化，防路径穿越）
/// - [existingNames]：目标目录已存在的文件名集合（不含路径）
///
/// 返回 `baseDir + 分隔符 + 唯一文件名`。分隔符随 [baseDir] 风格自适应
/// （含 `\` 视为 Windows 风格，否则用 `/`）；两端重复分隔符不叠加。
///
/// 纯函数：同输入同输出，不依赖运行时环境。
String planDownloadTargetPath({
  required String baseDir,
  required String sourceName,
  required Set<String> existingNames,
}) {
  final safe = sanitizeFileName(sourceName);
  final unique = uniqueFileName(safe, existingNames);
  if (baseDir.isEmpty) return unique;
  final winStyle = baseDir.contains('\\');
  final sep = winStyle ? '\\' : '/';
  if (baseDir.endsWith('/') || baseDir.endsWith('\\')) {
    return '$baseDir$unique';
  }
  return '$baseDir$sep$unique';
}
