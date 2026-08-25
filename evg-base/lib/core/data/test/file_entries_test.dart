/// extractFileEntries / FileEntry 纯函数测试（T8a）。
library;

import 'package:test/test.dart';

import '../file_entries.dart';

void main() {
  group('FileEntry', () {
    test('toJson 仅写出非空可选字段', () {
      const e = FileEntry(
          url: 'https://x/a.pdf', name: 'a.pdf', mime: 'application/pdf');
      expect(e.toJson(), {
        'url': 'https://x/a.pdf',
        'name': 'a.pdf',
        'mime': 'application/pdf',
      });

      const minimal = FileEntry(url: 'https://x/b.bin');
      expect(minimal.toJson(), {'url': 'https://x/b.bin'});
    });

    test('相等性与 hashCode', () {
      const a = FileEntry(url: 'u', name: 'n', mime: 'm');
      const b = FileEntry(url: 'u', name: 'n', mime: 'm');
      const c = FileEntry(url: 'u2');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('extractFileEntries', () {
    test('files 列表形态：Map 元素规范化 url/name/mime', () {
      final entries = extractFileEntries({
        'files': [
          {
            'url': 'https://x/a.pdf',
            'name': 'a.pdf',
            'mime': 'application/pdf'
          },
          {'url': 'https://x/b.csv'},
        ],
      });
      expect(entries, hasLength(2));
      expect(entries[0].url, 'https://x/a.pdf');
      expect(entries[0].name, 'a.pdf');
      expect(entries[0].mime, 'application/pdf');
      expect(entries[1].url, 'https://x/b.csv');
      expect(entries[1].name, isNull);
    });

    test('downloads 列表形态：字符串元素 → url-only 条目', () {
      final entries = extractFileEntries({
        'downloads': ['https://x/1.zip', 'https://x/2.zip'],
      });
      expect(entries.map((e) => e.url).toList(),
          ['https://x/1.zip', 'https://x/2.zip']);
      expect(entries.every((e) => e.name == null), isTrue);
    });

    test('attachments 列表形态', () {
      final entries = extractFileEntries({
        'attachments': [
          {
            'url': 'https://x/img.png',
            'filename': 'img.png',
            'mimeType': 'image/png'
          },
        ],
      });
      expect(entries, hasLength(1));
      expect(entries.single.name, 'img.png');
      expect(entries.single.mime, 'image/png');
    });

    test('files 单对象形态（非 List）→ 单条目', () {
      final entries = extractFileEntries({
        'files': {'url': 'https://x/solo.pdf'},
      });
      expect(entries, hasLength(1));
      expect(entries.single.url, 'https://x/solo.pdf');
    });

    test('file 单对象形态（url 或 downloadEndpoint）', () {
      expect(
          extractFileEntries({
            'file': {'url': 'https://x/f.bin'}
          }).single.url,
          'https://x/f.bin');
      expect(
          extractFileEntries({
            'file': {'downloadEndpoint': 'https://x/g.bin'}
          }).single.url,
          'https://x/g.bin');
    });

    test('downloadEndpoint 字符串形态（模型 B 风格）', () {
      final entries = extractFileEntries({'downloadEndpoint': 'https://x/dl'});
      expect(entries, hasLength(1));
      expect(entries.single.url, 'https://x/dl');
    });

    test('未知结构 / 缺失 → 空列表', () {
      expect(extractFileEntries({}), isEmpty);
      expect(
          extractFileEntries({
            'items': [1, 2, 3]
          }),
          isEmpty);
      expect(extractFileEntries({'files': 'not-a-list-nor-map'}), isEmpty);
      expect(extractFileEntries({'files': []}), isEmpty);
    });

    test('元素缺 url / 非法元素被跳过', () {
      final entries = extractFileEntries({
        'files': [
          {'name': 'no-url'},
          'https://x/ok.pdf',
          42,
        ],
      });
      expect(entries, hasLength(1));
      expect(entries.single.url, 'https://x/ok.pdf');
    });

    test('name/mime 别名解析（fileName/type/contentType）', () {
      final entries = extractFileEntries({
        'files': [
          {
            'url': 'https://x/n.docx',
            'fileName': 'n.docx',
            'contentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          },
        ],
      });
      expect(entries.single.name, 'n.docx');
      expect(entries.single.mime,
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    });
  });
}
