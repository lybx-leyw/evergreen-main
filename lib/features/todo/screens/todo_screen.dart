import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/todo_provider.dart';
import '../services/todo_service.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../core/config/theme.dart';
import '../../../core/utils/auto_refresh.dart';

/// 待办筛选器配置。
enum TodoSourceFilter { all, courses, pintia }

/// Todo screen — 待办事项 + 多维度筛选。
class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key});

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  bool _showExpired = false;
  TodoSourceFilter _sourceFilter = TodoSourceFilter.all;
  bool _sortAscending = true; // true = 时间升序（最近的在前）

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (shouldRefresh(ref)) ref.invalidate(todoListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final todosAsync = ref.watch(todoListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(todoListProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 筛选栏 ──
          _buildFilterBar(context),
          const Divider(height: 1),
          // ── 列表 ──
          Expanded(
            child: todosAsync.when(
              loading: () =>
                  const LoadingWidget(message: '加载待办列表...'),
              error: (err, _) => ErrorCard(
                message: '加载待办失败',
                detail: err.toString(),
                onRetry: () => ref.invalidate(todoListProvider),
              ),
              data: (todos) => _buildList(context, todos),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          // 第一行：平台筛选
          Row(
            children: [
              const Icon(Icons.filter_list, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              ...TodoSourceFilter.values.map((f) {
                final label = switch (f) {
                  TodoSourceFilter.all => '全部',
                  TodoSourceFilter.courses => '学在浙大',
                  TodoSourceFilter.pintia => 'PTA',
                };
                final selected = _sourceFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _sourceFilter = f),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：过期 + 排序
          Row(
            children: [
              // 过期开关
              FilterChip(
                label: const Text('已过期', style: TextStyle(fontSize: 12)),
                selected: _showExpired,
                onSelected: (v) => setState(() => _showExpired = v),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              // 排序切换
              ActionChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('时间', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 2),
                    Icon(
                      _sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14,
                    ),
                  ],
                ),
                onPressed: () =>
                    setState(() => _sortAscending = !_sortAscending),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<TodoItem> allTodos) {
    // 筛选
    var todos = allTodos.where((t) => !t.isSubmitted).toList();

    // 平台筛选
    if (_sourceFilter == TodoSourceFilter.courses) {
      todos = todos.where((t) => t.source == 'courses').toList();
    } else if (_sourceFilter == TodoSourceFilter.pintia) {
      todos = todos.where((t) => t.source == 'pintia').toList();
    }

    // 过期筛选
    if (!_showExpired) {
      todos = todos.where((t) => !t.isExpired).toList();
    }

    // 排序
    todos.sort((a, b) {
      final aDate = a.deadlineDate;
      final bDate = b.deadlineDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return _sortAscending
          ? aDate.compareTo(bDate)
          : bDate.compareTo(aDate);
    });

    if (todos.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: '没有待办事项',
        subtitle: '太棒了！当前筛选条件下无可显示任务',
      );
    }

    final expiredCount = allTodos.where((t) => t.isExpired && !t.isSubmitted).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 统计条
        if (expiredCount > 0 && !_showExpired)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _showExpired = true),
              child: Text(
                '隐藏了 $expiredCount 个已过期任务 — 点击显示',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        // 任务卡片
        ...todos.map((todo) => _TodoCard(todo: todo)),
      ],
    );
  }
}

class _TodoCard extends StatelessWidget {
  final TodoItem todo;
  const _TodoCard({required this.todo});

  @override
  Widget build(BuildContext context) {
    final priorityColors = [
      Colors.grey,
      Colors.blue,
      AppTheme.warningOrange,
      AppTheme.dangerRed,
      AppTheme.dangerRed,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: priorityColors[todo.priority.clamp(0, 4)],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(todo.title,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        todo.courseName,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: todo.source == 'pintia'
                              ? Colors.purple.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          todo.sourceLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: todo.source == 'pintia'
                                ? Colors.purple.shade700
                                : Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (todo.deadlineDate != null)
                  Text(
                    todo.statusLabel,
                    style: TextStyle(
                      color: priorityColors[todo.priority.clamp(0, 4)],
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
