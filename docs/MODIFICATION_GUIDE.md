# 修改规范 & 耦合牵连指南

> 改哪个模块时要注意什么？谁依赖了它？改了会炸什么？

---

## 1. 黄金规则

1. **永远不要跳过 Auth 层改任何 ZJU API 调用** — 所有功能模块的 Provider 都依赖 `authProvider` 获取 `ssoCookie`，改认证流程 = 全量回归测试。
2. **改 Core 层 → 所有 Feature 都可能受影响**，尤其是 `dio_client.dart`、`app_config.dart`、`auth_interceptor.dart`。
3. **每个 Feature 内部遵循 providers → services → screens 的单向依赖**，Screen 不应该直接调 Service（必须通过 Provider）。
4. **新增网络请求** 必须套 `try/catch` 并在 AuthInterceptor 中注册 session-expiry 特征码。
5. **改 Agent 工具（core/agent/tools/）** 必须同步更新 Flutter 层的 `ZjuDataSource` 实现。

---

## 2. 耦合牵连矩阵

### 2.1 改了 `core/config/app_config.dart`

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `features/auth/` | 读取 `ZJU_USERNAME`、`ZJU_PASSWORD` 进行登录 | 🔴 必测 |
| `features/settings/` | 读写所有配置项，调用 `saveToEnvFile()` | 🔴 必测 |
| `features/tutor/` | 读取 `DEEPSEEK_API_KEY`、`DEEPSEEK_MODEL` | 🟡 功能降级 |
| `features/downloads/` | 读取 `MATERIAL_DOWNLOAD_PATH` | 🟡 功能降级 |
| `features/rvpn/` | 读取 `CHALAOSHI_SCRIPT` | 🟢 轻量 |

**修改规范：**
- 新增字段 → `_loadFromEnv()` + `_loadFromEnvFile()` + `_loadFromPrefs()` + `set()` + `saveToEnvFile()` + `SettingsService._keys` 五处同步添加
- 删除字段 → 从以上五处移除，确保 Settings 界面不报 key 缺失
- 修改 `.env` 路径逻辑 → 影响所有配置加载

### 2.2 改了 `core/network/dio_client.dart`

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| **所有 Feature** | 所有 Provider 通过 `dioClientProvider` / `cookieJarProvider` 获取 HTTP 客户端 | 🔴 全量回归 |
| `features/auth/` | `authProvider` 依赖 `dio` + `cookieJar` 注入 | 🔴 必测 |
| `core/agent/provider.dart` | `DeepSeekProvider` 接收外部 Dio 实例 | 🔴 必测 |

**修改规范：**
- 新增拦截器 → 加到拦截器链末尾（`DebugInterceptor` 在最前，`RetryInterceptor` 在最后）
- 修改 User-Agent / 默认 headers → 可能影响反爬虫
- 修改超时 → 慢网环境下的 ZDBK / 智云课堂可能超时

### 2.3 改了 `core/network/auth_interceptor.dart`

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| **所有 ZJU API 调用** | 拦截器挂载在 Dio 上，检测 302/登录页 HTML 并触发自动重登 | 🔴 全量回归 |
| `features/auth/providers/auth_provider.dart` | 设置了 `AuthInterceptor.onRelogin` 回调 | 🔴 必测 |

**修改规范：**
- `_isSessionExpiredError()` → 新增特征码时注意 CAS 登录页的 HTML 模式（`login_ssologin`、`cas/login`、`统一身份认证`）
- `_tryRelogin()` → 最大重试 2 次，修改此值可能导致无限重登
- 重登成功后 `_reloginAttempts` 必须重置为 0

### 2.4 改了 `core/agent/`（Agent 运行时）

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `features/agent/` | AI 助手聊天界面直接使用 Agent | 🔴 必测 |
| `features/tutor/` | AI 笔记可能通过 Agent 工具获取数据 | 🟡 功能降级 |
| `core/agent/tools/` | 所有内置工具依赖 Tool 接口定义 | 🔴 编译期检测 |

**修改规范：**
- 改 `Tool` 接口 → 所有 `implements Tool` 的类需同步更新
- 改 `Message` 的 `toJson()` → 影响 LLM API 请求体格式
- 改 `Provider` 接口 → `DeepSeekProvider` 需同步
- 改 `Registry` → 所有注册工具的地方（`agent/chat_screen.dart`）
- Agent Loop 新增步骤 → 需要考虑 maxSteps 是否足够

