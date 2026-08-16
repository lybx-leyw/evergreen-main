// scraper_workflow v2 工程化测试（Phase 1 harness）。
//
// 覆盖：
// 1. 快照冻结（A18）：confirmCaptureDone → snapshotFrozen / 锁定回调
// 2. G5 门禁（A5/A10）：假数据标记 → requestDone 弹窗裁决 → 放行/拒绝两分支
// 3. 阶段级回退（A14）：rollbackTo + 回退后重过验收
// 4. refining（A16）：done 后 feedbackTriggered → debugging
// 5. 调试轮次（A15）：连续 3 轮失败 → warning
// 6. 验收门槛（G1-G4）
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HttpRequestLog log(String url) => HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: url,
      );

  group('阶段转换与验收门槛', () {
    test('idle → capturing 自动开始', () {
      final w = ScraperWorkflow();
      expect(w.startCapturing(), isTrue);
      expect(w.phase, ScraperPhase.capturing);
    });

    test('G1：无日志时 startAnalyzing 被拒', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      expect(w.startAnalyzing(), isFalse);
      expect(w.phase, ScraperPhase.capturing);
    });

    test('G1：有日志后 startAnalyzing 通过', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/api'));
      expect(w.startAnalyzing(), isTrue);
      expect(w.phase, ScraperPhase.analyzing);
    });
  });

  group('日志快照（A18）', () {
    test('confirmCaptureDone 冻结快照并触发锁定回调', () {
      final w = ScraperWorkflow();
      var locked = false;
      w.onWebViewLock = () => locked = true;
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.addLog(log('https://a.com/2'));
      w.confirmCaptureDone();
      expect(w.snapshotFrozen, isTrue);
      expect(w.snapshot.length, 2);
      expect(locked, isTrue);
      // 冻结后 addLog 不再进快照
      w.addLog(log('https://a.com/3'));
      expect(w.snapshot.length, 2);
    });

    test('restartCapture 清空快照并回 capturing', () {
      final w = ScraperWorkflow();
      var restarted = false;
      w.onRestartCapture = () => restarted = true;
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.confirmCaptureDone();
      w.restartCapture();
      expect(w.phase, ScraperPhase.capturing);
      expect(w.snapshotFrozen, isFalse);
      expect(w.hasLogs, isFalse);
      expect(restarted, isTrue);
    });

    test('快照优先：冻结后 requestLogsSummary 返回快照', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.confirmCaptureDone();
      w.addLog(log('https://a.com/2'));
      final summary = w.requestLogsSummary();
      expect(summary.contains('已冻结快照'), isTrue);
      expect(summary.contains('a.com/2'), isFalse);
    });
  });

  group('G5 假数据门禁（A5/A10）', () {
    test('无假数据标记 → requestDone 直接 done', () async {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      final ok = await w.requestDone();
      expect(ok, isTrue);
      expect(w.phase, ScraperPhase.done);
    });

    test('假数据标记 → 弹窗放行 → done 且清标记', () async {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      var asked = false;
      String? reasonShown;
      w.onUserConfirmRequest = (reason, ai) async {
        asked = true;
        reasonShown = reason;
        return true; // 用户放行
      };
      final ok = await w.requestDone(aiClarification: '这是静态 JSON 页');
      expect(ok, isTrue);
      expect(asked, isTrue);
      expect(reasonShown, contains('假数据'));
      expect(w.phase, ScraperPhase.done);
      expect(w.suspectedFakeData, isFalse);
    });

    test('假数据标记 → 弹窗拒绝 → 转 debugging', () async {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      w.onUserConfirmRequest = (reason, ai) async => false; // 用户拒绝
      final ok = await w.requestDone();
      expect(ok, isFalse);
      expect(w.phase, ScraperPhase.debugging);
    });

    test('假数据标记无回调 → 默认拒绝（fail-closed）', () async {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      final ok = await w.requestDone();
      expect(ok, isFalse);
      expect(w.phase, ScraperPhase.debugging);
    });
  });

  group('阶段级回退（A14）', () {
    test('rollbackTo 已完成阶段 + 记录轨迹', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      expect(w.rollbackTo(ScraperPhase.capturing), isTrue);
      expect(w.phase, ScraperPhase.capturing);
      expect(w.rollbackHistory, contains(ScraperPhase.analyzing));
    });

    test('不能回退到未完成/当前阶段', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      expect(w.rollbackTo(ScraperPhase.done), isFalse);
      expect(w.rollbackTo(ScraperPhase.analyzing), isFalse);
    });

    test('回退后前进需重过验收', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      // 清空日志模拟回退后状态丢失
      w.rollbackTo(ScraperPhase.capturing);
      w.clearLogs();
      expect(w.startAnalyzing(), isFalse); // 无日志 → 拒绝
    });
  });

  group('refining 循环（A16）', () {
    test('done 后 feedbackTriggered → debugging（不重新抓包）', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.startAnalyzing();
      // 直接完成
      w.markDone();
      expect(w.phase, ScraperPhase.done);
      // 用户反馈
      w.feedbackTriggered();
      expect(w.phase, ScraperPhase.debugging);
    });

    test('非 done 状态 feedbackTriggered 忽略', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.feedbackTriggered();
      expect(w.phase, ScraperPhase.capturing);
    });

    test('A19：refining 轮次计数递增（不设硬上限，仅展示）', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.markDone();
      w.feedbackTriggered();
      expect(w.refineCount, 1);
      w.markDone(); // 优化后再次完成
      w.feedbackTriggered();
      expect(w.refineCount, 2);
      w.markDone();
      w.feedbackTriggered();
      expect(w.refineCount, 3); // 无硬上限
    });

    test('restartCapture 重置 refineCount', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.markDone();
      w.feedbackTriggered();
      expect(w.refineCount, 1);
      w.restartCapture();
      expect(w.refineCount, 0);
    });
  });

  group('调试轮次（A15）', () {
    test('连续 3 轮失败 → warning 回调', () {
      final w = ScraperWorkflow();
      String? warn;
      w.onWarning = (msg) => warn = msg;
      w.startDebugging();
      w.startDebugging();
      expect(warn, isNull);
      w.startDebugging(); // 第 3 轮
      expect(warn, isNotNull);
      expect(warn, contains('连续 3 轮'));
      expect(w.warningSent3, isTrue);
    });

    test('成功重置计数后重新计数', () {
      final w = ScraperWorkflow();
      String? warn;
      w.onWarning = (msg) => warn = msg;
      w.startDebugging();
      w.startDebugging();
      w.resetDebugLoop(); // 成功
      w.startDebugging();
      w.startDebugging();
      expect(warn, isNull); // 计数已重置
      w.startDebugging();
      expect(warn, isNotNull);
    });

    test('warning 只发一次（反复提醒语义）', () {
      final w = ScraperWorkflow();
      var count = 0;
      w.onWarning = (msg) => count++;
      for (var i = 0; i < 6; i++) {
        w.startDebugging();
      }
      expect(count, 1); // 只触发一次 warning 标记
    });
  });

  group('reset', () {
    test('reset 清空全部状态', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.confirmCaptureDone();
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      w.startDebugging();
      w.reset();
      expect(w.phase, ScraperPhase.idle);
      expect(w.hasLogs, isFalse);
      expect(w.snapshotFrozen, isFalse);
      expect(w.guardFlags, isEmpty);
      expect(w.rollbackHistory, isEmpty);
      expect(w.consecutiveFailures, 0);
    });
  });

  group('G6 注册防线状态（A3/A5）', () {
    test('suspectedFakeData 标记可被 G6 接线读取', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      // G6 接线（_generatePlugin）读取此标记决定是否拒绝注册
      expect(w.suspectedFakeData, isTrue);
      expect(w.guardFlags.contains(GuardFlags.suspectedFakeData), isTrue);
    });

    test('clearGuardFlag 清除后 G6 可放行', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      w.clearGuardFlag(GuardFlags.suspectedFakeData);
      expect(w.suspectedFakeData, isFalse);
    });

    test('lint 的假数据 warning 可写入 guardFlags（G6 兜底链）', () {
      final w = ScraperWorkflow();
      w.startCapturing();
      w.addLog(log('https://a.com/1'));
      // 模拟 hooks：lint 命中假数据 → setGuardFlag
      w.setGuardFlag(GuardFlags.suspectedFakeData);
      // 模拟 G6：读 flag → 拒绝注册
      expect(w.suspectedFakeData, isTrue);
    });
  });
}
