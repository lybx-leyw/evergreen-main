# PLAN_REFACTOR：渲染层六层架构重构

> 创建：2026-07-09 | 背景：showcase-v3 首页重设计 → 发现 ScaledSlot 缩放 bug → 渲染代码混乱 → 重构
> 原则：逐文件迁移，每批完跑 `flutter test`，零回归

---

## 一、新架构（六层 + 功能域）

```
lib/renderer/
├── app/           App层 —— 顶层壳、命令面板
│   └── service/   App级服务（theme、providers、models）
├── module/        模块层 —— ModuleDispatch、ModulePage
├── page/          页面层 —— CompositeView、布局引擎、独立页面
│   └── service/   页面级服务（EventBus、进程管理）
├── slot/          Slot层 —— SlotDispatch、SlotScale、SlotCard
├── components/    组件层 —— 45 具名组件 + 20 placeholder（全仓库共 65 种），按功能域分组
│   ├── shared/    跨组件共享原子
│   ├── document/  文档与媒体 (12)
│   ├── data/      数据驱动 (11)
│   ├── interaction/ 智能交互 (5)，chat/ 深层拆分
│   ├── creative/  创作工具 (4)
│   ├── learning/  学习 (5)
│   ├── controls/  导航控件 (6)
│   └── placeholder/ 预留 (20)
└── html/          HTML 渲染（仅 dispatch map，渲染函数与 Dart 同目录）
```

### 组件功能域分组

| 域 | 组件 | 数量 |
|----|------|------|
| document | markdown, document, doc-viewer, doc-editor, notepad, code-editor, diff-viewer, presentation, video-player, video, audio-player, image-gallery | 12 |
| data | data-table, card-list, chart, stat-tile, kanban, tree, timeline, map, timetable, calendar, data-dashboard | 11 |
| interaction | ai-assistant, chat, form, settings, prompt-builder | 5 |
| creative | spreadsheet, whiteboard, mindmap, terminal | 4 |
| learning | type-check, flashcards, quiz, crossword, pronunciation | 5 |
| controls | button, nav-button, divider, custom, webview, lottery-wheel | 6 |
| placeholder | placeholder-01 ~ placeholder-20 | 20 |

---

## 二、完整目录结构

