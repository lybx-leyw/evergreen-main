# 网络谱仪 (Network Spectrometer)

> **定位**：统一的服务连通性检测 + 数据新鲜度追踪系统。将"QuickConnect 连通性检查"与"IDEA1 数据更新时间展示"合并为单一的"数据状态面板"。

---

## 核心类总览

```
┌─────────────────────────────────────────────────────┐
│                  QuickConnectScreen                   │  ← UI 层：汇总卡片 + 连通性列表 + 新鲜度列表
└──────────┬──────────────────────────┬────────────────┘
           │                          │
           ▼                          ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│   ConnectionManager   │  │     DataStatusManager         │  ← 业务层
│   连通性检查 (7 服务)   │  │   数据新鲜度追踪 (13 数据源)     │
└──────────┬───────────┘  └──────────┬───────────────────┘
           │                          │
           ▼                          ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│   ConnectionResult    │  │      DataSourceStatus          │  ← 数据模型
│   service / ok / ms   │  │   name / ttl / lastFetchedAt   │
└──────────────────────┘  └──────────┬───────────────────┘
                                      │
                                      ▼
                          ┌──────────────────────────────┐
                          │   WebCacheDatabase            │  ← 持久化层
                          │   getCacheTimestamp(key)       │
                          └──────────────────────────────┘
```

---

## 伪代码

### 1. ConnectionResult — 连通性检测结果

```
class ConnectionResult:
    field service : string       // 服务名，如 "ZDBK 教务网"
    field ok      : bool         // 是否可达
    field message : string?      // 失败原因
    field elapsed : Duration     // 耗时
```

### 2. ConnectionManager — 连通性检查器

```
class ConnectionManager:
    field _httpClient  : HttpClient
    field _cookieJar   : PersistCookieJar
    field _auth        : AuthState
    field _zdbkService : () -> ZdbkService

    method checkAll() -> List<ConnectionResult>:
        services = [
            "ZJUAM SSO",
            "ZDBK 教务网",
            "Courses 学在浙大",
            "Classroom 智云课堂",
            "PTA 编程题",
            "DeepSeek AI",
            "PDF Translate",
        ]
        results = []
        for each service in services:
            results.append(checkOne(service))
        return results

    method checkOne(service : string) -> ConnectionResult:
        if _auth.ssoCookie is null:
            return ConnectionResult(service, ok=false, message="SSO 未登录")

        switch service:
            case "ZJUAM SSO":
                // SSO 本身不需要额外请求——有 cookie 即说明已登录
                return _result(service, noop)

            case "ZDBK 教务网":
                return _check(service, () => _zdbkService().login(_httpClient, sso))

            case "Courses 学在浙大":
                return _check(service, () => AuthService.loginCourses(sso))

            case "Classroom 智云课堂":
                return _check(service, () => AuthService.loginClassroom(sso))

            case "PTA 编程题":
                return _check(service, ():
                    session = AppConfig.ptaSession
                    if session 为空: throw "未配置 PTASession"
                    svc = PintiaService(dio, _cookieJar)
                    svc.setSessionCookie(session)
                    if not svc.hasValidSession(): throw "PTASession 已失效"
                )

            case "DeepSeek AI":
                return _result(service, ():
                    key = AppConfig.deepseekApiKey
                    if key 为空: throw "未配置 API Key"
                )

            case "PDF Translate":
                return _result(service, ():
                    if scripts/pdf2zh_next/ 目录不存在: throw "pdf2zh 模块未安装"
                    if python --version 失败: throw "Python 不可用"
                )

            default:
                return ConnectionResult(service, ok=false, message="未知服务")

    // ─── 私有辅助 ───

    helper _result(service, fn) -> ConnectionResult:
        start = now()
        try:
            fn()
            return ConnectionResult(service, ok=true, elapsed=now()-start)
        catch e:
            return ConnectionResult(service, ok=false, message=e, elapsed=now()-start)

    async helper _check(service, fn) -> ConnectionResult:
        // 同 _result，但 fn 是异步的
        start = now()
        try:
            await fn()
            return ConnectionResult(service, ok=true, elapsed=now()-start)
        catch e:
            return ConnectionResult(service, ok=false, message=e, elapsed=now()-start)
```

---

### 3. DataSourceStatus — 数据源状态快照

