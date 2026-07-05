# Widgets — 原子渲染组件

> 单一职责 UI 部件，可被任意视图组合复用。

## 通用工具（从旧 shared/ 迁移）

| 组件 | 文件 | 说明 |
|------|------|------|
| Toast | `toast.dart` | Toast/SnackBar 通知（success/error/info） |
| EmptyState | `empty_state.dart` | 空状态占位 |
| ErrorCard | `error_card.dart` | 错误卡片 + 重试按钮 |
| EvergreenProgress | `evergreen_progress.dart` | 品牌化进度条 |
| FreshnessBadge | `freshness_badge.dart` | 数据新鲜度徽章 |
| LoadingIndicator | `loading_indicator.dart` | 加载指示器 |
| TouchTarget | `touch_target.dart` | 48×48 触摸区域扩展 |

## 应用级组件（从旧 widgets/ 迁移）

| 组件 | 文件 | 说明 |
|------|------|------|
| AppShell | `app_shell.dart` | 侧边栏 + 桌面/移动端导航 |
| CommandPalette | `command_palette.dart` | Ctrl+K 命令面板 |
| MarkdownRenderer | `markdown_renderer.dart` | Markdown 渲染（代码高亮/公式/图表） |
| MindMapWidget | `mindmap_widget.dart` | 思维导图 |
| FlashcardView | `flashcard_view.dart` | 闪卡翻面视图 |

## 交互原子

| 组件 | 文件 | 说明 |
|------|------|------|
| CrudToolbar | `crud_toolbar.dart` | 新建/编辑/删除按钮栏 |
| SelectionOverlay | `selection_overlay.dart` | 单选/多选覆盖层 |
| ConfirmDialog | `confirm_dialog.dart` | 通用确认弹窗 |
| SortHeader | `sort_header.dart` | 可排序列头 |
| ExportMenu | `export_menu.dart` | CSV/PDF/JSON 导出菜单 |
| SearchBar | `search_bar.dart` | 搜索输入栏 |
| RefreshWidget | `refresh_widget.dart` | 下拉刷新 + 自动刷新 |

## 数据展示原子

| 组件 | 文件 | 说明 |
|------|------|------|
| DataTable | `data_table.dart` | 数据表格（display=table） |
| DataList | `data_list.dart` | 数据列表（display=list） |
| DataCardGrid | `data_card_grid.dart` | 卡片网格（display=card） |

## Chat 原子

| 组件 | 文件 | 说明 |
|------|------|------|
| MessageBubble | `message_bubble.dart` | 聊天气泡 |
| ThinkingBlock | `thinking_block.dart` | AI 思考过程展示 |
| ToolCallCard | `tool_call_card.dart` | 工具调用卡片 |
| StreamingCursor | `streaming_cursor.dart` | 流式光标效果 |
| ChatInputBar | `chat_input_bar.dart` | 聊天输入栏 |

## Spreadsheet 原子

| 组件 | 文件 | 说明 |
|------|------|------|
| SpreadsheetGrid | `spreadsheet_cell.dart` | 单元格网格 |
| FormulaBar | `formula_bar.dart` | 公式输入栏 |
| ChartRenderer | `chart_renderer.dart` | 图表渲染器 |
| SheetTabBar | `sheet_tab_bar.dart` | 多 Sheet 标签栏 |

## Document 原子

| 组件 | 文件 | 说明 |
|------|------|------|
| RichTextEditor | `rich_text_editor.dart` | 富文本编辑器 |
| TrackChangesGutter | `track_changes_gutter.dart` | 修订标记栏 |
| CommentThread | `comment_thread.dart` | 批注面板 |

## Presentation 原子

| 组件 | 文件 | 说明 |
|------|------|------|
| SlideCanvas | `slide_canvas.dart` | 幻灯片画布 |
| SlideSorter | `slide_sorter.dart` | 幻灯片排序器 |
| SpeakerNotesPanel | `speaker_notes_panel.dart` | 演讲者备注面板 |

## 其他范式原子

| 组件 | 文件 | 说明 |
|------|------|------|
| DashboardCard | `dashboard_card.dart` | KPI 卡片 |
| CodeEditor | `code_editor.dart` | 代码编辑器 |
| TypeCheckInput | `type_check_input.dart` | 打字检查输入 |
| SelectInput | `select_input.dart` | 选择输入 |
| FormFieldRenderer | `form_field_renderer.dart` | 动态表单字段 |

## 媒体渲染原子

| 组件 | 文件 | 说明 |
|------|------|------|
| MediaHost | `media_host.dart` | 媒体后缀匹配 + 模式分发 |
| VideoPlayer | `video_player.dart` | 视频播放器 |
| AudioPlayer | `audio_player.dart` | 音频播放器 |
| DocumentViewer | `document_viewer.dart` | 文档查看器 |
| ImageViewer | `image_viewer.dart` | 图片查看器 |

## 辅助渲染原子

| 组件 | 文件 | 说明 |
|------|------|------|
| TimelineWidget | `timeline_widget.dart` | 时间线视图 |
| MapPanel | `map_panel.dart` | 地图面板 |
| WorkspacePanel | `workspace_panel.dart` | 文件工作区面板 |
