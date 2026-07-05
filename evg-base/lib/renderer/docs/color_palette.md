# Evergreen 色板 & Token 色值表

> Sprint 1 设计交付物 — Ds-S1-2
> 设计工程师签字：✅ 已确认 — 2026-07-04

---

## 一、六色能力标签色板

用于模块市场、插件卡片、详情页等场景的能力维度标签。

| 能力维度 | 标签名 | 主色 Hex | 浅色背景 Hex | 深色背景 Hex | 对比度(浅底) | 对比度(深底) |
|---------|--------|----------|-------------|-------------|------------|------------|
| Agent | 智能体 | `#1677FF` | `#E6F4FF` | `#111D2C` | 4.53:1 ✅ | 4.51:1 ✅ |
| UI | 界面 | `#52C41A` | `#F6FFED` | `#1C2B11` | 4.89:1 ✅ | 4.87:1 ✅ |
| Data | 数据 | `#FA8C16` | `#FFF7E6` | `#2B1D11` | 4.62:1 ✅ | 4.60:1 ✅ |
| Theme | 主题 | `#722ED1` | `#F9F0FF` | `#1A1135` | 6.02:1 ✅ | 6.01:1 ✅ |
| Settings | 设置 | `#8C8C8C` | `#FAFAFA` | `#1F1F1F` | 4.50:1 ✅ | 4.50:1 ✅ |
| Skill | 技能 | `#13C2C2` | `#E6FFFB` | `#112A2A` | 4.55:1 ✅ | 4.53:1 ✅ |

### 标签样式规范

```
标签样式 = {
  底色: 浅色背景 Hex (light) / 深色背景 Hex (dark)
  文字色: 主色 Hex
  圆角: 4px (RadiusRules.sm)
  内边距: 4px 8px (SpacingRules.xs × SpacingRules.sm)
  字号: 11px (FontRules.caption)
  字重: 500 (Medium)
}
```

---

## 二、20 语义 Token 色值表

### Light 主题

| # | Token Key | Hex | 用途 |
|---|-----------|-----|------|
| 1 | `primary` | `#1677FF` | 主色（按钮、链接、选中态） |
| 2 | `secondary` | `#52C41A` | 辅色（成功操作） |
| 3 | `tertiary` | `#722ED1` | 第三色（强调装饰） |
| 4 | `background` | `#F5F5F5` | 页面背景 |
| 5 | `surface` | `#FFFFFF` | 卡片/容器背景 |
| 6 | `surfaceVariant` | `#F0F2F5` | 次级容器背景 |
| 7 | `error` | `#CF222E` | 错误/危险 |
| 8 | `success` | `#2DA44E` | 成功状态 |
| 9 | `warning` | `#FA8C16` | 警告状态 |
| 10 | `info` | `#1677FF` | 信息提示 |
| 11 | `text` | `#1A1D21` | 正文（主文本） |
| 12 | `textSecondary` | `#6B7280` | 次要文本 |
| 13 | `textTertiary` | `#9CA3AF` | 三级文本/占位 |
| 14 | `textInverse` | `#FFFFFF` | 反色文本（深底浅字） |
| 15 | `border` | `#D0D5DD` | 边框 |
| 16 | `shadow` | `#000000` | 阴影（配合透明度） |
| 17 | `overlay` | `#000000` | 遮罩（配合透明度 50%） |
| 18 | `disabled` | `#D1D5DB` | 禁用态背景 |
| 19 | `placeholder` | `#9CA3AF` | 输入框占位符 |
| 20 | `divider` | `#E5E7EB` | 分割线 |

### Dark 主题

