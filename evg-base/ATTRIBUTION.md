# 致谢与开源许可

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | 开源合规 |

Evergreen Base 建立在以下开源项目的基础上。

---

## Reasonix → Greenix — Agent 运行时

- **上游项目**: Reasonix — AI 编码助手的 Agent 运行时（Go 实现）
- **仓库**: https://github.com/esengine/reasonix
- **许可证**: MIT License

Evergreen Base 的 AI 助手内核命名为 **Greenix**——参考 Reasonix 架构，以 Dart 复刻核心逻辑。

| 模块 | 对应 Reasonix 源 |
|---|---|
| `message.dart` | `internal/provider/provider.go` |
| `event.dart` | `internal/event/event.go` |
| `tool.dart` | `internal/tool/` |
| `provider.dart` | `internal/provider/` |
| `agent/agent.dart` | `internal/agent/agent.go` |
| `agent/session.dart` | `internal/agent/session.go` |
| `agent/compose.dart` | `internal/control/` |
| `controller/` | `internal/control/controller.go` |
| `memory/` | `internal/memory/` |
| `skill/` | `internal/skill/` |
| `compact/` | `internal/agent/compact.go` |

每个移植模块的文件头部保留了指向 Reasonix 原始 Go 源的文档注释。

---

## 第三方依赖

| 依赖 | 许可证 |
|---|---|
| flutter (BSD-3-Clause) | 应用框架 |
| flutter_riverpod (MIT) | 状态管理 |
| go_router (BSD-3-Clause) | 路由 |
| dio (MIT) | HTTP 客户端 |
| media_kit (MIT) | 视频播放 |
| 其余依赖 | 见各包 LICENSE |

---

## 许可证

**Evergreen Base** 以 **GNU General Public License v3.0 (GPL-3.0)** 发布。

```
Evergreen Base
Copyright (C) 2024-2026  Evergreen Base 贡献者

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

*最后更新：2026-06*