### 2.5 改了 `core/utils/python_env.dart`（Python 子进程）

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `features/tutor/providers/notes_provider.dart` | OCR 脚本调用 | 🟡 功能降级 |
| `features/agent/chat_screen.dart` | 文件 OCR | 🟡 功能降级 |
| `features/agent/providers/agent_provider.dart` | 培养方案 OCR | 🟡 功能降级 |

**修改规范：**
- 改 `runOcrProcess()` → 所有 OCR 子进程调用方自动受影响
- 改 `PythonEnv.ensureReady()` → 依赖检测逻辑变更
- 添加 Python 依赖 → 同步更新 `scripts/requirements.txt`

### 2.6 改了 `core/utils/auto_refresh.dart`（自动刷新）

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `widgets/dashboard.dart` | 5 个 Provider 的 `invalidate` | 🟡 功能降级 |
| `features/courses/screens/courses_screen.dart` | `coursesListProvider` 刷新 | 🟢 轻量 |
| `features/todo/screens/todo_screen.dart` | `todoListProvider` 刷新 | 🟢 轻量 |
| `features/scores/screens/scores_screen.dart` | `zdbkEverythingProvider` 刷新 | 🟢 轻量 |
| `features/exams/screens/exams_screen.dart` | `examsListProvider` 刷新 | 🟢 轻量 |
| `features/settings/screens/settings_screen.dart` | 设置页保存时重启定时器 | 🟢 轻量 |
| `lib/app.dart` | `EvergreenApp.initState()` 调用 `initAutoRefresh()` | 🟡 启动流程 |

**修改规范：**
- 新增设置项 → `settings_service.dart._keys` + `auto_refresh.dart.readPrefs()` 同步
- 改 `shouldRefresh()` 逻辑 → 影响所有页面是否刷新

### 2.9 改了 `features/auth/`（认证模块）

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| **所有 ZJU Feature** | 所有 Provider 通过 `authProvider` 检查登录状态 + 获取 `ssoCookie` | 🔴 全量回归 |
| `app.dart` | 自动登录逻辑 `_triggerAutoLogin` 依赖 `authProvider` + `ZjuAmService` | 🔴 启动流程 |
| `core/network/auth_interceptor.dart` | 设置了重登回调 | 🔴 必测 |

**具体牵连：**
- `features/zdbk/providers/zdbk_provider.dart` — 所有 provider 都检查 `auth.isLoggedIn` 和 `auth.ssoCookie`
- `features/courses/providers/courses_provider.dart`
- `features/classroom/providers/classroom_provider.dart`
- `features/scores/providers/scores_provider.dart`
- `features/exams/providers/exams_provider.dart`
- `features/todo/providers/todo_provider.dart`
- `features/library/providers/library_provider.dart`
- `features/ecard/providers/ecard_provider.dart`
- `features/teachers/providers/teachers_provider.dart`
- `features/autosign/providers/autosign_provider.dart`

**修改规范：**
- 改 `ZjuAmResult` → `AuthNotifier.login()` 的返回值处理需同步
- 改 RSA 加密逻辑 → 必须用真实账号测试 CAS 登录
- 改 cookie 域（`.zju.edu.cn`）→ 所有 ZJU 子域 cookie 下发可能失效
- 新增 SSO 步骤 → 需要重测整个自动登录链

### 2.8 改了 `features/zdbk/`（教务系统）

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `features/scores/` | 成绩数据来源于 ZDBK | 🔴 必测 |
| `features/exams/` | 考试数据来源于 ZDBK | 🔴 必测 |
| `features/schedule/` | 课表数据来源于 ZDBK | 🔴 必测 |
| `features/scheduler/` | 调度依赖课表 | 🟡 功能降级 |
| `features/zdbk/screens/zdbk_notifications_screen.dart` | 通知公告页 | 🟡 新功能 |
| `core/models/grade.dart` | Grade.fromJson 解析 ZDBK 的 `jd`/`cj`/`xf` 字段 | 🟡 数据模型 |
| `core/models/course_offering.dart` | 解析 ZDBK 的开课情况字段 | 🟡 数据模型 |
| `core/agent/tools/zju_scores.dart` | Agent 工具调用 ZDBK | 🟢 轻量 |
| `core/agent/tools/zju_notifications.dart` | Agent 通知工具依赖 `getNotifications()` | 🟢 轻量 |

