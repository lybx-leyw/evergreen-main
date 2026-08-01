/// v5P Phase 3: 核心组件 Schema 定义注册。
library;

import 'slot_schema.dart';

void _registerSchemas() {
  SlotSchema.register('chart', () => _ChartSchema());
  SlotSchema.register('card-list', () => _CardListSchema());
  SlotSchema.register('data-table', () => _DataTableSchema());
  SlotSchema.register('stat-tile', () => _StatTileSchema());
  SlotSchema.register('tree', () => _TreeSchema());
}
bool _schemasRegistered = false;
void ensureSchemasRegistered() {
  if (!_schemasRegistered) { _schemasRegistered = true; _registerSchemas(); }
}

class _ChartSchema extends SlotSchema {
  @override String get slotType => 'chart';
  @override late final fields = [
    StringField('title', defaultValue: ''),
    StringField('type', defaultValue: 'bar', allowedValues: ['bar', 'line', 'pie']),
    BoolField('showLegend', defaultValue: true),
  ];
}

class _CardListSchema extends SlotSchema {
  @override String get slotType => 'card-list';
  @override late final fields = [
    StringField('title', defaultValue: ''),
    ListField('cards', defaultValue: []),
  ];
}

class _DataTableSchema extends SlotSchema {
  @override String get slotType => 'data-table';
  @override late final fields = [
    StringField('title', defaultValue: ''),
    ListField('columns', defaultValue: []),
    ListField('rows', defaultValue: []),
    BoolField('editable', defaultValue: false),
  ];
}

class _StatTileSchema extends SlotSchema {
  @override String get slotType => 'stat-tile';
  @override late final fields = [
    StringField('title', defaultValue: ''),
    StringField('value', defaultValue: '--'),
    StringField('subtitle', defaultValue: ''),
    StringField('trend', defaultValue: 'neutral'),
    BoolField('trendUp', defaultValue: false),
  ];
}

class _TreeSchema extends SlotSchema {
  @override String get slotType => 'tree';
  @override late final fields = [
    StringField('title', defaultValue: '树形视图'),
  ];
}
