# 模块速查手册 — Evergreen Multi-Tools v1.3.1

> 每个模块的职责、依赖、入口、关键文件

---

## Core 层 — 上游基础

### AppConfig

| 项目 | 内容 |
|---|---|
| 路径 | `core/config/app_config.dart` |
| 职责 | 应用配置管理：3 层优先级加载（环境变量 > .env > SharedPreferences） |
| 上游依赖 | 无（纯静态工具类） |
| 下游消费者 | auth（凭证）· tutor（API key）· settings（读写）· downloads（路径） |
| 入口 | `AppConfig.initialize()`（main.dart 调用） |
| 关键方法 | `initialize()`, `set(key, value)`, `saveToEnvFile()` |
| 配置项 | `ZJU_USERNAME`, `ZJU_PASSWORD`, `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL`, `DEEPSEEK_THINKING`, `DEEPSEEK_OCR_API_KEY`, `PTA_SESSION`, `DINGTALK_WEBHOOK`, `MATERIAL_DOWNLOAD_PATH`, `VIDEO_OPENER`, `TRANSLATE_LANG_OUT`, `TRANSLATE_LANG_IN`, `PYTHON_EXE`, `STUDENT_GRADE`, `STUDENT_MAJOR`, `STUDENT_MINOR`, `PERSONAL_TRAINING_PLAN_OCR`, `OTHER_TRAINING_PLAN_OCR`, `AUTO_REFRESH_ENABLED`, `AUTO_REFRESH_INTERVAL` |

### Theme

| 项目 | 内容 |
|---|---|
| 路径 | `core/config/theme.dart` |
| 职责 | 5 套主题变体：system / light / dark / evergreen / liyu |
| 上游依赖 | Material Design |
| 下游消费者 | `app.dart` (EvergreenApp) |

### DioClient

| 项目 | 内容 |
|---|---|
| 路径 | `core/network/dio_client.dart` |
| 职责 | 创建配置好的 Dio HTTP 客户端（含拦截器链 + CookieJar） |
| 上游依赖 | `dio`, `dio_cookie_manager`, `cookie_jar` |
| 下游消费者 | 所有通过 Dio 发请求的 Feature |
| 出口 Provider | `dioClientProvider`, `cookieJarProvider` |
| 拦截器链 | DebugInterceptor → CookieManager → AuthInterceptor → RetryInterceptor |

### AuthInterceptor

| 项目 | 内容 |
|---|---|
| 路径 | `core/network/auth_interceptor.dart` |
| 职责 | 拦截 ZJU 会话过期（302 / 登录页 HTML），触发自动重登后重试原请求 |
| 上游依赖 | `dio`, `cookie_jar`, `HtmlParser` |
| 下游消费者 | 所有通过 Dio 发 ZJU 请求的 Feature（透明拦截） |
| 静态回调 | `AuthInterceptor.onRelogin` — 由 `auth_provider.dart` 设置 |
| 关键常量 | `_maxReloginAttempts = 2` |

### CookieManager（旧版）

| 项目 | 内容 |
|---|---|
| 路径 | `core/network/cookie_manager.dart` |
| 职责 | SSO cookie 的 JSON 文件持久化（`CookieStore`），被 `auth_provider.dart` 使用 |
| 关键方法 | `getSsoCookie()`, `setSsoCookie()`, `clearSsoCookie()` |

### WebCacheDatabase

| 项目 | 内容 |
|---|---|
| 路径 | `core/storage/database.dart` |
| 职责 | ZDBK API 响应的文件缓存（JSON 文件，非 SQLite） |
| 消费者 | `ZdbkService`（zdbk feature） |
| 关键方法 | `setCachedWebPage(key, jsonString)`, `getCachedWebPage(key)`, `getCachedList(key)`, `clearAll()` |