**修改规范：**
- ZDBK API 返回字段名变更 → `Grade.fromJson` + `CourseOffering.fromJson` + `TimetableSession.fromJson` 同步更新
- 新增缓存键 → 同步更新 `WebCacheDatabase` 的清理逻辑
- 改 `ZdbkService.login()` → 所有 `zdbk*Provider` 的 `service.isLoggedIn` 检查生效

### 2.10 改了 `core/models/grade.dart`

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `core/utils/gpa_calculator.dart` | 使用 `fivePoint`、`fourPointGpa`、`hundredPoint` 等字段 | 🔴 必测 |
| `features/scores/` | 展示 GPA | 🔴 必测 |
| `features/zdbk/` | `Grade.fromJson` 构造 Grade 对象 | 🔴 必测 |

**修改规范：**
- 改 `fivePoint` 类型（int ↔ double）→ GPA 计算结果可能全变
- 改 `_scoreToFivePoint` 映射表 → 影响 ZDBK 无 jd 字段时的回退逻辑
- 改 `isExcludedFromGpa` → 影响 GPA 计算中哪些课程被排除

### 2.11 改了 `widgets/sidebar.dart`

| 牵连模块 | 原因 | 严重度 |
|---|---|---|
| `app.dart` | 路由表需要与侧栏条目一一对应 | 🟡 导航失效 |
| `features/todo/` | 侧栏显示待办 badge（依赖 `todoListProvider`） | 🟢 轻量 |
| `features/exams/` | 侧栏显示考试 badge（依赖 `examsListProvider`） | 🟢 轻量 |

**修改规范：**
- 新增导航项 → `app.dart` 的 `GoRoute` 列表同步添加
- 删除导航项 → 检查是否有深层链接直接访问该路由
- 修改移动端导航 → `_MobileNavBar._getMobileIndex()` 同步

---

## 3. Feature 模块内部结构规范

每个 Feature 模块遵循统一的结构：

```
features/<name>/
├── providers/
│   └── <name>_provider.dart    # Riverpod Provider（暴露数据给 UI）
├── services/
│   └── <name>_service.dart     # 业务逻辑 + API 调用（不依赖 UI）
├── screens/
│   └── <name>_screen.dart      # UI 页面
├── widgets/                    # 可选：该 Feature 专属组件
├── models/                     # 可选：该 Feature 专属数据模型
└── tools/                      # 可选：Agent 工具（如 teachers/tools/）
```

**依赖方向：** `screens → providers → services → core/network & core/config`

**勿做的反模式：**
- ❌ Screen 直接 new Service（绕过 Provider 层）
- ❌ Service 中 import Flutter Widget
- ❌ Provider 跨 Feature 导入（应通过公共 Provider 或接口）
- ❌ Service 中硬编码 URL（应从 AppConfig 或常量中获取）

---

## 4. 新增 Feature 检查清单

- [ ] `features/<name>/providers/<name>_provider.dart` — 至少一个 Provider
- [ ] `features/<name>/services/<name>_service.dart` — 业务逻辑
- [ ] `features/<name>/screens/<name>_screen.dart` — UI 页面
- [ ] `app.dart` — 添加 GoRoute
- [ ] `widgets/sidebar.dart` — 添加导航项（桌面 + 移动端）
- [ ] 如需 Agent 工具 → `core/agent/tools/` + `ZjuDataSource` 接口扩展
- [ ] 如需新模型 → `core/models/`
- [ ] 如需缓存 → `core/storage/database.dart` 添加缓存键前缀
- [ ] 如需配置 → `core/config/app_config.dart` 五处同步
- [ ] 测试 → `test/features/<name>/`

---

## 5. 危险操作一览

| 操作 | 风险 | 建议 |
|---|---|---|
| 删除 `httpClientProvider` | 所有 ZJU 服务崩溃 | 先 grep 所有 `httpClientProvider` 引用 |
| 修改 `iPlanetDirectoryPro` 域名 | Cookie 无法下发到子域 | 在测试环境验证 courses/library/ecard |
| 修改 `DeepSeekProvider` 的 API URL | AI 功能全部不可用 | 先检查 DeepSeek 官方 API 变更 |
| 重构 `app.dart` 的 `_triggerAutoLogin` | 启动时自动登录链断裂 | 逐个服务测试登录 |
| 删除 `ZjuDataSource` 中的方法 | Agent 工具调用报错 | 同步更新所有 implements + 工具实现 |
| 修改 Flutter SDK 版本范围 | 编译失败 | 检查 `pubspec.yaml` 所有依赖兼容性 |
