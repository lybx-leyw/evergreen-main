/// ProtonVPN screen — login form, server browser, VPN connection panel.
///
/// Three panels:
///   1. Login card (not logged in)
///   2. Server list + user info (logged in, not connected)
///   3. Connection status panel (connected / connecting / error)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/protonvpn_provider.dart';
import '../services/protonvpn_models.dart';
import '../../../core/config/theme.dart';

class ProtonVpnScreen extends ConsumerStatefulWidget {
  const ProtonVpnScreen({super.key});

  @override
  ConsumerState<ProtonVpnScreen> createState() => _ProtonVpnScreenState();
}

class _ProtonVpnScreenState extends ConsumerState<ProtonVpnScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(protonVpnProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ProtonVPN'),
        actions: [
          if (state.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '登出',
              onPressed: () => ref.read(protonVpnProvider.notifier).logout(),
            ),
        ],
      ),
      body: state.isLoggedIn ? _buildLoggedIn(state, theme) : _buildLogin(state, theme),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Login panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildLogin(ProtonVpnState state, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 40),
        // Logo area
        Icon(Icons.shield, size: 72, color: AppTheme.zjuBlue),
        const SizedBox(height: 12),
        Text(
          'ProtonVPN',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '登录以浏览服务器并连接 VPN',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),

        // Error
        if (state.authError != null) ...[
          _errorBanner(state.authError!),
          const SizedBox(height: 12),
        ],

        // Login card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Proton 用户名',
                    hintText: 'your-username',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) => _doLogin(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: state.isLoggingIn ? null : _doLogin,
                  icon: state.isLoggingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login),
                  label: Text(state.isLoggingIn ? '登录中...' : '登录'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.zjuBlue,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Registration link
        Text(
          '还没有账号？请在 protonvpn.com 注册',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Logged-in panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildLoggedIn(ProtonVpnState state, ThemeData theme) {
    final conn = state.connection;
    final isConnected = conn.status == VpnConnectionStatus.connected;
    final isConnecting = conn.status == VpnConnectionStatus.connecting;

    return Column(
      children: [
        // ── Connection status bar ──
        _buildConnectionBar(state, theme),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── User info ──
              _buildUserCard(state, theme),
              const SizedBox(height: 12),

              // ── Selected server + connect ──
              _buildConnectCard(state, theme),
              const SizedBox(height: 12),

              // ── Server list ──
              _buildServerList(state, theme),
            ],
          ),
        ),

        // ── Log panel (collapsed at bottom) ──
        if (isConnecting || isConnected) _buildLogDrawer(state, theme),
      ],
    );
  }

  // ── Connection status bar ──

  Widget _buildConnectionBar(ProtonVpnState state, ThemeData theme) {
    final conn = state.connection;
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (conn.status) {
      case VpnConnectionStatus.connected:
        bg = AppTheme.successGreen;
        fg = Colors.white;
        icon = Icons.check_circle;
        label = conn.serverName ?? '已连接';
      case VpnConnectionStatus.connecting:
        bg = AppTheme.warningOrange;
        fg = Colors.white;
        icon = Icons.sync;
        label = '连接中...';
      case VpnConnectionStatus.disconnecting:
        bg = Colors.grey.shade600;
        fg = Colors.white;
        icon = Icons.sync_disabled;
        label = '断开中...';
      case VpnConnectionStatus.error:
        bg = AppTheme.dangerRed;
        fg = Colors.white;
        icon = Icons.error;
        label = conn.message ?? '错误';
      case VpnConnectionStatus.disconnected:
        bg = Colors.transparent;
        fg = Colors.transparent;
        icon = Icons.circle;
        label = '';
    }

    if (conn.status == VpnConnectionStatus.disconnected) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bg,
      child: Row(
        children: [
          conn.status == VpnConnectionStatus.connecting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── User info card ──

  Widget _buildUserCard(ProtonVpnState state, ThemeData theme) {
    final name = state.displayName ?? state.username ?? '用户';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.zjuBlue.withAlpha(30),
              child: const Icon(Icons.person, color: AppTheme.zjuBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  if (state.email != null)
                    Text(state.email!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.read(protonVpnProvider.notifier).fetchServers(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新服务器'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Connect card ──

  Widget _buildConnectCard(ProtonVpnState state, ThemeData theme) {
    final server = state.selectedServer;
    final conn = state.connection;
    final isConnected = conn.status == VpnConnectionStatus.connected;
    final isConnecting = conn.status == VpnConnectionStatus.connecting;
    final isBusy = isConnected || isConnecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, size: 18, color: AppTheme.zjuBlue),
                const SizedBox(width: 8),
                Text('连接', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),

            if (server != null) ...[
              _serverTile(server, theme, trailing: null),
              const SizedBox(height: 12),
            ] else ...[
              Text('请从下方列表选择一个服务器',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade500)),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (server != null && !isBusy)
                        ? () => ref.read(protonVpnProvider.notifier).connect()
                        : null,
                    icon: isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: Text(isConnected ? '已连接' : isConnecting ? '连接中...' : '连接'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.successGreen,
                      minimumSize: const Size(120, 40),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isBusy
                      ? () => ref.read(protonVpnProvider.notifier).disconnect()
                      : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('断开'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dangerRed,
                    minimumSize: const Size(100, 40),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Server list ──

  Widget _buildServerList(ProtonVpnState state, ThemeData theme) {
    if (state.isLoadingServers) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (state.serversError != null) {
      return _errorBanner(state.serversError!);
    }

    if (state.servers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.dns_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('暂无可用服务器',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey.shade500)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.dns, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '服务器 (${state.servers.length})',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.servers.length,
            itemBuilder: (context, index) {
              final server = state.servers[index];
              final isSelected =
                  state.selectedServer?.id == server.id;
              return _serverTile(
                server,
                theme,
                selected: isSelected,
                trailing: null,
                onTap: () =>
                    ref.read(protonVpnProvider.notifier).selectServer(server),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Server tile ──

  Widget _serverTile(
    LogicalServerResponse server,
    ThemeData theme, {
    bool selected = false,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: selected ? AppTheme.zjuBlue.withAlpha(15) : null,
        child: Row(
          children: [
            // Country indicator
            Container(
              width: 36,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                server.exitCountry,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            // Name + city
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${server.city}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 8),
                      _tierChip(server.tier),
                      const SizedBox(width: 6),
                      // Load bar
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: server.load / 100.0,
                            minHeight: 4,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              server.load < 50
                                  ? AppTheme.successGreen
                                  : server.load < 80
                                      ? AppTheme.warningOrange
                                      : AppTheme.dangerRed,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${server.load}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: server.load < 50
                    ? AppTheme.successGreen
                    : server.load < 80
                        ? AppTheme.warningOrange
                        : AppTheme.dangerRed,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _tierChip(int tier) {
    final String label;
    final Color fg, bg;
    switch (tier) {
      case 2:
        label = 'Plus';
        fg = AppTheme.zjuBlue;
        bg = AppTheme.zjuBlue.withAlpha(25);
      case 3:
        label = 'Visionary';
        fg = AppTheme.accentPurple;
        bg = AppTheme.accentPurple.withAlpha(25);
      default:
        label = 'Free';
        fg = Colors.grey.shade600;
        bg = Colors.grey.shade200;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
    );
  }

  // ── Log drawer ──

  Widget _buildLogDrawer(ProtonVpnState state, ThemeData theme) {
    final logs = ref.read(protonVpnProvider.notifier).connectionLogs;
    return Container(
      height: 150,
      color: theme.brightness == Brightness.light
          ? Colors.grey.shade900
          : const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: Colors.greenAccent),
                const SizedBox(width: 6),
                Text('运行日志',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final line = logs[index];
                final color = line.contains('[stderr]') ||
                        line.contains('error') ||
                        line.contains('Error')
                    ? Colors.redAccent
                    : line.contains('warn') || line.contains('WARN')
                        ? Colors.orangeAccent
                        : Colors.green.shade300;
                return Text(line,
                    style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.4,
                        color: color));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Error banner ──

  Widget _errorBanner(String message) {
    return Card(
      color: AppTheme.dangerRed.withAlpha(15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.dangerRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppTheme.dangerRed, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  void _doLogin() {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (username.isEmpty || password.isEmpty) return;
    ref.read(protonVpnProvider.notifier).login(username, password);
  }
}
