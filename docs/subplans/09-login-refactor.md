# 09 — 登录流程重构（细化版）

**层级：** 二 | **估时：** 3 天 | **依赖：** 03 AppConfig, 07 网络层 | **关联 Bug：** BUG-10

---

## 1. 现状问题

### 1.1 代码散落在错误的位置

| 位置 | 行数 | 问题 |
|------|:---:|------|
| `EvergreenApp._loginCourses` | ~200 行 | Widget 类中的静态方法——不应在此 |
| `EvergreenApp._loginClassroom` | ~150 行 | 同上 |
| `EvergreenApp._triggerAutoLogin` | ~50 行 | 在 `build()` 中触发副作用——反模式 |
| 合计 | ~400 行 | 占 `app.dart` 的 60% |

### 1.2 用户体验问题

| 问题 | 现状 | 后果 |
|------|------|------|
| 无进度可见 | `_triggerAutoLogin` 静默运行 | 冷启动 → 白屏 5-10 秒，用户以为卡死 |
| 无错误隔离 | 一个服务失败→`catch(e) print(...)` | 用户不知道哪个服务挂了 |
| 无重试 | 失败即放弃 | 临时网络抖动 → 整个会话缺失数据 |
| 离线无体验 | 断网 → 异常堆栈 | 应该展示缓存数据 + "离线模式"提示 |

---

## 2. 设计目标

1. **抽离**：登录逻辑从 `app.dart` 移到独立的 `AuthService`
2. **可视化**：`AuthEvent` 事件流 → UI 展示实时进度条
3. **容错**：每个服务独立失败，不影响其他服务
4. **离线友好**：Cookie 过期 / 断网 → 不崩溃，展示缓存数据

---

## 3. 核心设计

### 3.1 `AuthService` — 登录编排器

```dart
// lib/features/auth/services/auth_service.dart

/// 自动登录编排器——管理 ZJU SSO → ZDBK / Courses / Classroom 的全链路。
///
/// 替代 `app.dart` 中的 `_loginCourses` / `_loginClassroom` / `_triggerAutoLogin`。
class AuthService {
  final HttpClient _httpClient;
  final PersistCookieJar _cookieJar;

  /// 按顺序登录所有 ZJU 子系统，通过 [onProgress] 报告进度。
  ///
  /// 每个服务独立失败——一个失败不影响后续服务。
  Future<AuthResult> loginAll({
    required Cookie ssoCookie,
    void Function(AuthProgress progress)? onProgress,
  }) async {
    final results = <String, ServiceResult>{};

    for (final target in _targets) {
      onProgress?.call(AuthProgress(
        service: target.name,
        step: '正在登录...',
        status: AuthStatus.inProgress,
      ));

      try {
        await target.login(_httpClient, ssoCookie, _cookieJar);
        results[target.name] = ServiceResult.success();
        onProgress?.call(AuthProgress(
          service: target.name,
          step: '登录成功',
          status: AuthStatus.success,
        ));
      } catch (e) {
        results[target.name] = ServiceResult.failure(e.toString());
        onProgress?.call(AuthProgress(
          service: target.name,
          step: '登录失败',
          status: AuthStatus.failed,
          error: e.toString(),
        ));
      }
    }

    return AuthResult(results: results);
  }
}
```

### 3.2 `AuthProgress` — 进度事件

```dart
enum AuthStatus { inProgress, success, failed }

class AuthProgress {
  final String service;   // 'ZDBK' / 'Courses' / 'Classroom'
  final String step;       // '正在登录...' / '登录成功' / '登录失败'
  final AuthStatus status;
  final String? error;
}

class ServiceResult {
  final bool ok;
  final String? error;
}

class AuthResult {
  final Map<String, ServiceResult> results;
  bool get allOk => results.values.every((r) => r.ok);
}
```

### 3.3 登录目标注册表

```dart
// 三个登录目标，各自独立，按顺序执行
final _targets = [
  _LoginTarget('ZDBK', _loginZdbk),
  _LoginTarget('Courses', _loginCourses),
  _LoginTarget('Classroom', _loginClassroom),
];
```

### 3.4 UI 集成

```dart
// Dashboard / AppShell 监听登录进度
StreamBuilder<AuthProgress>(
  stream: authService.loginAll(...).asStream(), // 简化示意
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return LinearProgressIndicator(
        value: snapshot.data!.progress,
      );
    }
    return child;
  },
);
```

---

## 4. 迁移对照

| 旧位置 | 新位置 |
|--------|--------|
| `EvergreenApp._loginCourses` (200 行) | `AuthService._loginCourses` (内部方法) |
| `EvergreenApp._loginClassroom` (150 行) | `AuthService._loginClassroom` (内部方法) |
| `EvergreenApp._triggerAutoLogin` (50 行) | `AuthService.loginAll()` + Dashboard 监听 |
| `print('[AutoLogin] ...')` | `Log()` + `AuthProgress` 事件流 |

---

## 5. 执行计划

| 步骤 | 内容 | 估时 |
|------|------|------|
| **Step 1** | 创建 `AuthProgress` / `AuthResult` 模型 | 0.2 天 |
| **Step 2** | 创建 `AuthService`——搬移 `_loginCourses` + `_loginClassroom` | 1 天 |
| **Step 3** | `AuthService` 集成 `Log()` + 独立错误隔离 | 0.3 天 |
| **Step 4** | `app.dart` 瘦身——删除 ~400 行，改为调用 `AuthService` | 0.3 天 |
| **Step 5** | UI 进度条集成（Dashboard 或 AppShell） | 0.3 天 |
| **Step 6** | 测试 + 全量回归 | 0.3 天 |

---

## 6. 验收标准

- [ ] `AuthService.loginAll()` 从 `app.dart` 中完全抽离
- [ ] 三个服务独立失败不互相影响
- [ ] 登录进度通过 `AuthProgress` 事件流向 UI 暴露
- [ ] 离线启动不崩溃（Cookie 过期 → 展示缓存数据）
- [ ] `print()` → `Log()` 全面迁移
- [ ] 171 测试全绿
