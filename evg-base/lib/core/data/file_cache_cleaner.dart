/// 文件缓存清理 —— **配额裁剪（LRU）+ 孤儿 `.part` 回收**（方案 P4）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §6 P4。
///
/// 内容寻址缓存（`evg_lib.download`）**只增不减**：平台可随时清理，插件必须
/// 容忍缺失（`file-data-plugin-protocol-v1.md` §9）。本文件提供平台侧清理：
///
/// | 能力 | 说明 |
/// | --- | --- |
/// | [clearOrphanPartials] | 回收下载中断残留的 `.part.*`（含被 kill 的子进程留下的） |
/// | [trimFileCache] | 超配额时按 **mtime 从旧到新** 淘汰，直到回到配额内 |
/// | [fileCacheStats] | 统计文件数与总字节数（供看板/诊断） |
///
/// # 淘汰策略（诚实说明）
/// - 使用 **`File.lastModifiedSync()`** —— 即**下载时间**，**不是真实访问时间**
///   （多数文件系统不更新 atime，且在 Android 上不可靠）。故严格说是
///   "最旧下载优先淘汰"（FIFO-by-mtime），而非严格 LRU。
/// - **宽限期 [kFileCacheGrace]**（默认 10 分钟）：**绝不动**刚下载的文件——
///   它们很可能正被某个 slot 消费（`video`/`pdf`），删了会立刻报错。
/// - **至少保留最新 1 个文件**：即使单文件就超过配额，也不清空缓存
///   （否则插件永远无法命中，等于禁用文件源）。
/// - `.part` 与正式文件**分开处理**：`.part` 只看超龄，不参与配额。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../log.dart';
import '../utils/greenix_path.dart';

/// 默认缓存配额：2 GiB（单集录播通常 100–500 MB，约容纳 4–20 集）。
const int kDefaultFileCacheMaxBytes = 2 * 1024 * 1024 * 1024;

/// 宽限期：此时间内修改过的文件**永不**被配额裁剪命中。
const Duration kFileCacheGrace = Duration(minutes: 10);

/// 孤儿 `.part` 的默认最大存活时长（超时才回收）。
const Duration kOrphanPartialMaxAge = Duration(hours: 1);

/// 缓存统计快照。
class FileCacheStats {
  final int fileCount;
  final int totalBytes;
  final int partialCount;

  const FileCacheStats({
    required this.fileCount,
    required this.totalBytes,
    required this.partialCount,
  });

  Map<String, dynamic> toJson() => {
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        'partialCount': partialCount,
      };

  @override
  String toString() =>
      'FileCacheStats(files: $fileCount, bytes: $totalBytes, partials: $partialCount)';
}

/// 清理结果。
class FileCacheCleanResult {
  final int removedFiles;
  final int removedPartials;
  final int reclaimedBytes;
  final int remainingFiles;
  final int remainingBytes;

  const FileCacheCleanResult({
    required this.removedFiles,
    required this.removedPartials,
    required this.reclaimedBytes,
    required this.remainingFiles,
    required this.remainingBytes,
  });

  Map<String, dynamic> toJson() => {
        'removedFiles': removedFiles,
        'removedPartials': removedPartials,
        'reclaimedBytes': reclaimedBytes,
        'remainingFiles': remainingFiles,
        'remainingBytes': remainingBytes,
      };

  @override
  String toString() => 'FileCacheCleanResult(removedFiles: $removedFiles, '
      'removedPartials: $removedPartials, reclaimedBytes: $reclaimedBytes, '
      'remaining: $remainingFiles/$remainingBytes)';
}

/// 是否为下载临时文件（`<name>.part.<pid>.<ts>`，与 `evg_lib.download`
/// 及 `DataFileService` 的命名一致）。
bool isPartialFile(String fileName) => fileName.contains('.part');

Directory _dirOf(String? dir) =>
    Directory(dir ?? greenixFileCacheDir);