### PythonEnv

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/python_env.dart` |
| 职责 | Python 子进程执行（`runOcrProcess`）+ 依赖管理（`PythonEnv`）——OCR + PDF 翻译 |
| 下游消费者 | notes_provider, chat_screen, agent_provider（OCR 脚本调用）；pdf_translate_service（翻译子进程） |
| 关键方法 | `runOcrProcess()`, `PythonEnv.ensureReady()`, `PythonEnv.checkDeps()`, `checkPdf2zhDeps()`, `installPdf2zhDeps()`, `ensurePdf2zhReady()` |

### AutoRefresh

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/auto_refresh.dart` |
| 职责 | 全局自动刷新管理：后台定时刷新 + 页面打开时刷新，受用户设置控制 |
| 关键函数 | `initAutoRefresh()`, `shouldRefresh()`, `restartAutoRefresh()` |
| 设置项 | `AUTO_REFRESH_ENABLED`, `AUTO_REFRESH_INTERVAL` |

### SettingsService

| 项目 | 内容 |
|---|---|
| 路径 | `core/storage/settings_service.dart` |
| 职责 | 设置持久化（SharedPreferences + .env 双写） |
| 上游依赖 | `AppConfig` |
| 下游消费者 | `features/settings/` |
| 出口 Provider | `settingsServiceProvider` |

### GpaCalculator

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/gpa_calculator.dart` |
| 职责 | 4 种 GPA 制式计算：5.0 / 4.3 / 4.0 / 百分制 |
| 上游依赖 | `core/models/grade.dart` (Grade) |
| 关键方法 | `calculateGpa()`, `calculateWeightedGpa()`, `pickFirstAttempt()`, `pickHighestAttempt()` |

### HtmlParser

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/html_parser.dart` |
| 职责 | HTML 解析工具：CAS 登录页检测、execution token 提取等 |
| 消费者 | `AuthInterceptor`, `ZjuAmService` |

