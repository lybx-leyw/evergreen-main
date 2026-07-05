import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/registry/modules.dart';
import 'providers/auth_provider.dart';

/// 认证模块——纯服务层，无 UI 页面。
///
/// 被几乎所有 Feature 模块依赖，提供 SSO 认证 + Cookie 管理。
class AuthModule extends FeatureModule {
  @override String get id => 'auth';
  @override String get name => '认证服务';

  @override List<ProviderBase<Object?>> get exports => [
    authProvider,
  ];
}
