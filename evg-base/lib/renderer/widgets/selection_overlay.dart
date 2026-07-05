/// 多选覆盖层——根据选择模式提供选择态 UI。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 选中项集合提供者。
final selectedItemsProvider =
    StateProvider<Set<String>>((ref) => {});

/// 选择模式提供者。
final selectionModeProvider =
    StateProvider<String>((ref) => 'none');

/// 项选择 Widget——包裹在列表/表格项外，提供选择 UI。
///
/// 当 [ActionDescriptor.selection] 为 "single" 或 "multi" 时显示选择控件。
class SelectionOverlay extends ConsumerWidget {
  final Widget child;
  final String itemId;
  final ActionDescriptor? actions;

  const SelectionOverlay({
    super.key,
    required this.child,
    required this.itemId,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = actions?.selection ?? 'none';
    if (selection == 'none') return child;

    final selected = ref.watch(selectedItemsProvider);
    final isSelected = selected.contains(itemId);

    return InkWell(
      onTap: () {
        ref.read(selectedItemsProvider.notifier).update((state) {
          final next = <String>{};
          if (selection == 'single') {
            if (isSelected) {
              // 取消选择
            } else {
              next.add(itemId);
            }
          } else if (selection == 'multi') {
            next.addAll(state);
            if (isSelected) {
              next.remove(itemId);
            } else {
              next.add(itemId);
            }
          }
          return next;
        });
      },
      child: Row(
        children: [
          if (selection == 'multi')
            Checkbox(
              value: isSelected,
              onChanged: (_) {
                ref.read(selectedItemsProvider.notifier).update((state) {
                  final next = <String>{...state};
                  if (isSelected) {
                    next.remove(itemId);
                  } else {
                    next.add(itemId);
                  }
                  return next;
                });
              },
            ),
          if (selection == 'single')
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) {
                ref
                    .read(selectedItemsProvider.notifier)
                    .update((_) => {itemId});
              },
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 获取当前选中项数量。
class SelectionCount extends ConsumerWidget {
  const SelectionCount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedItemsProvider);
    if (selected.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '已选 ${selected.length} 项',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
