import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/config/theme.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/ocr_pipeline.dart';
import '../../../core/services/deepseek_ocr_service.dart';
import '../../../core/utils/auto_refresh.dart';
import '../../../core/result.dart';
import '../providers/settings_provider.dart';
import '../../tutor/services/deepseek_client.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../app.dart';
import '../../../widgets/loading_indicator.dart';

/// Settings screen — all application configuration.
///
/// Ports the settings functionality from app/js/components/settings.js.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;

  /// 默认掩码的字段（密码、API Key 等敏感信息）。
  /// key = true 表示当前为掩码状态，用户可点击眼睛图标切换。
  final Map<String, bool> _obscured = {
    'ZJU_PASSWORD': true,
    'PTA_SESSION': true,
    'DEEPSEEK_API_KEY': true,
    'DEEPSEEK_OCR_API_KEY': true,
  };

  @override
  void initState() {
    super.initState();
    _controllers = {};
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(Map<String, String?> values) {
    const keys = [
      'ZJU_USERNAME', 'ZJU_PASSWORD', 'DEEPSEEK_API_KEY',
      'DEEPSEEK_MODEL', 'DEEPSEEK_THINKING', 'DEEPSEEK_OCR_API_KEY', 'PTA_SESSION',
      'DINGTALK_WEBHOOK',
      'MATERIAL_DOWNLOAD_PATH', 'VIDEO_OPENER',
      'TRANSLATE_LANG_OUT', 'TRANSLATE_LANG_IN', 'PYTHON_EXE',
      'STUDENT_GRADE', 'STUDENT_MAJOR', 'STUDENT_MINOR',
      'PERSONAL_TRAINING_PLAN_OCR', 'OTHER_TRAINING_PLAN_OCR',
      'AUTO_REFRESH_ENABLED', 'AUTO_REFRESH_INTERVAL',
    ];
    for (final key in keys) {
      _controllers.putIfAbsent(key, () => TextEditingController(text: values[key] ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          if (settingsState.isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
        ],
      ),
      body: settingsState.isLoading
          ? const LoadingWidget(message: '加载设置...')
          : _buildForm(settingsState),
    );
  }

  Widget _buildForm(SettingsState state) {
    _initControllers(state.values);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.saveError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(state.saveError!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          _sectionHeader('个人信息'),
          _buildField('STUDENT_GRADE', '年级', Icons.people),
          _buildField('STUDENT_MAJOR', '主修', Icons.school),
          _buildField('STUDENT_MINOR', '其他（选填，如微辅修）', Icons.auto_awesome),
          const Divider(),
          _sectionHeader('培养方案（选填）'),
          _buildTrainingPlanField('PERSONAL_TRAINING_PLAN_OCR', '个人主修培养方案', Icons.description),
          _buildTrainingPlanField('OTHER_TRAINING_PLAN_OCR', '其他培养方案', Icons.article),
          const Divider(),
          _sectionHeader('ZJU 统一认证'),
          _buildField('ZJU_USERNAME', '学号', Icons.person),
          _buildField('ZJU_PASSWORD', '密码', Icons.lock, obscure: true),
          const Divider(),
          _sectionHeader('DeepSeek AI'),
          _buildDeepSeekKeyField(),
          _buildField('DEEPSEEK_MODEL', '模型', Icons.model_training, hint: 'deepseek-v4-flash'),
          _buildOcrKeyField(),
          _buildField('DEEPSEEK_THINKING', '思考模式', Icons.psychology, hint: 'enabled'),
          const SizedBox(height: 12),
          const Divider(),
          _sectionHeader('PDF 翻译'),
          _buildField('PYTHON_EXE', 'Python 路径', Icons.terminal, hint: '留空自动检测（自带 Python）'),
          _buildField('TRANSLATE_LANG_IN', '源语言', Icons.language, hint: 'en'),
          _buildField('TRANSLATE_LANG_OUT', '目标语言', Icons.translate, hint: 'zh'),
          const SizedBox(height: 12),
          const Divider(),
          _sectionHeader('下载'),
          _buildField('MATERIAL_DOWNLOAD_PATH', '下载路径', Icons.folder),
          _buildField('VIDEO_OPENER', '视频播放器路径', Icons.videocam),
          const Divider(),
          _sectionHeader('PTA (Pintia)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '1. 用浏览器打开 pintia.cn 并登录\n'
                      '2. F12 → 应用(Application) → Cookies → pintia.cn\n'
                      '3. 复制 PTASession 的值粘贴到下方',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildField('PTA_SESSION', 'PTASession cookie', Icons.code, obscure: true),
          const Divider(),
          _sectionHeader('外观'),
          _buildThemeSelector(),
          const Divider(),
          _sectionHeader('自动刷新'),
          _buildAutoRefreshToggle(),
          _buildAutoRefreshInterval(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    final variant = ref.watch(themeVariantProvider);

    return Column(
      children: [
        _themeOption(ThemeVariant.system, '跟随系统', Icons.brightness_auto, variant),
        _themeOption(ThemeVariant.light, '亮色模式(蓝)', Icons.light_mode, variant),
        _themeOption(ThemeVariant.dark, '暗色模式', Icons.dark_mode, variant),
        _themeOption(ThemeVariant.evergreen, '绿意不息风', Icons.eco, variant),
        _themeOption(ThemeVariant.liyu, '黎语未央风', Icons.favorite, variant),
        _themeOption(ThemeVariant.highContrast, '高对比度', Icons.contrast, variant),
      ],
    );
  }

  Widget _themeOption(ThemeVariant value, String label, IconData icon, ThemeVariant current) {
    final selected = value == current;
    return ListTile(
      leading: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : null),
      title: Text(label),
      trailing: Radio<ThemeVariant>(
        value: value,
        groupValue: current,
        onChanged: (v) {
          if (v != null) ref.read(themeVariantProvider.notifier).set(v);
        },
      ),
      onTap: () => ref.read(themeVariantProvider.notifier).set(value),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildField(String key, String label, IconData icon, {bool obscure = false, String? hint}) {
    // 只有标记为 obscure 的字段才受掩码控制
    final isMasked = obscure && (_obscured[key] ?? false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[key],
        obscureText: isMasked,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: obscure
              ? IconButton(
                  icon: Icon(isMasked ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscured[key] = !(_obscured[key] ?? true)),
                )
              : null,
        ),
      ),
    );
  }

  /// 培养方案 OCR 字段：多行文本 + 从文件导入按钮。
  Widget _buildTrainingPlanField(String key, String label, IconData icon) {
    final controller = _controllers[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.file_open, size: 16),
                label: const Text('从文件导入', style: TextStyle(fontSize: 12)),
                onPressed: () => _importOcr(key, controller),
              ),
              if (controller.text.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('清空', style: TextStyle(fontSize: 12)),
                  onPressed: () => controller.clear(),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: '从文件导入培养方案 PDF 或截图，或手动粘贴文本',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  /// 从文件导入 OCR 文本（两级 OCR：DeepSeek → Tesseract）。
  Future<void> _importOcr(String key, TextEditingController controller) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp', 'pdf'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR 识别中...'), duration: Duration(seconds: 30)),
        );
      }

      final dio = ref.read(dioClientProvider);
      final ocrText = await OcrPipeline(dio).recognizeFile(path);

      if (ocrText == null || ocrText.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OCR 未识别到文字')),
          );
        }
        return;
      }

      controller.text = ocrText;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR 完成，${ocrText.length} 字符')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }


  /// 自动刷新开关。
  Widget _buildAutoRefreshToggle() {
    final key = 'AUTO_REFRESH_ENABLED';
    final controller = _controllers[key]!;
    final enabled = controller.text != 'false';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: SwitchListTile(
          title: const Text('数据自动刷新', style: TextStyle(fontSize: 14)),
          subtitle: const Text('打开页面时及后台定时刷新数据',
              style: TextStyle(fontSize: 12)),
          value: enabled,
          onChanged: (v) {
            controller.text = v.toString();
            setState(() {});
          },
        ),
      ),
    );
  }

  /// 自动刷新间隔选择。
  Widget _buildAutoRefreshInterval() {
    final controller = _controllers['AUTO_REFRESH_INTERVAL']!;
    final interval = int.tryParse(controller.text) ?? 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 18),
          const SizedBox(width: 10),
          const Text('刷新间隔', style: TextStyle(fontSize: 13)),
          const Spacer(),
          DropdownButton<int>(
            value: interval.clamp(1, 30),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 分钟')),
              DropdownMenuItem(value: 3, child: Text('3 分钟')),
              DropdownMenuItem(value: 5, child: Text('5 分钟')),
              DropdownMenuItem(value: 10, child: Text('10 分钟')),
              DropdownMenuItem(value: 30, child: Text('30 分钟')),
            ],
            onChanged: (v) {
              if (v != null) {
                controller.text = v.toString();
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  /// DeepSeek API Key 输入框 + 测试连接按钮。
  Widget _buildDeepSeekKeyField() {
    final key = 'DEEPSEEK_API_KEY';
    final isMasked = _obscured[key] ?? true;
    final controller = _controllers[key]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: isMasked,
              decoration: InputDecoration(
                labelText: 'API Key',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(isMasked ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscured[key] = !(_obscured[key] ?? true)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '测试 API 连接',
            child: IconButton(
              icon: const Icon(Icons.wifi_find),
              onPressed: () => _testDeepSeekConnection(controller.text.trim()),
              style: IconButton.styleFrom(
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 测试 DeepSeek API 连接。
  Future<void> _testDeepSeekConnection(String apiKey) async {
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 API Key'), duration: Duration(seconds: 2)),
      );
      return;
    }

    // 显示加载状态
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在测试连接...'),
          ],
        ),
      ),
    );

    try {
      final dio = ref.read(dioClientProvider);
      final client = DeepSeekClient(dio, apiKey: apiKey);
      final result = await client.testConnection();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关闭加载弹窗

      if (result.isOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(result.unwrapOr('连接成功')!)),
              ],
            ),
            backgroundColor: Colors.green.shade50,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        final err = (result as Err).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('连接失败: ${err.userMessage}')),
              ],
            ),
            backgroundColor: Colors.red.shade50,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关闭加载弹窗
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('测试失败: $e')),
            ],
          ),
          backgroundColor: Colors.red.shade50,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// OCR API Key 输入框 + 测试连接按钮。
  Widget _buildOcrKeyField() {
    final key = 'DEEPSEEK_OCR_API_KEY';
    final isMasked = _obscured[key] ?? true;
    final controller = _controllers[key]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: isMasked,
              decoration: InputDecoration(
                labelText: 'OCR API Key (DashScope)',
                hintText: '用于高精度图片文字识别，留空则用本地 OCR',
                prefixIcon: const Icon(Icons.document_scanner),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(isMasked ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscured[key] = !(_obscured[key] ?? true)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '测试 OCR 连接',
            child: IconButton(
              icon: const Icon(Icons.wifi_find),
              onPressed: () => _testOcrConnection(controller.text.trim()),
              style: IconButton.styleFrom(
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 测试 DashScope OCR API 连接。
  Future<void> _testOcrConnection(String apiKey) async {
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 OCR API Key'), duration: Duration(seconds: 2)),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在测试 OCR 连接...'),
          ],
        ),
      ),
    );

    try {
      final dio = ref.read(dioClientProvider);
      final service = DeepSeekOcrService(dio, apiKey);
      final result = await service.testConnection();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (result.isOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(result.unwrap())),
              ],
            ),
            backgroundColor: Colors.green.shade50,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        final err = (result as Err<String>).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('OCR 连接失败: ${err.userMessage}')),
              ],
            ),
            backgroundColor: Colors.red.shade50,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('测试失败: $e')),
            ],
          ),
          backgroundColor: Colors.red.shade50,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _save() async {
    debugPrint('[Settings] _save() called');
    final notifier = ref.read(settingsProvider.notifier);
    final values = <String, String>{};
    _controllers.forEach((key, controller) {
      values[key] = controller.text;
    });
    debugPrint('[Settings] values=$values');
    await notifier.saveAll(values);
    debugPrint('[Settings] saveAll done, error=${notifier.state.saveError}');

    // 检查是否有保存错误
    final saveError = notifier.state.saveError;

    // 更新自动刷新设置
    initAutoRefresh(ref);

    // Trigger login if credentials were saved
    final username = values['ZJU_USERNAME'] ?? '';
    final password = values['ZJU_PASSWORD'] ?? '';
    if (username.isNotEmpty && password.isNotEmpty) {
      final authNotifier = ref.read(authProvider.notifier);
      final ok = await authNotifier.login();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveError != null
                ? '已保存到本地，但配置文件写入失败（Android 正常现象）'
                : ok
                    ? '设置已保存，登录成功'
                    : '设置已保存，但登录失败：${authNotifier.state.error?.userMessage ?? "未知错误"}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saveError != null ? '已保存到本地' : '设置已保存'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }
}
