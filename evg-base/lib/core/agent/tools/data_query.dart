/// Agent 工具：与数据中枢（DataOrchestrator）交互——查询、刷新、状态检查。
///
/// 允许 AI 助手通过 [DataOrchestrator] 调取任意已注册数据源，包括：
/// - 列举所有数据类型
/// - 按名称获取/刷新数据
/// - 查询数据源状态
/// - 列出分类
///
/// # [DataQueryTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |------|------|------|------|
/// | `DataQueryTool({orchestrator})` | DataOrchestrator 引用 | `DataQueryTool` | 构造 |
/// | `execute(args)` | `{'action': ..., 'type_name': ...}` | `Future<String>` | 执行查询 |
library;

import 'dart:convert';

import '../../data/orchestrator.dart';
import '../../data/exceptions.dart';
import '../tool.dart';

/// 数据中枢查询工具——让 AI 具备与 DataOrchestrator 交互的能力。
///
/// 支持的操作（通过 action 参数选择）：
/// - `list_types`: 列出所有已注册数据类型（名称、分类、标签、TTL、新鲜度）
/// - `get`: 获取指定数据的缓存内容（缓存优先）
/// - `refresh`: 强制重新拉取指定数据
/// - `status`: 查询数据源连通状态（可指定类型名或返回全部）
/// - `categories`: 列出所有数据分类
/// - `count`: 返回数据源统计（总数/连通数/新鲜数）
class DataQueryTool extends Tool {
  final DataOrchestrator? _orchestrator;

  DataQueryTool({DataOrchestrator? orchestrator})
      : _orchestrator = orchestrator;

  @override
  String get name => 'data_query';

