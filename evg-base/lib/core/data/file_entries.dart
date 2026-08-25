/// 文件条目 —— 数据源 stdout 声明的可下载文件清单元素（T8a）。
///
/// 数据源「文件清单」来源约定（模型 A CLI）：脚本 stdout 顶层 JSON 含
/// `files` / `downloads` / `attachments`（或单元素 `file` / `downloadEndpoint`
/// 形态）时，消费方可据此逐项下载。本文件提供纯函数 [extractFileEntries] 把
/// 这些常见键规范化为 [FileEntry] 列表；未知结构/缺失时返回空列表（不抛）。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `FileEntry(url, name?, mime?)` | 规范化文件条目（url 必填，name/mime 可选） |
/// | `FileEntry.toJson()` | 序列化（可选字段仅非空写出） |
/// | `extractFileEntries(Map data)` | 从 stdout 顶层 Map 提取文件条目列表（纯函数，未知结构返回空） |
library;

/// 单个可下载文件条目。
class FileEntry {
  /// 下载地址（必填）。
  final String url;

  /// 文件名（可选，供落盘命名/展示；缺省由消费方从 url 派生）。
  final String? name;

  /// MIME 类型（可选，如 `application/pdf`）。
  final String? mime;

  const FileEntry({required this.url, this.name, this.mime});

  Map<String, dynamic> toJson() => {
        'url': url,
        if (name != null) 'name': name,
        if (mime != null) 'mime': mime,
      };

  @override
  bool operator ==(Object other) =>
      other is FileEntry &&
      other.url == url &&
      other.name == name &&
      other.mime == mime;

  @override
  int get hashCode => Object.hash(url, name, mime);

  @override
  String toString() => 'FileEntry($url${name != null ? ', $name' : ''}'
      '${mime != null ? ', $mime' : ''})';
}

/// 列表形态的文件清单键（按优先级识别）。
const List<String> _fileListKeys = [
  'files',
  'downloads',
  'attachments',
  'fileList',
];

/// 从数据源 stdout 顶层 Map 提取规范化文件条目列表（纯函数）。
///
/// 识别形态（按优先级，命中即返回，不再继续）：
/// 1. 列表键 `files` / `downloads` / `attachments` / `fileList`：
///    - 值为 `List`：逐元素解析（字符串 → url；Map → `{url, name?, mime?}`）；
///    - 值为单元素（字符串 / Map）：按单条目返回。
/// 2. 单对象键 `file`：`{url | downloadEndpoint, name?, mime?}`。
/// 3. 字符串键 `downloadEndpoint`（模型 B 风格）。
///
/// 未知结构 / 缺失 / 元素缺 `url` → 对应条目被跳过；全部无有效条目 → 返回空列表。
List<FileEntry> extractFileEntries(Map data) {
  // 1) 列表形态（files/downloads/attachments/fileList）
  for (final key in _fileListKeys) {
    final value = data[key];
    if (value is List) {
      final entries = <FileEntry>[];
      for (final e in value) {
        final entry = _entryFrom(e);
        if (entry != null) entries.add(entry);
      }
      if (entries.isNotEmpty) return entries;
    } else if (value is Map) {
      final entry = _entryFrom(value);
      if (entry != null) return [entry];
    }
  }

  // 2) 单对象 `file` 形态
  final file = data['file'];
  if (file is Map) {
    final entry = _entryFrom(file);
    if (entry != null) return [entry];
  }

  // 3) `downloadEndpoint` 字符串形态（模型 B 风格，缺省零影响）
  final endpoint = data['downloadEndpoint'];
  if (endpoint is String && endpoint.trim().isNotEmpty) {
    return [FileEntry(url: endpoint.trim())];
  }

  return const [];
}

/// 把单个元素规范化为 [FileEntry]；不合法返回 null。
FileEntry? _entryFrom(dynamic e) {
  if (e is String) {
    final url = e.trim();
    return url.isEmpty ? null : FileEntry(url: url);
  }
  if (e is Map) {
    final url =
        e['url'] ?? e['downloadEndpoint'] ?? e['href'] ?? e['link'] ?? e['src'];
    if (url is! String || url.trim().isEmpty) return null;
    final name = _strOrNull(e['name'] ?? e['filename'] ?? e['fileName']);
    final mime =
        _strOrNull(e['mime'] ?? e['mimeType'] ?? e['type'] ?? e['contentType']);
    return FileEntry(url: url.trim(), name: name, mime: mime);
  }
  return null;
}

String? _strOrNull(dynamic v) => v is String && v.isNotEmpty ? v : null;
