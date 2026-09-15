// 文件型数据源缓存目录契约测试（协议 §2 / §7）。
//
// 锁定两件事：
//  1. [greenixFileCacheDir] 是 `<base>/file_cache`，与 Python 侧
//     `evg_lib.download.resolve_cache_dir()`（`dirname(--greenix-config)/file_cache`）
//     指向同一物理目录 —— 这是「冷/热插件共享同一缓存」的前提。
//  2. [isUnderFileCache] 的越界校验语义：仅接受**缓存目录内的绝对文件路径**，
//     同前缀兄弟目录（`file_cache_evil/`）不得被误判，相对路径一律拒绝。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/utils/greenix_path.dart';

void main() {
  group('greenixFileCacheDir', () {
    test('位于 greenix 基础目录下的 file_cache', () {
      expect(p.basename(greenixFileCacheDir), equals('file_cache'));
    });

    test('与 --greenix-config 父目录派生一致（协议 §2 单一真相源）', () {
      // greenixConfigPath = <base>/config.json
      // 缓存目录 = dirname(greenixConfigPath)/file_cache
      final derived = p.join(p.dirname(greenixConfigPath), 'file_cache');
      expect(
        p.equals(greenixFileCacheDir, derived),
        isTrue,
        reason: 'Python 侧由 --greenix-config 父目录派生，二者必须同目录',
      );
    });
  });

  group('isUnderFileCache（协议 §7 越界校验）', () {
    final root = p.normalize(p.absolute(greenixFileCacheDir));

    test('缓存目录内的绝对路径 → true', () {
      final f = p.join(root, 'a1b2c3d4e5f60718-9f8e7d6c5b4a3210.mp4');
      expect(isUnderFileCache(f), isTrue);
    });

    test('嵌套子目录内的文件 → true', () {
      final f = p.join(root, 'sub', 'x.bin');
      expect(isUnderFileCache(f), isTrue);
    });

    test('同前缀兄弟目录 → false（不得被误判）', () {
      final sibling = p.join(p.dirname(root), 'file_cache_evil', 'x.bin');
      expect(isUnderFileCache(sibling), isFalse);
    });

    test('缓存目录本身 → false（要求是文件）', () {
      expect(isUnderFileCache(root), isFalse);
    });

    test('相对路径 → false（协议要求绝对路径）', () {
      expect(isUnderFileCache('file_cache/x.mp4'), isFalse);
      expect(isUnderFileCache('./x.mp4'), isFalse);
    });

    test('null / 空串 → false', () {
      expect(isUnderFileCache(null), isFalse);
      expect(isUnderFileCache(''), isFalse);
    });

    test('越界到缓存外的路径 → false', () {
      final outside = p.join(p.dirname(root), 'config.json');
      expect(isUnderFileCache(outside), isFalse);
    });

    test('用 .. 逃逸到缓存外 → false（规范化后判定）', () {
      final escape = p.join(root, '..', 'config.json');
      expect(isUnderFileCache(escape), isFalse);
    });

    test('平台分隔符：绝对路径判定与当前平台一致', () {
      expect(Platform.isWindows ? isUnderFileCache(r'C:\x\y.mp4') : isUnderFileCache('/x/y.mp4'),
          isFalse,
          reason: '缓存外的绝对路径必须被拒');
    });
  });
}
