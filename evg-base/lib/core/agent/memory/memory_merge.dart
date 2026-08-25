/// 记忆合并 — 同步中心「全局记忆直接拼接」合并语义。
///
/// 契约：`docs/superpowers/specs/egsync-sync-center-spec-v1.md` §八（合并语义总表）。
/// 本文件为 t-C4（core-agent）实施落点，供导入端（t-C3 core-module）调用。
library;

import 'memory.dart' show Memory;
import 'store_interface.dart';

// ═══════ MemoryMergeResult ═══════

/// 记忆合并结果。
class MemoryMergeResult {
  /// 拼接后的全量记忆（本地 + 新增导入）。
  final List<Memory> merged;

  /// 因同 id（name）已存在而被跳过的导入记忆（不重复写入）。
  final List<Memory> skippedDuplicates;

  const MemoryMergeResult({
    required this.merged,
    required this.skippedDuplicates,
  });
}

// ═══════ mergeMemories ═══════

/// 纯函数：直接拼接本地与导入记忆。
///
/// 用户语义为「直接拼接即可」：不做内容级去重；但**避免同 id（name）重复写入**——
/// 记忆文件名即 id（`<name>.md`），两个文件不能同名。由于 name 多为内容哈希
/// （如 `fact-<hash>` / `central-<特质>`），**同内容天然同 id**，本函数即为内容去重；
/// 同名不同内容（罕见，手工编辑场景）保留本地版本，导入版本计入 [skippedDuplicates]。
MemoryMergeResult mergeMemories(List<Memory> local, List<Memory> imported) {
  final seen = <String>{for (final m in local) m.name};
  final merged = <Memory>[...local];
  final skipped = <Memory>[];
  for (final m in imported) {
    if (seen.contains(m.name)) {
      skipped.add(m);
      continue;
    }
    seen.add(m.name);
    merged.add(m);
  }
  return MemoryMergeResult(merged: merged, skippedDuplicates: skipped);
}

/// 应用到记忆存储：保存新增导入记忆并重建自动索引。
///
/// [IMemoryStore.save]（FileMemoryStore → MemoryStore.save）每次写入后自动重建
/// MEMORY.md 索引，因此无需额外重建步骤。
Future<MemoryMergeResult> mergeMemoriesIntoStore(
  IMemoryStore store,
  List<Memory> imported,
) async {
  final local = await store.all();
  final result = mergeMemories(local, imported);
  final skipNames = <String>{for (final s in result.skippedDuplicates) s.name};
  for (final m in imported) {
    if (skipNames.contains(m.name)) continue;
    await store.save(m);
  }
  return result;
}