### DateUtils

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/date_utils.dart` |
| 职责 | 学期日期计算、工作日判断等 |

### TokenEstimator

| 项目 | 内容 |
|---|---|
| 路径 | `core/utils/token_estimator.dart` |
| 职责 | Token 数量估算（用于上下文压实判断） |

### Palace Core — 认知中间件

| 项目 | 内容 |
|---|---|
| 路径 | `core/palace/` |
| 职责 | 认知事件采集、AI 分析、教训冶炼。横切所有 Feature 的平台层 |
| 上游依赖 | Agent Runtime (DeepSeekProvider/Tool) |
| 下游消费者 | `features/palace/`（UI 层）· Agent 工具注册（`agent_provider.dart`） |
| 入口 | `palace.dart`（库入口） |
| 子模块 | `models/`（事件/教训/情境快照模型）· `storage/`（EventStore + 三重索引）· `capture/`（采集管线）· `refinery/`（AI 分析：教训提取/追问/标签）· `tools/`（capture_to_palace Agent 工具） |
| 存储 | `.greenix/palace/events/`（事件文件 + EVENTS_BY_DATE/TYPE/TAG.md 索引）· `.greenix/palace/lessons/`（教训文件） |
| 测试 | `test/core/palace/`（模型序列化 · EventStore CRUD · 情境采集 · AI 解析） |

---

## Core Models — 共享数据模型

### Grade

| 项目 | 内容 |
|---|---|
| 路径 | `core/models/grade.dart` |
| 消费者 | GpaCalculator, ZdbkService, ScoresScreen, Agent tools |
| 关键字段 | `fivePoint`（ZDBK 权威 `jd` 绩点）, `hundredPoint`, `fourPointGpa`, `fourPointLegacyGpa` |
| 构造器 | `Grade.fromJson()` — 从 ZDBK API 解析<br>`Grade.fromScoresJson()` — 从 Scores feature 解析 |
| 注意 | `fivePoint` 是 double，不是 int — 保留 ZDBK 的精度（如 4.8） |

### CourseOffering

| 项目 | 内容 |
|---|---|
| 路径 | `core/models/course_offering.dart` |
| 消费者 | ZdbkService, CourseOfferingsScreen |
| 关键字段 | `courseCode`, `courseName`, `teacher`, `schedule`, `location`, `credits` |

### Exam

| 项目 | 内容 |
|---|---|
| 路径 | `core/models/exam.dart` |
| 消费者 | ExamsScreen, ExamsProvider, Agent tools |

### TimetableSession

| 项目 | 内容 |
|---|---|
| 路径 | `core/models/timetable_session.dart` |
| 消费者 | ScheduleService (iCal export), SchedulerService |

### ZdbkNotification

| 项目 | 内容 |
|---|---|
| 路径 | `core/models/zdbk_notification.dart` |
| 消费者 | ZdbkNotificationsScreen, Agent tools |
| 关键函数 | `parseZdbkNotifications()` — 从 ZDBK HTML 解析通知列表 |

---

## Core Agent Runtime — AI 引擎

### 入口

| 项目 | 内容 |
|---|---|
| 路径 | `core/agent/agent.dart`（库入口，统一导出所有子模块） |

### Message

| 路径 | `core/agent/message.dart` |
|---|---|
| 职责 | 对话消息模型：user / assistant / system / tool |
| 关键类 | `Message`, `Role`, `ToolCall` |

### Event

| 路径 | `core/agent/event.dart` |
|---|---|
| 职责 | 17 种类型化事件（AgentEvent）+ EventSink |

### Tool

| 路径 | `core/agent/tool.dart` |
|---|---|
| 职责 | Tool 接口 + Registry + BuiltinRegistry + schema 导出 |
| 关键类 | `Tool`（抽象接口）, `Registry`, `BuiltinRegistry`, `Previewer`（mixin） |

### Provider

| 路径 | `core/agent/provider.dart` |
|---|---|
| 职责 | LLM Provider 抽象 + DeepSeek 流式实现 |
| 关键类 | `Provider`（抽象）, `DeepSeekProvider`（具体实现） |
| 支持特性 | reasoning_content, tool_calls delta 合并, 自动重试（429/502/503） |

### Agent

| 路径 | `core/agent/agent/agent.dart` |
|---|---|
| 职责 | Agent 主循环：compose → LLM call → tool execute → loop → readiness |
| 关键类 | `Agent`, `AgentOptions`, `Gate`, `ToolHooks`, `StormBreaker`, `FinalReadiness` |
| 流程 | `run(input)` → Stream\<AgentEvent\> |

### Session

| 路径 | `core/agent/agent/session.dart` |
|---|---|
| 职责 | 会话管理：消息历史、token 统计、JSON 序列化 |

### Compose

| 路径 | `core/agent/agent/compose.dart` |
|---|---|
| 职责 | 消息组装：系统提示词 + 工具定义 + 会话历史 → LLM 请求消息列表 |

### 子模块

| 子模块 | 路径 | 职责 |
|---|---|---|
| controller | `core/agent/controller/` | 会话驱动器（传输无关） |
| memory | `core/agent/memory/` | 四类记忆 + 文件存储 + MEMORY.md 索引 |
| skill | `core/agent/skill/` | 技能加载器 + 索引 + 内置技能 |
| output_style | `core/agent/output_style/` | 输出风格：explanatory/learning/concise/socratic |
| evidence | `core/agent/evidence/` | 工具调用证据分类账本 |
| compact | `core/agent/compact/` | 上下文压实（三档阈值） |

### 内置工具

| 工具 | 路径 | ZjuDataSource 方法 |
|---|---|---|
| get_courses | `tools/zju_courses.dart` | `getCourses()` |
| get_scores | `tools/zju_scores.dart` | `getScores()` |
| get_classroom_courses | `tools/zju_classroom.dart` | `getClassroomCourses()` |
| get_ecard_balance | `tools/zju_ecard.dart` | `getEcardBalance()` |
| get_todos | `tools/zju_todos.dart` | `getTodos()` |
| get_exams | `tools/zju_exams.dart` | `getExams()` |
| get_timetable | `tools/zju_timetable.dart` | `getTimetable()` |
| get_notifications | `tools/zju_notifications.dart` | `getNotifications()` |
| get_user_info | `tools/user_info.dart` | 无（读取 SharedPreferences） |
| get_semester_info | `tools/semester_info.dart` | 无（纯计算） |
| web_search / web_fetch | `tools/web_search.dart` | 无（DeepSeek 联网） |

---

## Features 层 — 功能模块

### Auth — 统一认证

| 项目 | 内容 |
|---|---|
| 路径 | `features/auth/` |
| 职责 | ZJU SSO RSA 登录 · 会话恢复 · cookie 验证 · 自动登录 |
| 入口 Provider | `authProvider` |
| 依赖 | `AppConfig`（凭证）· `ZjuAmService`（RSA）· `CookieStore`（持久化） |
| 被依赖 | **所有** ZJU Feature |
| 关键文件 | `providers/auth_provider.dart` — AuthNotifier（login/restoreSession/ensureAuth）<br>`services/zjuam_service.dart` — RSA 加密 + CAS 登录<br>`screens/` — 登录界面 |
| 出口 | `httpClientProvider`（被所有 ZJU 服务复用）<br>`authProvider` 的 `AuthState.ssoCookie` |

### ZDBK — 教务系统

| 项目 | 内容 |
|---|---|
| 路径 | `features/zdbk/` |
| 职责 | 成绩查询 · 课表 · 开课情况 · 考试安排 · 通知公告的底层数据源 |
| 入口 Provider | `zdbkServiceInstanceProvider` |
| 依赖 | `authProvider`（ssoCookie）· `httpClientProvider` · `WebCacheDatabase` |
| 被依赖 | scores, exams, schedule, scheduler, Agent tools |
| 关键文件 | `services/zdbk_service.dart` — 核心 API 调用<br>`providers/zdbk_provider.dart` — 多个 FutureProvider（everything/transcript/exams/courseOfferings/timetable）<br>`screens/zdbk_notifications_screen.dart` — 通知公告页 |
| 缓存 | 通过 `WebCacheDatabase` 缓存所有 API 响应 |
| 认证 | 需 ZDBK 独立 CAS service validation 获取 JSESSIONID |

### Courses — 课程列表

| 项目 | 内容 |
|---|---|
| 路径 | `features/courses/` |
| 职责 | 展示当前学期课程 · 课程详情 |
| 入口 Provider | `coursesProvider` |
| 依赖 | `authProvider` · `courses.zju.edu.cn` session cookie |

### Classroom — 智云课堂

| 项目 | 内容 |
|---|---|
| 路径 | `features/classroom/` |
| 职责 | 课程视频播放 · PPT 幻灯片查看 · 字幕时间轴 |
| 入口 Provider | `classroomProvider` |
| 依赖 | `authProvider` · `media_kit`（视频播放） |
| 特色 | `ppt_viewer.dart` + OCR（external Python exe）· `subtitle_timeline.dart` · `video_player_panel.dart` |
| 模型 | `ppt_slide.dart`, `subtitle.dart` |
| 认证 | 需 OAuth2 重定向链（tgmedia → ZJUAM → classroom） |

### Scores — 成绩

| 项目 | 内容 |
|---|---|
| 路径 | `features/scores/` |
| 职责 | 成绩展示 · GPA 计算 · 图表 |
| 入口 Provider | `scoresProvider` |
| 依赖 | `ZdbkService` · `GpaCalculator` · `Grade` |

### Exams — 考试

| 项目 | 内容 |
|---|---|
| 路径 | `features/exams/` |
| 职责 | 考试倒计时 · 考试安排列表 |
| 入口 Provider | `examsProvider` |
| 依赖 | `ZdbkService` · `Exam` 模型 |

### Todo — 待办

| 项目 | 内容 |
|---|---|
| 路径 | `features/todo/` |
| 职责 | 作业/待办管理 · 钉钉 webhook 提醒 |
| 入口 Provider | `todoProvider` |
| 依赖 | `authProvider`（courses.zju.edu.cn 抓取） |

### Library — 图书馆 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/library/` |
| 职责 | 借阅查询 · 续借 |
| 入口 Provider | `libraryProvider` |
| 依赖 | `authProvider` · `library_service.dart` |

