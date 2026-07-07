import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ecard_provider.dart';
import '../../../widgets/loading_indicator.dart';

class EcardScreen extends ConsumerWidget {
  const EcardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(ecardBalanceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('一卡通')),
      body: balanceAsync.when(
        loading: () => const LoadingWidget(message: '查询校园卡余额...'),
        error: (e, _) => Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.credit_card_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('无法获取校园卡信息'),
                  const SizedBox(height: 8),
                  const Text(
                    '一卡通官方未提供公开 API，请通过 ecard.zju.edu.cn 网页手动查询。\n\n已知限制：以下端点均为推测，实际成功率低。\n如有可用 API 端点，请提交至项目仓库。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(ecardBalanceProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.credit_card_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('无法连接校园卡 API'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(ecardBalanceProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final balance = data['balance'] ?? data['card_balance'] ?? data['amount'] ?? data['total'] ?? '未知';
          final cardNo = data['card_no'] ?? data['card_number'] ?? data['cardId'] ?? '-';
          final name = data['name'] ?? data['cardholder'] ?? '-';

          return Column(
            children: [
              const SizedBox(height: 40),
              Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Text(balance.toString(), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('账户余额 (元)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(children: [Text(cardNo.toString()), const Text('卡号', style: TextStyle(color: Colors.grey))]),
                          Column(children: [Text(name.toString()), const Text('姓名', style: TextStyle(color: Colors.grey))]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
