/// ProtonVPN data models — mirrored from the ProtonVPN C# API contracts
/// in .reference/win-app/src/Api/ProtonVPN.Api.Contracts/.
///
/// All JSON key mappings follow the ProtonVPN API naming convention
/// (PascalCase with Newtonsoft.Json PropertyName overrides where applicable).

// ═══════════════════════════════════════════════════════════
// Base response wrapper (every ProtonVPN API response)
// ═══════════════════════════════════════════════════════════

class ProtonVpnBaseResponse {
  final int code;
  final String? error;

  const ProtonVpnBaseResponse({required this.code, this.error});

  bool get isOk => code == 1000;

  factory ProtonVpnBaseResponse.fromJson(Map<String, dynamic> json) {
    return ProtonVpnBaseResponse(
      code: json['Code'] as int? ?? -1,
      error: json['Error'] as String?,
    );
  }
}

/// Thrown when the API returns a non-1000 Code.
class ProtonVpnApiException implements Exception {
  final int code;
  final String message;

  const ProtonVpnApiException(this.code, this.message);

  @override
  String toString() => 'ProtonVpnApiException($code): $message';
}

// ═══════════════════════════════════════════════════════════
// Auth — POST auth/info response
// ═══════════════════════════════════════════════════════════

class AuthInfoResponse extends ProtonVpnBaseResponse {
  final String modulus;
  final String serverEphemeral;
  final int version;
  final String salt;
  final String srpSession;
  final String? ssoChallengeToken;

  const AuthInfoResponse({
    required super.code,
    super.error,
    required this.modulus,
    required this.serverEphemeral,
    required this.version,
    required this.salt,
    required this.srpSession,
    this.ssoChallengeToken,
  });

