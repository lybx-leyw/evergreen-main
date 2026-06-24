# 架构总览 — Evergreen Multi-Tools v1.3.1

> Flutter 桌面应用 · 浙江大学多功能集成工具  
> 17 个功能模块 · Riverpod 状态管理 · 自研 Agent 运行时 · Palace 认知中间件

---

## 1. 项目定位

一个面向浙大学生的 **Windows/macOS/Linux 桌面应用**，集成课程管理、成绩追踪、智云课堂、AI 笔记、智能调度、一卡通、自动签到、背词等功能。底层使用自研的 **Agent 运行时**（Reasonix 的 Dart 复刻），驱动 AI 助手处理自然语言查询。

## 2. 分层架构

```
┌──────────────────────────────────────────────────────────────┐
│  UI Layer (widgets/ + 各 feature 的 screens/)               │
│  GoRouter (app.dart) · Sidebar · Dashboard · PalaceScreen   │
├──────────────────────────────────────────────────────────────┤
│  Feature Layer (features/*/)                                │
│  providers/  →  services/  →  screens/  + widgets/          │
├──────────────────────────────────────────────────────────────┤
│  Palace Core (core/palace/)       ← 认知中间件（新增）        │
│  采集管线 · AI 分析 · 教训冶炼 · 认知回响                     │
├──────────────────────────────────────────────────────────────┤
│  Agent Runtime (core/agent/)                                │
│  Agent · Session · Provider(LLM) · Tool · Registry          │
├──────────────────────────────────────────────────────────────┤
│  Core Infrastructure (core/)                                │
│  Network(Dio+Interceptors) · Storage · Config · Models       │
├──────────────────────────────────────────────────────────────┤
│  External: DeepSeek API · ZJU SSO · ZDBK · 智云课堂          │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 层级间依赖规则

- **UI 层** 只能依赖 Feature 层和 Widgets 层，不直接访问 Core 的 `dio`/`httpClient`
- **Feature 层** 通过 Provider 暴露数据，内部 Service 可访问 Core 的 `dio`/`httpClient`/`AppConfig`
- **Palace Core** 横切所有 Feature，从 Agent 对话和用户手动输入中采集认知事件。通过 `CaptureToPalaceTool` 注册到 Agent 运行时，不修改其核心循环
- **Agent 运行时** 独立于 Feature 层，通过 `ZjuDataSource` 接口与业务数据解耦
- **Core 基础设施** 不依赖任何 Feature 或 UI 代码

## 3. 目录结构

```
lib/
├── main.dart                      # 入口：MediaKit 初始化 → 窗口配置 → runApp
├── app.dart                       # MaterialApp.router + 主题 + 自动登录
│
├── core/                          # ── 基础设施层（上游，零业务依赖）──
│   ├── config/
│   │   ├── app_config.dart        #   配置管理：.env / 环境变量 / SharedPreferences
│   │   └── theme.dart             #   主题定义（5 套变体）
│   ├── models/
│   │   ├── grade.dart             #   成绩模型 + GPA 多制式换算
│   │   ├── course_offering.dart   #   开课情况模型
│   │   ├── exam.dart              #   考试模型
│   │   └── timetable_session.dart #   课表 session 模型
│   ├── network/
│   │   ├── dio_client.dart        #   Dio 实例 + CookieJar + 拦截器链
│   │   ├── auth_interceptor.dart  #   会话过期检测 + 自动重登
│   │   ├── cookie_manager.dart    #   旧版 CookieStore（JSON 持久化）
│   │   ├── debug_interceptor.dart #   调试日志拦截器
│   │   └── retry_interceptor.dart #   指数退避重试
│   ├── storage/
│   │   ├── database.dart          #   文件缓存（WebCacheDatabase）
│   │   ├── cache_manager.dart     #   缓存管理
│   │   └── settings_service.dart  #   设置持久化服务
│   ├── utils/
│   │   ├── gpa_calculator.dart    #   GPA 计算器（4 种制式）
│   │   ├── date_utils.dart        #   日期工具
│   │   ├── html_parser.dart       #   HTML 解析（CAS 页面检测等）
│   │   ├── token_estimator.dart   #   Token 估算
│   │   ├── python_env.dart        #   Python 子进程管理 + OCR 依赖
│   │   └── auto_refresh.dart      #   全局自动刷新（定时 + 打开页面）
│   ├── palace/                    #   ── Palace 认知中间件 ──
│   │   ├── palace.dart            #     库入口
│   │   ├── models/                #     数据模型（事件/教训/情境快照）
│   │   ├── storage/               #     文件存储（EventStore + 三重索引）
│   │   ├── capture/               #     事件采集（情境采集 + 快速捕捉）
│   │   ├── refinery/              #     AI 分析（教训提取/追问生成/标签）
│   │   └── tools/                 #     Agent 工具（capture_to_palace）
│   └── agent/                     #   ── Agent 运行时 ──
│       ├── agent.dart             #     库入口（统一导出）
│       ├── message.dart           #     消息数据模型
│       ├── event.dart             #     17 种类型化事件 + Sink
│       ├── tool.dart              #     Tool 接口 + Registry
│       ├── provider.dart          #     LLM Provider + DeepSeek 实现
│       ├── agent/
│       │   ├── agent.dart         #       Agent 主循环
│       │   ├── session.dart       #       会话管理
│       │   ├── compose.dart       #       消息组装
│       │   ├── gate.dart          #       权限门控
│       │   └── hooks.dart         #       工具钩子
│       ├── controller/            #     会话驱动器
│       ├── memory/                #     四类记忆 + 文件存储
│       ├── skill/                 #     技能加载器
│       ├── output_style/          #     输出风格系统
│       ├── evidence/              #     工具调用证据
│       ├── compact/               #     上下文压实
│       └── tools/                 #     内置 ZJU 工具
│           ├── zju_data_source.dart   #  ZjuDataSource 接口
│           ├── zju_courses.dart       #  课程查询工具
│           ├── zju_scores.dart        #  成绩查询工具
│           ├── zju_classroom.dart     #  智云课堂工具
│           ├── zju_ecard.dart         #  一卡通工具
│           ├── zju_todos.dart         #  待办工具
│           ├── zju_exams.dart         #  考试工具
│           ├── zju_timetable.dart     #  课表工具
│           ├── zju_notifications.dart #  教务通知工具
│           ├── user_info.dart         #  用户个人信息工具
│           ├── semester_info.dart     #  学期信息工具
│           └── web_search.dart        #  联网搜索工具
│
├── features/                      # ── 功能模块层 ──
│   ├── auth/                      #    统一认证（SSO RSA 登录）
│   ├── zdbk/                      #    教务系统（成绩/课表/开课情况/通知公告）
│   ├── courses/                   #    课程列表
│   ├── classroom/                 #    智云课堂（视频 + PPT）
│   ├── scores/                    #    成绩展示 + GPA
│   ├── exams/                     #    考试安排
│   ├── todo/                      #    待办事项
│   ├── library/                   #    图书馆
│   ├── ecard/                     #    一卡通
│   ├── teachers/                  #    查老师
│   ├── quiz/                      #    答题
│   ├── autosign/                  #    自动签到
│   ├── rvpn/                      #    RVPN 代理
│   ├── schedule/                  #    课表导出（iCal）
│   ├── scheduler/                 #    智能调度（Flow）
│   ├── tutor/                     #    AI 笔记 + DeepSeek 对话
│   ├── agent/                     #    AI 助手聊天界面
│   ├── translate/                 #    PDF 翻译（DeepSeek + pdf2zh 引擎）
│   ├── wordpecker/                #    背词（FSRS 算法）
│   ├── downloads/                 #    课件下载管理
│   ├── plan/                      #    计划管理（多计划 + 周时间表）
│   ├── palace/                     #    个人世界宫殿（PalaceCore 认知中间件 UI）
│   └── settings/                  #    设置界面
│
├── widgets/                       # ── 共享 UI 组件 ──
│   ├── sidebar.dart               #    导航侧栏 / 底部导航
│   ├── dashboard.dart             #    仪表盘
│   ├── empty_state.dart           #    空状态占位
│   ├── error_card.dart            #    错误卡片
│   ├── loading_indicator.dart     #    加载指示器
│   └── mindmap_widget.dart        #    思维导图组件
│
├── assets/
│   ├── prompts/                   #    AI 提示词模板
│   ├── icons/                     #    图标资源
│   └── data/teacher_ratings.json  #    教师评分数据
│
└── test/
    ├── widget_test.dart
    ├── agent_test.dart
    ├── core/utils/
    └── features/
        ├── auth/
        ├── tutor/
        └── zdbk/