### Ecard — 一卡通 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/ecard/` |
| 职责 | 余额查询 · 消费记录 |
| 入口 Provider | `ecardProvider` |
| 依赖 | `authProvider` · 推测性 API（成功率低） |

### Teachers — 查老师

| 项目 | 内容 |
|---|---|
| 路径 | `features/teachers/` |
| 职责 | 教师评分查询 · 搜索 |
| 入口 Provider | `teachersProvider` |
| 依赖 | `authProvider` · `chalaoshi_service.dart` |
| Agent 工具 | `tools/search_teacher.dart` |

### Quiz — 答题 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/quiz/` |
| 职责 | 在线答题辅助 |
| 依赖 | `authProvider`（pintia cookie） |

### Autosign — 自动签到 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/autosign/` |
| 职责 | 定时签到 · 签到状态 |
| 依赖 | `authProvider` |

### RVPN — 代理 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/rvpn/` |
| 职责 | 校外访问校内资源（zju-connect 代理） |
| 依赖 | `authProvider` · 外部 zju-connect.exe |

### Schedule — 课表导出

| 项目 | 内容 |
|---|---|
| 路径 | `features/schedule/` |
| 职责 | 课表 iCal 导出 |
| 依赖 | `ZdbkService`（timetable） |
| 关键文件 | `services/ical_exporter.dart` — iCal 格式生成 |

