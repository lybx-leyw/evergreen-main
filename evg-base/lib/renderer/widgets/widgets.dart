/// 原子渲染组件——单一职责 UI 部件，可被任意视图组合复用。
library widgets;

// ── 共享模型 ──
export 'models.dart';

// ── 通用工具（从旧 shared/ 迁移） ──
export 'toast.dart';
export 'empty_state.dart';
export 'error_card.dart';
export 'evergreen_progress.dart';
export 'freshness_badge.dart';
export 'loading_indicator.dart';
export 'touch_target.dart';

// ── 应用级组件（从旧 widgets/ 迁移） ──
export 'app_shell.dart';
export 'command_palette.dart';
export 'markdown_renderer.dart';
export 'mindmap_widget.dart';
export 'flashcard_view.dart';

// ── 交互原子 ──
export 'crud_toolbar.dart';
export 'selection_overlay.dart';
export 'confirm_dialog.dart';
export 'sort_header.dart';
export 'export_menu.dart';
export 'search_bar.dart';
export 'refresh_widget.dart';

// ── 数据展示原子 ──
export 'data_table.dart';
export 'data_list.dart';
export 'data_card_grid.dart';

// ── Chat 原子 ──
export 'message_bubble.dart';
export 'thinking_block.dart';
export 'tool_call_card.dart';
export 'streaming_cursor.dart';
export 'chat_input_bar.dart';

// ── Spreadsheet 原子 ──
export 'spreadsheet_cell.dart';
export 'formula_bar.dart';
export 'chart_renderer.dart';
export 'sheet_tab_bar.dart';

// ── Document 原子 ──
export 'rich_text_editor.dart';
export 'track_changes_gutter.dart';
export 'comment_thread.dart';

// ── Presentation 原子 ──
export 'slide_canvas.dart';
export 'slide_sorter.dart';
export 'speaker_notes_panel.dart';

// ── 其他范式原子 ──
export 'dashboard_card.dart';
export 'code_editor.dart';
export 'type_check_input.dart';
export 'select_input.dart';
export 'form_field_renderer.dart';

// ── 媒体渲染原子 ──
export 'media_host.dart';
export 'video_player.dart';
export 'audio_player.dart';
export 'document_viewer.dart';
export 'image_viewer.dart';

// ── 辅助渲染原子 ──
export 'timeline_widget.dart';
export 'map_panel.dart';
export 'workspace_panel.dart';

// ── Sprint 2: 页面辅助组件 ──
export 'ability_tag.dart';
export 'install_progress.dart';
export 'permission_dialog.dart';
export 'notification_card.dart';