```
class DataSourceStatus:
    field name          : string        // 显示名，如 "ZDBK 成绩"
    field category      : string        // 分类: ZDBK | Courses | Classroom | Todo | PTA | AI
    field cacheKey      : string?       // WebCacheDatabase 中的 key；null = 内存缓存/API 源
    field ttl           : Duration      // 新鲜度 TTL
    field connected     : bool = false  // 服务是否可达
    field lastFetchedAt : DateTime?     // 上次成功拉取时间
    field lastError     : string?       // 上次错误信息

    computed isFresh -> bool:
        return lastFetchedAt != null
           and (now() - lastFetchedAt) < ttl

    computed freshnessLabel -> string:
        if lastFetchedAt is null: return "从未"
        if isFresh:              return "新鲜"
        else:                    return "过期"

    computed relativeTime -> string:
        if lastFetchedAt is null:  return "从未更新"
        diff = now() - lastFetchedAt
        if diff < 60s:   return "刚刚"
        if diff < 60min: return "${diff.minutes} 分钟前"
        if diff < 24h:   return "${diff.hours} 小时前"
        return "${diff.days} 天前"
```

---

### 4. DataStatusManager — 全局数据状态管理器

```
class DataStatusManager:
    field _sources : Map<string, DataSourceStatus> = {}

    // ═══ 注册 ═══

    method registerSource(source : DataSourceStatus):
        _sources[source.name] = source

    method registerDefaults():
        // ── ZDBK 数据源（6 个） ──
        registerSource(name="ZDBK 成绩",    category="ZDBK",  cacheKey="zdbk_Transcript",        ttl=1h)
        registerSource(name="ZDBK 考试",    category="ZDBK",  cacheKey="zdbk_exams",             ttl=1h)
        registerSource(name="ZDBK 课表",    category="ZDBK",  cacheKey=null,                    ttl=1h)   // 动态 key
        registerSource(name="开课情况",      category="ZDBK",  cacheKey=null,                    ttl=24h)  // 动态 key
        registerSource(name="培养方案",      category="ZDBK",  cacheKey="zdbk_trainingPlans",     ttl=24h)
        registerSource(name="教务通知",      category="ZDBK",  cacheKey="zdbk_notifications",     ttl=30min)

        // ── Classroom ──
        registerSource(name="智云课堂",      category="Classroom", cacheKey="classroom_courses", ttl=1h)

        // ── Courses API（内存缓存）（2 个） ──
        registerSource(name="学在浙大 课程",  category="Courses", cacheKey=null,  ttl=5min)
        registerSource(name="学在浙大 考试",  category="Courses", cacheKey=null,  ttl=10min)

        // ── Todo / PTA ──
        registerSource(name="待办事项",       category="Todo",    cacheKey=null,  ttl=5min)
        registerSource(name="PTA 编程题",     category="PTA",     cacheKey=null,  ttl=30min)

        // ── AI 服务（连通性检查） ──
        registerSource(name="DeepSeek API",  category="AI",   cacheKey=null,  ttl=1min)
        registerSource(name="DeepSeek OCR",  category="AI",   cacheKey=null,  ttl=1min)

    // ═══ 查询 ═══

    method sources -> List<DataSourceStatus>:
        // 按分类 + 名称排序返回全部数据源
        order = ["ZDBK", "Courses", "Classroom", "Todo", "PTA", "AI"]
        return _sources.values 按 order 排序

    method source(name) -> DataSourceStatus?:
        return _sources[name]

    method byCategory(category) -> List<DataSourceStatus>:
        return _sources.values.where(s.category == category)

    method categories -> List<string>:
        // 按注册顺序返回不重复的分类列表

    // ═══ 计数 ═══

    computed connectedCount -> int:
        return count(s in _sources where s.connected == true)

    computed freshCount -> int:
        return count(s in _sources where s.isFresh == true)

    computed totalCount -> int:
        return _sources.length

    // ═══ 状态刷新 ═══

    method refreshFreshness(db : WebCacheDatabase):
        // 从文件缓存读取各数据源的 cachedAt 时间戳
        // 仅更新 cacheKey != null 的数据源

        now = DateTime.now()
        isAW = (now.month >= 9 or now.month <= 2)
        year = isAW ? now.year : now.year - 1
        semester = isAW ? 3 : 12

        for each s in _sources.values:
            found = false

            // 优先查静态 cacheKey
            if s.cacheKey != null:
                ts = db.getCacheTimestamp(s.cacheKey)
                if ts != null:
                    s.lastFetchedAt = ts
                    found = true

            // 回退到动态 key（ZDBK 课表 / 开课情况）
            if not found:
                for each k in _dynamicKeys(s.name, year, semester):
                    ts = db.getCacheTimestamp(k)
                    if ts != null:
                        s.lastFetchedAt = ts
                        found = true
                        break

            // cacheKey=null 的数据源不在此处设置时间戳——
            // 由 updateDataStatus() 显式赋值，避免过期后永远显示"过期"

    helper _dynamicKeys(name, year, semester) -> List<string>:
        switch name:
            case "ZDBK 课表": return ["zdbk_Timetable{year}_{semester}"]
            case "开课情况":   return ["zdbk_courseOfferings_{year}_{semester}"]
            default:          return []

    // ═══ 连通性更新 ═══

    method updateConnectivity(name, connected, error?):
        s = _sources[name]
        if s != null:
            s.connected = connected
            s.lastError = error
```

