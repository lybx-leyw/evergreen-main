# zju-grades —— 浙大成绩数据源插件（data-source · 模型 A CLI）

ZJU 教务（zdbk.zju.edu.cn）**真实成绩单**数据源。`data/scraper.py` 用纯 Python
标准库（urllib + 裸 RSA）实现与平台内置 Dart fetcher **同源同构**的登录与取数链路，
输出 `{"grades": [...], "domestic_gpa": {...}, "abroad_gpa": {...}}`（成绩 + 双策略 GPA）。

## 逆向接线（对齐 zju_modle，非占位实现）

| 环节 | 参考实现（平台 Dart） | 本插件实现 |
|------|----------------------|-----------|
| CAS SSO 登录（execution + RSA 公钥 + rememberMe） | `zju_auth/zjuam_service.dart` | `scraper.py: ZdbkClient.sso_login` |
| RSA 加密（UTF-8 → BigInt → modPow → hex 补零 128 位） | `zjuam_service.rsaEncrypt` | `scraper.py: rsa_encrypt` |
| ZDBK 会话（service validation → 302 Location → JSESSIONID/route cookie） | `zju_auth/zju_session.dart` + `zdbk/services/zdbk_service.dart: login` | `scraper.py: ZdbkClient.zdbk_login` |
| 成绩单接口 | `zdbk_service.getTranscript` → `…/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000` | `scraper.py: ZdbkClient.get_transcript` |
| 标准请求头（Referer / X-Requested-With / Accept） | `zdbk_service._zdbkSetHeaders` | `scraper.py: _zdbk_post` |
| items 提取正则（limit / totalResult 两步） | `zju_auth/zdbk_patterns.dart` | `scraper.py: extract_items` |
| 会话过期检测 + 自动重登 1 次 | `html_parser.isSessionExpired` + `_withAutoRelogin` | `scraper.py: _is_session_expired` / `fetch_grades` |
| 成绩模型（排除规则 / 绩点映射 / realId 归一化） | `shared/models/zju_grade.dart` | `scraper.py: ZjuGrade` |
| 双策略 GPA（保研首考 / 出国最高，4 刻度） | `shared/utils/zju_gpa_calculator.dart` | `scraper.py: calculate_gpa` + `pick_first_attempt` / `pick_highest_attempt` |

### 登录链路（无凭据不可达，未在真实账号下验证）

```
GET  https://zjuam.zju.edu.cn/cas/login
     → 解析 name="execution" value="..."
GET  https://zjuam.zju.edu.cn/cas/v2/getPubKey
     → {"modulus": <hex 128>, "exponent": "10001"}
POST https://zjuam.zju.edu.cn/cas/login
     username / password(RSA-hex 补零 128) / execution / _eventId=submit / rememberMe=true
     → Set-Cookie: iPlanetDirectoryPro（域 .zju.edu.cn）
GET  https://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html
     （携带 iPlanetDirectoryPro，禁重定向）→ 302 Location
GET  Location（http→https 归一）→ Set-Cookie: JSESSIONID(path=/jwglxt) + route
POST https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000
     → 响应含 items JSON 数组 → 解析 → grades
```

会话失效（响应命中 `login_ssologin` / `cas/login` / `统一身份认证` 等 CAS 页特征）
时自动重登一次；仍失败则错误信息带 `ZdbkAuthError` 前缀——平台
`zjuIsSessionExpiredError`（`zju_session.dart`）按该特征识别为会话失效，会经
`SessionCoordinator`（zju 会话提供者）单点重登后自动重拉本数据源。

## CLI 契约（plugin-registry-spec-v1.md §六）

```
python scraper.py --type zju_grades --project-root <root> --greenix-config <cfg>
```

- stdout 顶层 Map（UTF-8，`ensure_ascii=False`）
- 成功（exit 0）：`{"grades":[{xkkh,kcmc,xf,cj,jd,major}], "domestic_gpa":{…},
  "abroad_gpa":{…}, "authenticated":true, "source":"zdbk"}`
- 失败（exit ≠ 0）：`{"error":"<人类可读>", "errorClass":"<分类>"}`

| errorClass | 退出码 | 场景 |
|------------|--------|------|
| `config_missing` | 2 | 未配置 ZJU_USERNAME / ZJU_PASSWORD |
| `network` | 3 | 网络不可达 / 超时 / TLS 异常 |
| `auth` | 4 | 学号或密码错误 / 验证码 |
| `session_expired` | 4 | ZDBK 会话失效且自动重登失败（消息含 `ZdbkAuthError`） |
| `parse` | 5 | 教务页面结构变更 / 响应解析失败 |
| `unknown` | 1 | 兜底 |

凭证三级降级读取（`--greenix-config` 的 config.json → `GREENIX_CONFIG_PATH` /
`<project-root>/.greenix/config.json` → 环境变量），**不硬编码、不落盘密码**。

## 诚实声明

- **不伪造数据**：只输出教务网真实返回的成绩；无法登录 / 取数一律 error JSON +
  非零退出。manifest `fallbackJson` 仅含 `"grades": []` + `fromFallback: true`
  标记（拉取失败且无旧缓存时由数据中枢返回），**不包含任何虚构成绩**。
- **完整登录未在真实账号下验证**（无凭据）。已在线验证的环节见下。
- 平台侧 `zju_scores`（`zju_data_sources.dart` 内置 Dart fetcher）是**权威实现**；
  本 CLI 插件是与之同源的可选路径（外部脚本 / 无 Dart 环境场景），数据与口径一致。
- CLI 每次调用全量登录（无 cookie 持久化）；数据中枢 `persistentKey: zju_grades`
  + TTL 10m 缓存缓解重复登录。

## 验证记录（2026-08，Windows / Python 3.10）

- `python -m py_compile scraper.py` ✅；manifest / config JSON 解析 ✅
- 在线探测（无凭据只读）：
  - `cas/login` 返回 200 且含 execution token ✅
  - `cas/v2/getPubKey` 返回 modulus（128 hex）+ exponent ✅
  - CAS service validation 无有效 SSO cookie → 200 无重定向（与参考
    `location == null` → 会话无效分支一致）✅
  - `zdbk.zju.edu.cn` 可达 ✅
- 无凭据路径：exit 2 + `config_missing` ✅；假凭据全链路：走完 SSO 4 步后
  服务器拒绝 → exit 4 + `auth`（登录链已真实执行）✅
- 解析 / GPA 单测（合成 ZDBK 响应样本）：items 提取、重修分组、首考/最高
  双策略 ✅（见 `data/scraper.py` 内置函数，可用 `python -c` 自测）

## 维护提示

- ZDBK 改版时只需调整 `extract_items` 正则（对齐 `zdbk_patterns.dart`）。
- TLS 校验默认开启；个别 Windows Python 发行版证书库损坏时自动降级为不校验
  （`_ssl_context`），该降级会削弱传输保护，请尽量使用证书库正常的解释器。
