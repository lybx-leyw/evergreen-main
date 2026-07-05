/// Palace 全局标签云 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'palace_event_store_provider.dart';

/// 从所有事件中聚合的标签云。
final palaceTagsProvider = Provider<List<String>>((ref) {
  final store = ref.watch(palaceEventStoreProvider);
  return store.allTags();
});