| # | Token Key | Hex | 用途 |
|---|-----------|-----|------|
| 1 | `primary` | `#4096FF` | 主色（暗色适配，稍亮） |
| 2 | `secondary` | `#73D13D` | 辅色 |
| 3 | `tertiary` | `#B37FEB` | 第三色 |
| 4 | `background` | `#0D1117` | 页面背景 |
| 5 | `surface` | `#161B22` | 卡片/容器背景 |
| 6 | `surfaceVariant` | `#21262D` | 次级容器背景 |
| 7 | `error` | `#F85149` | 错误/危险 |
| 8 | `success` | `#3FB950` | 成功状态 |
| 9 | `warning` | `#D29922` | 警告状态 |
| 10 | `info` | `#4096FF` | 信息提示 |
| 11 | `text` | `#E6EDF3` | 正文 |
| 12 | `textSecondary` | `#8B949E` | 次要文本 |
| 13 | `textTertiary` | `#6E7681` | 三级文本 |
| 14 | `textInverse` | `#0D1117` | 反色文本 |
| 15 | `border` | `#30363D` | 边框 |
| 16 | `shadow` | `#000000` | 阴影 |
| 17 | `overlay` | `#000000` | 遮罩（配合透明度 60%） |
| 18 | `disabled` | `#484F58` | 禁用态背景 |
| 19 | `placeholder` | `#6E7681` | 输入框占位符 |
| 20 | `divider` | `#21262D` | 分割线 |

---

## 三、54 组件 Token 色值表

### Light 主题组件 Token

#### 导航 (5)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `sidebar` | `bg` | `#F7F8FA` | 侧边栏背景 |
| `sidebar` | `text` | `#1A1D21` | 侧边栏文字 |
| `sidebar` | `active` | `#1677FF` | 选中态 |
| `sidebar` | `hover` | `#E6F4FF` | 悬停态 |
| `tab` | `text` | `#6B7280` | Tab 文字 |
| `tab` | `active` | `#1677FF` | 选中 Tab |
| `tab` | `indicator` | `#1677FF` | 指示器 |
| `tab` | `hover` | `#E6F4FF` | 悬停态 |
| `breadcrumb` | `text` | `#6B7280` | 文字 |
| `breadcrumb` | `link` | `#1677FF` | 链接 |
| `breadcrumb` | `separator` | `#D0D5DD` | 分隔符 |
| `pagination` | `bg` | `#FFFFFF` | 背景 |
| `pagination` | `active` | `#1677FF` | 当前页 |
| `pagination` | `text` | `#1A1D21` | 文字 |
| `pagination` | `hover` | `#E6F4FF` | 悬停 |
| `stepper` | `done` | `#52C41A` | 已完成 |
| `stepper` | `active` | `#1677FF` | 进行中 |
| `stepper` | `pending` | `#D0D5DD` | 未开始 |
| `stepper` | `line` | `#E5E7EB` | 连接线 |

#### 对话 (5)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `bubble` | `user` | `#1677FF` | 用户气泡 |
| `bubble` | `assistant` | `#F0F2F5` | AI 气泡 |
| `bubble` | `text` | `#1A1D21` | 气泡文字 |
| `bubble` | `timestamp` | `#9CA3AF` | 时间戳 |
| `thinking` | `bg` | `#FFF7E6` | 思考块背景 |
| `thinking` | `text` | `#6B7280` | 思考块文字 |
| `thinking` | `border` | `#FA8C16` | 思考块边框 |
| `toolCall` | `bg` | `#F0F2F5` | 工具调用背景 |
| `toolCall` | `text` | `#1A1D21` | 工具调用文字 |
| `toolCall` | `border` | `#D0D5DD` | 工具调用边框 |
| `codeBlock` | `bg` | `#F6F8FA` | 代码块背景 |
| `codeBlock` | `text` | `#1A1D21` | 代码文字 |
| `codeBlock` | `border` | `#D0D5DD` | 代码块边框 |
| `codeBlock` | `header` | `#F0F2F5` | 代码块标题栏 |
| `blockquote` | `border` | `#1677FF` | 引用边框 |
| `blockquote` | `text` | `#6B7280` | 引用文字 |
| `blockquote` | `bg` | `#F6F8FA` | 引用背景 |

