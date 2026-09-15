/// 文件型数据源**输出条目**的规范化解析（纯函数，无 Flutter 依赖）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §2.3。
///
/// 文件型数据源的 stdout 有两种形态，同一 `files[]` 数组内按字段区分：
/// | 形态 | 判别 | 消费方行为 |
/// | --- | --- | --- |
/// | 已落盘 | 有 `path` | UI 直接「播放 / 打开」（零下载） |
/// | 待下载 | 有 `url` | UI 列出 + **选择性下载** |
///
/// # 公开 API
/// | 成员 | 说明 |
/// | --- | --- |
/// | `FileSourceEntry` | 规范化条目（`url`/`path` 二选一 + name/size/mime） |
/// | `parseFileSourceEntries(data)` | 从 payload 解析（纯函数，未知结构返回空，不抛） |
/// | `.isCached` | 是否已落盘（有 `path`） |
library;

/// 单个文件条目。
class FileSourceEntry {
  /// 待下载地址（与 [path] 二选一；两者都有时以 [path] 为准——已落盘优先）。
  final String? url;

  /// 已落盘的本地绝对路径（必须位于 `file_cache/` 内，已由平台校验）。
  final String? path;

  /// 展示名（缺省由 url 末段派生）。
  final String name;

  /// 字节数（已落盘时通常有；待下载时未知为 null）。
  final int? size;

  /// MIME（可选，供 `video`/`pdf` slot 分派）。
  final String? mime;

  const FileSourceEntry({
    this.url,
    this.path,
    this.name = '',
    this.size,
    this.mime,
  });

  /// 是否已落盘（据此决定 UI 给「打开」还是「下载」）。
  bool get isCached => path != null && path!.isNotEmpty;

  /// 供展示的字节数文本（`12.3 MB` / `未知`）。
  String get sizeLabel {
    final s = size;
    if (s == null || s <= 0) return '未知';
    if (s >= 1024 * 1024 * 1024) {
      return '${(s / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (s >= 1024 * 1024) {
      return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (s >= 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    return '$s B';
  }

  Map<String, dynamic> toJson() => {
        if (url != null && url!.isNotEmpty) 'url': url,
        if (path != null && path!.isNotEmpty) 'path': path,
        if (name.isNotEmpty) 'name': name,
        if (size != null) 'size': size,
        if (mime != null && mime!.isNotEmpty) 'mime': mime,
      };

  @override
  String toString() => 'FileSourceEntry($name, '
      '${isCached ? 'cached:$path' : 'url:$url'}, ${sizeLabel})';
}

/// 从文件型数据源 payload 解析条目（纯函数，**不抛**）。
///
/// 识别形态：
/// 1. `files` 为数组 → 逐元素解析（缺 url 与 path 者跳过）；
/// 2. `files` 为单对象 / 顶层 `file` 对象 → 按单条目返回；
/// 3. 顶层 `path` → 单条目（`status: ready` 单文件形态）。
///
/// 未知结构 / 缺失 → 空列表。
List<FileSourceEntry> parseFileSourceEntries(dynamic data) {
  if (data is! Map) return const [];

  final out = <FileSourceEntry>[];

  void take(dynamic e) {
    final entry = _entryFrom(e);
    if (entry != null) out.add(entry);
  }

  final files = data['files'];
  if (files is List) {
    for (final e in files) {
      take(e);
    }
  } else if (files is Map) {
    take(files);
  }

  final file = data['file'];
  if (file is Map) take(file);

  // 单文件形态：顶层直接给 path（或 url）
  if (out.isEmpty) take(data);

  return out;
}

/// 把单元素规范化；既无 url 也无 path → null。
FileSourceEntry? _entryFrom(dynamic e) {
  if (e is! Map) return null;
  final path = _strOrNull(e['path']);
  final url = _strOrNull(e['url'] ?? e['downloadEndpoint'] ?? e['href'] ?? e['src']);

  // 已落盘优先：同时给出时以 path 为准（协议 §5.4 边界规则）。
  if (path == null && url == null) return null;

  final rawName = _strOrNull(e['name'] ?? e['filename'] ?? e['fileName'] ?? e['title']);
  return FileSourceEntry(
    url: url,
    path: path,
    name: rawName ?? _deriveName(path ?? url!),
    size: _intOrNull(e['size'] ?? e['length'] ?? e['bytes']),
    mime: _strOrNull(e['mime'] ?? e['mimeType'] ?? e['contentType'] ?? e['type']),
  );
}

/// 由路径/URL 末段派生展示名。
String _deriveName(String source) {
  final norm = source.split('?').first.split('#').first;
  final segs = norm.split('/').where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? source : segs.last;
}

String? _strOrNull(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _intOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
