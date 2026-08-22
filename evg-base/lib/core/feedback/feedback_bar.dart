import 'package:flutter/material.dart';
import 'feedback_dialog.dart';

/// 可拖动浮窗——反馈入口。
///
/// 用户可拖放到屏幕任意位置，避免遮挡原有功能。
/// 单击展开反馈表单（不依赖 Navigator，自行管理 overlay）。
class FeedbackFab extends StatefulWidget {
  const FeedbackFab({super.key});

  @override
  State<FeedbackFab> createState() => _FeedbackFabState();
}

class _FeedbackFabState extends State<FeedbackFab> {
  double _x = 16;
  double _y = 120;
  bool _open = false;
  /// 截屏模式：仅把遮罩设为透明且不可点击，dialog 仍保持 mounted，
  /// 以便发 Issue 工作流能正常渲染、同时截到真实 bug 现场。
  bool _captureMode = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return Positioned.fill(
        child: Opacity(
          opacity: _captureMode ? 0 : 1,
          child: IgnorePointer(
            ignoring: _captureMode,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Stack(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _open = false),
                    child: Container(color: Colors.black38),
                  ),
                  Center(
                    child: SizedBox(
                      width: 420,
                      child: FeedbackDialog(
                        onClose: () => setState(() => _open = false),
                        onCaptureMode: (hide) =>
                            setState(() => _captureMode = hide),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 折叠态——浮动按钮
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _x += d.delta.dx;
          _y += d.delta.dy;
        }),
        onTap: () => setState(() => _open = true),
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('🐛', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
