import 'dart:convert';

import 'package:evergreen_base/core/agent/ref/fileutil/encoding/encoding.dart' as enc;
import 'package:test/test.dart';

void main() {
  test('detect UTF-8', () {
    final (kind, _) = enc.detect(utf8.encode('hello'));
    expect(kind, enc.EncodingKind.utf8);
  });

  test('detect UTF-8 BOM and decode strips BOM', () {
    final data = [0xEF, 0xBB, 0xBF, ...utf8.encode('hi')];
    final (kind, raw) = enc.detect(data);
    expect(kind, enc.EncodingKind.utf8bom);
    expect(enc.decode(raw, kind), utf8.encode('hi'));
  });

  test('detect UTF-16 LE', () {
    final data = [0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]; // hi
    final (kind, raw) = enc.detect(data);
    expect(kind, enc.EncodingKind.utf16le);
    expect(utf8.decode(enc.decode(raw, kind)), 'hi');
  });

  test('round-trip UTF-16 BE', () {
    final original = 'hello 🌍';
    final data = enc.encode(original, enc.EncodingKind.utf16be);
    final (kind, raw) = enc.detect(data);
    expect(kind, enc.EncodingKind.utf16be);
    expect(utf8.decode(enc.decode(raw, kind)), original);
  });
}
