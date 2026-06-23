# 贡献协议

> 所有对 Evergreen Multi-Tools 的修改必须满足以下要求，否则将被驳回。

---

## 1. 基础设施架构

### 1.1 网络层

- 所有 HTTP 请求必须通过 `Dio` 实例（`dioClientProvider`），禁止直接使用 `dart:io HttpClient`
- Cookie 管理必须通过 `CookieManager` + `PersistCookieJar`（`cookieJarProvider`），禁止手动拼接 `Cookie` 头
- 自定义拦截器必须遵循已有拦截器顺序：`DebugInterceptor` → `CookieManager` → `AuthInterceptor` → `RetryInterceptor`
- 所有日志输出必须使用 `Log()`（`debug`/`info`/`warn`/`error`），禁止 `print()` / `debugPrint()`
- 超时、重试、域名白名单必须使用 `NetworkConfig` 中的常量

### 1.2 认证体系

| 平台 | 认证方式 | 说明 |
|------|---------|------|
| ZJU SSO (CAS) | `Cookie: iPlanetDirectoryPro=xxx` | ZDBK / Courses / Classroom |
| BlueWare (慧新E校) | `synjones-auth: bearer <token>` | elife 一卡通 — **功能暂停** |
| Courses 答题 | `Cookie: session=xxx` | classrooms API 已废弃 — **功能暂停** |
| PTA (Pintia) | `Cookie: PTASession=xxx` | 需手动粘贴（腾讯云验证码） |
| DeepSeek | `Authorization: Bearer $KEY` | API Key |
| PTA OAuth | 待实现 | pintia.cn/api/oauth/authorize |

- 不同平台的认证方式**不允许混用**
- 新增平台时必须先确认其认证方式并更新本表

### 1.3 统一自动登录

所有服务的自动登录必须通过 `ConnectionManager`（`core/connectivity/connection_manager.dart`）统一管理：

```dart
// ✅ 正确：使用 ConnectionManager 统一检查
final manager = ConnectionManager(httpClient, cookieJar, auth, () => zdbkService);
final results = await manager.checkAll();

// ❌ 禁止：在 app.dart 或其他地方逐个手动登录
```

**规则：**
- 新增服务时，在 `ConnectionManager.checkAll()` 中添加对应的检查方法
- 自动登录在 `app.dart` 的 `_triggerAutoLogin` 中统一调用 `manager.checkAll()`
- 各服务的登录逻辑封装在自身的 Service 类中，`ConnectionManager` 只负责编排
- 登录失败不允许阻断其他服务的登录流程（每个服务独立失败）
- 失败服务自动重试 1 次（`connectivityCheckProvider` 内置 `checkOne` 兜底）
- 连接检查每 5 分钟自动刷新（`_refreshTickProvider` 驱动 `connectivityCheckProvider` 重跑）
- 新增服务的认证方式必须同步更新到本协议的 1.2 认证体系表格

**Provider 刷新规则：** 依赖登录态的 Provider 必须使用 `ref.watch(authProvider)` 而非 `ref.read(authProvider)`，否则登录完成后不会自动重新加载数据。参见 `zdbk_provider.dart` 和 `courses_provider.dart`。

**当前管理的服务：**

| 服务 | 检查方式 | 失败容忍 |
|------|---------|:--------:|
| ZDBK 教务网 | `ZdbkService.login()` | 容忍 + 自动重试 |
| Courses 学在浙大 | `AuthService.loginCourses()` | 容忍 + 自动重试 |
| Classroom 智云课堂 | `AuthService.loginClassroom()` | 容忍 + 自动重试 |
| PTA 编程题 | `PintiaService.hasValidSession()` | 容忍 + 自动重试 |
| DeepSeek AI | `AppConfig.deepseekApiKey` 存在性 | 容忍 |
| DeepSeek-OCR | `AppConfig.deepseekOcrApiKey` 存在性 | 容忍（降级本地 Tesseract） |

### 1.4 状态管理

- 所有共享状态必须通过 Riverpod `Provider`/`FutureProvider`/`StateNotifierProvider`
- Provider 的依赖必须显式声明（`ref.read` / `ref.watch`）
- 配置值通过 `AppConfig` / `AppConfigData` 管理，枚举类字段需加 `@Secure()` 标记
- 异步结果使用 `Result<T>`（`Ok` / `Err`），错误使用 `AppError`

### 1.5 错误处理

```
UI Layer          → 显示用户友好的错误信息
     ↕ Result<T> / AppError
Service Layer     → 返回 Result<T>，不抛异常
     ↕ DioException catch → AppError
Network Layer     → 抛出 DioException（拦截器处理重试）
```

- 所有 Service 方法必须返回 `Result<T>`，不得向外抛出异常
- `AppError` 必须包含 `userMessage`（面向用户）和 `recoveryHint`（恢复指引）
- 网络错误/超时/404 均需映射为有意义的 `AppError`，不允许透传 DioException 原文

---

## 2. 代码风格

### 2.1 Dart

- 遵循 `flutter_lints` 5.x 规则
- `import` 排序：Dart SDK → Flutter → Riverpod → 项目内部（从 core 到 features）
- 私有方法/类加 `_` 前缀
- 不可变数据类必须提供 `copyWith` + `toJson` + `fromJson`
- 敏感字段 toString() 必须脱敏（`AppConfigData.mask`）

### 2.2 Widget

- 复用型 Widget 放在 `lib/widgets/`
- 功能页面放在 `lib/features/<feature>/screens/`
- `build()` 方法中不允许有副作用（网络请求、状态变更）
- 使用 `ConsumerWidget` / `ConsumerStatefulWidget` 而非 `StatelessWidget` + `Provider.of`

