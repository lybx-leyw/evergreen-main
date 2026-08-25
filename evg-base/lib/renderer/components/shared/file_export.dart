/// 平台级「数据源文件导出」服务 —— 导出到用户自选路径（T8b，验收目标 4 UI/module 侧）。
///
/// 让「数据源返回的文件（PDF 等）→ module 页面可一键导出到用户自选路径」成立：
/// 消费方经 [pickExportDirectory] 选目录 → [exportFileEntry] / [exportFileEntries]
/// 逐项把 [FileEntry]（来自 core `extractFileEntries`）经 core [DataFileService] 下载
/// 到目标目录。文件名经 [sanitizeFileName] 净化（防路径穿越），同名冲突按
/// [uniqueFileName] 追加序号（不覆盖）。
///
/// # 分层（守 renderer 红线）
///
/// - **下载走 core**：不直连 HTTP，下载能力全部委托 [DataFileService]（T8a core 侧，
///   已含 headers/超时/重试/沙箱）；
/// - **纯逻辑可单测**：文件名净化 / 冲突命名在 `file_export_names.dart`（零依赖）；
/// - **凭据注入**：headers 由调用方回调提供（T2 会话中心导出，本任务不实作 zju 头）；
/// - **选目录**：`file_picker`（已在依赖中，无新 pub 依赖）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/data/file_entries.dart';
import 'package:evergreen_base/core/result.dart';
import 'package:evergreen_base/core/services/data_file_service.dart';

import 'file_export_names.dart';

/// 弹出目录选择对话框，返回用户选定的目录绝对路径；取消返回 `null`。
///
/// 选型说明：用 [fp.FilePicker.platform.getDirectoryPath]（file_picker 8.x 提供的
/// **目录选择**对话框）。桌面（Windows/macOS/Linux）返回绝对路径，[initialDirectory]
/// 指定打开位置——这是「导出到用户自选路径」的原生语义，比 `pickFiles`（文件选择）
/// 或 `saveFile`（单文件保存）更贴合「选一个目录、批量下载多个文件」的需求。
///
/// 限制与降级：部分移动端对目录选择支持有限（返回 `/` 或抛
/// `UnimplementedError`），此处吞掉异常返回 `null`；调用方据此回退到默认下载目录
/// （如 `getDownloadsDirectory()`）。
Future<String?> pickExportDirectory({
  String? initialDirectory,
  String? dialogTitle,
}) async {
  try {
    return await fp.FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle ?? '选择导出目录',
      initialDirectory: initialDirectory,
    );
  } catch (_) {
    return null;
  }
}

/// 从数据源运行时数据提取文件条目（薄封装 + 类型守卫）。
///
/// [data] 是 `orch.get(type)` / `orch.refresh(type)` 返回的 `dynamic` 顶层数据；
/// 仅当为 [Map] 时调用 core [extractFileEntries]（未知结构/非 Map 返回空，不抛）。
/// 与 [extractFileEntries] 组合后形成「fileOf → 拉数据 → 提清单 → 选目录 → 下载」
/// 完整链路（见 renderer README「数据源文件导出」）。
List<FileEntry> fileEntriesFromData(dynamic data) {
  if (data is Map) return extractFileEntries(data);
  return const [];
}

/// 计算单个文件的目标路径：净化 + 冲突命名（公开，供单测与复用）。
///
/// - [fileName] 原始文件名（未净化）→ 内部经 [sanitizeFileName]；
/// - [overwrite] 为 true 时直接返回 `targetDir/<safeName>`（覆盖语义）；
///   默认 false：目标目录已存在同名文件时追加序号（不覆盖用户既有文件）；
/// - [existingNames] 可注入「已存在文件名集合」（纯逻辑测试用）；缺省扫描
///   [targetDir] 实际磁盘。
String resolveExportTargetPath(
  String targetDir,
  String fileName, {
  bool overwrite = false,
  Set<String>? existingNames,
}) {
  final safe = sanitizeFileName(fileName);
  if (overwrite) return p.join(targetDir, safe);
  final existing = existingNames ?? _existingNames(targetDir);
  return p.join(targetDir, uniqueFileName(safe, existing));
}

/// 把单个 [FileEntry] 下载到 [targetDir]，返回 `Result<String>`（Ok = 落盘绝对路径）。
///
/// 文件名：优先 [FileEntry.name]，缺省从 [FileEntry.url] 派生；统一经
/// [resolveExportTargetPath] 净化 + 冲突处理（默认**不覆盖**）。
///
/// 下载委托 core [DataFileService.downloadFile]（headers/超时/重试/沙箱），凭据头经
/// [headers] 注入（T2 会话中心导出，本任务由调用方回调提供）。
Future<Result<String>> exportFileEntry({
  required FileEntry entry,
  required DataFileService service,
  required String targetDir,
  Map<String, String>? headers,
  bool overwrite = false,
}) async {
  final rawName = entry.name ?? fileNameFromUrl(entry.url);
  final targetPath = resolveExportTargetPath(
    targetDir,
    rawName,
    overwrite: overwrite,
  );
  return service.downloadFile(
    url: entry.url,
    targetPath: targetPath,
    headers: headers,
  );
}

/// 批量把 [entries] 下载到 [targetDir]（**串行**，逐项结果，单项失败不阻塞后续项）。
///
/// 冲突基线：先扫描一次 [targetDir] 已有文件名作为冲突命名基线，随后把每项成功
/// 写入的名字并入基线，避免串行下载时「前一项刚写入的文件」未被后续同名项看到而
/// 覆盖。返回与 [entries] 等长的逐项 `Result<String>`。
Future<List<Result<String>>> exportFileEntries({
  required List<FileEntry> entries,
  required DataFileService service,
  required String targetDir,
  Map<String, String>? headers,
  bool overwrite = false,
}) async {
  final existing = _existingNames(targetDir);
  final results = <Result<String>>[];
  for (final entry in entries) {
    final rawName = entry.name ?? fileNameFromUrl(entry.url);
    final targetPath = resolveExportTargetPath(
      targetDir,
      rawName,
      overwrite: overwrite,
      existingNames: existing,
    );
    final result = await service.downloadFile(
      url: entry.url,
      targetPath: targetPath,
      headers: headers,
    );
    result.fold<void>((path) {
      existing.add(p.basename(path));
    }, (_) {});
    results.add(result);
  }
  return results;
}

/// 扫描目标目录已存在的**文件名集合**（失败/不存在 → 空集合）。
Set<String> _existingNames(String dir) {
  try {
    final d = Directory(dir);
    if (!d.existsSync()) return <String>{};
    return d
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toSet();
  } catch (_) {
    return <String>{};
  }
}
