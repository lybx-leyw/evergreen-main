# 数据流 & 依赖链

> 从用户操作到数据返回的完整链路。理解这些链路后即可定位问题出在哪一环。

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

## 12. 关键接口与注入点

| 接口/Provider | 定义位置 | 注入位置 | 用途 |
|---|---|---|---|
| `ZjuDataSource` | `core/agent/tools/zju_data_source.dart` | `features/agent/` | Agent 工具获取业务数据 |
| `httpClientProvider` | `features/auth/providers/auth_provider.dart` | 各 Service | ZJU API 调用的共享 HttpClient |
| `dioClientProvider` | `core/network/dio_client.dart` | 各 Provider | Dio HTTP 客户端 |
| `cookieJarProvider` | `core/network/dio_client.dart` | auth + app.dart | Cookie 持久化 |
| `AuthInterceptor.onRelogin` | `core/network/auth_interceptor.dart` | auth_provider.dart | 自动重登回调 |
