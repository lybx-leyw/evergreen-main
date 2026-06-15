/// 安全解析工具——JSON → Dart 类型，永不抛异常。
///
/// 所有 `tryParse` 失败返回默认值，null 返回默认值。
/// 消除模型中重复的 `double.tryParse(x?.toString() ?? '') ?? 0` 模式。
///
/// 用法：
/// ```dart
/// final name = SafeParse.string(json['kcmc'], default: '未命名');
/// final credits = SafeParse.double_(json['xf']);
/// final hours = SafeParse.int_(json['zxss']);
/// ```
class SafeParse {
  SafeParse._();

  /// 解析 String——null、非字符串均不抛异常，返回 [defaultValue]。
  static String string(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  /// 解析 double——null、非数字均不抛异常，返回 [defaultValue]。
  static double double_(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }

  /// 解析 int——null、非整数均不抛异常，返回 [defaultValue]。
  static int int_(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  /// 解析 bool——null、非布尔均不抛异常，返回 [defaultValue]。
  ///
  /// 支持: `true`/`false`、`"true"`/`"false"`、`1`/`0`、`"1"`/`"0"`。
  static bool bool_(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  /// 解析 DateTime（ISO 8601）——null、失败均返回 null。
  static DateTime? dateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
