/// Archive stub for config module isolation (same pattern as core/lib/archive_stub).
library archive;

// ═══════ Minimal Archive types for compilation ═══════
// 真实环境由 config/pubspec.yaml 的 dependency_overrides: archive ^3.4.0 解析；
// 本 stub 仅保证离线/纯 Dart 环境下可编译。

class Archive {
  final List<ArchiveFile> files = <ArchiveFile>[];
  void addFile(ArchiveFile file) => files.add(file);
}

class ArchiveFile {
  final String name;
  final int size;
  final dynamic content;

  ArchiveFile(this.name, this.size, this.content);
}

class ZipEncoder {
  List<int>? encode(Archive archive, {int level = 6}) => null;
}

class ZipDecoder {
  Archive decodeBytes(List<int> bytes) => Archive();
}
