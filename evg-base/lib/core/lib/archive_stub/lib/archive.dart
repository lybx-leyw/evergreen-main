/// Archive stub for core module isolation.
library archive;

// ═══════ Minimal Archive types for compilation ═══════

class ZipDecoder {
  Archive decodeBytes(List<int> bytes) => Archive();
  Archive decodeBuffer(dynamic buffer) => Archive();
}

class Archive {
  final List<ArchiveFile> files = <ArchiveFile>[];
  void clear() {}
}

class ArchiveFile {
  final String name;
  final List<int> content;
  final bool isFile;

  ArchiveFile(this.name, this.content, {this.isFile = true});
}

class InputStreamBase {}
