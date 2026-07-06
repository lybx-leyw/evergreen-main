# V2 事件系统契约（Event Contract）

> **版本**: 1.0  
> **状态**: 正式  
> **覆盖范围**: Dart 端 `PageEventBus` + HTML 端 `window.evergreen`

---

## 1. 核心概念

事件系统是页内 slot 间通信的唯一通道。每个页面拥有独立的 `PageEventBus` 实例（Dart）或 `window.evergreen` 全局对象（HTML），**不跨页面、不跨模块、不持久化**。

```
┌─────────────────── Page "learn" ───────────────────┐
│  Slot "left"          Slot "center"    Slot "right" │
│  ┌─────────┐         ┌─────────┐      ┌─────────┐  │
│  │ emit() ─┼───bus──→│ on()    │      │ on()    │  │
│  └─────────┘         └─────────┘      └─────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 2. Manifest 声明

每个 slot 通过 `events` 字段声明自己产生和关注的事件：

```json
{
  "slots": {
    "left": {
      "component": { "type": "type-check" },
      "events": {
        "emit": ["word_completed", "answer_correct"],
        "listen": [
          { "event": "reset_round", "handler": "restart" },
          { "event": "difficulty_changed", "handler": "setDifficulty" }
        ],
        "delegates": {
          "onClick": { "action": "navigate", "target": "learn" },
          "onKeyPress": { "key": "Enter", "action": "submit" }
        }
      }
    }
  }
}
```

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `events.emit` | `string[]` | 否 | 此 slot 会发出的事件名列表 |
| `events.listen` | `{event, handler}[]` | 否 | 此 slot 关注的事件 + 处理函数名 |
| `events.delegates` | `object` | 否 | 交互委托（见 §4） |

---

## 3. Emit / Listen 协议

### 3.1 Dart 端 (`PageEventBus`)

```dart
// ── 发出事件 ──
bus.emit(
  'word_completed',           // 事件名（必须匹配 manifest emit 声明）
  sourceSlot: 'left',         // 发出方 slot 标识
  data: {                     // 附带数据（可选）
    'total': 10,
    'correct': 8,
    'wrong': 2,
  },
);

// ── 订阅事件 ──
final sub = bus.on('word_completed').listen((SlotEvent e) {
  print('${e.sourceSlot} → ${e.event}: ${e.data}');
  // e.sourceSlot = "left"
  // e.event = "word_completed"
  // e.data = {total: 10, correct: 8, wrong: 2}
  // e.timestamp = DateTime
});

// ── 释放 ──
sub.cancel();
bus.dispose(); // 页面切走时自动调用
```

**行为规则**:
- `emit()` 是广播（broadcast），所有 `on()` 订阅者都会收到
- `sourceSlot` 必须是发出方的真实 slot key，用于区分来源
- 事件不排队、不重放——只在发出后通知当前订阅者
- `dispose()` 后不能再 emit/on，所有订阅自动释放

### 3.2 HTML 端 (`window.evergreen`)

```javascript
// ── 发出事件 ──
window.evergreen.emit('word_completed', {
  total: 10,
  correct: 8,
  wrong: 2,
});