  factory AuthInfoResponse.fromJson(Map<String, dynamic> json) {
    return AuthInfoResponse(
      code: json['Code'] as int? ?? -1,
      error: json['Error'] as String?,
      modulus: json['Modulus'] as String? ?? '',
      serverEphemeral: json['ServerEphemeral'] as String? ?? '',
      version: json['Version'] as int? ?? 4,
      salt: json['Salt'] as String? ?? '',
      srpSession: json['SRPSession'] as String? ?? '',
      ssoChallengeToken: json['SSOChallengeToken'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Auth — POST auth response
// ═══════════════════════════════════════════════════════════

class AuthResponse extends ProtonVpnBaseResponse {
  /// Session UID ("UID" in JSON → renamed to avoid Dart SDK conflict).
  final String uid;

  final String accessToken;
  final String refreshToken;
  final String? userId;
  final String? scope;
  final String? serverProof;
  final int twoFactorEnabled;

  const AuthResponse({
    required super.code,
    super.error,
    required this.uid,
    required this.accessToken,
    required this.refreshToken,
    this.userId,
    this.scope,
    this.serverProof,
    this.twoFactorEnabled = 0,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final twoFactor = json['2FA'] as Map<String, dynamic>?;
    return AuthResponse(
      code: json['Code'] as int? ?? -1,
      error: json['Error'] as String?,
      uid: json['UID'] as String? ?? '',
      accessToken: json['AccessToken'] as String? ?? '',
      refreshToken: json['RefreshToken'] as String? ?? '',
      userId: json['UserID'] as String?,
      scope: json['Scope'] as String?,
      serverProof: json['ServerProof'] as String?,
      twoFactorEnabled: (twoFactor?['Enabled'] as int?) ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// User — GET core/v4/users
// ═══════════════════════════════════════════════════════════

class UserResponse {
  final String userId;
  final String? name;
  final String? displayName;
  final String? email;
  final int createTime;

  const UserResponse({
    required this.userId,
    this.name,
    this.displayName,
    this.email,
    this.createTime = 0,
  });

  String get username {
    return (name?.isNotEmpty == true)
        ? name!
        : (email?.isNotEmpty == true)
            ? email!
            : displayName ?? userId;
  }

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    final userJson = json['User'] as Map<String, dynamic>? ?? {};
    return UserResponse(
      userId: userJson['ID'] as String? ?? '',
      name: userJson['Name'] as String?,
      displayName: userJson['DisplayName'] as String?,
      email: userJson['Email'] as String?,
      createTime: userJson['CreateTime'] as int? ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Server — GET vpn/v2/logicals (LogicalServerResponse)
// ═══════════════════════════════════════════════════════════

class LogicalServerResponse {
  final String id;
  final String name;
  final String city;
  final String? state;
  final String entryCountry;
  final String exitCountry;
  final String? domain;
  final int tier;
  final int features;
  final int status;
  final int load;
  final double score;
  final String? hostCountry;
  final String? gatewayName;

  const LogicalServerResponse({
    required this.id,
    required this.name,
    required this.city,
    this.state,
    required this.entryCountry,
    required this.exitCountry,
    this.domain,
    required this.tier,
    this.features = 0,
    this.status = 0,
    this.load = 0,
    this.score = 0,
    this.hostCountry,
    this.gatewayName,
  });

  /// 1 = online
  bool get isOnline => status == 1;

  /// 0 = free, 2 = paid
  bool get isFreeTier => tier == 0;

  String get tierLabel {
    switch (tier) {
      case 0:
        return 'Free';
      case 1:
        return 'Basic';
      case 2:
        return 'Plus';
      case 3:
        return 'Visionary';
      default:
        return 'Tier $tier';
    }
  }

  factory LogicalServerResponse.fromJson(Map<String, dynamic> json) {
    return LogicalServerResponse(
      id: json['ID'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      city: json['City'] as String? ?? '',
      state: json['State'] as String?,
      entryCountry: json['EntryCountry'] as String? ?? '',
      exitCountry: json['ExitCountry'] as String? ?? '',
      domain: json['Domain'] as String?,
      tier: json['Tier'] as int? ?? 0,
      features: json['Features'] as int? ?? 0,
      status: json['Status'] as int? ?? 0,
      load: json['Load'] as int? ?? 0,
      score: (json['Score'] as num?)?.toDouble() ?? 0.0,
      hostCountry: json['HostCountry'] as String?,
      gatewayName: json['GatewayName'] as String?,
    );
  }
}

class ServersResponse extends ProtonVpnBaseResponse {
  final List<LogicalServerResponse> logicalServers;

  const ServersResponse({
    required super.code,
    super.error,
    required this.logicalServers,
  });

  factory ServersResponse.fromJson(Map<String, dynamic> json) {
    final serversJson = json['LogicalServers'] as List<dynamic>? ?? [];
    return ServersResponse(
      code: json['Code'] as int? ?? -1,
      error: json['Error'] as String?,
      logicalServers: serversJson
          .map((s) => LogicalServerResponse.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// VPN connection state
// ═══════════════════════════════════════════════════════════

enum VpnConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class VpnConnectionState {
  final VpnConnectionStatus status;
  final String? message;
  final String? serverName;
  final String? remoteIp;
  final int? exitCode;

  const VpnConnectionState({
    this.status = VpnConnectionStatus.disconnected,
    this.message,
    this.serverName,
    this.remoteIp,
    this.exitCode,
  });

  VpnConnectionState copyWith({
    VpnConnectionStatus? status,
    String? message,
    String? serverName,
    String? remoteIp,
    int? exitCode,
  }) {
    return VpnConnectionState(
      status: status ?? this.status,
      message: message ?? this.message,
      serverName: serverName ?? this.serverName,
      remoteIp: remoteIp ?? this.remoteIp,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Combined UI state
// ═══════════════════════════════════════════════════════════

class ProtonVpnState {
  // Auth
  final bool isLoggedIn;
  final bool isLoggingIn;
  final String? username;
  final String? uid;
  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final String? displayName;
  final String? email;
  final String? authError;

  // Servers
  final bool isLoadingServers;
  final List<LogicalServerResponse> servers;
  final LogicalServerResponse? selectedServer;
  final String? serversError;

  // Connection
  final VpnConnectionState connection;

  // SharedPreferences keys used for token persistence
  static const String prefKeyUid = 'protonvpn_uid';
  static const String prefKeyAccessToken = 'protonvpn_access_token';
  static const String prefKeyRefreshToken = 'protonvpn_refresh_token';
  static const String prefKeyUsername = 'protonvpn_username';

  const ProtonVpnState({
    this.isLoggedIn = false,
    this.isLoggingIn = false,
    this.username,
    this.uid,
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.displayName,
    this.email,
    this.authError,
    this.isLoadingServers = false,
    this.servers = const [],
    this.selectedServer,
    this.serversError,
    this.connection = const VpnConnectionState(),
  });

  ProtonVpnState copyWith({
    bool? isLoggedIn,
    bool? isLoggingIn,
    String? username,
    String? uid,
    String? accessToken,
    String? refreshToken,
    String? userId,
    String? displayName,
    String? email,
    String? authError,
    bool clearAuthError = false,
    bool? isLoadingServers,
    List<LogicalServerResponse>? servers,
    Object? selectedServer, // pass null to clear, or the value to set
    String? serversError,
    bool clearServersError = false,
    VpnConnectionState? connection,
  }) {
    return ProtonVpnState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoggingIn: isLoggingIn ?? this.isLoggingIn,
      username: username ?? this.username,
      uid: uid ?? this.uid,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      authError: clearAuthError ? null : authError ?? this.authError,
      isLoadingServers: isLoadingServers ?? this.isLoadingServers,
      servers: servers ?? this.servers,
      selectedServer: selectedServer == null
          ? this.selectedServer
          : selectedServer as LogicalServerResponse?,
      serversError:
          clearServersError ? null : serversError ?? this.serversError,
      connection: connection ?? this.connection,
    );
  }
}
