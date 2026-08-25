/// 数据源文件导出——纯函数：文件名净化 + 冲突命名（零依赖，可独立单测）。
///
/// renderer 共享层「文件导出」链路（T8b，验收目标 4 UI/module 侧）的纯逻辑部分：
/// 与 Flutter / file_picker / core 服务解耦，仅做字符串与集合运算，便于独立分析
/// 与单测（主包 `flutter test` 受沙箱 1GB 内存限制时，本文件仍可用纯 Dart 工具链
/// 验证，不触碰 Flutter Widget 或文件系统）。
library;

/// 缺省回退文件名（净化后为空 / 非法时使用）。
const String kExportFallbackName = 'download';

/// Windows 保留设备名（大小写不敏感；作为文件名「基名」时需前缀下划线规避）。
const Set<String> _windowsReservedNames = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// 文件名长度安全上限（保守：远小于多数文件系统 255 字节限制，为扩展名预留空间）。
const int kMaxFileNameLength = 200;

/// 净化文件名，防止路径穿越与跨平台非法字符。
///
/// 规则（依次）：
/// 1. **取末段（防路径穿越）**：统一 `\`→`/` 后切分，只保留最后一个非空段——
///    即便上游误传了带路径的名字（如 `../../etc/passwd`、`..\..\x`），也只取其
///    末段 `passwd` / `x`，结果恒为单段文件名、不含任何路径分隔符；
/// 2. 跨平台非法/控制字符 `< > : " | ? * \x00-\x1f` → `_`；
/// 3. 折叠连续空白、去首尾空白；
/// 4. 去结尾的点与空格（Windows 不允许）；
/// 5. 去开头的点（避免隐藏文件与 `.`/`..` 父目录名）；
/// 6. 超长截断（保留扩展名，见 [kMaxFileNameLength]）；
/// 7. 结果为空 → [fallback]；基名为 Windows 保留设备名 → 前缀 `_`。
///
/// 纯函数：同输入同输出，不依赖运行时环境。
String sanitizeFileName(String raw, {String fallback = kExportFallbackName}) {
  final segments = raw
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  var name = segments.isEmpty ? '' : segments.last;
  name = name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  name = name.replaceFirst(RegExp(r'[. ]+$'), '');
  name = name.replaceFirst(RegExp(r'^\.+'), '');
  name = _truncateName(name);
  if (name.isEmpty) return fallback;
  final base = name.split('.').first;
  if (_windowsReservedNames.contains(base.toLowerCase())) {
    name = '_$name';
  }
  return name;
}

/// 从 URL 末段派生文件名（`Uri.pathSegments` 已做百分号解码），并做净化。
///
/// 仅接受 http/https URL（文件下载端点语义）；无法解析 / 非 http(s) / 末段为空时
/// 回退 [fallback]。供 [FileEntry.name] 缺失时兜底命名。
String fileNameFromUrl(String url, {String fallback = kExportFallbackName}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return fallback;
  }
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.last.isNotEmpty) {
    return sanitizeFileName(segs.last, fallback: fallback);
  }
  return fallback;
}

/// 冲突命名：当 [name] 已存在于 [existing] 时，返回 `base (n).ext` 形式的首个可用名。
///
/// 示例：`report.pdf` 且 `report.pdf` / `report (1).pdf` 已存在 → `report (2).pdf`；
/// 无扩展名 `slides` → `slides (1)`。这是「不覆盖、追加序号」冲突策略的纯函数核心
/// （导出是「另存」，覆盖用户既有文件属不可接受的数据丢失）。
///
/// 纯函数：仅依赖 [name] 与 [existing] 集合，便于离线单测。
String uniqueFileName(String name, Set<String> existing) {
  if (!existing.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var i = 1;
  while (true) {
    final candidate = '$base ($i)$ext';
    if (!existing.contains(candidate)) return candidate;
    i++;
  }
}

/// 截断过长文件名，保留扩展名（扩展名超长时整体截断）。
String _truncateName(String name) {
  if (name.length <= kMaxFileNameLength) return name;
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    final ext = name.substring(dot);
    final keepBase = kMaxFileNameLength - ext.length;
    if (keepBase > 0) return name.substring(0, keepBase) + ext;
  }
  return name.substring(0, kMaxFileNameLength);
}
