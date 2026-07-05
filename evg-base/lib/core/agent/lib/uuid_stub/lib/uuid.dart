/// UUID stub — 最小 v4 实现，供 example 独立编译使用。
library uuid;

import 'dart:math';

// ═══════ Uuid ═══════

class Uuid {
  /// 生成 UUID v4 字符串。
  String v4() {
    final r = Random();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    return '${_hex(bytes, 0, 4)}-${_hex(bytes, 4, 2)}-${_hex(bytes, 6, 2)}'
        '-${_hex(bytes, 8, 2)}-${_hex(bytes, 10, 6)}';
  }

  /// 生成 UUID v4 字符串（无连字符）。
  String v4noDash() {
    final r = Random();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _hex(List<int> bytes, int start, int length) {
    return bytes
        .sublist(start, start + length)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
