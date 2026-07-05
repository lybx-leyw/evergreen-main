/// 多智能体视图——两页双栏，每栏一个独立 Agent。
///
/// ## 架构
/// ```
/// TabBar [页面1] [页面2]
/// ┌──────────────┬──────────────┐
/// │  Agent A1    │  Agent A2    │  ← 页面1 (双栏)
/// │  (独立记忆)   │  (独立记忆)   │
/// │  (独立工作区) │  (独立工作区) │
/// ├──────────────┼──────────────┤
/// │  Agent B1    │  Agent B2    │  ← 页面2 (双栏)
/// └──────────────┴──────────────┘
/// ```
///
/// ## 隔离
/// | 维度 | 隔离方式 |
/// |------|---------|
/// | 工作区 | `.greenix/workspaces/multi-agent/<page>/<col>/` |
/// | 记忆 | `.greenix/multi-agent/<page>/<col>/memories/` |
/// | 会话 | `.greenix/multi-agent/<page>/<col>/sessions/` |
/// | Agent | 通过 [AgentAssembly.fromConfig] 创建隔离 Controller |
///
/// ## PLAN_NOW 整合
/// 每个 Agent 列通过 [AgentAssembly] 工厂创建，而非手动构建 Agent 栈。
/// 共享 [DeepSeekProvider]（同 API Key），隔离 Registry/Memory/Session/Skill。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/config.dart';
import '../../core/agent/agent.dart' as agent;
import '../../providers.dart';
import 'single_agent_column.dart';

/// 多智能体页签定义。
class _AgentPageConfig {
  final String title;
  final List<AgentColumnConfig> columns;
  const _AgentPageConfig({required this.title, required this.columns});
}

class MultiAgentView extends ConsumerStatefulWidget {
  const MultiAgentView({super.key});

  @override
  ConsumerState<MultiAgentView> createState() => _MultiAgentViewState();
}

class _MultiAgentViewState extends ConsumerState<MultiAgentView> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final List<_AgentPageConfig> _pages;
  String _apiKey = '';
  bool _loaded = false;

  // 共享的 LLM Provider（同一 API Key，复用连接 —— PLAN_NOW §十）
  agent.Provider? _sharedProvider;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (mounted) {
        setState(() {
          _apiKey = key;
          _loaded = true;
          if (key.isNotEmpty) {
            _sharedProvider = agent.DeepSeekProvider(
              dio: Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 120),
              )),
              apiKey: key,
            );
          }
          _buildPages();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _buildPages() {
    // 构建 2 页 × 2 栏 = 4 个独立智能体，通过 AgentAssembly 工厂创建
    _pages = List.generate(2, (pageIdx) {
      final pageTitle = '工作区 ${pageIdx + 1}';
      final cols = List.generate(2, (colIdx) {
        final slot = 'p${pageIdx}-c$colIdx';
        final name = 'Agent ${String.fromCharCode(65 + pageIdx * 2 + colIdx)}'; // A/B/C/D
        return AgentColumnConfig(
          id: slot,
          name: name,
          apiKey: _apiKey,
          sharedProvider: _sharedProvider,
          // AgentAssembly 所需全局依赖（从 Riverpod 读取）
          globalSkillIndex: ref.read(skillIndexProvider),
          globalMemoryStore: ref.read(memoryStoreProvider),
          // PLAN_NOW 配置：每个 Agent 列使用 research-full 预设
          // 全部工具 + 全局记忆 + workspace + 多会话
          aiConfig: const {
            'preset': 'research-full',
            'system_prompt': '你是一个AI助手，工作在多智能体协作环境中。简洁回答。',
          },
        );
      });
      return _AgentPageConfig(title: pageTitle, columns: cols);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white70 : Colors.black87;

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_apiKey.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_off, size: 36, color: Colors.orange.shade300),
            const SizedBox(height: 12),
            const Text('未配置 API Key', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            const Text('请在 设置 > API Key 中配置 DEEPSEEK_API_KEY',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('多智能体', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _pages.map((p) => Tab(text: p.title)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _pages.map(_buildPage).toList(),
      ),
    );
  }

  Widget _buildPage(_AgentPageConfig page) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏(<600px) 改为上下排列
        final useRow = constraints.maxWidth >= 600;
        if (useRow) {
          return Row(
            children: [
              for (final col in page.columns)
                Expanded(child: SingleAgentColumn(config: col)),
            ],
          );
        }
        return Column(
          children: [
            for (final col in page.columns)
              Expanded(child: SingleAgentColumn(config: col)),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