```

## 4. 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 框架 | Flutter 3.9+ (Dart) | 跨平台桌面应用 |
| 状态管理 | flutter_riverpod ^2.6 | Provider 模式 |
| 路由 | go_router ^14.0 | ShellRoute + 自定义过渡 |
| HTTP | Dio ^5.9 + cookie_jar ^4.0 | 拦截器链 + Cookie 持久化 |
| 存储 | Drift ^2.21 + SharedPreferences ^2.3 | SQLite + KV |
| 视频 | media_kit ^1.2 | 跨平台播放器（libmpv/ExoPlayer/AVPlayer） |
| LLM | DeepSeek API | Chat Completions + Function Calling |
| 加密 | pointycastle ^3.9 | RSA 加密（SSO 登录） |

## 5. 关键设计决策

### 5.1 双 HTTP 客户端

- **`dart:io HttpClient`**（`httpClientProvider`）：用于 SSO 认证流程和 ZDBK 服务。精确控制 cookie 和重定向，避免 Dio 的 CookieManager 导致的 cookie 累积 bug。
- **`Dio`**（`dioClientProvider`）：用于其他所有 HTTP 请求。内置拦截器链：Debug → CookieManager → Auth → Retry。

### 5.2 Agent 运行时是 Reasonix 的 Dart 复刻

`core/agent/` 目录是一个自研的 LLM Agent 框架，完整实现了：

- **Agent Loop**：compose → LLM call → tool execute → loop → final readiness
- **Provider 抽象**：DeepSeek 流式调用，支持 reasoning_content + tool_calls
- **Tool Registry**：内置工具注册 + 启用/禁用 + 批量 schema 生成
- **Session**：消息历史管理 + token 统计
- **Gate**：权限门控（工具调用前检查）
- **StormBreaker**：检测重复失败的工具调用模式
- **Compact**：上下文压实（三档阈值）

### 5.3 ZjuDataSource 解耦

Agent 工具通过 `ZjuDataSource` 接口获取数据，Flutter 层通过 Provider 注入实现。这样工具层不依赖 Riverpod，可独立测试。

### 5.4 自动登录链

启动时 `app.dart` 的 `_triggerAutoLogin` 串联三个服务：

1. **ZJU SSO** → 获取 `iPlanetDirectoryPro` cookie
2. **ZDBK** → CAS service validation → JSESSIONID
3. **Courses** → Keycloak 重定向链 → courses session cookie
4. **Classroom** → OAuth2 重定向链 → 跨四个域的 cookies

任一失败不影响其他，静默降级。

## 6. 上游基础 vs 下游功能

### 上游（不依赖任何 Feature）

| 模块 | 路径 | 职责 |
|---|---|---|
| AppConfig | `core/config/app_config.dart` | 配置加载，3 层优先级 |
| DioClient | `core/network/dio_client.dart` | HTTP 客户端工厂 |
| AuthInterceptor | `core/network/auth_interceptor.dart` | 会话过期自动重登 |
| WebCacheDatabase | `core/storage/database.dart` | 文件缓存 |
| SettingsService | `core/storage/settings_service.dart` | 设置持久化 |
| GpaCalculator | `core/utils/gpa_calculator.dart` | 4 制式 GPA 计算 |
| HtmlParser | `core/utils/html_parser.dart` | HTML 解析工具 |
| Grade/Models | `core/models/` | 共享数据模型 |
| Agent Runtime | `core/agent/` | LLM Agent 框架 |
| Shared Widgets | `widgets/` | 可复用 UI |

### 中游（被多个 Feature 依赖）

| 模块 | 被依赖方 |
|---|---|
| Auth（authProvider） | zdbk, courses, classroom, library, ecard, scores, exams, todo, teachers, autosign, schedule, quiz |
| ZdbkService | scores, exams, schedule, scheduler |
| CookieJar | 所有通过 Dio 发送 ZJU 请求的 Feature |

### 下游（叶子 Feature）

| 模块 | 依赖 |
|---|---|
| downloads | auth, courses |
| rvpn | auth |
| scheduler | zdbk (timetable) |
| wordpecker | 独立（仅依赖本地词典 + DeepSeek） |
| palace | Agent Runtime (DeepSeekProvider共享 + CaptureToPalaceTool) · AppConfig · EventStore(文件I/O) |
| tutor | AppConfig (DeepSeek API key) |
| agent | ZjuDataSource 实现（由上层注入） |
| translate | AppConfig (DeepSeek API key) · Python pdf2zh 引擎 |
