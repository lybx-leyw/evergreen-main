/// 数据类型描述符——每种数据的唯一标识。
///
/// | 属性 | 说明 |
/// |------|------|
/// | `name` | 唯一标识 |
/// | `category` | 分类标签 |
/// | `displayName` | UI 展示名，默认同 name |
/// | `ttl` | 缓存有效期，默认 5 分钟 |
/// | `persistentKey` | 持久化键，不设则不缓存 |
/// | `fallback` | 静态兜底值（可选）；拉取失败且无旧缓存时由中枢返回，缺省 null 零行为变化 |
/// | `sessionProviderId` | 会话提供者标识（可选）；来自 manifest `auth.sessionProvider`，缺省 null 零行为变化 |
/// | `sessionDomain` | 数据来源网站域（可选）；来自 manifest `auth.sessionDomain`，作为登录锁分组键，缺省 null 回退 sessionProviderId 分组 |
/// | `label` | displayName ?? name |

class DataType<T> {
  final String name;
  final String category;
  final String? displayName;
  final Duration ttl;
  final String? persistentKey;

  /// 静态兜底值（可选，默认 null）。仅当拉取失败/返回空且无旧缓存时由
  /// [DataOrchestrator] 返回该值，并标记 `lastError` 含「使用静态兜底」。
  /// 未声明（null）时行为与历史完全一致（拉取失败返回 null、保留旧缓存）。
  final Object? fallback;

  /// 会话提供者标识（可选，默认 null）。来自数据源 manifest `auth.sessionProvider`；
  /// 非 null 时，[DataOrchestrator] 在拉取失败且错误被判为「会话失效」时，经
  /// [SessionCoordinator] 单点重登后重拉一次。缺省 null 零行为变化。
  final String? sessionProviderId;

  /// 数据来源网站域（可选，默认 null）。来自数据源 manifest `auth.sessionDomain`，
  /// 作为**登录锁分组键**：非 null 时，[DataOrchestrator] 按 [sessionDomain]
  /// （而非 [sessionProviderId]）分组去重重登——同一网站域拉取的数据源共享同一把
  /// 登录锁；缺省 null 时回退到按 [sessionProviderId] 分组（零行为变化）。
  final String? sessionDomain;

  const DataType({
    required this.name,
    this.category = '未分类',
    this.displayName,
    this.ttl = const Duration(minutes: 5),
    this.persistentKey,
    this.fallback,
    this.sessionProviderId,
    this.sessionDomain,
  });

  String get label => displayName ?? name;

  @override
  bool operator ==(Object other) => other is DataType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'DataType<$T>($name)';
}
