/// Palace EventStore 单例 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/palace/storage/event_store.dart';
import '../../../core/palace/storage/palace_paths.dart';

/// EventStore 全局单例——启动时初始化，整个 App 生命周期内复用。
final palaceEventStoreProvider = Provider<EventStore>((ref) {
  ensurePalaceDirs();
  return EventStore(palaceEventsDir);
});
