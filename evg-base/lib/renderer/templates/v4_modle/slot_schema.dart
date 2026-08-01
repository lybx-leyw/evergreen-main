/// 组件配置 Schema — manifest 配置的类型安全校验层。
///
/// 每个组件声明 config schema，manifest 加载时校验字段类型、必填性和默认值。
/// 把运行时"静默空态"变成加载期可定位的 `[SlotSchema]` 警告/错误。
///
/// # 使用
/// ```dart
/// class ChartSlotSchema extends SlotSchema {
///   String get slotType => 'chart';
///   final title = string('title', defaultValue: '');
///   final chartType = stringEnum('type', values: ['bar', 'line', 'pie'], defaultValue: 'bar');
///   @override List<SchemaField> get fields => [title, chartType];
/// }
/// ```
library;

import 'package:evergreen_base/core/log.dart';

// ═══════ SchemaField 字段族 ═══════

/// 带类型、默认值、校验的配置字段。
abstract class SchemaField<T> {
  final String key;
  final T? defaultValue;
  final String? description;
  final bool required;

  const SchemaField(this.key, {this.defaultValue, this.description, this.required = false});

  /// 从原始 Map 中解析。失败时：
  /// - 有默认值 → 返回默认值 + warn
  /// - required 且无默认值 → 抛 [SlotSchemaException]
  T resolve(Map<String, dynamic> raw, String slotType);
}

class StringField extends SchemaField<String> {
  final List<String>? allowedValues;
  const StringField(super.key, {super.defaultValue, super.description, super.required, this.allowedValues});

  @override
  String resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? '';
    }
    if (v is! String) {
      if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 String，收到 ${v.runtimeType}，使用默认值'); return defaultValue!; }
      if (required) throw _typeError(slotType, 'String', v);
      return v.toString();
    }
    if (allowedValues != null && !allowedValues!.contains(v)) {
      if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: "$v" 不在允许值 $allowedValues 中'); return defaultValue!; }
    }
    return v;
  }
}

class BoolField extends SchemaField<bool> {
  const BoolField(super.key, {super.defaultValue, super.description, super.required});

  @override
  bool resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? false;
    }
    if (v is bool) return v;
    if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 bool，使用默认值'); return defaultValue!; }
    throw _typeError(slotType, 'bool', v);
  }
}

class IntField extends SchemaField<int> {
  final int? min;
  final int? max;
  const IntField(super.key, {super.defaultValue, super.description, super.required, this.min, this.max});

  @override
  int resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? 0;
    }
    if (v is int) return _clamp(v);
    if (v is num) return _clamp(v.toInt());
    if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 int，使用默认值'); return defaultValue!; }
    throw _typeError(slotType, 'int', v);
  }
  int _clamp(int v) {
    if (min != null && v < min!) return min!;
    if (max != null && v > max!) return max!;
    return v;
  }
}

class DoubleField extends SchemaField<double> {
  const DoubleField(super.key, {super.defaultValue, super.description, super.required});

  @override
  double resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? 0.0;
    }
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 double，使用默认值'); return defaultValue!; }
    throw _typeError(slotType, 'double', v);
  }
}

class ListField<E> extends SchemaField<List<E>> {
  final E Function(dynamic)? itemParser;
  const ListField(super.key, {super.defaultValue, super.description, super.required, this.itemParser});

  @override
  List<E> resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? [];
    }
    if (v is! List) {
      if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 List，使用默认值'); return defaultValue!; }
      throw _typeError(slotType, 'List', v);
    }
    if (itemParser != null) {
      return v.map((e) => itemParser!(e)).toList();
    }
    return v.cast<E>();
  }
}

class MapField extends SchemaField<Map<String, dynamic>> {
  const MapField(super.key, {super.defaultValue, super.description, super.required});

  @override
  Map<String, dynamic> resolve(Map<String, dynamic> raw, String slotType) {
    final v = raw[key];
    if (v == null) {
      if (required && defaultValue == null) throw _missing(slotType);
      return defaultValue ?? {};
    }
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    if (defaultValue != null) { Log().warn('[SlotSchema] $slotType.$key: 期望 Map，使用默认值'); return defaultValue!; }
    throw _typeError(slotType, 'Map', v);
  }
}

// ═══════ 异常 ═══════

class SlotSchemaException implements Exception {
  final String slotType;
  final String fieldKey;
  final String message;
  final dynamic receivedValue;

  SlotSchemaException(this.slotType, this.fieldKey, this.message, {this.receivedValue});

  @override String toString() => '[SlotSchema] $slotType.$fieldKey: $message (收到: $receivedValue)';
}

SlotSchemaException _missing(String slotType, [String? key]) => SlotSchemaException(slotType, key ?? '', '必填字段缺失');
SlotSchemaException _typeError(String slotType, String expected, dynamic received) =>
    SlotSchemaException(slotType, '', '期望 $expected，收到 ${received.runtimeType}', receivedValue: received);

// ═══════ SlotSchema 抽象基类 ═══════

abstract class SlotSchema {
  String get slotType;
  List<SchemaField> get fields;

  const SlotSchema();

  static final _registry = <String, SlotSchema Function()>{};

  /// 注册 schema 工厂。
  static void register(String type, SlotSchema Function() factory) {
    _registry[type] = factory;
  }

  /// 从原始 Map 创建并校验。
  factory SlotSchema.from(String slotType, Map<String, dynamic> raw) {
    final factory = _registry[slotType];
    if (factory == null) {
      Log().warn('[SlotSchema] 未注册: $slotType（透传原始 Map）');
      return _UnknownSchema(slotType);
    }
    final schema = factory();
    for (final field in schema.fields) {
      try {
        field.resolve(raw, slotType);
      } on SlotSchemaException catch (e) {
        if (field.required && field.defaultValue == null) rethrow;
        Log().warn(e.toString());
      }
    }
    return schema;
  }
}

class _UnknownSchema extends SlotSchema {
  @override final String slotType;
  const _UnknownSchema(this.slotType);
  @override List<SchemaField> get fields => const [];
}
