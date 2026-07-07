import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/rvpn_provider.dart';
import '../../../core/config/app_config.dart' show AppConfig;
import '../../../core/config/theme.dart';
import '../../../widgets/error_card.dart';

/// RVPN proxy management screen.
class RvpnScreen extends ConsumerWidget {
  const RvpnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rvpnProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RVPN 代理'),
        actions: [
          // 实验性功能角标
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade300, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.science, size: 14, color: Colors.orange.shade800),
                const SizedBox(width: 4),
                Text('实验性',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 温馨提示
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '此功能未经充分测试，仅供预览。'
                      '使用中如遇到问题请提交 Issue。',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (state.isChecking)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 60),
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在检查 zju-connect...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else if (!state.hasBinary)
            ErrorCard(
              message: '未找到 zju-connect',
              detail: 'zju-connect 是 Go 语言编写的 ZJU 校园网 SOCKS5 代理。\n'
                  '请从 https://github.com/Mythologyli/zju-connect/releases 下载。\n\n'
                  '启动后可通过 127.0.0.1:1080 访问校内资源。',
              onRetry: () => ref.read(rvpnProvider.notifier).checkBinary(),
            )
          else ...[
            // ── 状态面板 ──
            _buildStatusPanel(context, state, ref),
            const SizedBox(height: 12),
            // ── 凭证配置 ──
            _buildCredentialSection(context, state, ref),
            const SizedBox(height: 12),
            // ── 日志面板 ──
            _buildLogPanel(context, state, ref),
          ],
        ],
      ),
    );
  }

  // ── 状态面板 ────────────────────────────────────────────

  Widget _buildStatusPanel(BuildContext context, RvpnState state, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 运行状态徽标
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statusBadge(state),
                const SizedBox(width: 12),
                if (state.isRunning && state.healthChecking)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (state.isRunning)
                  Icon(
                    state.healthOk ? Icons.check_circle : Icons.warning_amber_rounded,
                    size: 16,
                    color: state.healthOk ? Colors.green.shade600 : Colors.orange.shade600,
                  ),
              ],
            ),
            const SizedBox(height: 20),

            Icon(
              state.isRunning ? Icons.vpn_lock : Icons.vpn_lock_outlined,
              size: 56,
              color: state.isRunning ? AppTheme.successGreen : Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(state.statusMessage,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: () {
                final notifier = ref.read(rvpnProvider.notifier);
                if (state.isRunning) {
                  notifier.stop();
                } else {
                  notifier.start();
                }
              },
              icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(state.isRunning ? '停止代理' : '启动代理'),
              style: FilledButton.styleFrom(
                backgroundColor: state.isRunning
                    ? AppTheme.dangerRed
                    : AppTheme.zjuBlue,
                minimumSize: const Size(180, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(RvpnState state) {
    Color bgColor;
    Color borderColor;
    Color textColor;
    String label;

    if (state.isRunning && state.healthOk) {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      textColor = Colors.green.shade700;
      label = '● 运行中';
    } else if (state.isRunning) {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      textColor = Colors.orange.shade700;
      label = '⚠ 异常';
    } else {
      bgColor = Colors.grey.shade100;
      borderColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
      label = '○ 已停止';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  // ── 凭证配置 ────────────────────────────────────────────

  Widget _buildCredentialSection(BuildContext context, RvpnState state, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.hasCredentials ? Icons.lock_open : Icons.lock_outline,
                  size: 18,
                  color: state.hasCredentials ? Colors.green.shade600 : Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Text('ZJU 凭证', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (state.hasCredentials)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('已配置',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('未配置',
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.hasCredentials) ...[
              Text('学号: ${AppConfig.zjuUsername ?? ""}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('密码: ${_maskPassword(AppConfig.zjuPassword)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            ] else ...[
              Text('请在应用设置中填写 ZJU 学号和密码，'
                  '或通过环境变量 ZJU_USERNAME / ZJU_PASSWORD 配置。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.4,
                  )),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ref.read(rvpnProvider.notifier).refreshCredentials(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新凭证'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppTheme.zjuBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _maskPassword(String? pwd) {
    if (pwd == null || pwd.isEmpty) return '(空)';
    if (pwd.length <= 4) return '*' * pwd.length;
    return '${pwd.substring(0, 2)}${'*' * (pwd.length - 4)}${pwd.substring(pwd.length - 2)}';
  }

  // ── 日志面板 ────────────────────────────────────────────

  Widget _buildLogPanel(BuildContext context, RvpnState state, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: theme.brightness == Brightness.light
                ? Colors.grey.shade50
                : Colors.grey.shade900,
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text('运行日志', style: theme.textTheme.labelMedium),
                const Spacer(),
                if (state.logLines.isNotEmpty)
                  GestureDetector(
                    onTap: () => ref.read(rvpnProvider.notifier).clearLog(),
                    child: Text('清空',
                        style: TextStyle(fontSize: 12, color: AppTheme.zjuBlue)),
                  ),
              ],
            ),
          ),
          // 日志内容
          if (state.logLines.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  state.isRunning ? '等待日志输出...' : '暂无日志',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: state.logLines.length,
                itemBuilder: (context, index) {
                  final line = state.logLines[index];
                  final isError = line.contains('[error]', 0) ||
                      line.contains('Error', 0) ||
                      line.contains('error', 0);
                  final isWarning = line.contains('warn', 0) ||
                      line.contains('WARN', 0) ||
                      line.contains('[rvpn]', 0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                        color: isError
                            ? AppTheme.dangerRed
                            : isWarning
                                ? Colors.orange.shade700
                                : Colors.grey.shade700,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