### Scheduler — 智能调度 ⚠️ 暂停

| 项目 | 内容 |
|---|---|
| 路径 | `features/scheduler/` |
| 职责 | 基于 Flow 的智能任务调度 |
| 依赖 | `ZdbkService`（timetable） |
| 关键文件 | `services/flow_scheduler.dart` |

### Tutor — AI 笔记

| 项目 | 内容 |
|---|---|
| 路径 | `features/tutor/` |
| 职责 | AI 对话笔记 · PPT OCR · DeepSeek 问答 |
| 入口 Provider | `tutorProvider`, `notesProvider` |
| 依赖 | `AppConfig`（DeepSeek API key）· `DeepSeekClient` |
| 关键文件 | `services/deepseek_client.dart` — DeepSeek API 流式调用<br>`screens/notes_screen.dart` — 笔记编辑<br>`screens/tutor_screen.dart` — AI 对话 |

### Agent Chat — AI 助手

| 项目 | 内容 |
|---|---|
| 路径 | `features/agent/` |
| 职责 | 自然语言 AI 助手（使用 Agent 运行时） |
| 入口 Provider | `agentProvider` |
| 依赖 | `core/agent/`（全套 Agent 运行时）· `DeepSeekProvider` · 所有 ZJU Tools |
| 关键文件 | `chat_screen.dart` — 聊天 UI<br>`providers/agent_provider.dart` — Agent 实例管理 |

### Translate — PDF 翻译

| 项目 | 内容 |
|---|---|
| 路径 | `features/translate/` |
| 职责 | DeepSeek API 驱动的 PDF 翻译，输出保留排版、公式、图表的双语对照 PDF |
| 入口 Provider | `translateJobProvider`, `translateBatchProvider`, `translateHistoryProvider` |
| 依赖 | `AppConfig`（DeepSeek API key）· `PdfTranslateService` · `PythonEnv` |
| 关键文件 | `screens/translate_screen.dart` — 翻译界面（选文件、语言、进度、历史）<br>`providers/translate_provider.dart` — 状态管理（单文件/批量/历史）<br>`widgets/pdf_preview_widget.dart` — 内嵌 PDF 预览（pdfrx）<br>`core/services/pdf_translate_service.dart` — Python 子进程管理<br>`scripts/pdf_translate.py` — 翻译子进程脚本<br>`scripts/pdf2zh_next/` — pdf2zh 引擎源码 |
| 外部依赖 | Python 3.10+ · babeldoc · pymupdf · openai |
| 平台 | Windows（桌面端完整支持）· Android（标记开发中） |

### WordPecker — 背词

| 项目 | 内容 |
|---|---|
| 路径 | `features/wordpecker/` |
| 职责 | 基于 FSRS 算法的间隔重复背词 · AI 词源分析 |
| 入口 Provider | `wordpeckerProvider` |
| 依赖 | `AppConfig`（DeepSeek API key）· 本地词典 JSON |
| 模型 | `fsrs_card.dart`, `word_entry.dart` |
| 关键文件 | `services/fsrs_service.dart` — FSRS 调度算法<br>`services/dictionary_service.dart` — 词典服务<br>`services/etymology_service.dart` — 词源分析 |