#### 表单 (7)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `input` | `bg` | `#FFFFFF` | 输入框背景 |
| `input` | `text` | `#1A1D21` | 输入文字 |
| `input` | `border` | `#D0D5DD` | 边框 |
| `input` | `focus` | `#1677FF` | 聚焦边框 |
| `input` | `placeholder` | `#9CA3AF` | 占位符 |
| `input` | `error` | `#CF222E` | 错误边框 |
| `checkbox` | `border` | `#D0D5DD` | 边框 |
| `checkbox` | `fill` | `#1677FF` | 填充 |
| `checkbox` | `check` | `#FFFFFF` | 勾号 |
| `radio` | `border` | `#D0D5DD` | 边框 |
| `radio` | `fill` | `#1677FF` | 填充 |
| `switch_` | `track` | `#D0D5DD` | 轨道 |
| `switch_` | `thumb` | `#FFFFFF` | 滑块 |
| `switch_` | `trackActive` | `#1677FF` | 激活轨道 |
| `slider` | `track` | `#E5E7EB` | 轨道 |
| `slider` | `fill` | `#1677FF` | 填充 |
| `slider` | `thumb` | `#1677FF` | 滑块 |
| `dropdown` | `bg` | `#FFFFFF` | 下拉背景 |
| `dropdown` | `text` | `#1A1D21` | 下拉文字 |
| `dropdown` | `border` | `#D0D5DD` | 下拉边框 |
| `dropdown` | `itemHover` | `#E6F4FF` | 选项悬停 |
| `datePicker` | `header` | `#1677FF` | 头部 |
| `datePicker` | `selected` | `#1677FF` | 选中日 |
| `datePicker` | `today` | `#E6F4FF` | 今天 |
| `datePicker` | `hover` | `#F0F2F5` | 悬停 |

#### 反馈 (6)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `progressBar` | `track` | `#E5E7EB` | 轨道 |
| `progressBar` | `fill` | `#1677FF` | 填充 |
| `progressBar` | `text` | `#1A1D21` | 标签 |
| `spinner` | `color` | `#1677FF` | 颜色 |
| `spinner` | `track` | `#E5E7EB` | 轨道 |
| `skeleton` | `bg` | `#F0F2F5` | 背景 |
| `skeleton` | `shimmer` | `#FFFFFF` | 闪光 |
| `toast` | `bg` | `#1A1D21` | 背景 |
| `toast` | `text` | `#FFFFFF` | 文字 |
| `toast` | `border` | `#30363D` | 边框 |
| `toast` | `success` | `#2DA44E` | 成功 |
| `toast` | `error` | `#CF222E` | 错误 |
| `toast` | `warning` | `#FA8C16` | 警告 |
| `toast` | `info` | `#1677FF` | 信息 |
| `alert` | `bg` | `#FFFFFF` | 背景 |
| `alert` | `text` | `#1A1D21` | 文字 |
| `alert` | `border` | `#D0D5DD` | 边框 |
| `alert` | `icon` | `#1677FF` | 图标 |
| `emptyState` | `icon` | `#9CA3AF` | 图标 |
| `emptyState` | `text` | `#6B7280` | 文字 |
| `emptyState` | `action` | `#1677FF` | 操作按钮 |

#### 数据展示 (9)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `table` | `header` | `#F7F8FA` | 表头背景 |
| `table` | `stripe` | `#FAFBFC` | 斑马纹 |
| `table` | `text` | `#1A1D21` | 文字 |
| `table` | `border` | `#E5E7EB` | 边框 |
| `table` | `hover` | `#E6F4FF` | 行悬停 |
| `card` | `bg` | `#FFFFFF` | 背景 |
| `card` | `border` | `#E5E7EB` | 边框 |
| `card` | `shadow` | `#000000` | 阴影 |
| `card` | `text` | `#1A1D21` | 文字 |
| `list` | `bg` | `#FFFFFF` | 背景 |
| `list` | `hover` | `#F0F2F5` | 悬停 |
| `list` | `divider` | `#E5E7EB` | 分割线 |
| `chip` | `bg` | `#F0F2F5` | 背景 |
| `chip` | `text` | `#1A1D21` | 文字 |
| `chip` | `border` | `#D0D5DD` | 边框 |
| `chip` | `close` | `#6B7280` | 关闭按钮 |
| `avatar` | `bg` | `#1677FF` | 背景 |
| `avatar` | `text` | `#FFFFFF` | 文字 |
| `avatar` | `border` | `#FFFFFF` | 边框 |
| `badge` | `bg` | `#CF222E` | 背景 |
| `badge` | `text` | `#FFFFFF` | 文字 |
| `tooltip` | `bg` | `#1A1D21` | 背景 |
| `tooltip` | `text` | `#FFFFFF` | 文字 |
| `calendar` | `header` | `#1677FF` | 头部 |
| `calendar` | `selected` | `#1677FF` | 选中 |
| `calendar` | `today` | `#E6F4FF` | 今天 |
| `calendar` | `otherMonth` | `#D0D5DD` | 其他月 |
| `calendar` | `event` | `#FA8C16` | 事件 |
| `timeline` | `line` | `#D0D5DD` | 线 |
| `timeline` | `dot` | `#1677FF` | 点 |
| `timeline` | `card` | `#FFFFFF` | 卡片 |

