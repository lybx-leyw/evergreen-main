/// Port of reasonix/internal/fileutil/encoding.
///
/// Detects and converts file encodings. UTF-8, UTF-8 BOM, UTF-16 LE/BE (with and
/// without BOM) are fully supported. GB18030 detection is preserved but
/// conversion falls back to lossy UTF-8 when no GB18030 codec is available;
/// this is marked TODO for full parity.
library;

import 'dart:convert';
import 'dart:typed_data';

enum EncodingKind {
  utf8,
  utf8bom,
  utf16le,
  utf16be,
  gb18030,
  lossyUtf8,
  utf16leNoBom,
  utf16beNoBom,
}

const _utf8BOM = [0xEF, 0xBB, 0xBF];

(EncodingKind, List<int>) detect(List<int> data) {
  if (data.length >= 3 &&
      data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    return (EncodingKind.utf8bom, data);
  }
  if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
    return (EncodingKind.utf16le, data);
  }
  if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
    return (EncodingKind.utf16be, data);
  }
  if (detectUtf16NoBom(data) case (final kind, true)) {
    return (kind, data);
  }
  try {
    utf8.decode(data, allowMalformed: false);
    return (EncodingKind.utf8, data);
  } on FormatException {
    // Try GB18030 only when a codec is wired.
    if (_isGB18030(data)) {
      return (EncodingKind.gb18030, data);
    }
    return (EncodingKind.lossyUtf8, data);
  }
}

EncodingKind detectQuick(List<int> peek) {
  if (peek.length >= 3 &&
      peek[0] == 0xEF && peek[1] == 0xBB && peek[2] == 0xBF) {
    return EncodingKind.utf8bom;
  }
  if (peek.length >= 2 && peek[0] == 0xFF && peek[1] == 0xFE) {
    return EncodingKind.utf16le;
  }
  if (peek.length >= 2 && peek[0] == 0xFE && peek[1] == 0xFF) {
    return EncodingKind.utf16be;
  }
  return EncodingKind.utf8;
}

(EncodingKind, bool) detectUtf16NoBom(List<int> b) {
  final n = b.length;
  if (n < 16) return (EncodingKind.utf8, false);
  final even = b.length.isEven ? b.length : b.length - 1;
  var evenNul = 0;
  var oddNul = 0;
  for (var i = 0; i < even; i++) {
    if (b[i] != 0) continue;
    if (i.isEven) {
      evenNul++;
    } else {
      oddNul++;
    }
  }
  final half = even ~/ 2;
  if (oddNul * 10 >= half * 3 && evenNul * 20 <= half) {
    return (EncodingKind.utf16leNoBom, true);
  }
  if (evenNul * 10 >= half * 3 && oddNul * 20 <= half) {
    return (EncodingKind.utf16beNoBom, true);
  }
  return (EncodingKind.utf8, false);
}

bool _isGB18030(List<int> data) {
  // TODO: wire a real GB18030 codec (e.g. fast_gbk package) when available.
  // Returning false keeps data as lossy UTF-8.
  return false;
}

List<int> decode(List<int> data, EncodingKind enc) {
  switch (enc) {
    case EncodingKind.utf8bom:
      return data.sublist(3);
    case EncodingKind.utf16le:
      return _decodeUtf16(data.sublist(2), Endian.little);
    case EncodingKind.utf16be:
      return _decodeUtf16(data.sublist(2), Endian.big);
    case EncodingKind.utf16leNoBom:
      return _decodeUtf16(data, Endian.little);
    case EncodingKind.utf16beNoBom:
      return _decodeUtf16(data, Endian.big);
    case EncodingKind.gb18030:
      // TODO: real GB18030 decoder.
      return data;
    case EncodingKind.utf8:
    case EncodingKind.lossyUtf8:
      return data;
  }
}

List<int> decodeToUtf8(List<int> data) {
  final (enc, raw) = detect(data);
  return decode(raw, enc);
}

Future<List<int>> readFileUtf8(String path) async {
  final data = await File(path).readAsBytes();
  return decodeToUtf8(data);
}

List<int> encode(String text, EncodingKind enc) {
  switch (enc) {
    case EncodingKind.utf8bom:
      return [..._utf8BOM, ...utf8.encode(text)];
    case EncodingKind.utf16le:
      return [...[0xFF, 0xFE], ..._encodeUtf16(text, Endian.little)];
    case EncodingKind.utf16be:
      return [...[0xFE, 0xFF], ..._encodeUtf16(text, Endian.big)];
    case EncodingKind.utf16leNoBom:
      return _encodeUtf16(text, Endian.little);
    case EncodingKind.utf16beNoBom:
      return _encodeUtf16(text, Endian.big);
    case EncodingKind.gb18030:
      // TODO: real GB18030 encoder.
      return utf8.encode(text);
    case EncodingKind.utf8:
    case EncodingKind.lossyUtf8:
      return utf8.encode(text);
  }
}

List<int> _decodeUtf16(List<int> bytes, Endian endian) {
  if (bytes.isEmpty) return <int>[];
  final evenLen = bytes.length.isEven ? bytes.length : bytes.length - 1;
  final codeUnits = <int>[];
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  for (var i = 0; i + 1 < evenLen; i += 2) {
    codeUnits.add(view.getUint16(i, endian));
  }
  return utf8.encode(_utf16ToString(codeUnits));
}

List<int> _encodeUtf16(String text, Endian endian) {
  final codeUnits = _stringToUtf16(text);
  final out = Uint8List(codeUnits.length * 2);
  final view = out.buffer.asByteData();
  for (var i = 0; i < codeUnits.length; i++) {
    view.setUint16(i * 2, codeUnits[i], endian);
  }
  return out.toList();
}

String _utf16ToString(List<int> codeUnits) {
  final buffer = StringBuffer();
  for (var i = 0; i < codeUnits.length; i++) {
    final c = codeUnits[i];
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < codeUnits.length) {
      final c2 = codeUnits[i + 1];
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        buffer.writeCharCode(0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00));
        i++;
        continue;
      }
    }
    buffer.writeCharCode(c);
  }
  return buffer.toString();
}

List<int> _stringToUtf16(String text) {
  final out = <int>[];
  for (final r in text.runes) {
    if (r >= 0x10000) {
      final s = r - 0x10000;
      out.add(0xD800 + (s >> 10));
      out.add(0xDC00 + (s & 0x3FF));
    } else {
      out.add(r);
    }
  }
  return out;
}