// ── 订阅事件（通过 DOM data-listen 属性） ──
// 在 HTML 元素上声明：
// <div data-listen='[{"event":"word_completed","handler":"updateScore"}]'>
//
// 事件到达时，元素会收到 CustomEvent：
element.addEventListener('evg:word_completed', (e) => {
  // e.detail = { total: 10, correct: 8, wrong: 2 }
  updateScore(e.detail);
});
```

**行为规则**:
- `emit()` 遍历所有 `[data-listen]` 元素，匹配 `event` 字段后派发 `CustomEvent`
- 事件名统一加前缀 `evg:` 组成 CustomEvent type
- 未匹配到任何 listener 时静默忽略（不抛异常）
- 事件历史存储在 `window.evergreen.events` 数组中（仅调试，不自动清理）

### 3.3 事件命名规范

| 规则 | 示例 | 说明 |
|------|------|------|
| 小写下划线 | `word_completed` | 事件名一律 snake_case |
| 动词过去式 | `answer_correct`, `card_flipped` | 表示已发生的动作 |
| 语义清晰 | `difficulty_changed` | 明确表达什么变了 |
| 禁止空格/特殊字符 | ❌ `word completed` | 只用 `[a-z0-9_]` |

**保留事件名**（系统级）:

| 事件名 | 发出方 | 说明 |
|--------|--------|------|
| `test_started` | quiz | 测验开始 |
| `test_completed` | quiz | 测验结束（含分数） |
| `question_answered` | quiz | 单题回答 |
| `card_flipped` | flashcards | 闪卡翻转 |
| `card_known` | flashcards | 标记认识 |
| `card_forgotten` | flashcards | 标记忘记 |
| `answer_correct` | type-check | 打字正确 |
| `answer_wrong` | type-check | 打字错误 |
| `word_completed` | type-check | 一轮完成 |
| `reset_round` | (任意) | 重置当前轮次 |

---

## 4. Delegates（交互委托）

Delegates 将 UI 交互映射到声明式动作，无需编写事件处理代码。

### 4.1 声明格式

```json
{
  "events": {
    "delegates": {
      "onClick": { "action": "navigate", "target": "results" },
      "onKeyPress": { "key": "Enter", "action": "submit" },
      "onHover": { "action": "tooltip", "text": "点击查看详情" },
      "propagate": { "event": "selection_changed", "data": { "selected": true } }
    }
  }
}
```

### 4.2 支持的 delegate 类型

| Delegate | 触发条件 | action 值 | 说明 |
|----------|----------|-----------|------|
| `onClick` | 鼠标点击 / 触摸 | `navigate` / `emit` / `toggle` / `submit` | 点击动作 |
| `onKeyPress` | 键盘按键 | `submit` / `navigate` / `emit` | 需指定 `key` |
| `onHover` | 鼠标悬停 | `tooltip` / `highlight` | 视觉反馈 |
| `propagate` | 任意触发 | `emit` | 转发事件到总线 |

### 4.3 action 参数

| action | 必需参数 | 可选参数 | 说明 |
|--------|----------|----------|------|
| `navigate` | `target` (pageId) | — | 切换到指定页面 |
| `emit` | `event` | `data` | 发出事件 |
| `submit` | — | `target` (slotKey) | 触发表单提交 |
| `toggle` | `target` (元素选择器) | — | 切换可见性 |
| `tooltip` | `text` | — | 显示提示文本 |
| `highlight` | — | `color`, `duration` | 高亮闪烁 |

### 4.4 行为规则（两端一致）

- **Dart 端**: `CompositeView` 在构建 slot 时解析 `delegates`，注入 `GestureDetector` / `InkWell`
- **HTML 端**: 在 `wrapSlot()` 中生成 `data-delegates` 属性，由 `_eventJs()` 中的 JS 统一处理
- 未识别的 action → 静默忽略，不抛异常
- 未识别的 delegate 类型 → 静默忽略

---

## 5. 跨端一致性保证

| 行为 | Dart (`PageEventBus`) | HTML (`window.evergreen`) | 一致性 |
|------|----------------------|--------------------------|--------|
| 广播语义 | ✅ `StreamController.broadcast()` | ✅ 遍历所有 `[data-listen]` | ✅ |
| 事件历史 | ❌ 不保存 | ✅ `events[]` 数组（仅调试） | ⚠️ |
| 未匹配静默 | ✅ `Stream.where` 无匹配 | ✅ 不抛异常 | ✅ |
| 生命周期 | ✅ 页面切走 dispose | ✅ 页面关闭自然释放 | ✅ |
| 事件前缀 | 无前缀 | `evg:` 前缀 | ⚠️ 内部细节 |
| 时间戳 | ✅ `DateTime.now()` | ✅ `Date.now()` | ✅ |
| 数据格式 | `Map<String, dynamic>` | JSON-serializable object | ✅ |

---

## 6. 测试检查清单

- [ ] emit → on: 同一事件名能正确路由
- [ ] 多订阅者: 一个 emit 通知所有 on
- [ ] 事件隔离: 不同事件名不互相干扰
- [ ] 释放: dispose 后 emit 不报错
- [ ] 空 listeners: emit 无匹配时静默成功
- [ ] delegates: onClick → navigate 正确切换页面
- [ ] 未知 action: 不崩溃
- [ ] 跨 slot: left slot emit → right slot on 收到
