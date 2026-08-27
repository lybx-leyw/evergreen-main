/// Task 七 9.1/9.2 下载目标路径规划纯函数测试（workspace_download_names.dart）。
///
/// 运行：cd evg-base/lib/renderer && dart test test/workspace_download_names_test.dart
/// 注意：renderer 子包的 .dart_tool/package_config.json 需将 evergreen_base 的
/// rootUri 指向仓库根（`../../..`，即 evg-base），使 package:evergreen_base/…
/// 解析到真实源码（与 agent_A6_final.md 的 session_branch_test 说明一致）。
library;

import 'package:evergreen_base/renderer/components/shared/workspace_download_names.dart';
import 'package:test/test.dart';

void main() {
  group('planDownloadTargetPath — 基本', () {
    test('简单文件名 → baseDir + 分隔符 + 文件名', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/home/u/Downloads',
          sourceName: 'report.pdf',
          existingNames: const {},
        ),
        '/home/u/Downloads/report.pdf',
      );
    });

    test('带路径的源名 → 仅取末段（防路径穿越）', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: '../../etc/passwd',
          existingNames: const {},
        ),
        '/d/passwd',
      );
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'sub/dir/notes.md',
          existingNames: const {},
        ),
        '/d/notes.md',
      );
    });

    test('Windows 风格 baseDir → 反斜杠分隔', () {
      expect(
        planDownloadTargetPath(
          baseDir: r'C:\Users\me\Downloads',
          sourceName: 'a.txt',
          existingNames: const {},
        ),
        r'C:\Users\me\Downloads\a.txt',
      );
    });

    test('baseDir 尾部分隔符 → 不叠加', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d/',
          sourceName: 'a.txt',
          existingNames: const {},
        ),
        '/d/a.txt',
      );
      expect(
        planDownloadTargetPath(
          baseDir: r'C:\d\',
          sourceName: 'a.txt',
          existingNames: const {},
        ),
        r'C:\d\a.txt',
      );
    });

    test('空 baseDir → 仅返回唯一文件名', () {
      expect(
        planDownloadTargetPath(
          baseDir: '',
          sourceName: 'a.txt',
          existingNames: const {},
        ),
        'a.txt',
      );
    });
  });

  group('planDownloadTargetPath — 同名去重（不覆盖）', () {
    test('无冲突 → 原名', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'report.pdf',
          existingNames: const {'other.txt'},
        ),
        '/d/report.pdf',
      );
    });

    test('同名存在 → report (1).pdf', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'report.pdf',
          existingNames: const {'report.pdf'},
        ),
        '/d/report (1).pdf',
      );
    });

    test('多级冲突 → 追加序号递增', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'report.pdf',
          existingNames: const {'report.pdf', 'report (1).pdf', 'report (2).pdf'},
        ),
        '/d/report (3).pdf',
      );
    });

    test('无扩展名 → slides (1)', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'slides',
          existingNames: const {'slides'},
        ),
        '/d/slides (1)',
      );
    });

    test('已有同名净化形式同样去重（源名带非法字符）', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'a<b>.txt',
          existingNames: const {'a_b_.txt'},
        ),
        '/d/a_b_ (1).txt',
      );
    });
  });

  group('planDownloadTargetPath — 净化（复用 file_export_names）', () {
    test('跨平台非法字符 → 下划线', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'a<b>:"|?.txt',
          existingNames: const {},
        ),
        '/d/a_b_____.txt',
      );
    });

    test('Windows 保留设备名 → 前缀下划线', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: 'con.txt',
          existingNames: const {},
        ),
        '/d/_con.txt',
      );
    });

    test('净化后为空 → fallback 名', () {
      expect(
        planDownloadTargetPath(
          baseDir: '/d',
          sourceName: '...',
          existingNames: const {},
        ),
        '/d/download',
      );
    });
  });
}
