/// 工作区文件导入辅助（Task 四决策 4.1）。
///
/// 「用户上传任意类型文件 = 把目标文件放入工作区」的落盘实现：
/// 字节拷贝源文件到 `workspaceDir`（二进制 / 文本通吃），同名冲突自动追加
/// 时间戳 / 序号（不覆盖），路径经 [PathSandbox] 校验防越界。
///
/// ## API
/// | 函数 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `importToWorkspace({sourcePath, workspaceDir})` | 源文件绝对路径 + 工作区根目录 | `WorkspaceImportResult` | 复制并返回工作区相对路径 |
///
/// 纯 `dart:io` 实现，renderer / core 均可调用；相对路径计算用 `package:path`。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/path_sandbox.dart';

// ═══════ WorkspaceImportResult ═══════

/// 工作区导入结果。
class WorkspaceImportResult {
  final bool ok;

  /// 相对工作区根的落盘路径（如 `report.pdf` / `report_20260826_153045.pdf`）。
  /// 失败时为 null。
  final String? relativePath;

  /// 落盘绝对路径。失败时为 null。
  final String? absolutePath;

  /// 失败原因（成功时为 null）。
  final String? error;

  const WorkspaceImportResult.ok({
    required String this.relativePath,
    required String this.absolutePath,
  })  : ok = true,
        error = null;

  const WorkspaceImportResult.fail(String this.error)
      : ok = false,
        relativePath = null,
        absolutePath = null;
}

// ═══════ importToWorkspace ═══════

/// 将 [sourcePath] 字节拷贝到 [workspaceDir]，返回落盘相对路径。
///
/// - 源文件必须存在；目标目录不存在则创建。
/// - 目标文件名取源文件 basename（剥离目录），经 [PathSandbox] 校验防 `..` 越界。
/// - 同名冲突：先试 `stem_yyyyMMdd_HHmmss.ext`，仍冲突则 `stem_..._N.ext`（N 递增），
///   绝不覆盖已有文件。
/// - 源文件本身已在工作区内（源 == 目标路径）时跳过复制直接返回成功。
Future<WorkspaceImportResult> importToWorkspace({
  required String sourcePath,
  required String workspaceDir,
}) async {
  final source = File(sourcePath);
  final sourceType = FileSystemEntity.typeSync(sourcePath);
  if (sourceType == FileSystemEntityType.notFound) {
    return WorkspaceImportResult.fail('源文件不存在: $sourcePath');
  }
  if (sourceType == FileSystemEntityType.directory) {
    return WorkspaceImportResult.fail('源文件是目录，请选择具体文件: $sourcePath');
  }

  final baseName = p.basename(sourcePath).trim();
  if (baseName.isEmpty || baseName == '.' || baseName == '..') {
    return WorkspaceImportResult.fail('无效的文件名: ${p.basename(sourcePath)}');
  }

  final workspace = Directory(workspaceDir);
  if (!workspace.existsSync()) {
    try {
      workspace.createSync(recursive: true);
    } catch (e) {
      return WorkspaceImportResult.fail('工作区目录创建失败: $e');
    }
  }

  // 沙箱校验（防 basename 残留路径穿越成分），并得到规范化绝对路径。
  final sandbox = PathSandbox(workspaceDir);
  final confined = sandbox.confine(baseName);
  if (confined == null) {
    return WorkspaceImportResult.fail('目标路径越出工作区: $baseName');
  }

  // 源文件已位于目标位置（用户直接选择工作区内的文件）：无需复制。
  if (p.equals(p.normalize(source.absolute.path), confined)) {
    return WorkspaceImportResult.ok(
        relativePath: baseName, absolutePath: confined);
  }

  // 同名冲突：先 `stem_yyyyMMdd_HHmmss.ext`，再冲突则追加序号，绝不覆盖。
  final relPath = _dedupeName(workspace, baseName);
  final target = sandbox.confine(relPath);
  if (target == null) {
    return WorkspaceImportResult.fail('目标路径越出工作区: $relPath');
  }

  try {
    await source.copy(target);
  } catch (e) {
    return WorkspaceImportResult.fail('复制失败: $e');
  }
  return WorkspaceImportResult.ok(relativePath: relPath, absolutePath: target);
}

// ═══════ 内部：重名策略 ═══════

/// 生成不冲突的目标相对路径：优先原名，冲突 → 时间戳后缀，再冲突 → 追加序号。
String _dedupeName(Directory workspace, String baseName) {
  if (!File(p.join(workspace.path, baseName)).existsSync()) return baseName;

  final ext = p.extension(baseName);
  final stem = p.basenameWithoutExtension(baseName);
  final ts = _timestamp();
  final tsName = '$stem${ts.isEmpty ? '' : '_$ts'}$ext';
  if (!File(p.join(workspace.path, tsName)).existsSync()) return tsName;

  for (var i = 1; i <= 999; i++) {
    final candidate = '$stem${ts.isEmpty ? '' : '_$ts'}${'_$i'}$ext';
    if (!File(p.join(workspace.path, candidate)).existsSync()) return candidate;
  }
  // 兜底：毫秒时间戳（理论上不可达，除非同秒内写入 1000 个同名文件）。
  return '$stem${ts.isEmpty ? '' : '_$ts'}'
      '_${DateTime.now().millisecondsSinceEpoch}$ext';
}

/// `yyyyMMdd_HHmmss` 风格时间戳。
String _timestamp() {
  final dt = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}'
      '_${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
}