### Downloads — 下载管理

| 项目 | 内容 |
|---|---|
| 路径 | `features/downloads/` |
| 职责 | 课件下载管理 |
| 依赖 | `authProvider` · `AppConfig`（下载路径） |

### Settings — 设置

| 项目 | 内容 |
|---|---|
| 路径 | `features/settings/` |
| 职责 | 配置编辑界面 · 主题切换 |
| 依赖 | `AppConfig` · `SettingsService` · `themeVariantProvider` |

### Palace — 个人世界宫殿

| 项目 | 内容 |
|---|---|
| 路径 | `features/palace/` |
| 职责 | Palace 认知中间件的 UI 层——宫殿主页面、快速捕捉弹窗、树状视图 |
| 入口 Provider | `palaceEventStoreProvider` · `palaceEventsProvider` · `palaceCaptureProvider` · `palaceLessonsProvider` · `palaceTagsProvider` · `palaceFilterProvider` |
| 依赖 | `core/palace/`（平台层）· `features/agent/`（DeepSeekProvider 共享） |
| 关键文件 | `screens/palace_screen.dart` — 主页面（类型→日期→卡片三层树状视图）<br>`dialogs/capture_dialog.dart` — 快速捕捉弹窗（showDialog）<br>`widgets/event_tree_view.dart` — 树状结构组件<br>`widgets/event_card.dart` — 事件卡片<br>`widgets/event_detail_panel.dart` — 事件详情展开面板 |
| 路由 | `/palace`（fade transition） |
| 导航 | 侧栏末尾「宫殿」入口（桌面展开/收起 + 移动端抽屉 + 移动端标题） |
| Agent 工具 | `capture_to_palace` — 用户在 AI 对话中用自然语言指挥写入 Palace |
| 测试 | `test/features/palace/`（Widget 渲染 · 树视图交互） |

---

## Widgets — 共享 UI 组件

| 组件 | 路径 | 用途 |
|---|---|---|
| AppShell | `widgets/sidebar.dart` | 桌面侧栏 + 移动端底部导航 |
| DashboardScreen | `widgets/dashboard.dart` | 仪表盘首页（`ConsumerStatefulWidget`，打开时刷新 5 个 Provider） |
| EmptyState | `widgets/empty_state.dart` | 无数据时的占位提示 |
| ErrorCard | `widgets/error_card.dart` | 错误提示卡片 |
| LoadingIndicator | `widgets/loading_indicator.dart` | 加载动画 |
| MindmapWidget | `widgets/mindmap_widget.dart` | 思维导图可视化 |
| MarkdownRenderer | `widgets/markdown_renderer.dart` | 统一富文本渲染（Markdown → HTML → `HtmlWidget`） |

---

## 依赖关系速查图

```
main.dart
  └── app.dart (EvergreenApp)
        ├── AppConfig.initialize()
        ├── GoRouter (所有路由)
        ├── themeVariantProvider
        └── _triggerAutoLogin()
              ├── authProvider → ZjuAmService → ZJU SSO
              ├── ZdbkService.login()
              ├── _loginCourses() → courses.zju.edu.cn session
              └── _loginClassroom() → tgmedia OAuth2 chain

Auth (authProvider)
  ├── [被依赖] zdbk, courses, classroom, library, ecard
  ├── [被依赖] scores, exams, todo, teachers, autosign, schedule, quiz
  └── [设置回调] AuthInterceptor.onRelogin

ZDBK (ZdbkService)
  ├── [被依赖] scores → GpaCalculator → Grade
  ├── [被依赖] exams → Exam
  ├── [被依赖] schedule → ICalExporter → TimetableSession
  └── [被依赖] scheduler → flow_scheduler

Agent Runtime
  ├── [被依赖] features/agent/ (AI 助手)
  └── [工具] ZjuDataSource → Flutter 层注入实现

Dio (dioClientProvider)
  └── [被依赖] 所有通过 Dio 发请求的 Feature
```
