// 探索模式 hooks 白名单测试（Phase 4 · D9）。
//
// 覆盖：
// 1. 探索模式全程禁用定向抓取工具（run_python_scraper 等）
// 2. 阶段白名单：present_data_sources 在 exploring 也可用（工具内部切阶段）
// 3. navigate_get URL 守卫预检（跨域/非 http(s)）
// 4. build_selected_source lint（violation block / 假数据 guardFlag 自动置位与清除）
// 5. register_batch：假数据未清除 → 拒绝批量注册（G6 语义）
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_hooks.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通过 lint（无 violation）但命中假数据 heuristic 的代码。
const String fakeDataCode = '''
import json
import os
from pathlib import Path

def _get_config(key):
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    return os.environ.get(key, '')

if __name__ == "__main__":
    print(json.dumps([{"id": 1, "name": "test"}]))
''';

/// 真实抓取代码（requests 网络库 + json.dumps(main())）。
const String cleanCode = '''
import json
import os
from pathlib import Path
import requests

def _get_config(key):
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    return os.environ.get(key, '')

def main():
    r = requests.get('https://site.com/1')
    return r.json()

if __name__ == "__main__":
    print(json.dumps(main()))
''';

/// violation 代码：缺少锁定模板。
const String violationCode = '''
import requests

if __name__ == "__main__":
    print("{}")
''';

ScraperHooks makeHooks({ExplorePhase phase = ExplorePhase.exploring}) {
  final capture = ScraperWorkflow();
  final ew = ExploreWorkflow();
  ew.startExploring(startUrl: 'https://site.com/');
  // P0-2：捕获一条与候选源 url 匹配的日志（证据终闸放行依据）
  capture.addLog(HttpRequestLog(
    timestamp: DateTime.now(),
    method: 'GET',
    url: 'https://site.com/1',
  ));
  // 把 ew 推到目标阶段
  if (phase != ExplorePhase.exploring) {
    ew.startCategorizing();
    if (phase == ExplorePhase.confirming) {
      ew.presentCandidates(const [
        CandidateDataSource(name: 'x', displayName: 'x', category: '', url: 'https://site.com/1'),
      ]);
    }
    if (phase == ExplorePhase.building) {
      ew.presentCandidates(const [
        CandidateDataSource(name: 'x', displayName: 'x', category: '', url: 'https://site.com/1'),
      ]);
      ew.confirmSelection(const [
        CandidateDataSource(name: 'x', displayName: 'x', category: '', url: 'https://site.com/1'),
      ]);
    }
    if (phase == ExplorePhase.registering) {
      ew.presentCandidates(const [
        CandidateDataSource(name: 'x', displayName: 'x', category: '', url: 'https://site.com/1'),
      ]);
      ew.confirmSelection(const [
        CandidateDataSource(name: 'x', displayName: 'x', category: '', url: 'https://site.com/1'),
      ]);
      ew.startRegistering();
    }
  }
  return ScraperHooks(workflow: capture, exploreWorkflow: ew);
}

void main() {
  group('探索模式工具白名单（D9）', () {
    test('定向抓取工具在探索模式被拒', () async {
      final h = makeHooks();
      for (final name in ['run_python_scraper', 'run_terminal_command', 'save_credential', 'export_and_register_scraper']) {
        final (block, msg) = await h.preToolUse(name, {});
        expect(block, isTrue, reason: '$name 应被拒');
        expect(msg, contains('探索模式守卫'));
        expect(msg, contains(name));
      }
    });

    test('present_data_sources 在 exploring/categorizing/confirming 均可用', () async {
      // exploring 放行：工具内部会先 startCategorizing() 再 presentCandidates
      final hExploring = makeHooks(phase: ExplorePhase.exploring);
      final (block, _) = await hExploring.preToolUse('present_data_sources', {'sources': '[]'});
      expect(block, isFalse);

      final hCat = makeHooks(phase: ExplorePhase.categorizing);
      final (catBlock, _) = await hCat.preToolUse('present_data_sources', {'sources': '[]'});
      expect(catBlock, isFalse);
    });

    test('explore_page_links 在 exploring 放行', () async {
      final h = makeHooks();
      final (block, _) = await h.preToolUse('explore_page_links', {});
      expect(block, isFalse);
    });
  });

  group('navigate_get URL 守卫预检', () {
    test('跨域 → block', () async {
      final h = makeHooks();
      final (block, msg) = await h.preToolUse('navigate_get', {'url': 'https://evil.com/x'});
      expect(block, isTrue);
      expect(msg, contains('非同域'));
    });

    test('非 http(s) → block', () async {
      final h = makeHooks();
      final (block, msg) = await h.preToolUse('navigate_get', {'url': 'javascript:alert(1)'});
      expect(block, isTrue);
      expect(msg, contains('仅允许 http/https'));
    });

    test('同域 GET → 放行', () async {
      final h = makeHooks();
      final (block, _) = await h.preToolUse('navigate_get', {'url': 'https://site.com/a'});
      expect(block, isFalse);
    });
  });

  group('build_selected_source lint + register_batch 门禁', () {
    test('violation → block', () async {
      final h = makeHooks(phase: ExplorePhase.building);
      final (block, msg) = await h.preToolUse('build_selected_source', {'code': violationCode});
      expect(block, isTrue);
      expect(msg, contains('代码审查未通过'));
    });

    test('假数据 warning → 放行但写 guardFlag；修正后自动清除（A5）', () async {
      final h = makeHooks(phase: ExplorePhase.building);
      final (b1, _) = await h.preToolUse('build_selected_source', {'code': fakeDataCode});
      expect(b1, isFalse);
      expect(h.workflow.suspectedFakeData, isTrue);

      final (b2, _) = await h.preToolUse('build_selected_source', {'code': cleanCode});
      expect(b2, isFalse);
      expect(h.workflow.suspectedFakeData, isFalse);
    });

    test('假数据未清除 → register_batch 拒绝（G6 语义）', () async {
      final h = makeHooks(phase: ExplorePhase.building);
      await h.preToolUse('build_selected_source', {'code': fakeDataCode});
      expect(h.workflow.suspectedFakeData, isTrue);

      final (block, msg) = await h.preToolUse('register_batch', {'names': '["x"]'});
      expect(block, isTrue);
      expect(msg, contains('拒绝批量注册'));

      // 修正后放行
      await h.preToolUse('build_selected_source', {'code': cleanCode});
      final (ok, _) = await h.preToolUse('register_batch', {'names': '["x"]'});
      expect(ok, isFalse);
    });

    test('P0-2：确认源无捕获日志证据 → register_batch 放行（放宽，仅提示）', () async {
      final capture = ScraperWorkflow(); // 无任何日志
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://site.com/');
      ew.startCategorizing();
      const src = CandidateDataSource(
        name: 'ghost',
        displayName: '幽灵',
        category: '',
        url: 'https://site.com/api/ghost',
        sourceLogId: 'log-99',
      );
      ew.presentCandidates(const [src]);
      ew.confirmSelection(const [src]);
      final h = ScraperHooks(workflow: capture, exploreWorkflow: ew);

      final (block, _) = await h.preToolUse('register_batch', {'names': '["ghost"]'});
      expect(block, isFalse); // 无日志证据不再拦截
    });
  });

  group('定向模式（无 exploreWorkflow）行为不变', () {
    test('run_python_scraper 违规代码仍被 lint 拦截', () async {
      final h = ScraperHooks(workflow: ScraperWorkflow());
      final (block, msg) = await h.preToolUse('run_python_scraper', {'code': violationCode});
      expect(block, isTrue);
      expect(msg, contains('代码审查未通过'));
    });
  });
}
