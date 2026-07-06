/// Presentation 视图——幻灯片画布 + 版式 + 切换/元素动画 + 演讲者视图 + 母版。
///
/// 公开类：[PresentationView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/models.dart';
import '../widgets/slide_canvas.dart';
import '../widgets/slide_sorter.dart';
import '../widgets/speaker_notes_panel.dart';
import '../widgets/empty_state.dart';

/// 演示文稿范式完整视图。
///
/// V2: 选项从 [ComponentDescriptor.config] 中解析。
class PresentationView extends StatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor? component;

  const PresentationView({super.key, required this.descriptor, this.component});

  @override
  State<PresentationView> createState() => _PresentationViewState();
}

class _PresentationViewState extends State<PresentationView> {
  int _activeSlide = 0;
  bool _showSorter = false;
  bool _showNotes = false;

  PresentationOptions get _opts {
    final raw = widget.component?.config['presentation'];
    if (raw is Map<String, dynamic>) return PresentationOptions.fromJson(raw);
    return const PresentationOptions();
  }

  // 示例幻灯片数据
  static const _slides = <SlideData>[
    SlideData(title: '标题幻灯片', layout: 'title'),
    SlideData(title: '内容幻灯片', layout: 'content'),
    SlideData(title: '结束页', layout: 'end'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(context),
          Expanded(
            child: Row(
              children: [
                // 幻灯片排序器
                if (_showSorter)
                  SizedBox(
                    width: 200,
                    child: SlideSorter(
                      slides: _slides,
                      activeIndex: _activeSlide,
                      onSlideSelected: (i) =>
                          setState(() => _activeSlide = i),
                    ),
                  ),

                // 幻灯片画布
                Expanded(
                  child: SlideCanvas(
                    slide: _activeSlide < _slides.length
                        ? _slides[_activeSlide]
                        : null,
                    layouts: _opts.layouts,
                    transitions: _opts.transitions,
                    animations: _opts.animations,
                  ),
                ),
              ],
            ),
          ),

          // 演讲者备注
          if (_showNotes && _opts.speakerNotes)
            SizedBox(
              height: 120,
              child: const SpeakerNotesPanel(),
            ),
        ],
      ),
      // 底部幻灯片导航
      bottomSheet: _slides.length > 1
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _activeSlide > 0
                        ? () => setState(() => _activeSlide--)
                        : null,
                  ),
                  Text(
                    '${_activeSlide + 1} / ${_slides.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _activeSlide < _slides.length - 1
                        ? () => setState(() => _activeSlide++)
                        : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (_opts.layouts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.dashboard_customize),
              tooltip: '版式',
              isSelected: _showSorter,
              onPressed: () =>
                  setState(() => _showSorter = !_showSorter),
            ),
          if (_opts.speakerNotes)
            IconButton(
              icon: const Icon(Icons.speaker_notes),
              tooltip: '演讲者备注',
              isSelected: _showNotes,
              onPressed: () =>
                  setState(() => _showNotes = !_showNotes),
            ),
        ],
      ),
    );
  }
}