  @override
  String get description =>
      '与数据中枢交互，查询/刷新已注册的数据源。'
      '可用于获取课表、成绩、天气、新闻等任意已注册数据。\n'
      '\n'
      '参数说明：\n'
      '- action: 操作类型（必填），取值：\n'
      '  · list_types — 列出所有可用数据类型\n'
      '  · get — 获取指定数据的缓存内容\n'
      '  · refresh — 强制重新拉取指定数据\n'
      '  · status — 查询数据源状态（连通性、新鲜度、最近错误）\n'
      '  · categories — 列出所有数据分类\n'
      '  · count — 返回统计（总数/连通数/新鲜数）\n'
      '- type_name: 数据类型名称（get/refresh/status 时使用）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': [
              'list_types',
              'get',
              'refresh',
              'status',
              'categories',
              'count',
            ],
            'description': '操作类型',
          },
          'type_name': {
            'type': 'string',
            'description': '数据类型名称（get/refresh/status 时必填）',
          },
        },
        'required': ['action'],
      };

  DataOrchestrator get _orch {
    if (_orchestrator == null) {
      throw StateError('DataOrchestrator 未注入——DataQueryTool 未正确初始化。');
    }
    return _orchestrator!;
  }

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    if (_orchestrator == null) {
      return '[data_query 不可用] DataOrchestrator 未注入。请在应用启动时正确初始化数据中枢。';
    }

    final action = args['action']?.toString() ?? '';
    final typeName = args['type_name']?.toString() ?? '';

    switch (action) {
      case 'list_types':
        return _listTypes();
      case 'get':
        return _getData(typeName);
      case 'refresh':
        return _refreshData(typeName);
      case 'status':
        return _status(typeName);
      case 'categories':
        return _categories();
      case 'count':
        return _count();
      default:
        return '[data_query 错误] 未知操作: "$action"。'
            '可用操作: list_types, get, refresh, status, categories, count。';
    }
  }

  @override
  bool get readOnly => true;

  // ═══════ 操作实现 ═══════

  /// 列举所有已注册数据类型。
  String _listTypes() {
    final statuses = _orch.allStatuses;
    if (statuses.isEmpty) {
      return '数据中枢当前无已注册的数据类型。\n'
          '请先在插件或模块中通过 DataOrchestrator.register() 注册数据源。';
    }

    final buf = StringBuffer();
    buf.writeln('## 数据中枢 — 已注册类型 (${statuses.length})\n');

    // 按分类分组
    final grouped = <String, List<DataSourceStatus>>{};
    for (final s in statuses) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    for (final cat in grouped.keys.toList()..sort()) {
      buf.writeln('### $cat');
      for (final s in grouped[cat]!) {
        buf.writeln('- **${s.displayName}** (`${s.name}`)');
        buf.writeln('  状态: ${s.connected ? "✓ 连通" : "✗ 未连通"}');
        buf.writeln('  新鲜度: ${s.freshnessLabel} (${s.relativeTime})');
        buf.writeln('  TTL: ${_fmtDuration(s.ttl)}');
        if (s.lastError != null) {
          buf.writeln('  最近错误: ${s.lastError}');
        }
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// 获取指定数据的缓存内容。
  Future<String> _getData(String typeName) async {
    if (typeName.isEmpty) {
      return '[data_query 错误] get 操作需要提供 type_name 参数。';
    }

    try {
      final data = await _orch.getByName(typeName);
      if (data == null) {
        return '[data_query] 类型 "$typeName" 数据拉取返回空。可能是数据源暂时不可用，'
            '请稍后重试或检查数据源连接状态。';
      }

      final encoded = const JsonEncoder.withIndent('  ').convert(data);
      return '## $typeName — 数据内容\n\n```json\n$encoded\n```\n'
          '_（共 ${encoded.length} 字符）_';
    } on DataTypeNotRegisteredException catch (e) {
      return '[data_query 错误] $e\n'
          '可用类型: ${_orch.registeredTypes.join(", ")}';
    } catch (e) {
      return '[data_query 错误] 获取 "$typeName" 失败: $e';
    }
  }

  /// 强制刷新指定数据。
  Future<String> _refreshData(String typeName) async {
    if (typeName.isEmpty) {
      return '[data_query 错误] refresh 操作需要提供 type_name 参数。';
    }

    try {
      final data = await _orch.refreshByName(typeName);
      if (data == null) {
        return '[data_query] 类型 "$typeName" 刷新失败——数据源不可用或返回无效数据。';
      }

      final encoded = const JsonEncoder.withIndent('  ').convert(data);
      return '## $typeName — 刷新成功 ✓\n\n```json\n$encoded\n```\n'
          '_（共 ${encoded.length} 字符）_';
    } on DataTypeNotRegisteredException catch (e) {
      return '[data_query 错误] $e\n'
          '可用类型: ${_orch.registeredTypes.join(", ")}';
    } catch (e) {
      return '[data_query 错误] 刷新 "$typeName" 失败: $e';
    }
  }

  /// 查询数据源状态。
  String _status(String typeName) {
    if (typeName.isNotEmpty) {
      // 查询单个类型
      final s = _orch.status(typeName);
      if (s == null) {
        return '[data_query 错误] 类型 "$typeName" 未注册。\n'
            '可用类型: ${_orch.registeredTypes.join(", ")}';
      }
      return _formatSingleStatus(s);
    }

    // 查询全部
    final all = _orch.allStatuses;
    if (all.isEmpty) {
      return '数据中枢无已注册类型。';
    }

    final buf = StringBuffer();
    buf.writeln('## 数据中枢 — 连接状态\n');

    var connected = 0;
    var fresh = 0;
    for (final s in all) {
      if (s.connected) connected++;
      if (s.isFresh) fresh++;
      final icon = s.connected ? '✓' : '✗';
      final freshMark = s.isFresh ? '🟢' : '🔴';
      buf.writeln(
          '- $freshMark $icon **${s.displayName}** (`${s.name}`) [${s.category}] — ${s.relativeTime}');
      if (s.lastError != null) {
        buf.writeln('  错误: ${s.lastError}');
      }
    }
    buf.writeln('\n_连通 $connected/${all.length} — 新鲜 $fresh/${all.length}_');
    return buf.toString();
  }

  /// 列出所有分类。
  String _categories() {
    final cats = _orch.categories;
    if (cats.isEmpty) return '数据中枢无已注册分类。';
    return '## 数据中枢 — 分类\n\n${cats.map((c) => '- $c').join("\n")}\n\n_共 ${cats.length} 个分类_';
  }

  /// 返回统计计数。
  String _count() {
    final total = _orch.totalCount;
    if (total == 0) return '数据中枢无已注册类型。';
    return '## 数据中枢 — 统计\n'
        '- 总数: $total\n'
        '- 连通: ${_orch.connectedCount}\n'
        '- 新鲜: ${_orch.freshCount}';
  }

  // ═══════ 工具函数 ═══════

  String _formatSingleStatus(DataSourceStatus s) {
    final buf = StringBuffer();
    buf.writeln('## ${s.displayName} (`${s.name}`)');
    buf.writeln('- 分类: ${s.category}');
    buf.writeln('- 连通: ${s.connected ? "是" : "否"}');
    buf.writeln('- 新鲜度: ${s.freshnessLabel}');
    buf.writeln('- 最近更新: ${s.relativeTime}');
    buf.writeln('- TTL: ${_fmtDuration(s.ttl)}');
    if (s.lastError != null) {
      buf.writeln('- 最近错误: ${s.lastError}');
    }
    return buf.toString();
  }

  static String _fmtDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays} 天';
    if (d.inHours > 0) return '${d.inHours} 小时';
    if (d.inMinutes > 0) return '${d.inMinutes} 分钟';
    return '${d.inSeconds} 秒';
  }
}
