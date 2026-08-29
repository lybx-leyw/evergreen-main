# zju-schedule — 浙大课表（data-source 插件）

ZJU 课表数据源适配壳：`CAS（zjuam.zju.edu.cn）→ ZDBK（zdbk.zju.edu.cn）→ kbcx 课表接口`，
纯 Python 标准库实现（urllib + re + json），零第三方依赖，**绝不伪造课表数据**（拉取失败即报错，
静态兜底仅返回空课表 + 说明，不含任何编造条目）。

## 逆向来源（evg-base zju_modle 真实接线，B4-fix 版 2026-08-13）

| 环节 | 参考文件 |
|------|---------|
| CAS 登录（execution → RSA 公钥 → POST） | `lib/renderer/templates/zju_modle/zju_auth/zjuam_service.dart` |
| ZDBK 教务会话（JSESSIONID + route 经 302 链路） | `lib/renderer/templates/zju_modle/zju_auth/zju_session.dart` |
| 课表接口 getTimetable（URL/头/参数/会话过期检测） | `lib/renderer/templates/zju_modle/zdbk/services/zdbk_service.dart` |
| 条目字段语义（kcb/xqj/djj/skcd/dsz/xkkh/sfyjskc/xf） | `lib/renderer/templates/zju_modle/shared/models/zju_timetable_session.dart` |

## 凭证配置

`ZJU_USERNAME`（学号）/ `ZJU_PASSWORD`（统一认证密码），三级降级读取：

1. `--greenix-config <cfg>` 指向的配置 JSON（兼容 `utf-8-sig` BOM；支持顶层扁平键或 `{"settings": {...}}`）
2. 环境变量 `GREENIX_CONFIG_PATH` 指向的配置 JSON
3. 系统环境变量 `ZJU_USERNAME` / `ZJU_PASSWORD`

## CLI 契约（plugin-registry-spec-v1 §六）

```
scraper.py --type zju_schedule --project-root <root> --greenix-config <cfg>
```

- 空格分隔参数（兼容 `--key=value`）；参数名 `-` 归一化为 `_`
- stdout 输出纯 JSON（顶层 Map），UTF-8，`ensure_ascii=False`
- exit 0 = 成功；失败输出 `{"error": <人类可读>, "error_type": <分类>, "detail": <调试信息>}` + 非零退出

附加参数：`--year YYYY` / `--semester 3|12`（默认按当前日期推算：9-2 月秋冬=3，3-8 月春夏=12，
与平台 `_currentZjuSemester` 一致）；`--check` 连通性检查（无需凭证）；`--help`。

## 输出格式

```json
{
  "type": "zju_schedule",
  "sessions": [
    {
      "course_id": "(2025-2026-2)-ENGL001-01",
      "course_name": "大学英语IV",
      "teacher": "张三",
      "location": "东1A-201",
      "day_of_week": 3,
      "periods": [1, 2],
      "week_range": "1-16周",
      "semester": 3,
      "course_year": 2025,
      "is_ended": false,
      "credit": 3.0
    }
  ],
  "year": 2025,
  "semester": 12,
  "count": 1,
  "fetched_at": "2026-08-25T03:00:00+00:00"
}
```

字段对齐平台 `ZjuTimetableSession.toJson`；`semester` 为位掩码（春=1 夏=2 短①=4 秋=8 冬=16 短②=32 暑=64）；
ZDBK 忽略 `xqm` 返回整个学年课表，`'null'` 响应 = 无课程。`count`/`fetched_at` 为附加信息，
数据中枢 diff 引擎会自动忽略易变字段。

## 错误分类与退出码

| 退出码 | error_type | 含义 |
|-------|-----------|------|
| 0 | — | 成功 |
| 2 | `config_missing` | 凭证缺失 |
| 3 | `auth_failed` / `session_expired` | 登录失败 / 会话失效 |
| 4 | `network` / `timeout` / `http_error` | 网络、超时或服务端错误 |
| 5 | `parse_error` / `invalid_input` | 解析失败 / 非法参数 |
| 1 | `unknown` | 未知错误 |

