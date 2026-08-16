// scraper_hooks 测试（Phase 1 harness：L2 前置审查 + guardFlags 生命周期）。
//
// 覆盖：
// 1. run_python_scraper：lint violation block / 假数据 warning 写标记
// 2. A5 修正语义：lint 无假数据 → 自动清除标记（G5 不反复拦截）
// 3. run_terminal_command：黑名单 block
// 4. save_credential：非法参数 block
// 5. export_and_register_scraper：假数据未清除 block（G6 兜底）
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_hooks.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScraperWorkflow newWorkflow() {
    final w = ScraperWorkflow();
    w.startCapturing();
    return w;
  }

  const fakeDataCode = '''
import json, os

def _get_config(key):
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    return ''

if __name__ == "__main__":
    print(json.dumps([{"name": "张三", "score": 99}]))
''';

  const realCode = '''
import json, requests
def _get_config(key):
    return os.environ.get('GREENIX_CONFIG_PATH', '')
def main():
    r = requests.get('https://api.zju.edu.cn/courses')
    return r.json()
if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False))
''';

  group('run_python_scraper lint（L2）', () {
    test('violation → block 且回灌违规清单', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, msg) =
          await hooks.preToolUse('run_python_scraper', {
        'code': 'print("hello")',
      });
      expect(block, isTrue);
      expect(msg, contains('代码审查未通过'));
    });

    test('假数据 warning → 放行 + 写 guardFlags（G5 门禁用）', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, _) = await hooks.preToolUse('run_python_scraper', {
        'code': fakeDataCode,
      });
      expect(block, isFalse); // warning 放行不阻断
      expect(w.suspectedFakeData, isTrue); // 标记写入
    });

    test('A5 修正语义：lint 无假数据 → 自动清除标记', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      // 先命中假数据
      await hooks.preToolUse('run_python_scraper', {'code': fakeDataCode});
      expect(w.suspectedFakeData, isTrue);
      // AI 修正为真实抓取 → 重新执行 → 标记自动清除
      final (block, _) = await hooks.preToolUse('run_python_scraper', {
        'code': realCode,
      });
      expect(block, isFalse);
      expect(w.suspectedFakeData, isFalse); // G5 不再反复拦截
    });

    test('真实抓取代码（含 requests.get）→ 无标记', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      await hooks.preToolUse('run_python_scraper', {'code': realCode});
      expect(w.suspectedFakeData, isFalse);
    });
  });

  group('run_terminal_command 守卫（L2）', () {
    test('黑名单命令 → block', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, msg) =
          await hooks.preToolUse('run_terminal_command', {
        'command': 'rm -rf /',
      });
      expect(block, isTrue);
      expect(msg, contains('守卫拒绝'));
    });

    test('白名单命令 → 放行', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, _) =
          await hooks.preToolUse('run_terminal_command', {
        'command': 'python scraper.py',
      });
      expect(block, isFalse);
    });
  });

  group('save_credential 校验（L2）', () {
    test('非法 key → block', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, _) =
          await hooks.preToolUse('save_credential', {
        'key': 'a/b',
        'value': 'v',
      });
      expect(block, isTrue);
    });

    test('合法 key → 放行', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, _) =
          await hooks.preToolUse('save_credential', {
        'key': 'ZJU_USERNAME',
        'value': 'test',
      });
      expect(block, isFalse);
    });
  });

  group('export_and_register_scraper G6 兜底', () {
    test('假数据未清除 → block 拒绝注册', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      final (block, msg) =
          await hooks.preToolUse('export_and_register_scraper', {
        'data_name': 'courses',
      });
      expect(block, isTrue);
      expect(msg, contains('拒绝注册'));
    });

    test('标记已清除 → 放行注册', () async {
      final w = newWorkflow();
      final hooks = ScraperHooks(workflow: w);
      final (block, _) =
          await hooks.preToolUse('export_and_register_scraper', {
        'data_name': 'courses',
      });
      expect(block, isFalse);
    });
  });
}
