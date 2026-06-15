import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/rvpn_provider.dart';
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
                  '请从原项目的 vendor/zju-connect/ 目录编译 Go 二进制文件，\n'
                  '或从 https://github.com/Mythologyli/zju-connect/releases 下载。\n\n'
                  '编译方法:\n'
                  '  cd vendor/zju-connect && node build.js\n\n'
                  '启动后可通过 127.0.0.1:1080 访问校内资源。',
              onRetry: () => ref.read(rvpnProvider.notifier).state =
                  const RvpnState(isChecking: true),
            )
          else
            _buildStatusPanel(context, state, ref),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(BuildContext context, RvpnState state, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 运行状态徽标（绿/灰/红）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: state.isRunning
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: state.isRunning ? Colors.green.shade300 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
              child: Text(
                state.isRunning ? '● 运行中' : '○ 已停止',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: state.isRunning ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Icon(
              state.isRunning ? Icons.vpn_lock : Icons.vpn_lock_outlined,
              size: 64,
              color: state.isRunning ? AppTheme.successGreen : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(state.statusMessage,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: () {
                ref.read(rvpnProvider.notifier).state =
                    state.copyWith(
                  isRunning: !state.isRunning,
                  statusMessage:
                      state.isRunning ? '代理已停止' : '代理运行中 — 127.0.0.1:1080',
                );
              },
              icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(state.isRunning ? '停止代理' : '启动代理'),
              style: FilledButton.styleFrom(
                backgroundColor: state.isRunning
                    ? AppTheme.dangerRed
                    : AppTheme.zjuBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