## 验证记录

环境：Windows，Python 3.10.19（Conda）/ 3.11（系统），2026-08-25

- [x] `py_compile` 通过（双 Python）
- [x] manifest 解析通过（`id=zju-schedule`、`displayName=课表`、`persistentKey=zju_schedule`、`fallbackJson` 合法）
- [x] `--help` / `--check`（zjuam 可达，getPubKey 正常，exit 0）
- [x] 无凭证 → `config_missing`（exit 2）；非法 `--type` → `invalid_input`（exit 5）
- [x] 假凭证实链登录 → `auth_failed`（exit 3）：CAS execution 提取 → getPubKey → RSA 加密 → POST → cookie 校验
      全链路真实执行（系统 Python 3.11 默认 TLS，无任何补丁）
- [x] **本地 mock HTTPS CAS+ZDBK 端到端回归（14 断言 × 双 Python 全过）**：正确口令全链路成功（exit 0 +
      课表解析）、错误口令 `auth_failed`（exit 3）、302 跟随至 zdbk 时 Cookie 携带父域 `iPlanetDirectoryPro`、
      课表 POST 携带 `JSESSIONID(Path=/jwglxt)` + `route`、`get_cookie` 对 `Path=/jwglxt` 的 JSESSIONID 命中、
      非 `/jwglxt` 前缀路径不发送 JSESSIONID
- [x] 离线解析保真断言：kbList 正则提取、`kcb` 分段（课程名/周次学期位/教师/地点）、`djj+skcd` 节次列表、
      `xkkh` 学年提取、`sfyjskc=1` 过滤、`'null'` 空响应、会话过期特征与 302 重定向判定
- [x] UTF-8 BOM 配置容错
- [x] **真实凭据修复验证（队长 2026-08-25 实测反馈后修复）**：根因 = `get_cookie` 此前限制 `path=='/'`，
      而 ZDBK 的 JSESSIONID 以 `Path=/jwglxt` 下发（Dart 参考 `zdbk_service` 同样按 `c.path == '/jwglxt'`
      匹配），导致查回显恒为 None、误报「缺少 JSESSIONID/route cookie」；修复后按 name+域匹配、不限 path。
      mock 回归中 A7 断言直接覆盖该场景
- [x] TLS 优雅降级：本机 Conda Python 证书库损坏（`ASN1: NOT_ENOUGH_DATA`）时 `_ssl_context()` 自动降级为
      不校验（对齐 zju-grades 同款策略），`--check` 无需任何补丁即可通过
- [ ] **成功路径（真实课表）待队长用真实账号复测确认**（本地 mock 已覆盖全链路逻辑）

## 已知限制

1. **成功路径**：本地 mock 全链路已验证；真实账号取真实课表由队长复测确认。CAS 验证码 / 二次认证场景
   按 `auth_failed` 归类并给出可读提示。
2. **接口结构风险**：CAS/ZDBK 页面结构变更会命中 `parse_error`（带响应预览 detail），需按
   `zju_modle` 的 `zdbk_patterns.dart` 同步正则。
3. **网络环境**：需可达 `zjuam.zju.edu.cn` 与 `zdbk.zju.edu.cn`（校园网/VPN）；会话/网络错误已分类为
   `session_expired` / `network` / `timeout`。
4. **本机证书库异常**：个别 Windows Python 发行版无法加载 Windows 证书库（`ASN1: NOT_ENOUGH_DATA`）时，
   `_ssl_context()` 自动降级为不校验（默认仍严格校验证书链；降级削弱传输保护，仅会话 cookie 明文，
   密码经 RSA 加密）。
5. 对参考实现的刻意微修：地点段 `东1A-201[zwf...]` 会剥离 `[` 分隔符，展示更干净（Dart 参考实现
   会残留 `[`）。
