# 数据流 & 依赖链 — Evergreen Multi-Tools v1.4.0

> 从用户操作到数据返回的完整链路。理解这些链路后即可定位问题出在哪一环。

---

## API 来源说明

项目中"DeepSeek"涉及**两个不同的 API 提供商**，容易混淆：

| 配置项 | 提供商 | API 地址 | 用途 |
|--------|--------|----------|------|
| `DEEPSEEK_API_KEY` | **DeepSeek 官网** | `api.deepseek.com` | AI 对话、AI 笔记、PDF 翻译 |
| `DEEPSEEK_OCR_API_KEY` | **阿里云 DashScope** | `dashscope.aliyuncs.com` | DeepSeek-OCR 云端图片识别 |

- **DeepSeek 官网** 的模型（`deepseek-chat` / `deepseek-v4-flash` 等）支持文本对话和翻译，**不支持 Vision / 图片识别**。在 [platform.deepseek.com](https://platform.deepseek.com) 获取 API Key。
- **阿里云 DashScope** 上架的 `vanchin/deepseek-ocr` 是第三方封装的 OCR 模型，专门用于图片文字识别。在 [dashscope.aliyuncs.com](https://dashscope.aliyuncs.com) 获取 API Key。

两个 Key **不能互换使用**，需分别在设置页面配置。

---

## 1. 启动流程

```
main()
  → WidgetsFlutterBinding.ensureInitialized()
  → MediaKit.ensureInitialized()
  → windowManager (size + title)
  → AppConfig.initialize()
      ├── _loadFromEnv()          ← 环境变量（最高优先级）
      ├── _loadFromEnvFile()      ← .env 文件（中优先级）
      └── _loadFromPrefs()        ← SharedPreferences（最低优先级）
  → runApp(ProviderScope(child: EvergreenApp()))
      → EvergreenApp.build()
          → _triggerAutoLogin(ref)  ← 🔥 自动登录链
              ├── 1. authProvider.ensureAuth()
              │     ├── restoreSession()  → CookieStore.getSsoCookie()
              │     └── login()           → ZjuAmService.login() → RSA → CAS
              ├── 2. ZdbkService.login(httpClient, ssoCookie)
              ├── 3. _loginCourses(httpClient, ssoCookie, cookieJar)
              └── 4. _loginClassroom(httpClient, ssoCookie, cookieJar)
```

**失败处理：** 每个登录步骤独立 try/catch，失败打印日志但不阻塞其他步骤。

---

## 2. 用户查看课程列表

```
Sidebar 点击「课程」
  → GoRouter: /courses
  → CoursesScreen
      → ref.watch(coursesProvider)
          → CoursesApiService.getCourses(dio)
              → GET courses.zju.edu.cn (带 Cookie)
                  → AuthInterceptor 检查响应
                      ├── 200 正常 → 返回数据
                      └── 302 / CAS 登录页 → 触发 onRelogin → 重试
```

**中间涉及的模块：**
- `widgets/sidebar.dart` — 导航触发
- `app.dart` — 路由分发
- `features/courses/screens/courses_screen.dart` — UI
- `features/courses/providers/courses_provider.dart` — 状态管理
- `features/courses/services/courses_api_service.dart` — API 调用
- `core/network/dio_client.dart` — HTTP 客户端
- `core/network/auth_interceptor.dart` — 会话过期处理
- `features/auth/providers/auth_provider.dart` — 重登回调

---

## 3. 用户查看成绩 → GPA 计算

```
Sidebar 点击「成绩」
  → GoRouter: /scores
  → ScoresScreen
      → ref.watch(zdbkEverythingProvider)
          → ZdbkService.getEverything(httpClient)
              ├── GET 成绩页面 HTML
              ├── 解析成绩表格
              └── 调用 WebCacheDatabase.setCachedWebPage()
          → GpaCalculator.calculateGpa(grades)
              ├── 过滤 isExcludedFromGpa
              ├── 加权计算 5.0 / 4.3 / 4.0 / 百分制
              └── 返回 GpaResult
  → 展示 GPA 卡片 + 成绩列表
```

**数据模型流转：**
```
ZDBK API JSON
  → Grade.fromJson()           ← core/models/grade.dart
      ├── jd → fivePoint (double)
      ├── cj → original
      └── xf → credit
  → GpaCalculator.calculateGpa()
      ├── fivePoint × credit / total
      ├── fourPointGpa × credit / total
      ├── fourPointLegacyGpa × credit / total
      └── hundredPoint × credit / total
  → GpaResult { fivePoint, fourPoint, fourPointLegacy, hundredPoint, earnedCredits }
```

---

## 4. AI 助手对话流程

```
用户在 AgentChatScreen 输入消息
  → agentProvider.run(input)
      → Agent.run(input, systemPrompt, toolHint, memoryContext)
          │
          ├── ① compose()
          │     └── 组装消息：[system] + [memory context] + [session history] + [user input]
          │     └── 附带 toolsToSchemas(enabled tools)
          │
          ├── ② DeepSeekProvider.chat(messages, tools)
          │     └── POST api.deepseek.com/chat/completions (stream)
          │     └── 逐个解析 SSE chunk → AgentEvent.text / .reasoning / .toolCalls
          │
          ├── ③ 如果 LLM 返回 tool_calls
          │     ├── Gate.check(toolName, args, readOnly) → 权限检查
          │     ├── ToolHooks.preToolUse(toolName, args) → 钩子
          │     ├── Registry.call(toolName, argsJson)
          │     │     └── Tool.execute(args) → 调用 ZjuDataSource 获取数据
          │     ├── ToolHooks.postToolUse(toolName, args, result) → 钩子
          │     └── 将工具结果放入 Session → 回到 ①（loop）
          │
          ├── ④ FinalReadiness.check() → 通过则结束，否则重试
          │
          └── Stream<AgentEvent> → UI 渲染
```

**Agent 工具调用链路示例（get_scores）：**
```
LLM 请求: tool_call { name: "get_scores" }
  → Registry.call("get_scores", "{}")
      → ZjuScoresTool.execute({})
          → ZjuDataSource.getScores()
              → [Flutter 层实现] → 返回 ZjuScoreResult
          → 格式化为文本
      → 返回文本 → 放入 Session
  → LLM 看到工具结果 → 生成自然语言回答
```

---

## 5. SSO 登录链路（深层细节）

```
ZjuAmService.login(username, password)
  ├── ① GET /cas/login
  │     ├── 获取 execution token（正则：name="execution" value="...")
  │     └── 收集 session cookies
  │
  ├── ② GET /cas/v2/getPubKey
  │     ├── 携带步骤①的 cookies
  │     └── 返回 { modulus, exponent }
  │
  ├── ③ RSA 加密密码
  │     └── UTF-8 → hex → BigInt.modPow(modulus, exponent) → hex(128)
  │
  ├── ④ POST /cas/login
  │     ├── 携带所有累积的 cookies
  │     ├── body: username + encrypted_password + execution + _eventId=submit
  │     └── 从 Set-Cookie 提取 iPlanetDirectoryPro
  │
  └── ⑤ 返回 ZjuAmResult { success, cookie }
        → AuthNotifier 将 cookie 存入 CookieStore + PersistCookieJar
```

**Cookie 域设置：**
- 存入 `PersistCookieJar` 时域设为 `.zju.edu.cn`
- 这样 Dio 的 CookieManager 对该域的所有子域（courses, api.lib, zdbk, classroom 等）都会自动附带此 cookie

---

## 6. 课程登录子链路（course.zju.edu.cn）

```
app.dart: _loginCourses(httpClient, ssoCookie, cookieJar)
  ├── ① GET courses.zju.edu.cn/user/index
  │     → 302 → Keycloak CAS (identity.zju.edu.cn)
  │     → 302 → ZJUAM (zjuam.zju.edu.cn)
  │
  ├── ② 到达 ZJUAM → 附带 ssoCookie
  │     → CAS 验证通过 → 302 + ticket
  │
  ├── ③ 跟随重定向回到 courses.zju.edu.cn
  │     → courses 设置 session cookie
  │
  └── ④ 将 cookies 保存到 PersistCookieJar
        (domain: courses.zju.edu.cn)
```

**依赖：** 步骤②需要有效的 `iPlanetDirectoryPro`（由 Auth 登录获得）。

---

## 7. 智云课堂登录子链路

```
app.dart: _loginClassroom(httpClient, ssoCookie, cookieJar)
  ├── ① GET tgmedia.cmc.zju.edu.cn/index.php?r=auth/login&forward=...
  │     → 302 → 302 → ZJUAM
  │
  ├── ② ZJUAM OAuth2 authorize
  │     → 多次 302 跳转（需正确携带 cookie）
  │
  ├── ③ 回到 tgmedia / classroom
  │     → 可能触发 meta-refresh 重定向
  │
  └── ④ 保存 cookies 到 4 个域：
        ├── classroom.zju.edu.cn
        ├── tgmedia.cmc.zju.edu.cn
        ├── education.cmc.zju.edu.cn
        └── yjapi.cmc.zju.edu.cn
```

**特殊处理：** 智云课堂使用 `meta http-equiv="refresh"` 而非标准 HTTP 302，需手动解析 HTML 中的 meta 标签。

---

## 8. 会话过期 → 自动重登

```
任何 ZJU API 请求
  → AuthInterceptor 拦截响应
      ├── onResponse: 检查 HTML 中是否包含 login_ssologin / cas/login / 统一身份认证
      ├── onError: 检查 301/302/303 状态码
      └── 如果过期 → _tryRelogin()
            ├── 检查重试次数 ≤ 2
            ├── 调用 AuthInterceptor.onRelogin() → authProvider.login()
            └── 成功 → 用原参数重试请求
                失败 → 透传错误给调用方
```

---

## 9. 配置修改（设置界面）

```
SettingsScreen
  → 用户编辑字段
  → SettingsService.saveAll(settings)
      ├── SharedPreferences.setString(key, value)  ← 持久化 1
      ├── AppConfig.set(key, value)                ← 运行时更新
      └── AppConfig.saveToEnvFile(values)          ← 持久化 2（.env 文件）
```

**优先级规则：** 下次启动时环境变量 > .env > SharedPreferences，所以如果用户通过系统环境变量设置了值，设置界面的修改会被覆盖。

---

## 10. 教务通知查看

```
侧栏「教务通知」
  → /zdbk-notifications
  → ZdbkNotificationsScreen
      → ref.watch(zdbkNotificationsProvider)
          → ZdbkService.getNotifications(httpClient, studentId)
              → POST index_cxTctxNews.html (time, gnmkdm, su)
              → parseZdbkNotifications(html)
                  → <li data-xwbh> → id + 标题
                  → 发布人 / 发布时间 / 浏览人数
                  → <div class="news_con"> → 正文 HTML
      → 列表展示（标题 + 发布人 + 日期）
      → 点击 → _NotificationDetailScreen
          → HtmlWidget(notification.content) 渲染 HTML
```

**Agent 工具链路：**
```
LLM 请求: tool_call { name: "get_notifications" }
  → ZjuNotificationsTool.execute({})
      → ZjuDataSource.getNotifications()
          → [Flutter 层] zdbkNotificationsProvider → ZdbkService.getNotifications()
      → 格式化为文本（标题 + 发布人 + 日期 + 内容前 500 字）
  → LLM 看到通知 → 回答用户
```

---

## 11. 自动刷新机制

```
App 启动
  → EvergreenApp.initState()
      → initAutoRefresh(ref)
          ├── 读取 SharedPreferences: AUTO_REFRESH_ENABLED / INTERVAL
          └── 启动 Timer.periodic (3/5/10/30 分钟)

页面打开
  → Screen.initState()
      → if (shouldRefresh(ref))
            ref.invalidate(keyProvider)
          → Provider 重跑 → 新数据 → UI 更新
      → else
          → 保留缓存数据（不刷新）

设置页保存
  → _save() → saveAll(values)
      → initAutoRefresh(ref)  ← 重新读取设置，重启定时器
```

**受控页面：** 仪表盘、课程、待办、成绩、考试、快速连接

---

## 12. WordPecker 背词（FSRS 算法）

```
WordPeckerScreen
  → wordpeckerProvider
      → DictionaryService.lookup(word)      ← 本地 JSON 词典
      → EtymologyService.analyze(word)       ← DeepSeek API
      → FsrsService.schedule(card, rating)   ← FSRS 间隔重复
          ├── 输入：上次复习时间 + 评分 (0-4)
          ├── 算法：FSRS-5 参数
          └── 输出：下次复习时间 + 状态 (New/Learning/Review/Relearning)
```

**独立性：** WordPecker 不依赖任何 ZJU 服务，仅需 DeepSeek API key（用于词源分析）。

---

## 11. 调度器 → iCal 导出

```
SchedulerScreen
  → ref.watch(zdbkTimetableProvider)
      → ZdbkService.getTimetable(httpClient, year, semester)
          → 返回 List<TimetableSession>
  → FlowScheduler.schedule(sessions)
  → ICalExporter.generate(courseSchedules, semesterStart)
      → 解析 schedule 字符串（如 "周一第1-2节{1-17周}"）
      → 生成 VEVENT → iCal 格式文本
  → 写入 .ics 文件
```

---

## 12. PDF 翻译

```
侧栏「PDF 翻译」
  → /translate
  → TranslateScreen (ConsumerStatefulWidget)
      → 用户选择 PDF 文件（file_picker）
      → 用户选择语言（langIn → langOut，默认 en → zh）
      → 点击「开始翻译」
          → TranslateNotifier.startJob()
              ├── ① Python 自动发现: resolvePythonExe()
              │     ├── ①a scripts/python/python.exe（安装包自带, 优先级最高）
              │     ├── ①b PYTHON_EXE 用户配置
              │     └── ①c 系统 PATH（python3 → python → py）
              │
              ├── ② PythonEnv.ensurePdf2zhReady()
              │     ├── checkPython()               ← python --version
              │     ├── checkPdf2zhDeps()           ← import pdf2zh_next
              │     └── [缺失时] installPdf2zhDeps() ← pip install babeldoc pymupdf openai tomlkit
              │
              ├── ③ PdfTranslateService.translate()
              │     └── Process.start(resolvedPython, ['scripts/pdf_translate.py',
              │           '--input', pdfPath, '--output', outputDir,
              │           '--api-key', AppConfig.deepseekApiKey,
              │           '--model', AppConfig.deepseekModel,
              │           '--lang-in', langIn, '--lang-out', langOut])
              │         ├── stdout: JSON 事件流
              │         │   ├── {"type":"stage","stage":"stage_parse","message":"正在解析 PDF..."}
              │         │   ├── {"type":"progress","current":1,"total":12,"message":"..."}
              │         │   └── {"type":"finish","dual_pdf":"...","seconds":45,"tokens":{...}}
              │         └── onProgress/onStage → 更新 UI（阶段管线 + 进度条）
              │
              └── ④ 完成
                  → [阅读] → 全屏 PdfPreviewWidget（应用内翻页阅读）
                  → [外部打开] → url_launcher
                  → 保存到历史 (SharedPreferences)
```

**批量模式（多文件）：**
```
BatchNotifier.startBatch()
  → PythonEnv.ensurePdf2zhReady() 一次性检查
  → 逐文件 for 循环调用 translate()
      → currentFilePage/Total/Message 实时更新进度
      → 完成一个 → 立即展示"阅读"按钮（边翻边读）
      → overallProgress 反映全部比例
  → 全部完成 → results 汇总
```

**中间涉及的模块：**
- `features/translate/screens/translate_screen.dart` — UI（阶段管线、全屏阅读、批量进度）
- `features/translate/providers/translate_provider.dart` — 不可变状态管理（copyWith）
- `features/translate/models/translation_job.dart` — TranslationJob/BatchState/TranslateStage
- `core/services/pdf_translate_service.dart` — 子进程管理（自动检测 Python）
- `core/utils/python_env.dart` — Python 环境 + resolvePythonExe()
- `scripts/pdf_translate.py` — 翻译子进程（stage 中文映射）
- `scripts/pdf2zh_next/` — pdf2zh 引擎（config/ translator/ high_level.py）
- `scripts/python/` — 嵌入式 Python 3.10.9 运行时（安装包自带）

---

## 13. Palace 认知事件流

```
用户触发捕捉
  ├── 方式 A：Agent 对话中自然语言触发
  │     → AI 调用 capture_to_palace({ event_type, content, tags, ... })
  │         → CaptureToPalaceTool.execute()
  │             → QuickCaptureService.capture()
  │                 ├── ① ConsciousnessEvent.create() → 初步事件
  │                 ├── ② DeepSeekProvider.chat() → AI 摘要
  │                 ├── ③ AutoTagger.suggest() → 标签建议（如未手动打标签）
  │                 ├── ④ EventStore.save() → 事件落盘 + 重建三重索引
  │                 ├── ⑤ LessonExtractor.extract() → 教训草稿 (version=0)
  │                 └── ⑥ QuestionGenerator.generate() → 3 个追问
  │
  ├── 方式 B：Palace 页面手动捕捉
  │     → FAB 点击 → CaptureDialog.show(context)
  │         → 用户填写内容 + 类型 + 情绪 + 标签
  │         → 点击「存入宫殿」
  │             → PalaceCaptureNotifier.submit()
  │                 → QuickCaptureService.capture() (同上①-⑥)
  │
  └── 存储
        → EventStore → .greenix/palace/events/{YYYY}/{MM}/{uuid}.md
        → 索引重建：EVENTS_BY_DATE.md / EVENTS_BY_TYPE.md / EVENTS_BY_TAG.md
        → 教训（如提炼）→ .greenix/palace/lessons/{id}.md

浏览路径
  → /palace 路由 → PalaceScreen
      → palaceEventsProvider (EventStore.all() / 按过滤条件)
      → EventTreeView (类型→日期→卡片 三层树)
      → 点击卡片 → EventDetailPanel (全文 + AI 摘要 + 元数据)
```

**中间涉及的模块：**
- `core/palace/capture/quick_capture_service.dart` — 捕捉管线编排（写入→AI补全→教训→追问）
- `core/palace/tools/capture_to_palace_tool.dart` — Agent 工具（用户自然语言指挥）
- `core/palace/storage/event_store.dart` — 文件存储 + 三重索引
- `core/palace/refinery/lesson_extractor.dart` — AI 教训提取
- `core/palace/refinery/question_generator.dart` — 苏格拉底追问
- `core/palace/refinery/auto_tagger.dart` — 自动标签建议
- `features/palace/screens/palace_screen.dart` — 主页面 UI
- `features/palace/dialogs/capture_dialog.dart` — 快速捕捉弹窗
- `features/palace/widgets/event_tree_view.dart` — 树状视图
- `features/palace/providers/palace_capture_provider.dart` — 捕捉状态管理
- `features/palace/providers/palace_events_provider.dart` — 事件列表 + 过滤

---

## 14. 关键接口与注入点

| 接口/Provider | 定义位置 | 注入位置 | 用途 |
|---|---|---|---|
| `ZjuDataSource` | `core/agent/tools/zju_data_source.dart` | `features/agent/` | Agent 工具获取业务数据 |
| `httpClientProvider` | `features/auth/providers/auth_provider.dart` | 各 Service | ZJU API 调用的共享 HttpClient |
| `dioClientProvider` | `core/network/dio_client.dart` | 各 Provider | Dio HTTP 客户端 |
| `cookieJarProvider` | `core/network/dio_client.dart` | auth + app.dart | Cookie 持久化 |
| `AuthInterceptor.onRelogin` | `core/network/auth_interceptor.dart` | auth_provider.dart | 自动重登回调 |
