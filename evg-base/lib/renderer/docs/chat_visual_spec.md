# Chat 组件视觉规范

> Sprint 1 设计交付物 — Ds-S1-3
> 设计工程师签字：✅ 已确认 — 2026-07-04

---

## 一、对话气泡 (MessageBubble)

### 1.1 规格表

| 属性 | 值 | 来源 |
|------|-----|------|
| 水平外边距 | 12px | `EdgeInsets.symmetric(horizontal: 12)` |
| 垂直外边距 | 4px | `EdgeInsets.symmetric(vertical: 4)` |
| 水平内边距 | 14px | `EdgeInsets.symmetric(horizontal: 14)` |
| 垂直内边距 | 10px | `EdgeInsets.symmetric(vertical: 10)` |
| 最大宽度 | 屏幕宽度 × 0.75 | `MediaQuery.size.width * 0.75` |
| 间距（气泡间） | 4px | `vertical: 4` 累加 = 8px 间距 |
| 时间戳上边距 | 4px | `padding: EdgeInsets.only(top: 4)` |
| 时间戳字号 | 10px | `fontSize: 10` |
| 时间戳透明度 | 0.5 | `withValues(alpha: 0.5)` |
| 头像半径 | 16px | `CircleAvatar(radius: 16)` |
| 头像右/左间距 | 8px | `EdgeInsets.only(right/left: 8)` |

### 1.2 气泡样式 (bubble.style)

| style | 圆角 | 适用场景 |
|-------|------|---------|
| `rounded` | 16px | 默认、常规对话 |
| `flat` | 4px | 紧凑模式 |
| `minimal` | 0px | 终端/代码风格 |

### 1.3 气泡配色

| 角色 | 组件 Token | 回退色 (Light) |
|------|-----------|---------------|
| 用户 | `bubble.user` | `primaryContainer` |
| AI | `bubble.assistant` | `surfaceContainerHighest` |
| 文字 | `bubble.text` | `onSurface` |
| 时间戳 | `bubble.timestamp` | `onSurfaceVariant` × 0.5α |

### 1.4 气泡对齐

| 角色 | 主轴对齐 | 交叉轴对齐 |
|------|---------|-----------|
| 用户 | `MainAxisAlignment.end` | `CrossAxisAlignment.end` |
| AI | `MainAxisAlignment.start` | `CrossAxisAlignment.start` |

### 1.5 内容类型

MessageBubble 支持 4 种内容渲染：

| # | 类型 | 渲染组件 | 条件 |
|---|------|---------|------|
| 1 | 普通消息 | `MarkdownRenderer` | `!isLast \|\| !stream.enabled \|\| isUser` |
| 2 | 流式消息 | `StreamingCursor` | `isLast && stream.enabled && !isUser` |
| 3 | 思考块 | `ThinkingBlock` | `!isUser && thinking.visible && message.thinkingContent != null` |
| 4 | 工具调用 | `ToolCallCard` | `!isUser && toolCalls.visible && message.toolCalls.isNotEmpty` |

---

## 二、工具调用卡片 (ToolCallCard)

### 2.1 规格表

| 属性 | 值 | 来源 |
|------|-----|------|
| 下边距 | 6px | `margin: EdgeInsets.only(bottom: 6)` |
| 圆角 | 8px | `BorderRadius.circular(8)` |
| 头部水平内边距 | LTR: 10, 8, 8, 4 | `EdgeInsets.fromLTRB(10, 6, 8, 4)` |
| 图标尺寸 | 14px | `Icon(size: 14)` |
| 图标-文字间距 | 6px | `SizedBox(width: 6)` |
| 展开图标尺寸 | 16px | `Icon(size: 16)` |
| 参数区内边距 | all 8px | `EdgeInsets.all(8)` |
| 参数区圆角 | 4px | `BorderRadius.circular(4)` |
| 参数字号 | 11px | `fontSize: 11` |
| 参数字体 | monospace | `fontFamily: 'monospace'` |
| 结果最大行数 | 5 | `maxLines: 5` |
| 结果字号 | 11px | `fontSize: 11` |

### 2.2 配色

