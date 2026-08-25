/// file_export_names 纯函数测试（T8b：文件名净化 / 冲突命名 / URL 派生）。
///
/// 纯逻辑（零 Flutter 依赖），本测试置于 flutter_test 下随 CI 运行。沙箱本地因主包
/// 1GB 内存限制不跑 `flutter test`，等价验证已通过：`dart analyze` 零问题 +
/// `dart run tool/verify_file_export_names.dart`（本地辅助脚本，`evg-base/tool/*`
/// gitignored，不入库）全部断言通过。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/components/shared/file_export_names.dart';

void main() {
  group('sanitizeFileName', () {
    test('保留普通文件名', () {
      expect(sanitizeFileName('report.pdf'), 'report.pdf');
      expect(sanitizeFileName('我的文件.pdf'), '我的文件.pdf');
    });

    test('路径穿越只取末段（单段安全文件名）', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\windows\system32'), 'system32');
      expect(sanitizeFileName('a/b/c.pdf'), 'c.pdf');
      expect(sanitizeFileName('a/b/'), 'b');
    });

    test('跨平台非法字符与控制字符被替换', () {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h'), 'a_b_c_d_e_f_g_h');
      expect(sanitizeFileName('bad\x00name\x1f.pdf'), 'bad_name_.pdf');
    });

    test('折叠空白与去首尾空白', () {
      expect(sanitizeFileName('  a   b  '), 'a b');
    });

    test('去结尾点/空格与开头点', () {
      expect(sanitizeFileName('report.pdf...'), 'report.pdf');
      expect(sanitizeFileName('.gitignore'), 'gitignore');
      expect(sanitizeFileName('..'), kExportFallbackName);
    });

    test('纯点号/空输入回退', () {
      expect(sanitizeFileName('...'), kExportFallbackName);
      expect(sanitizeFileName(''), kExportFallbackName);
      expect(sanitizeFileName('   '), kExportFallbackName);
    });

    test('Windows 保留设备名前缀下划线', () {
      expect(sanitizeFileName('con'), '_con');
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('nul'), '_nul');
      expect(sanitizeFileName('aux'), '_aux');
    });

    test('自定义 fallback', () {
      expect(sanitizeFileName('', fallback: 'file'), 'file');
    });

    test('超长文件名截断并保留扩展名', () {
      final long = 'x' * 500;
      final result = sanitizeFileName('$long.pdf');
      expect(result.length, lessThanOrEqualTo(kMaxFileNameLength + 4));
      expect(result.endsWith('.pdf'), isTrue);
    });
  });

  group('fileNameFromUrl', () {
    test('从 URL 末段派生并净化', () {
      expect(fileNameFromUrl('https://x.com/a/b/report.pdf'), 'report.pdf');
      expect(
        fileNameFromUrl('https://x.com/a/%E6%8A%A5%E5%91%8A.pdf'),
        '报告.pdf',
      );
    });

    test('末段为空/非法回退', () {
      expect(fileNameFromUrl('https://x.com/'), kExportFallbackName);
      expect(fileNameFromUrl('not a url'), kExportFallbackName);
      expect(fileNameFromUrl(''), kExportFallbackName);
    });
  });

  group('uniqueFileName', () {
    test('无冲突返回原名', () {
      expect(uniqueFileName('report.pdf', {'other.pdf'}), 'report.pdf');
    });

    test('冲突追加序号并保留扩展名', () {
      expect(uniqueFileName('report.pdf', {'report.pdf'}), 'report (1).pdf');
      expect(
        uniqueFileName('report.pdf', {'report.pdf', 'report (1).pdf'}),
        'report (2).pdf',
      );
    });

    test('无扩展名冲突', () {
      expect(uniqueFileName('slides', {'slides', 'slides (1)'}), 'slides (2)');
    });

    test('跳过既有序号直达首个可用', () {
      expect(
        uniqueFileName('a.pdf', {'a.pdf', 'a (1).pdf', 'a (2).pdf'}),
        'a (3).pdf',
      );
    });
  });
}
