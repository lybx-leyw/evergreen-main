// 文件型数据源路径越界校验测试（协议 §7 / §12 T10）。
//
// 锁定契约：
//  1. payload 含 path / files[].path / file.path 时，必须位于 file_cache/ 内，
//     否则抛 FormatException（前缀 kFileCacheViolationPrefix）→ 由 DataOrchestrator
//     落到 lastError。
//  2. **零行为变化**：无 path 声明的既有数据源（业务 Map / URL 清单形态）完全不介入。
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/data/file_cache.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

void main() {
  final root = p.normalize(p.absolute(greenixFileCacheDir));
  String inCache(String name) => p.join(root, name);

  group('fileCachePathsOf（提取，纯函数不抛）', () {
    test('顶层 path', () {
      expect(fileCachePathsOf({'path': '/a/b.mp4'}), equals(['/a/b.mp4']));
    });

    test('files[].path（多文件）', () {
      final data = {
        'files': [
          {'path': '/a/1.mp4', 'size': 1},
          {'path': '/a/2.pdf', 'size': 2},
        ]
      };
      expect(fileCachePathsOf(data), equals(['/a/1.mp4', '/a/2.pdf']));
    });

    test('file.path（单对象）', () {
      expect(fileCachePathsOf({'file': {'path': '/a/x.bin'}}), equals(['/a/x.bin']));
    });

    test('null / 非字符串 / 空串一律跳过', () {
      expect(fileCachePathsOf({'path': null}), isEmpty);
      expect(fileCachePathsOf({'path': ''}), isEmpty);
      expect(fileCachePathsOf({'path': 123}), isEmpty);
      expect(fileCachePathsOf({}), isEmpty);
    });

    test('files 为 URL 清单（既有形态）不产出 path', () {
      final data = {
        'files': [
          {'url': 'https://x/a.pdf', 'name': 'a.pdf'},
        ]
      };
      expect(fileCachePathsOf(data), isEmpty, reason: 'url 形态属既有导出语义，非本协议');
    });
  });

  group('validateFileCachePaths（§7 越界校验）', () {
    test('无 path 声明 → 不抛（零行为变化）', () {
      expect(() => validateFileCachePaths({'grades': [], 'authenticated': false}),
          returnsNormally);
    });

    test('status=missing 且 path=null → 不抛', () {
      expect(() => validateFileCachePaths({'status': 'missing', 'path': null}),
          returnsNormally);
    });

    test('缓存目录内的绝对路径 → 不抛', () {
      expect(() => validateFileCachePaths({'status': 'ready', 'path': inCache('a.mp4')}),
          returnsNormally);
    });

    test('缓存外的绝对路径 → 抛 FormatException（带前缀）', () {
      final outside = p.join(p.dirname(root), 'config.json');
      expect(
        () => validateFileCachePaths({'status': 'ready', 'path': outside}),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains(kFileCacheViolationPrefix))),
      );
    });

    test('相对路径 → 抛（协议要求绝对路径）', () {
      expect(() => validateFileCachePaths({'path': 'file_cache/x.mp4'}),
          throwsA(isA<FormatException>()));
    });

    test('files[] 中任一越界 → 抛', () {
      final data = {
        'files': [
          {'path': inCache('ok.mp4')},
          {'path': '/etc/passwd'},
        ]
      };
      expect(() => validateFileCachePaths(data), throwsA(isA<FormatException>()));
    });

    test('.. 逃逸 → 抛（规范化后判定）', () {
      expect(() => validateFileCachePaths({'path': p.join(root, '..', 'x')}),
          throwsA(isA<FormatException>()));
    });

    test('同前缀兄弟目录 → 抛（不得误判命中）', () {
      final sibling = p.join(p.dirname(root), 'file_cache_evil', 'x.bin');
      expect(() => validateFileCachePaths({'path': sibling}),
          throwsA(isA<FormatException>()));
    });
  });
}
