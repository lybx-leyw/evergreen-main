# zjucrawler — ZJU 教务数据源（data-source 插件）

| 项 | 值 |
|----|----|
| 插件 id | `zjucrawler`（**不可改**） |
| 形态 | data-source（模型 A：CLI 一次性脚本） |
| 数据类型 | `zju_course` — 我的课程（学在浙大，courses.zju.edu.cn） |
| 运行环境 | Python（纯标准库，零第三方依赖，双平台） |

## 做什么

用浙大统一认证（CAS）登录后，从「学在浙大」`courses.zju.edu.cn` 拉取**当前账号已选课程**
的真实数据，输出为 JSON 供 Evergreen 数据中枢缓存/消费。**绝不伪造/占位课程数据**：
登录失败、会话过期、网络错误一律返回分类错误 + 非零退出，由数据中枢走旧缓存/静态兜底降级。

## 逆向接线（对齐 evg-base 内置 Dart fetcher）

本适配壳逐段复刻 `lib/renderer/templates/zju_modle/` 内置 `zju_courses` 数据链路：

```
zju_data_sources.dart  _fetchZjuCourses
  → zju_session.dart   ensureZjuSession        （SSO cookie / 凭证登录）
  → zjuam_service.dart ZjuAmService.login       （CAS RSA 登录）
  → auth_service.dart  AuthService.loginCourses （courses 域会话换取）
  → courses_api_service.dart CoursesApiService.getMyCourses
```

Python 对应实现（scraper.py）：

0. **会话复用**（对齐 `ensureZjuSession` Tier 1）：本账号持久化 cookie jar
   （`<greenix>/.greenix/zjucrawler_cookies_<hash8>.txt`，Mozilla 格式，按学号
   hash 命名防跨账号串用）有效时直接取数（实测 ~6s）；接口判「会话过期」才走
   完整登录——避免慢网下逼近平台 60s 超时，也减少 CAS 登录挤占。
1. **CAS 登录** `https://zjuam.zju.edu.cn`：GET `/cas/login` 取 `execution` →
   GET `/cas/v2/getPubKey` 取 RSA 公钥 → RSA 加密密码（对齐 `rsaEncrypt`，
   `int.from_bytes` + `pow(m,e,n)` + hex 至少 128 位）→ POST `/cas/login`
   （`_eventId=submit&rememberMe=true`）→ 捕获 `iPlanetDirectoryPro`，按
   `.zju.edu.cn` 域级注入 cookie jar（对齐 `_injectSsoCookie`）。
2. **courses 会话**：GET `https://courses.zju.edu.cn/user/index` 沿 CAS 跳转链
   换取 courses 域会话 cookie（对齐 `_loginCourses`）。
3. **取数**：POST `https://courses.zju.edu.cn/api/my-courses`
   （`Content-Type: application/json`）→ 解析 `courses` 列表 → 归一化为内置
   `ZjuCourse.toJson` 同款字段（`id/name/course_code/class_name/teacher_name/
   teaching_place/course_type_name/is_started/is_closed/credits`）。

**TLS 鲁棒性**：严格校验证书为默认；个别 Windows 机器系统证书存储损坏时自动
回退 OpenSSL 自带 CA bundle（`[ASN1: NOT_ENOUGH_DATA]` 修复）；老站点
（courses）DH 参数过小时仅对该连接降级 `SECLEVEL=1` 重试一次（证书校验不变）。

> 为什么不在插件里做 Dart fetcher：本插件是第三方 data-source（registry 收录的
> 静态资源），运行时是独立 Python 进程；Dart 侧内置 `zju_courses` 仍是同一数据的
> 首选（共享 app 会话），本插件用于**无内置模板/独立环境**时提供等价数据。

## CLI 契约（模型 A）

```
python scraper.py --type zju_course --project-root <root> --greenix-config <cfg>
```

- 参数**空格分隔**（同时容忍 `--type=value` 写法）。
- stdout 只输出单个顶层 JSON Map（UTF-8）；日志一律走 stderr。
- 成功：exit 0，`{"courses": [ ... ], "count": N}`。
- 失败：`{"error": "<中文信息>", "error_code": "<分类>", "code": <退出码>}` + 非零退出。

### 错误分类（error_code → exit code）

| error_code | exit | 含义 |
|------------|------|------|
| `missing_config` | 2 | 未配置 `ZJU_USERNAME` / `ZJU_PASSWORD` |
| `auth_failed` | 3 | CAS 登录被拒绝（学号/密码错误、登录页解析失败） |
| `session_expired` | 4 | SSO 会话未被目标站接受（落在登录页 / 接口返回网页） |
| `network_error` | 5 | 网络不可达 / 超时 / TLS 失败 / HTTP 4xx/5xx |
| `parse_error` | 6 | 接口返回非预期格式 |
| `unsupported_type` | 7 | `--type` 不在支持列表（仅 `zju_course`） |
| `unknown` | 1 | 未分类异常兜底 |

### 凭证读取（多级降级，绝不硬编码）

`--greenix-config` 文件 → `GREENIX_CONFIG_PATH` 文件 → ConfigHttpServer
（`.config_port` → `/config/settings/<key>`）→ 环境变量。

## manifest 关键声明

- `auth.sessionProvider: "zju"` + `sessionDomain: "courses.zju.edu.cn"`：
  数据源与平台 zju 会话中心绑定（会话失效时可触发单点重登 + 后台同域重试）。
- `persistentKey: "zjucrawler_zju_course"`：独立缓存键（不与内置 `zju_courses` 冲突）。
- `fallbackJson: {"courses": []}`：拉取失败且无旧缓存时的**诚实空兜底**。
- `dataTypes[].name = "zju_course"`：避免覆盖注册内置 `zju_courses`。

## 本地验证

```bash
# 1. 语法
python -m py_compile data/scraper.py
# 2. 无凭据路径（应 exit 2 + missing_config JSON）
python data/scraper.py --type zju_course
# 3. 不支持类型（应 exit 7 + unsupported_type JSON）
python data/scraper.py --type zju_grades
# 4. 有凭据实测（.greenix/config.json 含 ZJU_USERNAME/ZJU_PASSWORD）
python data/scraper.py --type zju_course --project-root <repo> --greenix-config <repo>\.greenix\config.json
```

## 已知边界

- 仅实现 `zju_course`（我的课程）；旧版声称的成绩/考试（jwbinfosys 页）因登录
  参数与解析均与真实接口不符，已移除——需要成绩请用 `zju-grades` 插件，课表用
  `zju-schedule`。
- 每次运行独立登录（60s 平台超时内完成，脚本自带 50s 软期限）；依赖校园网/
  公网可达 `zjuam.zju.edu.cn` 与 `courses.zju.edu.cn`。
