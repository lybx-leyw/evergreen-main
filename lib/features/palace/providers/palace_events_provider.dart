/// Palace 事件列表 Provider —— 响应 EventStore 和过滤器变化。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/palace/models/consciousness_event.dart';
import '../../../core/palace/storage/event_store.dart' show EventStore;
import 'palace_event_store_provider.dart';
import 'palace_filter_provider.dart';

/// 事件列表状态。
class PalaceEventsState {
  final List<ConsciousnessEvent> events;
  final bool isLoading;

  const PalaceEventsState({this.events = const [], this.isLoading = false});

  PalaceEventsState copyWith({
    List<ConsciousnessEvent>? events,
    bool? isLoading,
  }) {
    return PalaceEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PalaceEventsNotifier extends StateNotifier<PalaceEventsState> {
  final EventStore _store;
  final Ref _ref;

  PalaceEventsNotifier(this._store, this._ref)
      : super(const PalaceEventsState()) {
    refresh();
  }

  /// 从 EventStore 加载事件，应用当前过滤条件。
  void refresh() {
    state = state.copyWith(isLoading: true);

    try {
      final filter = _ref.read(palaceFilterProvider);
      List<ConsciousnessEvent> events;

      if (filter.searchQuery.isNotEmpty) {
        // 搜索模式
        final ids = _store.search(filter.searchQuery);
        events = ids.map((id) => _store.get(id)).whereType<ConsciousnessEvent>().toList();
      } else {
        // 过滤模式
        final Set<String> idSet = {};

        if (filter.type != null) {
          idSet.addAll(_store.listByType(filter.type!));
        }
        if (filter.tag != null) {
          final tagIds = _store.listByTag(filter.tag!);
          if (idSet.isEmpty) {
            idSet.addAll(tagIds);
          } else {
            idSet.removeWhere((id) => !tagIds.contains(id));
          }
        }
        if (filter.dateFrom != null || filter.dateTo != null) {
          final from = filter.dateFrom ?? DateTime(2000);
          final to = filter.dateTo ?? DateTime(2100);
          final dateIds = _store.listByDateRange(from, to);
          if (idSet.isEmpty) {
            idSet.addAll(dateIds);
          } else {
            idSet.removeWhere((id) => !dateIds.contains(id));
          }
        }

        if (idSet.isEmpty && !filter.isActive) {
          // 无过滤 → 全部
          events = _store.all();
        } else {
          events = idSet.map((id) => _store.get(id)).whereType<ConsciousnessEvent>().toList()
            ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
        }
      }

      state = PalaceEventsState(events: events, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final palaceEventsProvider =
    StateNotifierProvider<PalaceEventsNotifier, PalaceEventsState>((ref) {
  final store = ref.watch(palaceEventStoreProvider);
  return PalaceEventsNotifier(store, ref);
});