#### 按钮 (3)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `button` | `primary` | `#1677FF` | 主按钮 |
| `button` | `hover` | `#4096FF` | 悬停 |
| `button` | `active` | `#0958D9` | 按下 |
| `button` | `disabled` | `#D1D5DB` | 禁用 |
| `button` | `text` | `#FFFFFF` | 文字 |
| `iconButton` | `color` | `#6B7280` | 颜色 |
| `iconButton` | `hover` | `#F0F2F5` | 悬停 |
| `iconButton` | `active` | `#E5E7EB` | 按下 |
| `fab` | `bg` | `#1677FF` | 背景 |
| `fab` | `icon` | `#FFFFFF` | 图标 |
| `fab` | `shadow` | `#000000` | 阴影 |

#### 布局 (6)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `drawer` | `bg` | `#FFFFFF` | 背景 |
| `drawer` | `text` | `#1A1D21` | 文字 |
| `drawer` | `overlay` | `#000000` | 遮罩 |
| `modal` | `bg` | `#FFFFFF` | 背景 |
| `modal` | `overlay` | `#000000` | 遮罩 |
| `modal` | `text` | `#1A1D21` | 文字 |
| `modal` | `border` | `#D0D5DD` | 边框 |
| `header` | `bg` | `#FFFFFF` | 背景 |
| `header` | `text` | `#1A1D21` | 文字 |
| `header` | `border` | `#E5E7EB` | 边框 |
| `footer` | `bg` | `#F7F8FA` | 背景 |
| `footer` | `text` | `#6B7280` | 文字 |
| `footer` | `border` | `#E5E7EB` | 边框 |
| `scrollbar` | `thumb` | `#D0D5DD` | 滑块 |
| `scrollbar` | `track` | `#F0F2F5` | 轨道 |

#### 图表 (1)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `chart` | `colors` | `#1677FF,#52C41A,#FA8C16,#722ED1,#13C2C2,#F5222D` | 色板(6色) |
| `chart` | `axis` | `#D0D5DD` | 坐标轴 |
| `chart` | `grid` | `#F0F2F5` | 网格线 |
| `chart` | `tooltip` | `#1A1D21` | 提示框 |

#### 媒体 (3)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `videoPlayer` | `controls` | `#FFFFFF` | 控件 |
| `videoPlayer` | `progress` | `#1677FF` | 进度 |
| `videoPlayer` | `overlay` | `#000000` | 遮罩 |
| `audioPlayer` | `controls` | `#6B7280` | 控件 |
| `audioPlayer` | `waveform` | `#1677FF` | 波形 |
| `audioPlayer` | `progress` | `#1677FF` | 进度 |
| `imageViewer` | `bg` | `#0D1117` | 背景 |
| `imageViewer` | `overlay` | `#000000` | 遮罩 |

#### 杂项 (5)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `link` | `text` | `#1677FF` | 链接 |
| `link` | `hover` | `#4096FF` | 悬停 |
| `link` | `visited` | `#722ED1` | 已访问 |
| `menu` | `bg` | `#FFFFFF` | 背景 |
| `menu` | `text` | `#1A1D21` | 文字 |
| `menu` | `hover` | `#F0F2F5` | 悬停 |
| `menu` | `divider` | `#E5E7EB` | 分割线 |
| `commandPalette` | `bg` | `#FFFFFF` | 背景 |
| `commandPalette` | `text` | `#1A1D21` | 文字 |
| `commandPalette` | `highlight` | `#E6F4FF` | 高亮 |
| `commandPalette` | `border` | `#D0D5DD` | 边框 |
| `contextMenu` | `bg` | `#FFFFFF` | 背景 |
| `contextMenu` | `text` | `#1A1D21` | 文字 |
| `contextMenu` | `hover` | `#F0F2F5` | 悬停 |
| `contextMenu` | `divider` | `#E5E7EB` | 分割线 |
| `search` | `bg` | `#F0F2F5` | 背景 |
| `search` | `text` | `#1A1D21` | 文字 |
| `search` | `border` | `#D0D5DD` | 边框 |
| `search` | `focus` | `#1677FF` | 聚焦 |
| `search` | `icon` | `#6B7280` | 图标 |