---

### 5. CacheTtl — TTL 常量

```
class CacheTtl:
    const transcript      = 1 hour
    const majorGrade      = 1 hour
    const exams           = 1 hour
    const timetable       = 1 hour
    const notifications   = 30 minutes
    const courseOfferings = 24 hours
    const trainingPlans   = 24 hours
    const practiceScores  = 6 hours
```

---

### 6. Provider 层（Riverpod 连接）

```
// ── ConnectionManager 实例 ──
provider connectionManagerProvider -> ConnectionManager:
    // 仅在鉴权状态变化时重建；不做定时自动检查（开销太大）
    return ConnectionManager(httpClient, cookieJar, auth, zdbkService)

// ── 全量连接检查（仅手动刷新时触发） ──
provider connectivityCheckProvider -> List<ConnectionResult>:
    results = await connectionManager.checkAll()

    // 自动重试失败的服务（最多 1 次）
    retried = []
    for each r in results:
        if not r.ok:
            retried.append(await connectionManager.checkOne(r.service))
        else:
            retried.append(r)
    return retried

// ── 数据状态管理器（持久实例） ──
provider dataStatusManagerProvider -> DataStatusManager:
    db = await WebCacheDatabase.getInstance()
    manager = DataStatusManager()
    manager.registerDefaults()
    manager.refreshFreshness(db)
    return manager

// ── 刷新计数器（UI watch 此 provider 可在刷新后重建） ──
provider dataStatusTickProvider -> int = 0

// ── 更新单个数据源状态 ──
function updateDataStatus(ref, name, ok, error?):
    mgr = ref.read(dataStatusManagerProvider)
    if mgr is null: return

    src = mgr.source(name)
    if src is null: return

    src.connected = ok
    if ok:
        src.lastFetchedAt = now()
        src.lastError = null
    else:
        src.lastError = error

    ref.read(dataStatusTickProvider)++   // 触发 UI 重建
```

---

### 7. UI 层（QuickConnectScreen）交互流程

```
state QuickConnectScreen:
    field _retryResults : Map<string, AsyncValue<ConnectionResult>>  // 单服务重试结果
    field _retrying     : Set<string>                                 // 正在重试的服务名

    on init / on resume:
        invalidate connectionManagerProvider    // 重建 ConnectionManager
        invalidate connectivityCheckProvider    // 重新检查连通性
        invalidate dataStatusManagerProvider    // 重新加载数据状态

    // ── Section 1: 服务连通性列表 ──
    build connectivityCards:
        for each ConnectionResult r in merged results:
            icon  = r.ok ? ✅ : ❌
            title = r.service
            sub   = r.ok ? "{r.elapsed}ms" : r.message
            trail = r.ok ? verified_icon : retry_button
            retry_button.onPressed => _retryService(manager, r.service)

    // ── Section 2: 数据新鲜度列表 ──
    build freshnessCards:
        for each category in manager.categories:
            section_header(category)
            for each DataSourceStatus s in manager.byCategory(category):
                badge = s.lastFetchedAt == null ? "从未"
                      : s.isFresh ? "新鲜"
                      : "过期"
                sub = s.relativeTime
                trail = refresh_button -> _refreshDataSource(s.name)

    // ── 全量刷新 ──
    method _refreshAll():
        invalidate 所有数据 provider（zdbk / courses / classroom / todo / connectivity）
        results = await connectivityCheckProvider.future
        invalidate dataStatusManagerProvider
        显示 SnackBar: "{ok}/{total} 连通"

    // ── 单源刷新 ──
    method _refreshDataSource(name):
        显示进度 SnackBar
        switch name 匹配对应的 provider → invalidate → await future
        调用 updateDataStatus(ref, name, ok, error)
        显示结果 SnackBar
```

---

## 数据流

```
用户点击刷新
    │
    ├─→ invalidate connectivityCheckProvider
    │       │
    │       ▼
    │   ConnectionManager.checkAll()
    │       │  依次检查 7 个服务
    │       │  失败服务自动重试 1 次
    │       ▼
    │   List<ConnectionResult>  →  UI Section 1 渲染
    │
    └─→ invalidate dataStatusManagerProvider
            │
            ▼
        DataStatusManager.refreshFreshness(db)
            │  从 WebCacheDatabase 读取各 cacheKey 的 cachedAt
            ▼
        List<DataSourceStatus>  →  UI Section 2 渲染
            │
            ▼
        用户点击单个数据源的刷新按钮
            │
            ▼
        _refreshDataSource(name)
            │  invalidate 对应 Provider → 发起网络请求
            │  成功后 updateDataStatus() 设置 lastFetchedAt = now()
            ▼
        dataStatusTickProvider++  →  UI Section 2 局部重建
```