### 2.3 测试

- 每个 Service 必须有对应测试文件（`test/features/<feature>/<name>_test.dart`）
- HTTP 模拟必须使用 `MockDioAdapter`（`test/mocks/mock_dio.dart`）
- Cookie 相关测试必须使用 `PersistCookieJar(ignoreExpires: true)`
- 每个测试用例必须使用独立的 cookie jar 实例（避免文件锁定 / 跨测试污染）
- 错误路径必须覆盖：成功、空数据、401/404、网络异常

### 2.4 运行测试

```bash
# 全量并行测试（推荐，对齐 CI 的 6 组 job，比串行 flutter test 快数倍）
python scripts/run_tests_parallel.py

# 跳过静态分析（更快）
python scripts/run_tests_parallel.py --no-analyze

# 只跑某一组
python scripts/run_tests_parallel.py --group core

# 单文件测试
flutter test test/features/xxx/xxx_test.dart

# 覆盖率
flutter test --coverage
```

> 并行脚本要求 Python 3.8+ 且 flutter 在 PATH 中（或设置 `FLUTTER` 环境变量指向可执行文件）。

---

## 3. 功能开发规范

### 3.1 开发中功能

当某个功能的后端 API 不可用（如 BlueWare token、图书馆 API 超时）：

1. **UI**：仪表盘使用 `_wipCard(title, subtitle, icon)` 替代 `_previewCard`
2. **侧边栏**：标签追加 `(开发中)`，路径指向 `/<feature>-wip`
3. **路由**：原路由注释保留，添加 `/<feature>-wip` → `_WipScreen`
4. **自动登录**：登录链中注释掉对应服务的调用，返回 `ServiceResult.failure`
5. **代码**：Service/Provider 代码完整保留（不删除），加文档说明阻塞原因
6. **文档**：`docs/dev/` 下写开发文档说明 API 现状和实现思路
7. **调试手册**：`test/network_debug_guide.md` 对应节标注"功能暂停"，尾部清单更新备注

### 3.2 阶段恢复步骤

```dart
// 1. app.dart — 恢复路由
// 2. auth_service.dart — 恢复自动登录
// 3. sidebar.dart — 移除 (开发中) 标记
// 4. dashboard.dart — 恢复 _previewCard
```

### 3.3 基础设施子计划

每次修改前应核对该子计划的验收标准：

| # | 子计划 | 关键验收项 |
|---|--------|-----------|
| 01 | 统一错误处理体系 | `print()` → `Log()`、`Result` + `AppError`、无透传异常 |
| 02 | 测试基础设施 | `MockDioAdapter`、独立 jar、错误路径覆盖 |
| 03 | AppConfig 规范化 | `@Secure()`、env/文件/SharedPreferences 三层优先级 |
| 04 | 数据模型固化 | `copyWith` + `toJson` + `fromJson`、不可变、toString 脱敏 |
| 05 | 共享 Widget 标准化 | 复用 `_previewCard` 等现有组件、不重复造轮子 |
| 06 | 记忆系统架构设计 | Agent 与 UI 共享记忆源 |
| 07 | 网络层加固 | `NetworkConfig`、`Log()`、`kDebugMode` 条件编译、deep copy |
| 08 | 工具类加固 | `SafeParse`、`DateUtils` 等工具类不重复造轮子 |
| 09 | 登录流程重构 | `AuthService.loginAll()`、各服务独立失败 |
| 10 | ZDBK Service 加固 | 数据源唯一、不依赖 courses.zju.edu.cn |

---

## 4. 认证架构详述

```
ZJU SSO (iPlanetDirectoryPro)
├── ZDBK（教务网）✅
│   ├── 成绩/绩点
│   ├── 课表 ← coursesListProvider 数据源
│   ├── 考试安排
│   ├── 开课情况
│   └── 实践分数
├── Courses（学在浙大）✅
│   ├── 课程活动/作业 ← todo 数据源
│   ├── 课程资料
│   └── 答题 — **暂停**（classrooms API 废弃）
├── Classroom（智云课堂）✅
│   ├── 课程视频
│   ├── PPT
│   └── 字幕

BlueWare (synjones-auth bearer token) ⚠️ 暂停
└── elife 一卡通
    └── 校园卡余额查询

Pintia (PTASession cookie) ⚠️ 需手动登录
└── PTA 编程题目集
    └── 题集列表（标题+截止时间）
        └── TodoItem

DeepSeek (Authorization: Bearer API Key) ✅
└── AI 对话

RVPN ⚠️ 不良集成 — 暂停

智能调度 ⚠️ 未完善 — 暂停

Library ⚠️ API 不可达 — 暂停
```

---

## 5. 禁止的行为

- ❌ 手动拼接 `Cookie` 头覆写 CookieManager
- ❌ 在 Widget `build()` 中触发网络请求
- ❌ 跨平台认证混用（如用 SSO cookie 调 BlueWare API）
- ❌ 不同数据源 ID 混用（如 ZDBK 课程 ID 对 courses.zju.edu.cn API）
- ❌ 使用 `print()` / `debugPrint()` 代替 `Log()`
- ❌ 删除暂时不可用功能的代码（应标记"开发中"并保留）
- ❌ Provider 中用 `ref.read(authProvider)` 替代 `ref.watch(authProvider)`（导致登录后不刷新）
- ❌ 新功能接入时跳过 `ConnectionManager.checkAll()` 直接调用 Service 登录
