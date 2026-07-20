// scraper stdout JSON 校验回归测试（纯 Dart，不挂载 widget / 不碰 Provider /
// SharedPreferences，绝不挂死）。
//
// 背景：skill 第 6 步 + 数据插件要求 scraper stdout 必须是合法 JSON（平台
// jsonDecode(stdout)）。但 AI 调试循环里的 run_python_scraper / 终端
// run_terminal_command 过去只检查 exitCode，导致「打印人类可读文本却 exitCode=0」
// 被误判成功、提前 markDone，平台真正校验时才失败——而 AI 全程看不到校验日志。
// 修复：AI 循环执行与平台一致的 JSON 校验，并把含 ❌ 的校验失败日志回灌给 AI。
//
// 本测试锁定契约：
// 1. 合法 JSON → validateScraperStdout.isValid == true
// 2. 非 JSON（人类文本 / 前缀文本 / 空输出）→ isValid == false
// 3. 失败回传消息含 ❌（_onAgentEvent 据此进入调试分支，使 AI 能自我修正）
// 4. isScraperRunCommand 仅对 scraper.py 命令返回 true（不会误校验 pip install）
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/scraper/scraper_json_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scraper stdout JSON 校验（与平台 jsonDecode 一致）', () {
    test('合法 JSON 对象 → 通过', () {
      final v = validateScraperStdout('{"name":"ZJU","score":99}');
      expect(v.isValid, isTrue);
      expect(v.error, isNull);
    });

    test('合法 JSON 数组 → 通过', () {
      final v = validateScraperStdout('[{"id":1},{"id":2}]');
      expect(v.isValid, isTrue);
    });

    test('首尾空白不影响的合法 JSON → 通过', () {
      final v = validateScraperStdout('\n  [1, 2, 3]  \n');
      expect(v.isValid, isTrue);
    });

    test('人类可读文本（非 JSON）→ 失败', () {
      final v = validateScraperStdout('正在抓取数据，请稍候...');
      expect(v.isValid, isFalse);
      expect(v.error, isNotNull);
    });

    test('前缀文本 + JSON（整体不可解析）→ 失败', () {
      // 平台 jsonDecode(stdout) 对整体解析会失败
      final v = validateScraperStdout('LOG: start\n{"a":1}');
      expect(v.isValid, isFalse);
    });

    test('空输出 → 失败', () {
      final v = validateScraperStdout('   ');
      expect(v.isValid, isFalse);
    });

    test('失败回传消息含 ❌（触发 AI 调试分支）', () {
      final msg = buildJsonValidationFailureMessage('not json');
      expect(msg, contains('❌'));
      expect(msg, contains('JSON'));
      // 同时校验终端变体的失败消息也带 ❌
      final termMsg = buildJsonValidationFailureMessageForTerminal('not json');
      expect(termMsg, contains('❌'));
    });

    test('成功消息含 ✅（触发 markDone）', () {
      final msg = buildJsonValidationSuccessMessage('{"ok":1}', '');
      expect(msg, contains('✅'));
      expect(msg, contains('JSON 输出校验通过'));
    });

    test('isScraperRunCommand 仅对 scraper.py 命中', () {
      expect(isScraperRunCommand('python scraper.py'), isTrue);
      expect(isScraperRunCommand('PYTHON Scraper.PY'), isTrue);
      expect(isScraperRunCommand('pip install requests'), isFalse);
      expect(isScraperRunCommand('python -m http.server'), isFalse);
    });
  });

  // root cause B：导出/热注册的「检验失败」（.exe 编译失败 / lastError /
  // orch.get 返回 null / 拉取异常）过去只弹 UI，AI 看不到、无法自修。
  // export_and_register_scraper 工具把完整日志作为工具结果回灌给 AI；
  // 手动按钮触发时用 exportRegisterLogHasFailure 判定是否需要回灌。
  group('导出/热注册检验失败判定（回灌 AI 依据）', () {
    test('.exe 编译失败（含 ❌）→ 判定为失败', () {
      const log = '🔧 开始生成插件...\n❌ .exe 编译失败: PyInstaller 打包失败';
      expect(exportRegisterLogHasFailure(log), isTrue);
    });

    test('orch.get 返回 lastError → 判定为失败', () {
      const log = '✅ 热注册完成 (1 个类型)\n**scores**:\n- ⚠ 返回 null\n'
          '- lastError: HTTP 901\n- connected: false';
      expect(exportRegisterLogHasFailure(log), isTrue);
    });

    test('orch.get 拉取异常 → 判定为失败', () {
      const log = '**courses**:\n- ❌ 拉取异常: TimeoutException';
      expect(exportRegisterLogHasFailure(log), isTrue);
    });

    test('orch.get 返回 null → 判定为失败', () {
      const log = '**data**:\n- ⚠ 返回 null';
      expect(exportRegisterLogHasFailure(log), isTrue);
    });

    test('全部成功（仅 ✅）→ 不回灌 AI', () {
      const log = '✅ .exe 编译完成\n✅ data/manifest.json\n✅ config/config.json\n'
          '🎉 全部完成\n**data**:\n- ✅ 拉取成功';
      expect(exportRegisterLogHasFailure(log), isFalse);
    });
  });
}
