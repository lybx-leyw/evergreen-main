/// 仓库路径配置面板 UI。
///
/// 提供文本输入框、校验状态指示、保存按钮和错误信息展示。
/// 配合 [RepoConfigService] 完成路径配置的闭环。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/services/repo_config_service.dart';

/// 仓库路径配置面板。
///
/// 提供一个紧凑的表单界面用于配置目标代码仓库路径。
/// 使用 [RepoConfigService] 进行路径校验和持久化。
///
/// [onConfigChanged] 回调在保存成功后触发，通知父组件更新仓库路径。
class RepoConfigPanel extends StatefulWidget {
  /// 当前模块 ID（用于确定存储路径）。
  final String moduleId;

  /// 当前已配置的 [RepoConfig]（从服务加载）。
  final RepoConfig? initialConfig;

  /// 配置变更回调（保存成功后触发）。
  final ValueChanged<RepoConfig>? onConfigChanged;

  const RepoConfigPanel({
    super.key,
    required this.moduleId,
    this.initialConfig,
    this.onConfigChanged,
  });

  @override
  State<RepoConfigPanel> createState() => _RepoConfigPanelState();
}

class _RepoConfigPanelState extends State<RepoConfigPanel> {
  late RepoConfigService _service;
  late TextEditingController _pathCtrl;
  late TextEditingController _urlCtrl;

  bool _isValidating = false;
  RepoConfig? _currentConfig;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _service = RepoConfigService(moduleId: widget.moduleId);
    _currentConfig = widget.initialConfig;
    _pathCtrl = TextEditingController(text: _currentConfig?.localPath ?? '');
    _urlCtrl = TextEditingController(text: _currentConfig?.remoteUrl ?? '');
  }

  @override
  void didUpdateWidget(RepoConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialConfig != oldWidget.initialConfig) {
      _currentConfig = widget.initialConfig;
      _pathCtrl.text = _currentConfig?.localPath ?? '';
      _urlCtrl.text = _currentConfig?.remoteUrl ?? '';
    }
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ═══════ 操作 ═══════

  Future<void> _validateAndSave() async {
    final rawPath = _pathCtrl.text.trim();
    if (rawPath.isEmpty) {
      setState(() => _errorText = '请输入目标仓库路径');
      return;
    }

    setState(() {
      _isValidating = true;
      _errorText = null;
    });

    try {
      final config = await _service.validateAndSave(rawPath);
      if (!mounted) return;

      setState(() {
        _currentConfig = config;
        _isValidating = false;
        _errorText = config.validationMessage;
      });

      widget.onConfigChanged?.call(config);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _errorText = '保存失败: $e';
      });
    }
  }

  Future<void> _clearConfig() async {
    _pathCtrl.clear();
    _urlCtrl.clear();
    setState(() {
      _currentConfig = RepoConfig.empty();
      _errorText = null;
    });

    try {
      await _service.clearConfig();
    } catch (_) {}

    widget.onConfigChanged?.call(RepoConfig.empty());
  }

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '目标代码仓库',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildStatusChip(colorScheme),
            ],
          ),
          const SizedBox(height: 8),

          // 路径输入框
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  decoration: InputDecoration(
                    hintText: '输入仓库绝对路径，如 D:\\projects\\my-app',
                    prefixIcon: const Icon(Icons.folder, size: 18),
                    suffixIcon: _pathCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _clearConfig,
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                    errorText: _errorText != null &&
                            _currentConfig?.validationStatus !=
                                RepoValidationStatus.valid
                        ? null // 用下方 chip 展示，不用 TextField errorText
                        : null,
                    filled: true,
                    fillColor: colorScheme.surface,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  onSubmitted: (_) => _validateAndSave(),
                ),
              ),
              const SizedBox(width: 8),

              // 保存按钮
              _isValidating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton.filled(
                      onPressed: _validateAndSave,
                      icon: const Icon(Icons.check, size: 18),
                      tooltip: '校验并保存',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                    ),
            ],
          ),

          // 错误 / 提示信息
          if (_errorText != null) ...[
            const SizedBox(height: 6),
            _buildValidationMessage(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(ColorScheme colorScheme) {
    final status = _currentConfig?.validationStatus;
    if (status == null || status == RepoValidationStatus.unknown) {
      return const SizedBox.shrink();
    }

    final (IconData icon, Color color, String label) = switch (status) {
      RepoValidationStatus.valid => (
          Icons.check_circle,
          Colors.green,
          '已校验',
        ),
      RepoValidationStatus.notFound => (
          Icons.error_outline,
          Colors.orange,
          '路径不存在',
        ),
      RepoValidationStatus.permissionDenied => (
          Icons.lock_outline,
          Colors.red,
          '权限不足',
        ),
      RepoValidationStatus.invalid => (
          Icons.cancel_outlined,
          Colors.red,
          '无效路径',
        ),
      _ => (Icons.help_outline, Colors.grey, '未知'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationMessage(ThemeData theme) {
    final status = _currentConfig?.validationStatus;
    final isError = status != null &&
        status != RepoValidationStatus.valid &&
        status != RepoValidationStatus.unknown;
    final isWarning = status == RepoValidationStatus.valid &&
        _errorText != null &&
        _errorText!.contains('未检测到');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError
              ? Icons.error_outline
              : isWarning
                  ? Icons.info_outline
                  : Icons.check_circle,
          size: 14,
          color: isError
              ? Colors.red
              : isWarning
                  ? Colors.orange
                  : Colors.green,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _errorText!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError
                  ? Colors.red.shade700
                  : isWarning
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
