/// 文件型数据源缓存路径校验（`file-data-plugin-protocol-v1.md` §7）。
///
/// 数据源 stdout 返回 `path`（或 `files[].path` / `file.path`）时，平台校验其
/// **必须位于 [greenixFileCacheDir] 内**，防止插件越界声明任意路径供上游读取
/// （协议 §4「不落盘到缓存外」、§7「平台可校验」）。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `kFileCacheViolationPrefix` | 违规文案前缀（便于测试与 UI 识别） |
/// | `fileCachePathsOf(data)` | 提取 payload 中声明的全部文件路径（纯函数，不抛） |
/// | `validateFileCachePaths(data)` | 越界即抛 [FormatException]（无违规零行为变化） |
///
/// # 零行为变化保证
/// 仅当 payload 含 **非空字符串** `path` / `files[].path` / `file.path` 时才校验。
/// 既有数据源（如教务类返回 `fallbackJson` 的业务 Map，或 `files` 为 URL 清单的
/// 导出形态）**不含** `path` 键 → 本校验完全不介入。
library;

import '../utils/greenix_path.dart';

/// 路径越界错误的文案前缀（协议 §7 / 测试 T10 的断言依据）。
const String kFileCacheViolationPrefix = '文件缓存路径越界';

/// 扩展名白名单违规的文案前缀（`file-source` 的 `files[].accept` 校验）。
const String kFileAcceptViolationPrefix = '文件扩展名不在白名单内';

/// 提取 payload 中声明的文件路径（纯函数）。
///
/// 识别形态（协议 §5.1 / §5.4）：
/// - 顶层 `path`：单文件形态；
/// - `files` 数组内各元素的 `path`：多文件形态；
/// - `file` 对象的 `path`：单对象形态。
///
/// 非字符串 / 空串 / 结构不符一律跳过（`status: missing|failed` 时 `path` 可为 null）。
List<String> fileCachePathsOf(Map<String, dynamic> data) {
  final out = <String>[];

  void take(dynamic v) {
    if (v is String && v.isNotEmpty) out.add(v);
  }

  take(data['path']);

  final files = data['files'];
  if (files is List) {
    for (final e in files) {
      if (e is Map) take(e['path']);
    }
  }

  final file = data['file'];
  if (file is Map) take(file['path']);

  return out;
}

/// 校验 payload 中声明的文件路径均位于缓存目录内；越界抛 [FormatException]。
///
/// 无 `path` 声明时直接返回（**零行为变化**）。
void validateFileCachePaths(Map<String, dynamic> data) {
  final paths = fileCachePathsOf(data);
  if (paths.isEmpty) return;
  for (final path in paths) {
    if (!isUnderFileCache(path)) {
      throw FormatException(
        '$kFileCacheViolationPrefix：$path 不在文件缓存目录内'
        '（协议 §7 要求 path 为 ${greenixFileCacheDir} 下的绝对路径）',
      );
    }
  }
}
