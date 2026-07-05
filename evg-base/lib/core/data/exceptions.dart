/// 数据层异常。
///
/// | 类 | 说明 |
/// |----|------|
/// | `DataTypeNotRegisteredException` | 请求了未注册的数据类型 |
/// | `DataFetchException` | 数据拉取失败，携带原始 [cause] |

/// 请求了未注册的数据类型。
class DataTypeNotRegisteredException implements Exception {
  final String typeName;
  const DataTypeNotRegisteredException(this.typeName);

  @override
  String toString() => 'DataTypeNotRegisteredException: 数据类型 "$typeName" 未注册。';
}

/// 数据拉取失败。
class DataFetchException implements Exception {
  final String typeName;
  final Object cause;
  const DataFetchException(this.typeName, this.cause);

  @override
  String toString() => 'DataFetchException: 拉取 "$typeName" 失败 → $cause';
}
