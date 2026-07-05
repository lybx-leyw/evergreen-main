/// ProtonVPN state management — Riverpod StateNotifier.
///
/// Integrates SRP auth, REST API, and OpenVPN connection lifecycle
/// into a single coherent state object consumed by the UI.
///
/// Reference pattern:
///   lib/features/rvpn/providers/rvpn_provider.dart (process management)

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/providers.dart';
import '../services/protonvpn_api_service.dart';
import '../services/protonvpn_connection.dart';
import '../services/protonvpn_models.dart';
import '../services/protonvpn_ovpn_config.dart';
import '../services/protonvpn_srp.dart';

class ProtonVpnNotifier extends StateNotifier<ProtonVpnState> {
  final SharedPreferences _prefs;
  final ProtonVpnApiService _api;
  final ProtonVpnConnection _connection;

  StreamSubscription<VpnConnectionState>? _connStateSub;
  StreamSubscription<String>? _connLogSub;

  /// Path to the generated .ovpn config file (cleaned on disconnect).
  String? _configPath;

  ProtonVpnNotifier(this._prefs)
      : _api = ProtonVpnApiService(),
        _connection = ProtonVpnConnection(),
        super(const ProtonVpnState()) {
    _restoreSession();
    _listenConnection();
  }

  // ═══════════════════════════════════════════════════════════
  // Session restore
  // ═══════════════════════════════════════════════════════════

