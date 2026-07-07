# plugins/courses 数据链路诊断报告

> 日期：2026-07-07 | 状态：✅ 全部修复，端到端验证通过

---

## 一、数据流链路（端到端）

```
用户打开课程页面
  → CompositeView._DataTableSlot / _TimetableSlot
  → _fetchFromData(ds, dataPort)
    → GET http://127.0.0.1:{dataPort}/data/types/{typeName}
    → DataHttpServer 路由
    → orchestrator.get(DataType(name))
    → main.dart _scanAndRegisterDataSources 注册的 CLI fetcher
    → Process.run("zdbk_data.exe", ["--type", typeArg, "--project-root", projectRoot])
      → zdbk_data.py 启动
        → 读 .config_port → ConfigHttpServer → 获取 ZJU_USERNAME/ZJU_PASSWORD
        → CAS 登录（zjuam.zju.edu.cn）→ iPlanetDirectoryPro cookie
        → courses.zju.edu.cn SSO（/user/index → Keycloak + CAS 重定向）→ session cookie
        → / zdbk.zju.edu.cn SSO（CAS → ZDBK 跳转）→ JSESSIONID
        → 数据 API 调用 → stdout JSON
    → orchestrator 缓存 → DataHttpServer 包装 → 返回给 renderer
  → _extractList(data, dataPath) → Flutter Widget 渲染
```

**关键洞察**：courses.zju.edu.cn 和 zdbk.zju.edu.cn 各有独立的 SSO 认证链路：
- `courses.zju.edu.cn`：CAS → Keycloak 联合认证，需要 `session`/`route`/`role_token` 专用 cookie
- `zdbk.zju.edu.cn`：CAS → ZDBK 跳转，需要 `JSESSIONID`

---

## 二、发现的 Bug（全部已修复）

### Bug #1：`_cas_login()` / `_zdbk_session()` 的 CookieJar 未被使用 🔴

**位置**：`plugins/courses/data/zdbk_data.py`

**根因**：创建了 `CookieJar` + `HTTPCookieProcessor` opener，但所有 HTTP 请求实际通过 `_urlopen()` 发出（直接创建连接，不经过 CookieJar），cookie 从未被捕获。

**修复**：新增 `_build_ssl_opener()`，所有认证相关请求改为 `op.open()`。

---

### Bug #2：SSL `DH_KEY_TOO_SMALL` 错误 🔴

**根因**：ZJU 服务器使用弱 DH 密钥（< 2048 bits），Python 3.10+ 默认拒绝。`ssl._create_unverified_context()` 仅跳过证书验证，不降低 DH 要求。

**修复**：所有 SSL context 添加 `set_ciphers('DEFAULT:@SECLEVEL=1')`。

---

### Bug #3：`zdbk_data.exe` 未编译 🔴

**根因**：只有 `.py` + `.spec`，无 `.exe`。`main.dart` 注册了 fetcher 但 `Process.run()` 找不到可执行文件。

**修复**：PyInstaller 编译 → 8.2MB 可执行文件。

---

### Bug #4：courses_list API 缺少 query 参数 → HTTP 400 🔴

**根因**：`GET /api/my-courses` 需要 `?page=1&page_size=1000&sort=all` 参数，原始代码未携带。

**修复**：添加 URL query 参数。

---

### Bug #5：timetable JSON 解析：regex `\[.*?\]` 对嵌套 JSON 匹配不完整 🔴

**根因**：`kbList` 包含嵌套对象，非贪婪匹配 `.` 不匹配换行 + `.*?` 在第一个 `]` 就停止，导致 JSON 截断。

**修复**：用括号深度匹配算法替代正则。

---

### Bug #6：`_zdbk_session()` 手动 Cookie header 在重定向时丢失 → HTTP 901 🔴

**根因**：`HTTPRedirectHandler` 创建重定向请求时不复制自定义 header（包括 `Cookie`）。手动添加的 `iPlanetDirectoryPro` header 在 CAS→ZDBK 跳转时丢失。

**修复**：将 `iPlanetDirectoryPro` 作为 Cookie 对象写入 CookieJar（`domain=.zju.edu.cn`），`HTTPCookieProcessor` 自动在所有匹配域名的请求中附上。

---

### Bug #7：`fetch_courses_list()` 缺少 courses.zju.edu.cn SSO 步骤 → HTTP 401 🔴

**根因**：courses.zju.edu.cn 使用 Keycloak + CAS 联合认证。仅靠 `iPlanetDirectoryPro` cookie 不够，需要先访问 `/user/index` 触发完整 SSO 重定向链，获取 `session`/`route`/`role_token` 等 courses 专用 cookie。

**修复**：新增 `_courses_session()` 函数，模拟完整 SSO 流程：
1. 先将 `iPlanetDirectoryPro` 写入 CookieJar（domain=`.zju.edu.cn`）
2. 访问 `courses.zju.edu.cn/user/index` → CAS 重定向 → Keycloak → courses 设置 session cookie
3. CookieJar 自动收集所有 cookie
4. 然后调用 API

---

## 三、修复范围总结

| 文件 | 修改内容 |
|------|---------|
| `plugins/courses/data/zdbk_data.py` | +`_build_ssl_opener()`；+`_courses_session()`；修复 `_cas_login()`/`_zdbk_session()` 使用 opener；SSL 降级；cookie 写入 CookieJar（domain）；JSON 括号深度解析；API query 参数 |
| `plugins/courses/data/zdbk_data.exe` | 重新编译（Python 3.14 + PyInstaller 6.21，含所有修复） |
| `main.dart` | **未修改** |

---

## 四、端到端验证结果

| 测试项 | 结果 | 说明 |
|--------|------|------|
| `zdbk_data.py` courses_list | ✅ 通过 | 29 门课程 |
| `zdbk_data.py` courses_timetable | ✅ 通过 | 41 个课时 |
| `zdbk_data.exe` courses_list | ✅ 通过 | 29 门课程（mock config server） |
| `zdbk_data.exe` courses_timetable | ✅ 通过 | 41 个课时（mock config server） |
| SSL 兼容性 | ✅ 通过 | `DH_KEY_TOO_SMALL` 已解决 |
| CookieJar 端到端 | ✅ 通过 | CAS + courses SSO + ZDBK SSO 全链路 |

**数据链路代码层面已全部验证通过。**
