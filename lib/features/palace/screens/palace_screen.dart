/// Palace 主页面 —— 树状视图 + 过滤栏 + 捕捉入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/capture_dialog.dart';
import '../providers/palace_capture_provider.dart';
import '../providers/palace_events_provider.dart';
import '../providers/palace_filter_provider.dart';
import '../providers/palace_tags_provider.dart';
import '../widgets/event_tree_view.dart';
import '../widgets/tag_chip_bar.dart';
import '../widgets/type_filter_bar.dart';

/// Palace 主页面。
class PalaceScreen extends ConsumerStatefulWidget {
  const PalaceScreen({super.key});

  @override
  ConsumerState<PalaceScreen> createState() => _PalaceScreenState();
}

class _PalaceScreenState extends ConsumerState<PalaceScreen> {
  @override
  void initState() {
    super.initState();
    // 首次进入时加载事件
    Future.microtask(() {
      ref.read(palaceEventsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(palaceEventsProvider);
    final filter = ref.watch(palaceFilterProvider);
    final tags = ref.watch(palaceTagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('宫殿'),
        actions: [
          // 搜索
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
            tooltip: '搜索',
          ),
        ],
      ),
      body: Column(
        children: [
          // 类型过滤栏
          TypeFilterBar(
            selected: filter.type,
            onChanged: (type) {
              ref.read(palaceFilterProvider.notifier).setType(type);
              ref.read(palaceEventsProvider.notifier).refresh();
            },
          ),

          // 标签栏
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TagChipBar(
                tags: tags,
                selectedTag: filter.tag,
                onSelected: (tag) {
                  final notifier = ref.read(palaceFilterProvider.notifier);
                  if (tag == filter.tag) {
                    notifier.clearTag();
                  } else {
                    notifier.setTag(tag);
                  }
                  ref.read(palaceEventsProvider.notifier).refresh();
                },
              ),
            ),

          const Divider(height: 1),

          // 主内容区
          Expanded(
            child: eventsState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : EventTreeView(
                    events: eventsState.events,
                    filterType: filter.type,
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(palaceCaptureProvider.notifier).open();
          CaptureDialog.show(context);
        },
        tooltip: '快速捕捉',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(
          text: ref.read(palaceFilterProvider).searchQuery,
        );
        return AlertDialog(
          title: const Text('搜索'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入关键词搜索事件...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (query) {
              ref.read(palaceFilterProvider.notifier).setSearch(query);
              ref.read(palaceEventsProvider.notifier).refresh();
              Navigator.of(ctx).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(palaceFilterProvider.notifier).clearAll();
                ref.read(palaceEventsProvider.notifier).refresh();
                Navigator.of(ctx).pop();
              },
              child: const Text('清除'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(palaceFilterProvider.notifier).setSearch(controller.text);
                ref.read(palaceEventsProvider.notifier).refresh();
                Navigator.of(ctx).pop();
              },
              child: const Text('搜索'),
            ),
          ],
        );
      },
    );
  }
}