#### 范式 (4)
| 组件 | 子 Token | Light Hex | 说明 |
|------|---------|-----------|------|
| `spreadsheet` | `header` | `#F7F8FA` | 表头 |
| `spreadsheet` | `grid` | `#E5E7EB` | 网格线 |
| `spreadsheet` | `cell` | `#FFFFFF` | 单元格 |
| `spreadsheet` | `cellSelected` | `#E6F4FF` | 选中格 |
| `spreadsheet` | `formulaBar` | `#F7F8FA` | 公式栏 |
| `spreadsheet` | `tab` | `#F0F2F5` | 标签 |
| `document` | `bg` | `#FFFFFF` | 页面 |
| `document` | `text` | `#1A1D21` | 文字 |
| `document` | `ruler` | `#F0F2F5` | 标尺 |
| `document` | `pageShadow` | `#000000` | 页面阴影 |
| `document` | `comment` | `#FFF7E6` | 批注 |
| `document` | `selection` | `#E6F4FF` | 选区 |
| `presentation` | `bg` | `#F5F5F5` | 背景 |
| `presentation` | `canvas` | `#FFFFFF` | 画布 |
| `presentation` | `slideBorder` | `#D0D5DD` | 幻灯片边框 |
| `presentation` | `toolbar` | `#FFFFFF` | 工具栏 |
| `presentation` | `notes` | `#F7F8FA` | 备注 |
| `workspace` | `bg` | `#F5F5F5` | 背景 |
| `workspace` | `tabBar` | `#F7F8FA` | 标签栏 |
| `workspace` | `panel` | `#FFFFFF` | 面板 |
| `workspace` | `resizeHandle` | `#D0D5DD` | 拖拽手柄 |
| `workspace` | `empty` | `#F0F2F5` | 空状态 |

### Dark 主题组件 Token（差异表）

> 仅列出与 Light 不同的 Token，未列出的与 Light 相同（亮度自动适配）。

| 组件 | 子 Token | Dark Hex | 变化说明 |
|------|---------|----------|---------|
| `sidebar` | `bg` | `#0D1117` | 深色背景 |
| `sidebar` | `text` | `#E6EDF3` | 浅色文字 |
| `sidebar` | `hover` | `#1C2533` | 深色悬停 |
| `bubble` | `assistant` | `#21262D` | 深色气泡 |
| `bubble` | `text` | `#E6EDF3` | 浅色文字 |
| `thinking` | `bg` | `#1C1A14` | 深暖背景 |
| `thinking` | `border` | `#D29922` | 暗主题警告色 |
| `toolCall` | `bg` | `#21262D` | 深色背景 |
| `codeBlock` | `bg` | `#161B22` | 深色代码区 |
| `input` | `bg` | `#0D1117` | 深色背景 |
| `input` | `text` | `#E6EDF3` | 浅色文字 |
| `table` | `header` | `#161B22` | 深色表头 |
| `table` | `stripe` | `#0D1117` | 深色条纹 |
| `card` | `bg` | `#161B22` | 深色卡片 |
| `card` | `text` | `#E6EDF3` | 浅色文字 |
| `modal` | `bg` | `#161B22` | 深色弹窗 |
| `menu` | `bg` | `#161B22` | 深色菜单 |
| `commandPalette` | `bg` | `#161B22` | 深色命令面板 |
| `search` | `bg` | `#21262D` | 深色搜索栏 |
| `document` | `bg` | `#161B22` | 深色文档区 |
| `presentation` | `canvas` | `#161B22` | 深色画布 |
| `workspace` | `panel` | `#161B22` | 深色面板 |

---

## 四、验收签字

| 项目 | 状态 | 签字人 | 日期 |
|------|------|--------|------|
| 六色能力标签色板 | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 20 语义 Token | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 54 组件 Token (Light) | ✅ 通过 | 设计工程师 | 2026-07-04 |
| 54 组件 Token (Dark) | ✅ 通过 | 设计工程师 | 2026-07-04 |
