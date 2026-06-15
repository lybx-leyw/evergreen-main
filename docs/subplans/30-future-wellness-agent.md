# 30 — 远期：心理陪聊版 Agent

**层级：** 远期 | **依赖：** 23 Agent 多会话记忆 | **关联：** GOAL-01

## 目标

在工具版 Agent 基础设施上，构建基于心理学原理的陪聊版 Agent。

## 共用基础设施（来自 23）

- Agent 运行时 + Session + Provider + Registry
- 多会话 UI 壳
- `MemoryFacade`（按 persona 隔离）
- `AgentPersona` 扩展点

## 分化层

| 维度 | 工具版 | 陪聊版 |
|---|---|---|
| System prompt | 浙大教学助手 | 温暖、共情、非评判倾听者 |
| 工具集 | 8 个 ZJU 业务工具 | 6 个心理学工具（心情记录、认知重构、压力评估、感恩练习、呼吸引导、对话反思） |
| 输出风格 | explanatory | companion（口语化、温暖） |
| UI 色调 | 通用 | 暖色调变体 |

## 实施步骤

- [ ] ① 与心理学专业同学协作设计 system prompt + 工具集
- [ ] ② 实现陪聊版 `AgentPersona` + 心理学工具
- [ ] ③ 新增陪聊 `ChatScreen`（复用对话组件）
- [ ] ④ 侧栏 persona 切换入口
- [ ] ⑤ A/B 测试陪聊质量，迭代 prompt

## 验收

- [ ] 新建陪聊对话 → Agent 以温暖口语风格回应
- [ ] 用户说"今天心情不好" → Agent 调用 `record_mood` 工具
- [ ] 工具响应标注"非诊断、非治疗"免责声明
