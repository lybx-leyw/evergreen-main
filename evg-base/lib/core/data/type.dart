/// 数据类型描述符——每种数据的唯一标识。
///
/// | 属性 | 说明 |
/// |------|------|
/// | `name` | 唯一标识 |
/// | `category` | 分类标签 |
/// | `displayName` | UI 展示名，默认同 name |
/// | `ttl` | 缓存有效期，默认 5 分钟 |
/// | `persistentKey` | 持久化键，不设则不缓存 |
/// | `label` | displayName ?? name |

class DataType<T> {
  final String name;
  final String category;
  final String? displayName;
  final Duration ttl;
  final String? persistentKey;

  const DataType({
    required this.name,
    this.category = '未分类',
    this.displayName,
    this.ttl = const Duration(minutes: 5),
    this.persistentKey,
  });

  String get label => displayName ?? name;

  @override
  bool operator ==(Object other) =>
      other is DataType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'DataType<$T>($name)';
}
