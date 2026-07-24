/// 右栏容器 — SegmentedButton 切换草稿本 / AI 答疑。
library;

import 'package:flutter/material.dart';
import '../paper_reading_state.dart';
import 'draft_pad.dart';
import 'ai_assistant_panel.dart';

class RightPanel extends StatefulWidget {
  final String paperId;

  const RightPanel({
    super.key,
    required this.paperId,
  });

  @override
  State<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<RightPanel> {
  int _selectedSegment = 0; // 0 = 草稿本, 1 = AI答疑

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F0E5),
      child: Column(
        children: [
          // 切换栏
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE5D5),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF8B6914)
                      .withAlpha(40),
                ),
              ),
            ),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('✏️ 草稿本'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('🤖 AI答疑'),
                ),
              ],
              selected: {_selectedSegment},
              onSelectionChanged: (set) {
                setState(() =>
                    _selectedSegment = set.first);
              },
              style: ButtonStyle(
                backgroundColor:
                    WidgetStateProperty.resolveWith(
                        (states) {
                  if (states.contains(
                      WidgetState.selected)) {
                    return const Color(0xFFFFF8E7);
                  }
                  return null;
                }),
                foregroundColor:
                    WidgetStateProperty.resolveWith(
                        (states) {
                  if (states.contains(
                      WidgetState.selected)) {
                    return const Color(0xFF4A2C00);
                  }
                  return const Color(0xFF8B6914);
                }),
              ),
            ),
          ),
          // 内容区
          Expanded(
            child: AnimatedSwitcher(
              duration:
                  const Duration(milliseconds: 250),
              child: _selectedSegment == 0
                  ? DraftPad(
                      key: const ValueKey('draft'))
                  : AiAssistantPanel(
                      key: const ValueKey('ai'),
                      paperId: widget.paperId,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
