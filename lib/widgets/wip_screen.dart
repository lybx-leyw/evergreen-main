import 'package:flutter/material.dart';

/// 开发中占位页面——供 WIP 模块的 module.dart 使用。
class WipScreen extends StatelessWidget {
  final String title;
  final String? message;
  const WipScreen({super.key, this.title = '一卡通', this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 64, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            const Text('功能开发中',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message ??
                    '该功能因后端 API 变更暂不可用，待实现后恢复。',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