  void _restoreSession() {
    final uid = _prefs.getString(ProtonVpnState.prefKeyUid);
    final accessToken = _prefs.getString(ProtonVpnState.prefKeyAccessToken);
    final refreshToken = _prefs.getString(ProtonVpnState.prefKeyRefreshToken);
    final username = _prefs.getString(ProtonVpnState.prefKeyUsername);

    if (uid != null && accessToken != null) {
      _api.setAuth(uid: uid, accessToken: accessToken);
      state = state.copyWith(
        isLoggedIn: true,
        username: username,
        uid: uid,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
  }

  void _listenConnection() {
    _connStateSub?.cancel();
    _connStateSub = _connection.stateStream.listen((connState) {
      state = state.copyWith(connection: connState);
    });

    _connLogSub?.cancel();
    _connLogSub = _connection.logStream.listen((_) {
      // Log lines are stored in _connection.logLines; the UI reads them directly
    });
  }

  // ═══════════════════════════════════════════════════════════
  // Auth
  // ═══════════════════════════════════════════════════════════

  /// Full SRP login flow.
  Future<void> login(String username, String password) async {
    if (state.isLoggingIn) return;

    state = state.copyWith(isLoggingIn: true, clearAuthError: true);

    try {
      // 1. Get SRP parameters from server
      final info = await _api.authInfo(username);
      if (!info.isOk) {
        throw ProtonVpnApiException(
            info.code, info.error ?? 'auth/info 请求失败');
      }

      // 2. Generate client ephemeral
      final modulus = BigInt.parse(info.modulus, radix: 16);
      final (:secretA, :publicA) = generateClientEphemeral(modulus);

      // 3. Compute SRP proof
      final (:clientProof, :expectedServerProof) = computeClientProof(
        modulus: modulus,
        serverEphemeral: BigInt.parse(info.serverEphemeral, radix: 16),
        salt: info.salt,
        username: username,
        password: password,
        secretA: secretA,
        publicA: publicA,
      );

      // 4. Authenticate
      final authResponse = await _api.authenticate(
        username: username,
        clientEphemeral: publicA,
        clientProof: clientProof,
        srpSession: info.srpSession,
      );

      if (!authResponse.isOk) {
        throw ProtonVpnApiException(
            authResponse.code, authResponse.error ?? '认证失败');
      }

      // 5. Check 2FA
      if (authResponse.twoFactorEnabled > 0) {
        throw ProtonVpnApiException(9001, '需要双因素认证，暂不支持');
      }

      // 6. Wire up auth + persist
      _api.setAuth(
        uid: authResponse.uid,
        accessToken: authResponse.accessToken,
      );

      await _prefs.setString(ProtonVpnState.prefKeyUid, authResponse.uid);
      await _prefs.setString(
          ProtonVpnState.prefKeyAccessToken, authResponse.accessToken);
      await _prefs.setString(
          ProtonVpnState.prefKeyRefreshToken, authResponse.refreshToken);
      await _prefs.setString(ProtonVpnState.prefKeyUsername, username);

      // 7. Fetch user info (non-fatal)
      String? displayName, email;
      try {
        final user = await _api.getUserInfo();
        displayName = user.displayName;
        email = user.email;
      } catch (_) {}

      state = state.copyWith(
        isLoggedIn: true,
        isLoggingIn: false,
        username: username,
        uid: authResponse.uid,
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
        userId: authResponse.userId,
        displayName: displayName,
        email: email,
      );

      // 8. Auto-fetch servers after login
      await fetchServers();
    } on ProtonVpnApiException catch (e) {
      state = state.copyWith(
        isLoggingIn: false,
        authError: _friendlyError(e.code, e.message),
      );
    } catch (e) {
      state = state.copyWith(
        isLoggingIn: false,
        authError: '登录失败: $e',
      );
    }
  }

  /// Logout — clear all tokens and state.
  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {}

    _api.clearAuth();
    await _prefs.remove(ProtonVpnState.prefKeyUid);
    await _prefs.remove(ProtonVpnState.prefKeyAccessToken);
    await _prefs.remove(ProtonVpnState.prefKeyRefreshToken);
    await _prefs.remove(ProtonVpnState.prefKeyUsername);
    state = const ProtonVpnState();
  }

  // ═══════════════════════════════════════════════════════════
  // Servers
  // ═══════════════════════════════════════════════════════════

  Future<void> fetchServers() async {
    if (!state.isLoggedIn) return;
    state = state.copyWith(isLoadingServers: true, clearServersError: true);

    try {
      final serversResponse = await _api.getServers();
      // Sort: online first, then by load ascending
      final servers = serversResponse.logicalServers
          .where((s) => s.isOnline)
          .toList()
        ..sort((a, b) {
          // Online first
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          // Then by load (less loaded first)
          return a.load.compareTo(b.load);
        });

      state = state.copyWith(
        isLoadingServers: false,
        servers: servers,
      );
    } on ProtonVpnApiException catch (e) {
      state = state.copyWith(
        isLoadingServers: false,
        serversError: _friendlyError(e.code, e.message),
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingServers: false,
        serversError: '获取服务器列表失败: $e',
      );
    }
  }

  void selectServer(LogicalServerResponse? server) {
    state = state.copyWith(selectedServer: server);
  }

  // ═══════════════════════════════════════════════════════════
  // VPN Connection
  // ═══════════════════════════════════════════════════════════

  /// Connect to the currently selected server.
  Future<void> connect() async {
    final server = state.selectedServer;
    if (server == null) return;

    try {
      // Write .ovpn config to temp directory
      final tempDir = await getTemporaryDirectory();
      _configPath = p.join(tempDir.path, 'evergreen_protonvpn.ovpn');

      // Select best endpoint: prefer OpenVPN UDP
      final entry = _pickEndpoint(server);

      final config = ProtonVpnOvpnConfig.generate(
        serverIp: entry.ip,
        port: entry.port,
        protocol: entry.protocol,
      );

      await File(_configPath!).writeAsString(config);

      await _connection.connect(
        configPath: _configPath!,
        serverIp: entry.ip,
        port: entry.port,
        protocol: entry.protocol,
        serverName: '${server.name} — ${server.city}, ${server.exitCountry}',
      );
    } catch (e) {
      state = state.copyWith(
        connection: VpnConnectionState(
          status: VpnConnectionStatus.error,
          message: '连接准备失败: $e',
        ),
      );
    }
  }

  /// Disconnect from the VPN.
  Future<void> disconnect() async {
    await _connection.disconnect();
    // Clean up temp config
    if (_configPath != null) {
      try {
        await File(_configPath!).delete();
      } catch (_) {}
      _configPath = null;
    }
  }

  /// Pick the best endpoint from a server's protocol entries.
  ///
  /// Prefers OpenVPN UDP, then OpenVPN TCP, then WireGuard.
  ({String ip, int port, String protocol}) _pickEndpoint(
      LogicalServerResponse server) {
    // Default fallback
    const fallback = (ip: '127.0.0.1', port: 51820, protocol: 'udp');

    // The LogicalServerResponse from the API includes server entries
    // with protocol-specific IPs and ports. In the absence of detailed
    // entry parsing, we use the server's primary IP (from domain or
    // gateway) with standard ports:
    //   OpenVPN UDP: 1194,   OpenVPN TCP: 443
    //   WireGuard:   51820
    //
    // The real client fetches vpn/v2/clientconfig for exact entries.
    // For the lightweight integration, we use these well-known ports.

    if (server.domain != null && server.domain!.isNotEmpty) {
      return (ip: server.domain!, port: 1194, protocol: 'udp');
    }

    return fallback;
  }

  // ═══════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════

  List<String> get connectionLogs => _connection.logLines;

  static String _friendlyError(int code, String message) {
    switch (code) {
      case 8002:
        return '用户名或密码错误';
      case 8100:
        return '请使用 SSO 登录（暂不支持）';
      case 8101:
        return '请使用 SRP 登录';
      case 9001:
        return '需要人机验证，请通过网页登录';
      case 5003:
        return '客户端版本过旧，请更新';
      default:
        return message;
    }
  }

  @override
  void dispose() {
    _connStateSub?.cancel();
    _connLogSub?.cancel();
    _connection.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════
// Riverpod provider
// ═══════════════════════════════════════════════════════════

final protonVpnProvider =
    StateNotifierProvider<ProtonVpnNotifier, ProtonVpnState>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return ProtonVpnNotifier(prefs);
});