```
lib/renderer/
├── app/
│   ├── app.dart
│   ├── app_shell.dart
│   ├── command_palette.dart
│   └── service/
│       ├── theme/
│       │   ├── theme.dart
│       │   ├── render_tokens.dart
│       │   └── theme_provider.dart
│       ├── providers/
│       │   └── renderer_providers.dart
│       └── models/
│           └── .gitkeep
├── module/
│   ├── module.dart
│   ├── module_dispatch.dart
│   ├── module_page.dart
│   └── service/
│       └── .gitkeep
├── page/
│   ├── page.dart
│   ├── composite_view.dart
│   ├── market_view.dart
│   ├── settings_view.dart
│   ├── plugin_detail_view.dart
│   ├── skill_management_view.dart
│   ├── global_memory_view.dart
│   ├── permission_management_view.dart
│   ├── file_viewer.dart
│   ├── my_plugins_view.dart
│   ├── data_dashboard_view.dart
│   ├── layouts/
│   │   ├── dock_layout.dart
│   │   ├── grid_layout.dart
│   │   ├── flex_layout.dart
│   │   ├── fullscreen_layout.dart
│   │   └── absolute_layout.dart
│   └── service/
│       ├── page_event_bus.dart
│       ├── page_process_manager.dart
│       └── .gitkeep
├── slot/
│   ├── slot.dart
│   ├── slot_dispatch.dart
│   ├── slot_card.dart
│   ├── interaction_wrapper.dart
│   └── service/
│       ├── slot_scale.dart
│       └── .gitkeep
├── components/
│   ├── shared/
│   │   ├── shared.dart
│   │   ├── empty_state.dart
│   │   ├── error_card.dart
│   │   ├── toast.dart
│   │   ├── loading_indicator.dart
│   │   ├── confirm_dialog.dart
│   │   ├── crud_toolbar.dart
│   │   ├── sort_header.dart
│   │   └── search_bar.dart
│   ├── document/
│   │   ├── document.dart
│   │   ├── widgets/
│   │   │   ├── media_host.dart
│   │   │   ├── video_player.dart
│   │   │   ├── audio_player.dart
│   │   │   ├── image_viewer.dart
│   │   │   ├── document_viewer.dart
│   │   │   └── rich_text_editor.dart
│   │   ├── markdown_slot.dart
│   │   ├── markdown_html.dart
│   │   ├── document_slot.dart
│   │   ├── document_html.dart
│   │   ├── doc_viewer_slot.dart
│   │   ├── doc_viewer_html.dart
│   │   ├── doc_editor_slot.dart
│   │   ├── doc_editor_html.dart
│   │   ├── notepad_slot.dart
│   │   ├── notepad_html.dart
│   │   ├── code_editor_slot.dart
│   │   ├── code_editor_html.dart
│   │   ├── diff_viewer_slot.dart
│   │   ├── diff_viewer_html.dart
│   │   ├── presentation_slot.dart
│   │   ├── presentation_html.dart
│   │   ├── video_slot.dart
│   │   ├── video_html.dart
│   │   ├── audio_player_slot.dart
│   │   ├── audio_player_html.dart
│   │   ├── image_gallery_slot.dart
│   │   ├── image_gallery_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   ├── data/
│   │   ├── data.dart
│   │   ├── widgets/
│   │   │   ├── data_table.dart
│   │   │   ├── data_list.dart
│   │   │   ├── dashboard_card.dart
│   │   │   ├── data_card_grid.dart
│   │   │   └── timeline_widget.dart
│   │   ├── data_table_slot.dart
│   │   ├── data_table_html.dart
│   │   ├── card_list_slot.dart
│   │   ├── card_list_html.dart
│   │   ├── chart_slot.dart
│   │   ├── chart_html.dart
│   │   ├── stat_tile_slot.dart
│   │   ├── stat_tile_html.dart
│   │   ├── kanban_slot.dart
│   │   ├── kanban_html.dart
│   │   ├── tree_slot.dart
│   │   ├── tree_html.dart
│   │   ├── timeline_slot.dart
│   │   ├── timeline_html.dart
│   │   ├── map_slot.dart
│   │   ├── map_html.dart
│   │   ├── timetable_slot.dart
│   │   ├── timetable_html.dart
│   │   ├── calendar_slot.dart
│   │   ├── calendar_html.dart
│   │   ├── data_dashboard_slot.dart
│   │   ├── data_dashboard_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   ├── interaction/
│   │   ├── interaction.dart
│   │   ├── chat/
│   │   │   ├── chat.dart
│   │   │   ├── chat_slot.dart
│   │   │   ├── chat_html.dart
│   │   │   ├── controller/
│   │   │   │   ├── chat_controller_view.dart
│   │   │   │   └── chat_sync_service.dart
│   │   │   ├── view/
│   │   │   │   ├── chat_view.dart
│   │   │   │   └── chat_input_bar.dart
│   │   │   ├── messages/
│   │   │   │   ├── message_bubble.dart
│   │   │   │   ├── thinking_block.dart
│   │   │   │   ├── tool_call_card.dart
│   │   │   │   └── streaming_cursor.dart
│   │   │   ├── services/
│   │   │   │   └── session_manager.dart
│   │   │   └── models/
│   │   │       └── chat_message.dart
│   │   ├── form_slot.dart
│   │   ├── form_html.dart
│   │   ├── settings_slot.dart
│   │   ├── settings_html.dart
│   │   ├── prompt_builder_slot.dart
│   │   ├── prompt_builder_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   ├── creative/
│   │   ├── creative.dart
│   │   ├── widgets/
│   │   │   ├── spreadsheet_cell.dart
│   │   │   ├── formula_bar.dart
│   │   │   ├── chart_renderer.dart
│   │   │   ├── sheet_tab_bar.dart
│   │   │   └── mindmap_widget.dart
│   │   ├── spreadsheet_slot.dart
│   │   ├── spreadsheet_html.dart
│   │   ├── whiteboard_slot.dart
│   │   ├── whiteboard_html.dart
│   │   ├── mindmap_slot.dart
│   │   ├── mindmap_html.dart
│   │   ├── terminal_slot.dart
│   │   ├── terminal_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   ├── learning/
│   │   ├── learning.dart
│   │   ├── type_check_slot.dart
│   │   ├── type_check_html.dart
│   │   ├── flashcards_slot.dart
│   │   ├── flashcards_html.dart
│   │   ├── quiz_slot.dart
│   │   ├── quiz_html.dart
│   │   ├── crossword_slot.dart
│   │   ├── crossword_html.dart
│   │   ├── pronunciation_slot.dart
│   │   ├── pronunciation_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   ├── controls/
│   │   ├── controls.dart
│   │   ├── button_bar.dart
│   │   ├── button_html.dart
│   │   ├── nav_button.dart
│   │   ├── nav_button_html.dart
│   │   ├── divider_slot.dart
│   │   ├── divider_html.dart
│   │   ├── custom_slot.dart
│   │   ├── custom_html.dart
│   │   ├── webview_slot.dart
│   │   ├── webview_html.dart
│   │   ├── lottery_wheel_slot.dart
│   │   ├── lottery_wheel_html.dart
│   │   └── service/
│   │       └── .gitkeep
│   └── placeholder/
│       └── unknown_slot.dart
├── multi_agent/
│   └── ... (不变)
├── html/
│   └── html_components.dart       # 精简为 dispatch map
└── renderer.dart                  # 顶层 barrel
```

---

## 三、执行计划（P0 ~ P7）

| 批次 | 内容 | 关键操作 |
|------|------|----------|
| P0 | ✅ 建全部新目录 + barrel 文件 + .gitkeep | 目录骨架 |
| P1 | 拆 `composite_view.dart` | 5 布局 + SlotDispatch + 6 内嵌组件 |
| P2 | 搬 app/ + module/ | 4 个文件 |
| P3 | 搬 page/ 独立页面视图 | ~8 个文件 |
| P4 | 搬 components/ 各域 slot | 逐域迁移 ~30 文件 |
| P5 | 拆 interaction/chat/ + HTML co-location | 深层拆分 |
| P6 | 搬 theme/ + shared/ + providers/ | ~3 文件 |
| P7 | 全局 import 替换 + flutter test | 收尾验证 |

**每批结束后必跑 `flutter test`，确保零回归。**

---

## 四、待修复 Bug（重构后处理）

1. **ScaledSlot 垂直缩放 bug** — dock top/bottom 区域 scale=0.3 导致文字微观不可见
   - 位置：`slot/service/slot_scale.dart`
   - 方向：改进缩放模型（选项 B），对非填充区域智能处理

---

## 五、交付物

- [ ] 新目录骨架（P0）
- [ ] 所有文件从 `shared/` `widgets/` 迁移到新层级
- [ ] `html_components.dart` 精简为 dispatch map
- [ ] 每层 barrel 导出文件
- [ ] `flutter test` 全部通过
- [ ] 无 `import` 路径残留对旧目录的引用
