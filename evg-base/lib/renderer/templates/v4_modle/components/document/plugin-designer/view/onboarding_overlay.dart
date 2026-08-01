/// 新手引导浮层 —— 首次使用插件设计器的分步引导。
///
/// 四阶段引导：
///   ① 模块配置（填写插件名称、图标、描述）
///   ② 页面编排（添加/排序页面）
///   ③ Slot 框选（在画布上拖拽框选区域）
///   ④ 组件绑定（从左侧面板拖入组件类型）
///
/// 使用 [showOnboardingOverlay] 一键显示。
library;

import 'package:flutter/material.dart';

/// 引导步骤描述。
class _OnboardingStep {
  final String title;
  final String description;
  final IconData icon;
  final Alignment alignment; // 高亮区域在屏幕中的位置
  final Offset offset; // 提示框偏移

  const _OnboardingStep({
    required this.title,
    required this.description,
    required this.icon,
    this.alignment = Alignment.topCenter,
    this.offset = const Offset(0, 80),
  });
}

/// 显示完整引导流程。
///
/// 返回 `true` 表示用户完成了引导（或跳过了）。
Future<void> showOnboardingOverlay(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _OnboardingOverlay(),
    ),
  );
}

/// 引导蒙层组件。
class _OnboardingOverlay extends StatefulWidget {
  const _OnboardingOverlay();

  @override
  State<_OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<_OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _dontShowAgain = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  static const _steps = [
    _OnboardingStep(
      title: '① 模块配置',
      description:
          '首先填写插件的基本信息：名称、图标、路由和描述。\n这是插件的"身份证"，决定了它在侧边栏的显示。',
      icon: Icons.settings,
      alignment: Alignment.topCenter,
      offset: Offset(0, 60),
    ),
    _OnboardingStep(
      title: '② 页面编排',
      description:
          '添加插件的页面（类似 PPT 的幻灯片）。\n每个页面可以选择不同的布局范式：全屏、网格、停靠、弹性。',
      icon: Icons.dashboard_customize,
      alignment: Alignment.topCenter,
      offset: Offset(0, 100),
    ),
    _OnboardingStep(
      title: '③ Slot 框选',
      description:
          '在画布上拖拽框选矩形区域来创建 Slot。\n每个 Slot 是页面上的一块"容器"，可以放置不同类型的组件。\n选中 Slot 后可以拖动调整位置。',
      icon: Icons.crop_free,
      alignment: Alignment.center,
      offset: Offset(0, -200),
    ),
    _OnboardingStep(
      title: '④ 组件绑定',
      description:
          '从左侧组件面板选择组件类型，拖入或点击绑定到 Slot。\n组件支持 9 大分组共 45+ 种类型。\n配置完毕后点击"保存"和"同步预览"查看效果。',
      icon: Icons.widgets,
      alignment: Alignment.centerLeft,
      offset: Offset(100, 0),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      _animCtrl.reverse().then((_) {
        setState(() => _step++);
        _animCtrl.forward();
      });
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _prev() {
    if (_step > 0) {
      _animCtrl.reverse().then((_) {
        setState(() => _step--);
        _animCtrl.forward();
      });
    }
  }

  void _skip() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 半透明蒙层
          Container(color: Colors.black54),
          // 引导卡片（居中偏下）
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                width: 440,
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        step.icon,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 标题
                    Text(
                      step.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 描述
                    Text(
                      step.description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 步骤指示器
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_steps.length, (i) {
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _step
                                ? theme.colorScheme.primary
                                : i < _step
                                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    // 按钮行
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 不再显示复选框
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 32,
                              width: 32,
                              child: Checkbox(
                                value: _dontShowAgain,
                                onChanged: (v) =>
                                    setState(() => _dontShowAgain = v ?? false),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => setState(
                                  () => _dontShowAgain = !_dontShowAgain),
                              child: Text('不再显示',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6))),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_step > 0)
                              TextButton(
                                onPressed: _prev,
                                child: const Text('上一步'),
                              ),
                            TextButton(
                              onPressed: _skip,
                              child: const Text('跳过'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: _next,
                              child: Text(
                                _step < _steps.length - 1 ? '下一步' : '完成',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 进度标签（顶部）
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '引导 ${_step + 1}/${_steps.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
