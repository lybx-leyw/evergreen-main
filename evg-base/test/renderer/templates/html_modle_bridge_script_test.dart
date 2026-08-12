/// Phase C 单测：共享 bridge 生成器（bridge_script.dart）。
///
/// 锁定三处入口（html_modle 运行期 / 创作中心预览）共用的契约：
/// 1. [buildBridgeScript] 生成的 JS 含全部 platform.* API + 双通道 + 幂等守卫；
/// 2. [forwardCoreHttp] 端口文件缺失时抛「服务未启动」；
/// 3. [DataSubscriptionPoller] 订阅幂等、快照变化推送、null 跳过、dispose 清理。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/html_modle/bridge_script.dart';
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart';

void main() {
  group('buildBridgeScript', () {
    final js = buildBridgeScript();

    test('含幂等守卫', () {
      expect(js, contains('__evgBridgeInjected'));
    });

    test('含全部 platform.data.* API', () {
      expect(js, contains('data.get'));
      expect(js, contains('data.list'));
      expect(js, contains('data.refresh'));
      expect(js, contains('data.testConnectivity'));
      expect(js, contains('data.subscribe'));
    });

    test('含 ai / api / settings / theme / emit-on', () {
      expect(js, contains('ai.chat'));
      expect(js, contains('api.call'));
      expect(js, contains('settings.get'));
      expect(js, contains('settings.set'));
      expect(js, contains('theme.getColors'));
      expect(js, contains('emit: function(event, payload)'));
      expect(js, contains('on: function(event, fn)'));
    });

    test('含双通道发送与全局回调', () {
      expect(js, contains('chrome.webview'));
      expect(js, contains('evgBridge'));
      expect(js, contains('window.__evgResolve'));
      expect(js, contains('window.__evgReject'));
      expect(js, contains('window.__evgFireEvent'));
      expect(js, contains('window.__evgApplyTheme'));
    });

    test('不含预览端旧版独有日志标记（已收敛）', () {
      expect(js, isNot(contains('[Evergreen Bridge] ready')));
      expect(js, contains('Evergreen bridge ready'));
    });

    test('含文档创建时主题自动应用', () {
      expect(js, contains("_call('theme.getColors', [])"));
    });
  });

  group('forwardCoreHttp', () {
    test('端口文件缺失 → 抛「服务未启动」', () async {
      final dir = Directory.systemTemp.createTempSync('evg_bridge_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final discovery = CoreApiDiscovery(projectRootOverride: dir.path);

      await expectLater(
        forwardCoreHttp(
          CoreService.data,
          'GET',
          '/data/types',
          null,
          discovery,
        ),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'toString', contains('未启动'))),
      );
    });
  });

  group('DataSubscriptionPoller', () {
    test('subscribe 幂等：重复订阅不增加轮询', () async {
      var value = {'n': 1};
      var fetched = 0;
      final poller = DataSubscriptionPoller(
        fetch: (name) async {
          fetched++;
          return value;
        },
        executeJs: (js) async {},
        interval: const Duration(milliseconds: 5),
      );
      poller.subscribe('a');
      poller.subscribe('a'); // 幂等
      expect(poller.subscribedNames, {'a'});
      await Future.delayed(const Duration(milliseconds: 25));
      poller.dispose();
      expect(fetched, greaterThanOrEqualTo(2));
    });

    test('值未变化 → 仅首次推送初始值，后续轮询不重复推送', () async {
      var value = {'n': 1};
      final executes = <String>[];
      final poller = DataSubscriptionPoller(
        fetch: (name) async => value,
        executeJs: (js) async => executes.add(js),
        interval: const Duration(milliseconds: 5),
      );
      poller.subscribe('a'); // 首次 poll：prev=null → 推送初始值 1 次
      await Future.delayed(const Duration(milliseconds: 25));
      poller.dispose();
      expect(executes.length, 1); // 快照未变，后续轮询不再推送
      expect(executes.first, contains('data:changed'));
    });

    test('值变化 → 推送 data:changed（含 name 与新值）', () async {
      var value = {'n': 1};
      final executes = <String>[];
      final poller = DataSubscriptionPoller(
        fetch: (name) async => value,
        executeJs: (js) async => executes.add(js),
        interval: const Duration(milliseconds: 5),
      );
      poller.subscribe('a');
      await Future.delayed(const Duration(milliseconds: 12));
      value = {'n': 2};
      await Future.delayed(const Duration(milliseconds: 15));
      poller.dispose();
      expect(executes.any((s) => s.contains('"n":2')), isTrue);
      expect(executes.any((s) => s.contains('"name":"a"')), isTrue);
    });

    test('fetch 返回 null（未注册）→ 跳过本轮，不更新快照', () async {
      var value = null;
      var fetched = 0;
      final executes = <String>[];
      final poller = DataSubscriptionPoller(
        fetch: (name) async {
          fetched++;
          return value;
        },
        executeJs: (js) async => executes.add(js),
        interval: const Duration(milliseconds: 5),
      );
      poller.subscribe('a');
      await Future.delayed(const Duration(milliseconds: 20));
      value = {'ok': true}; // 数据源注册后首次拿到数据
      await Future.delayed(const Duration(milliseconds: 12));
      poller.dispose();
      expect(fetched, greaterThanOrEqualTo(2));
      expect(executes, isNotEmpty); // null → 有值视为变化
    });

    test('dispose 清理全部订阅与快照', () async {
      var value = {'n': 1};
      final poller = DataSubscriptionPoller(
        fetch: (name) async => value,
        executeJs: (js) async {},
        interval: const Duration(milliseconds: 5),
      );
      poller.subscribe('a');
      poller.subscribe('b');
      expect(poller.subscribedNames, {'a', 'b'});
      poller.dispose();
      expect(poller.subscribedNames, isEmpty);
    });
  });
}
