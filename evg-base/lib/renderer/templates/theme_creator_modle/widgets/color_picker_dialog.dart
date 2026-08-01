/// 自研全精度颜色选择器——调色板 + RGB/HSV 滑杆 + hex。
///
/// 无第三方依赖（无网络环境无法 pub add 色盘包）。包含：
/// - **调色显示板**：顶部色相条（彩虹渐变，点击/拖拽选色相）
///   + 饱和度×明度二维板（点击/拖拽任意取色，带当前色标记）
/// - RGB 三通道连续滑杆（0-255 任意值）+ 数值输入
/// - HSV 三通道连续滑杆（H 0-360 / S 0-100 / V 0-100）+ 数值输入
/// - hex 直接输入（实时校验）
/// - 实时色块预览
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/core/theme/src/color.dart';

/// 打开颜色选择对话框。
///
/// 返回新颜色 `#RRGGBB`；用户取消返回 null。
Future<String?> showColorPickerDialog(
  BuildContext context, {
  required String initialHex,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ColorPickerDialog(initialHex: initialHex),
  );
}

// ═══════ HSV ↔ Color 转换（Flutter 只有 HSL，自实现 HSV） ═══════

/// HSV → Color（h 0-360，s/v 0-1）。
Color hsvToColor(double h, double s, double v) {
  final hh = ((h % 360) + 360) % 360;
  final c = v * s;
  final x = c * (1 - ((hh / 60) % 2 - 1).abs());
  final m = v - c;
  double r, g, b;
  if (hh < 60) {
    r = c; g = x; b = 0;
  } else if (hh < 120) {
    r = x; g = c; b = 0;
  } else if (hh < 180) {
    r = 0; g = c; b = x;
  } else if (hh < 240) {
    r = 0; g = x; b = c;
  } else if (hh < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  return Color.fromARGB(
    255,
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  );
}

/// Color → HSV（h 0-360，s/v 0-1）。
({double h, double s, double v}) colorToHsv(Color c) {
  final r = c.r, g = c.g, b = c.b;
  final maxV = math.max(r, math.max(g, b));
  final minV = math.min(r, math.min(g, b));
  final d = maxV - minV;
  double h;
  if (d == 0) {
    h = 0;
  } else if (maxV == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (maxV == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  final s = maxV == 0 ? 0.0 : d / maxV;
  return (h: h, s: s, v: maxV);
}

// ═══════ 颜色选择对话框 ═══════

/// 颜色选择对话框。
class ColorPickerDialog extends StatefulWidget {
  final String initialHex;

  const ColorPickerDialog({super.key, required this.initialHex});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _color;
  bool _rgbMode = true;

  // RGB 通道控制器（数值输入框）
  late final TextEditingController _rCtrl;
  late final TextEditingController _gCtrl;
  late final TextEditingController _bCtrl;
  // HSV 通道控制器
  late final TextEditingController _hCtrl;
  late final TextEditingController _sCtrl;
  late final TextEditingController _vCtrl;
  // hex 控制器
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _color = _parseHex(widget.initialHex) ?? Colors.black;
    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _hCtrl = TextEditingController();
    _sCtrl = TextEditingController();
    _vCtrl = TextEditingController();
    _hexCtrl = TextEditingController();
    _syncAllControllers();
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _hCtrl.dispose();
    _sCtrl.dispose();
    _vCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  // ═══════ 颜色 ↔ 通道 ═══════

  int get _r => (_color.r * 255).round();
  int get _g => (_color.g * 255).round();
  int get _b => (_color.b * 255).round();

  ({double h, double s, double v}) get _hsv => colorToHsv(_color);
  double get _h => _hsv.h;
  double get _s => _hsv.s * 100;
  double get _v => _hsv.v * 100;

  String get _hex => ThemeColor(_color.toARGB32()).toHex(withAlpha: false);

  void _setColor(Color c) {
    setState(() => _color = c);
    _syncAllControllers();
  }

  /// 调色板 / HSV 统一入口：s/v 为 0-100 百分比。
  void _setHsv(double h, double s, double v) =>
      _setColor(hsvToColor(h, s / 100, v / 100));

  void _syncAllControllers() {
    _rCtrl.text = '$_r';
    _gCtrl.text = '$_g';
    _bCtrl.text = '$_b';
    _hCtrl.text = _h.toStringAsFixed(1);
    _sCtrl.text = _s.toStringAsFixed(1);
    _vCtrl.text = _v.toStringAsFixed(1);
    _hexCtrl.text = _hex;
  }

  /// 数字输入框通用更新：解析失败/越界时忽略（保持滑杆为准）。
  void _onChannelInput(TextEditingController ctrl, double min, double max,
      ValueChanged<double> apply) {
    final v = double.tryParse(ctrl.text);
    if (v == null || v < min || v > max) return;
    apply(v);
  }

  Color _applyRgb(int r, int g, int b) => Color.fromARGB(
      255, r.clamp(0, 255).toInt(), g.clamp(0, 255).toInt(), b.clamp(0, 255).toInt());

  Color? _parseHex(String hex) {
    final c = ThemeDescriptor.parseHex(hex);
    return c != null ? Color(c.value) : null;
  }

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('选择颜色'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 实时色块
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(height: 12),
              // ── 调色显示板：饱和度×明度二维板 ──
              SizedBox(
                height: 160,
                child: _SvBoard(
                  hue: _h,
                  saturation: _s / 100,
                  value: _v / 100,
                  onChanged: (s, v) => _setHsv(_h, s * 100, v * 100),
                ),
              ),
              const SizedBox(height: 8),
              // ── 色相条 ──
              _HueStrip(hue: _h, onChanged: (h) => _setHsv(h, _s, _v)),
              const SizedBox(height: 12),
              // 模式切换：RGB / HSV
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('RGB')),
                  ButtonSegment(value: false, label: Text('HSV')),
                ],
                selected: {_rgbMode},
                onSelectionChanged: (s) => setState(() => _rgbMode = s.first),
                style:
                    const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 10),
              if (_rgbMode) ...[
                _channelSlider('R', _r.toDouble(), 0, 255,
                    (v) => _setColor(_applyRgb(v.round(), _g, _b)),
                    _rCtrl, 0, 255,
                    (v) => _setColor(_applyRgb(v.round(), _g, _b))),
                _channelSlider('G', _g.toDouble(), 0, 255,
                    (v) => _setColor(_applyRgb(_r, v.round(), _b)),
                    _gCtrl, 0, 255,
                    (v) => _setColor(_applyRgb(_r, v.round(), _b))),
                _channelSlider('B', _b.toDouble(), 0, 255,
                    (v) => _setColor(_applyRgb(_r, _g, v.round())),
                    _bCtrl, 0, 255,
                    (v) => _setColor(_applyRgb(_r, _g, v.round()))),
              ] else ...[
                _channelSlider('H', _h, 0, 360,
                    (v) => _setHsv(v, _s, _v),
                    _hCtrl, 0, 360, (v) => _setHsv(v, _s, _v)),
                _channelSlider('S', _s, 0, 100,
                    (v) => _setHsv(_h, v, _v),
                    _sCtrl, 0, 100, (v) => _setHsv(_h, v, _v)),
                _channelSlider('V', _v, 0, 100,
                    (v) => _setHsv(_h, _s, v),
                    _vCtrl, 0, 100, (v) => _setHsv(_h, _s, v)),
              ],
              const SizedBox(height: 6),
              // hex 输入
              Row(
                children: [
                  const Text('HEX', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      onChanged: (v) {
                        final c = _parseHex(v.trim());
                        if (c != null) {
                          setState(() => _color = c);
                          _syncAllControllers();
                        }
                      },
                      style: const TextStyle(
                          fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _parseHex(_hexCtrl.text.trim()) == null
                            ? '非法 hex'
                            : null,
                        errorStyle: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hex),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 单通道滑杆 + 数值输入。
  Widget _channelSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onSlider,
    TextEditingController ctrl,
    double ctrlMin,
    double ctrlMax,
    ValueChanged<double> onInput,
  ) {
    return Row(
      children: [
        SizedBox(
            width: 18,
            child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            // 不设 divisions → 连续任意精度
            onChanged: onSlider,
          ),
        ),
        SizedBox(
          width: 52,
          child: TextField(
            controller: ctrl,
            onChanged: (v) => _onChannelInput(ctrl, ctrlMin, ctrlMax, onInput),
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════ 调色显示板 ═══════

/// 饱和度(S)×明度(V) 二维调色板。
///
/// 横轴 = 饱和度（左 0% → 右 100%），纵轴 = 明度（下 0 → 上 100%）。
/// 点击/拖拽任意位置取色，白色圆圈标记当前位置。
///
/// 注意：不能使用 LayoutBuilder——本组件位于对话框的 SingleChildScrollView
/// 内，intrinsic 尺寸计算会抛错。改用 findRenderObject 取实际尺寸，
/// 标记用 Align 定位（不依赖具体像素）。
class _SvBoard extends StatelessWidget {
  final double hue;
  final double saturation;
  final double value;
  final void Function(double s, double v) onChanged;

  const _SvBoard({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  void _update(BuildContext context, Offset pos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final size = box.size;
    final s = (pos.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - pos.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    final base = hsvToColor(hue, 1, 1); // 当前色相的最饱和最亮色
    return GestureDetector(
      onTapDown: (d) => _update(context, d.localPosition),
      onPanDown: (d) => _update(context, d.localPosition),
      onPanUpdate: (d) => _update(context, d.localPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 底：当前色相最饱和色
            DecoratedBox(decoration: BoxDecoration(color: base)),
            // 饱和度轴：左白 → 右透明（白混入降低饱和度）
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.white, Colors.transparent],
                ),
              ),
            ),
            // 明度轴：下黑 → 上透明（黑混入降低明度）
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                ),
              ),
            ),
            // 边框
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
            ),
            // 当前色标记（Align 定位，与尺寸无关）
            Align(
              alignment: Alignment(
                -1 + 2 * saturation.clamp(0.0, 1.0),
                1 - 2 * value.clamp(0.0, 1.0),
              ),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 色相条——彩虹渐变，点击/拖拽选色相。
class _HueStrip extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueStrip({required this.hue, required this.onChanged});

  static const List<Color> _rainbow = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  void _update(BuildContext context, Offset pos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final h = (pos.dx / box.size.width * 360).clamp(0.0, 360.0);
    onChanged(h);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _update(context, d.localPosition),
      onPanDown: (d) => _update(context, d.localPosition),
      onPanUpdate: (d) => _update(context, d.localPosition),
      child: SizedBox(
        height: 18,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 彩虹渐变
            Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(colors: _rainbow),
                border: Border.all(color: Colors.black26),
              ),
            ),
            // 色相标记（Align 定位）
            Align(
              alignment: Alignment(-1 + 2 * (hue / 360).clamp(0.0, 1.0), 0),
              child: Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
