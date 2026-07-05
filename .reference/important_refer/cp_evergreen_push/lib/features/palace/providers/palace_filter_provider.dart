/// Palace 过滤条件 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/palace/models/consciousness_event.dart' show EventType;

/// 当前过滤条件。
class PalaceFilter {
  /// 按类型过滤（null=全部类型）。
  final EventType? type;

  /// 按标签过滤（null=不限标签）。
  final String? tag;

  /// 按日期范围过滤。
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// 搜索关键词。
  final String searchQuery;

  const PalaceFilter({
    this.type,
    this.tag,
    this.dateFrom,
    this.dateTo,
    this.searchQuery = '',
  });

  /// 是否有任何活跃过滤条件。
  bool get isActive =>
      type != null ||
      tag != null ||
      dateFrom != null ||
      dateTo != null ||
      searchQuery.isNotEmpty;

  PalaceFilter copyWith({
    EventType? type,
    String? tag,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? searchQuery,
    bool clearType = false,
    bool clearTag = false,
    bool clearDateRange = false,
    bool clearSearch = false,
  }) {
    return PalaceFilter(
      type: clearType ? null : (type ?? this.type),
      tag: clearTag ? null : (tag ?? this.tag),
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      searchQuery: clearSearch
          ? ''
          : (searchQuery ?? this.searchQuery),
    );
  }
}

class PalaceFilterNotifier extends StateNotifier<PalaceFilter> {
  PalaceFilterNotifier() : super(const PalaceFilter());

  void setType(EventType? type) =>
      state = state.copyWith(type: type, clearType: type == null);
  void setTag(String? tag) =>
      state = state.copyWith(tag: tag, clearTag: tag == null);
  void setDateRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(dateFrom: from, dateTo: to);
  void setSearch(String query) =>
      state = state.copyWith(searchQuery: query);
  void clearAll() =>
      state = const PalaceFilter();
  void clearType() =>
      state = state.copyWith(clearType: true);
  void clearTag() =>
      state = state.copyWith(clearTag: true);
}

final palaceFilterProvider =
    StateNotifierProvider<PalaceFilterNotifier, PalaceFilter>((ref) {
  return PalaceFilterNotifier();
});
