// 内容寻址（M3-1，纯函数）。
//
// 对「manifest + 资源清单」算稳定 ID（SHA-256 前若干字节），用于：
// - 安装缓存去重（同内容同 ID，不重复下载）
// - 篡改检测（改一字节 -> 不同 ID）
// - 能力清单绑定（安装时把 ID 与签名绑定）
//
// 纯 Dart，无 I/O，可单测。

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 内容地址：稳定 ID + 原始摘要，便于比对与落盘。
class ContentAddress {
  /// 稳定 ID（默认 16 字符十六进制）。
  final String id;

  /// 完整 SHA-256 十六进制（64 字符）。
  final String sha256;

  const ContentAddress({required this.id, required this.sha256});

  @override
  String toString() => 'ContentAddress($id)';

  @override
  bool operator ==(Object other) =>
      other is ContentAddress && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 计算内容寻址 ID（纯函数）。
///
/// [manifestJson] 为规范化前的 manifest 映射；[resourceHashes] 为
/// 「相对路径 -> 该资源 SHA-256 十六进制」的有序映射（资源纳入寻址）。
/// 规范化：manifest 按 key 排序序列化，再拼接资源哈希，整体 SHA-256。
///
/// [idLength] 为截断位数（十六进制字符数，默认 16，最大 64）。
ContentAddress computeContentAddress(
  Map<String, dynamic> manifestJson, {
  Map<String, String> resourceHashes = const {},
  int idLength = 16,
}) {
  if (idLength < 1 || idLength > 64) {
    throw ArgumentError('idLength 必须在 1..64 之间，收到 $idLength');
  }
  final normalized = _canonicalJson(manifestJson);
  final sortedRes = [...resourceHashes.entries]..sort((a, b) => a.key.compareTo(b.key));
  final buf = StringBuffer()
    ..write(normalized)
    ..write('\n');
  for (final e in sortedRes) {
    buf.write('${e.key}=${e.value}\n');
  }
  final full = _sha256Hex(buf.toString());
  return ContentAddress(id: full.substring(0, idLength), sha256: full);
}

/// 对单个文件内容算 SHA-256 十六进制（纯函数，供资源哈希用）。
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// 对字符串算 SHA-256 十六进制。
String sha256OfString(String s) => _sha256Hex(s);

String _sha256Hex(String s) {
  final digest = sha256.convert(utf8.encode(s));
  return digest.toString();
}

/// 规范化 JSON：递归按 key 排序后序列化，消除字段顺序/空格差异。
String _canonicalJson(dynamic value) {
  if (value is Map) {
    final keys = [...value.keys.cast<String>()]..sort();
    final parts = <String>[];
    for (final k in keys) {
      parts.add('${_jsonString(k)}:${_canonicalJson(value[k])}');
    }
    return '{${parts.join(',')}}';
  }
  if (value is List) {
    final parts = value.map(_canonicalJson).toList();
    return '[${parts.join(',')}]';
  }
  if (value is String) return _jsonString(value);
  if (value is num || value is bool) return value.toString();
  if (value == null) return 'null';
  return _jsonString(value.toString());
}

String _jsonString(String s) => json.encode(s);