/// 统计缓存现状；目录不存在时返回零值（不抛）。
FileCacheStats fileCacheStats({String? dir}) {
  final d = _dirOf(dir);
  if (!d.existsSync()) {
    return const FileCacheStats(fileCount: 0, totalBytes: 0, partialCount: 0);
  }
  var files = 0, bytes = 0, parts = 0;
  for (final e in d.listSync()) {
    if (e is! File) continue;
    final len = e.lengthSync();
    if (isPartialFile(p.basename(e.path))) {
      parts++;
    } else {
      files++;
      bytes += len;
    }
  }
  return FileCacheStats(
      fileCount: files, totalBytes: bytes, partialCount: parts);
}

/// 回收超过 [maxAge] 的孤儿 `.part.*`；**不动**任何正式缓存文件。
///
/// 也被下载中断（进程被 kill / 超时）留下的残片命中。返回回收个数。
int clearOrphanPartials({
  String? dir,
  Duration maxAge = kOrphanPartialMaxAge,
  DateTime? now,
}) {
  final d = _dirOf(dir);
  if (!d.existsSync()) return 0;
  final ref = now ?? DateTime.now();
  var n = 0;
  for (final e in d.listSync()) {
    if (e is! File) continue;
    if (!isPartialFile(p.basename(e.path))) continue;
    try {
      if (ref.difference(e.lastModifiedSync()) >= maxAge) {
        e.deleteSync();
        n++;
      }
    } catch (_) {
      // 正在写入的 `.part`（Windows 可能锁定）→ 跳过，下次再清
    }
  }
  if (n > 0) {
    Log().info('文件缓存：回收孤儿 .part', data: {'count': n});
  }
  return n;
}

/// 按配额裁剪缓存：**mtime 从旧到新**淘汰，直到总字节 ≤ [maxBytes]。
///
/// 保护规则（见库文档）：
/// 1. 宽限期内（`now - mtime < grace`）的文件**绝不动**；
/// 2. **至少保留最新 1 个**文件（即使它单独超配额）；
/// 3. 只处理正式缓存文件，不碰 `.part`。
FileCacheCleanResult trimFileCache({
  String? dir,
  int maxBytes = kDefaultFileCacheMaxBytes,
  Duration grace = kFileCacheGrace,
  DateTime? now,
}) {
  final d = _dirOf(dir);
  if (!d.existsSync()) {
    return const FileCacheCleanResult(
        removedFiles: 0,
        removedPartials: 0,
        reclaimedBytes: 0,
        remainingFiles: 0,
        remainingBytes: 0);
  }
  final ref = now ?? DateTime.now();

  // 收集正式缓存文件（排除 .part），按 mtime 升序（最旧在前）。
  final entries = <({File file, DateTime mtime, int size})>[];
  for (final e in d.listSync()) {
    if (e is! File) continue;
    if (isPartialFile(p.basename(e.path))) continue;
    try {
      entries.add((
        file: e,
        mtime: e.lastModifiedSync(),
        size: e.lengthSync(),
      ));
    } catch (_) {}
  }
  entries.sort((a, b) => a.mtime.compareTo(b.mtime));

  var total = entries.fold<int>(0, (s, e) => s + e.size);
  var removedFiles = 0, reclaimed = 0;
  var remaining = entries.length;

  for (final e in entries) {
    if (total <= maxBytes) break;
    if (remaining <= 1) break; // 保护规则 2：至少留 1 个
    if (ref.difference(e.mtime) < grace) continue; // 保护规则 1
    try {
      e.file.deleteSync();
      total -= e.size;
      reclaimed += e.size;
      removedFiles++;
      remaining--;
    } catch (_) {}
  }

  final partials = clearOrphanPartials(dir: dir, now: ref);

  if (removedFiles > 0 || partials > 0) {
    Log().info('文件缓存：清理完成', data: {
      'removedFiles': removedFiles,
      'removedPartials': partials,
      'reclaimedBytes': reclaimed,
      'remainingBytes': total,
      'maxBytes': maxBytes,
    });
  }

  return FileCacheCleanResult(
    removedFiles: removedFiles,
    removedPartials: partials,
    reclaimedBytes: reclaimed,
    remainingFiles: remaining,
    remainingBytes: total,
  );
}