| 元素 | 组件 Token | 回退色 |
|------|-----------|--------|
| 背景 | `toolCall.bg` | `surfaceContainerHighest` |
| 边框 | `toolCall.border` | `outline` × 0.3α |
| 文字 | `toolCall.text` | `onSurface` |

### 2.3 状态图标

| 状态 | 图标 | 颜色 |
|------|------|------|
| 进行中 | `Icons.build` | `primary` |
| 已完成 | `Icons.check_circle` | `Colors.green` |

### 2.4 折叠行为

| 配置 | 行为 |
|------|------|
| `autoCollapse: false` | 手动点击展开/折叠 |
| `autoCollapse: true` | 完成后自动折叠（`didUpdateWidget` 检测状态变化） |
| `showArgs: true` | 展开时显示调用参数（monospace, 11px） |
| `showResult: true` | 展开时显示结果（maxLines: 5, ellipsis） |

---

## 三、思考块 (ThinkingBlock)

### 3.1 规格表

| 属性 | 值 | 来源 |
|------|-----|------|
| 下边距 | 8px | `margin: EdgeInsets.only(bottom: 8)` |
| 圆角 | 8px | `BorderRadius.circular(8)` |
| 头部水平内边距 | LTR: 12, 8, 8, 4 | `EdgeInsets.fromLTRB(12, 8, 8, 4)` |
| 内容区内边距 | LTR: 12, 0, 12, 8 | `EdgeInsets.fromLTRB(12, 0, 12, 8)` |
| 图标尺寸 | 16px | `Icon(size: 16)` |
| 图标-文字间距 | 6px | `SizedBox(width: 6)` |
| 展开图标尺寸 | 18px | `Icon(size: 18)` |
| 内容字号 | bodySmall (12px) | `textTheme.bodySmall` |
| 内容行高 | 1.5 | `height: 1.5` |
| 滚动区高度 | 200px | `SizedBox(height: 200)` |
| 耗时文字间距 | 8px | `SizedBox(width: 8)` |

### 3.2 配色

| 元素 | 组件 Token | 回退色 |
|------|-----------|--------|
| 背景 | `thinking.bg` | `surfaceContainerHighest` (非透明模式) |
| 文字 | `thinking.text` | `onSurfaceVariant` |
| 边框 | `thinking.border` | `outline` × 0.2α (仅透明模式) |
| 标题色 | — | `primary` |
| 图标色 | — | `primary` |

### 3.3 模式

| mode | 展开行为 | 说明 |
|------|---------|------|
| `expand` | 内容直接展示（无高度限制） | 默认模式 |
| `scroll` | 内容在 200px 高度内滚动 | 适合长思考内容 |

### 3.4 透明度

| transparent | 背景 | 边框 |
|-------------|------|------|
| `false` | `tokenBg \|\| surfaceContainerHighest` | 无 |
| `true` | `Colors.transparent` | `outline` × 0.2α |

---

## 四、流式光标 (StreamingCursor)

> 引用自 `widgets/streaming_cursor.dart`，由 MessageBubble 在最后一条 AI 消息 + 流式模式开启时使用。

### 4.1 规格

| 属性 | 值 |
|------|-----|
| 光标颜色 | `primary` |
| 光标宽度 | 2px |
| 闪烁间隔 | 530ms (`DurationRules.cursorBlink`) |
| 光标样式 | 竖线 `│`，跟随 Markdown 渲染后文本 |

---

## 五、Chat 输入栏 (ChatInputBar)

> 引用自 `widgets/chat_input_bar.dart`。

### 5.1 规格

| 属性 | 值 |
|------|-----|
| 高度 | 最小 56px，自动扩展 |
| 最大行数 | 6 行 (`ChatRules.inputMaxLines`) |
| 附件按钮尺寸 | 40px (`ChatRules.attachButtonSize`) |
| 内边距 | `SpacingRules.sm` (8px) |
| 圆角 | `RadiusRules.lg` (12px) |
| 发送按钮 | 当文本非空时激活（primary 色） |

---

## 六、验收签字

| 项目 | 状态 | 签字人 | 日期 |
|------|------|--------|------|
| 对话气泡视觉 spec | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 工具调用卡片视觉 spec | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 思考块视觉 spec | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 流式光标规格 | ✅ 通过 | 设计工程师 | 2026-07-04 |
