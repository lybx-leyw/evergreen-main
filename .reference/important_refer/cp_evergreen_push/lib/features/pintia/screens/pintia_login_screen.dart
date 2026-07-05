import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/dio_client.dart';
import '../../todo/providers/todo_provider.dart';
import '../services/pintia_service.dart';

/// PTA 登录管理页面。
class PintiaLoginScreen extends ConsumerWidget {
  const PintiaLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ptaStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PTA 登录')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // 状态卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: status.when(
                data: (s) => Row(
                  children: [
                    Icon(
                      s == '已连接'
                          ? Icons.check_circle
                          : s == '未配置'
                              ? Icons.settings
                              : Icons.warning_amber,
                      color: s == '已连接'
                          ? Colors.green
                          : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s == '已连接'
                                ? 'PTA 已登录'
                                : s == '未配置'
                                    ? '未配置手机号'
                                    : '需要登录',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          Text(
                            s == '已连接'
                                ? '可以获取题目集和考试信息'
                                : s == '未配置'
                                    ? '请在设置中填写 PTA 手机号'
                                    : '请输入 PTASession cookie',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                loading: () => const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
                error: (_, __) => const Text('加载失败'),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            '登录步骤',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _Step(
              number: 1,
              title: '打开 PTA 登录页',
              subtitle: '在浏览器中登录你的 PTA 账号（需通过腾讯云验证码）'),
          const SizedBox(height: 8),
          _Step(
              number: 2,
              title: '复制 PTASession',
              subtitle:
                  'F12 → Application (应用) → Cookies → pintia.cn → 复制 PTASession 的值'),
          const SizedBox(height: 8),
          _Step(number: 3, title: '粘贴到下方输入框', subtitle: '点击"保存"完成登录'),
          const SizedBox(height: 20),

          // 打开浏览器按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser),
              label: const Text('在浏览器中打开 PTA'),
              onPressed: () =>
                  launchUrl(Uri.parse('https://pintia.cn'),
                      mode: LaunchMode.externalApplication),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // 粘贴 session
          const Text('手动输入 PTASession',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          _SessionInputWidget(),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String subtitle;

  const _Step({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text('$number',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionInputWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SessionInputWidget> createState() =>
      _SessionInputWidgetState();
}

class _SessionInputWidgetState extends ConsumerState<_SessionInputWidget> {
  final _controller = TextEditingController();
  bool _saving = false;
  bool? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: '粘贴 PTASession cookie 值',
            border: const OutlineInputBorder(),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _success = null);
                    },
                  )
                : null,
          ),
          maxLines: 2,
          onChanged: (_) => setState(() => _success = null),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_saving ? '保存中...' : '保存'),
            onPressed: _saving ? null : _saveSession,
          ),
        ),
        if (_success != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _success! ? Icons.check_circle : Icons.error,
                size: 16,
                color: _success! ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                _success! ? 'Session 已保存' : 'Session 无效，请检查后重试',
                style: TextStyle(
                    fontSize: 13,
                    color: _success! ? Colors.green : Colors.red),
              ),
            ],
          ),
          if (_success == true) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/todo'),
              child: const Text('查看待办事项'),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _saveSession() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;

    setState(() {
      _saving = true;
      _success = null;
    });

    try {
      final dio = ref.read(dioClientProvider);
      final jar = ref.read(cookieJarProvider);
      final service = PintiaService(dio, jar);
      await service.setSessionCookie(value);

      // 验证是否有效
      final valid = await service.hasValidSession();
      setState(() {
        _saving = false;
        _success = valid;
      });

      if (valid) {
        ref.invalidate(ptaStatusProvider);
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _success = false;
      });
    }
  }
}
