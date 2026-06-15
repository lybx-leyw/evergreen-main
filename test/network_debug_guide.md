# 网络端点调适手册

> 逐条 curl 验证，勾选确认。变量：`$SSO`=iPlanetDirectoryPro, `$JSID`=JSESSIONID, `$ROUTE`=route

---

## A. ZJUAM（统一认证）

| # | 端点 | curl |
|---|------|------|
| A1 | 获取 execution token | `curl -s 'https://zjuam.zju.edu.cn/cas/login' \| grep -oP 'name="execution"\s+value="\K[^"]+'` |
| A2 | RSA 公钥 | `curl -s 'https://zjuam.zju.edu.cn/cas/v2/getPubKey'` |
| A3 | 登录 | POST `/cas/login`，body: `username=学号&password=RSA密文&execution=TOKEN&_eventId=submit&rememberMe=true` |

**预期 A1:** 64 位 hex → ⬜
**预期 A2:** `{"modulus":"...","exponent":"10001"}` → ⬜
**预期 A3:** `Set-Cookie: iPlanetDirectoryPro=xxx` → ⬜

---

## B. ZDBK（教务）

**公共 Headers:** `Referer: https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html`, `X-Requested-With: XMLHttpRequest`, `Cookie: JSESSIONID=$JSID; route=$ROUTE`

| # | 端点 | 数据用途 | curl |
|---|------|---------|------|
| B0 | CAS 验证 | 登录 | `curl -s -D - 'https://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html' -H 'Cookie: iPlanetDirectoryPro=$SSO'` |
| B1 | 成绩单 | `Grade` 模型 | `curl -s -X POST 'https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000' -H '...'` |
| B2 | 主修成绩 | `Grade` + GPA | `curl -s -X POST 'https://zdbk.zju.edu.cn/jwglxt/zycjtj/xszgkc_cxXsZgkcIndex.html?doType=query&queryModel.showCount=5000' -H '...'` |
| B3 | 考试安排 | `Exam` 模型 | `curl -s -X POST 'https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html?doType=query&queryModel.showCount=5000' -H '...'` |
| B4 | 开课情况 | `CourseOffering` | `curl -s -X POST 'https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html?gnmkdm=N159035&doType=query&tjksxq=2024-20251&tjjsxq=2024-20251&cxType=jxrw&queryModel.showCount=10000' -H '...'` |
| B5 | 课表 | `TimetableSession` | `curl -s -X POST 'https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html' -H 'Content-Type: application/x-www-form-urlencoded' -H '...' -d 'xnm=2024&xqm=12'` |
| B6 | 实践分数 | 二/三/四课堂 | `curl -s 'https://zdbk.zju.edu.cn/jwglxt/dessktgl/dessktcx_cxDessktcxIndex.html?gnmkdm=N108001&layout=default&su=学号' -H '...'` |

**数据验证：**

| 端点 | 必须字段 | curl 结果 |
|------|---------|:---:|
| B1 | `items[].{xkkh, kcmc, xf, cj, jd}` | ⬜ |
| B3 | `items[].{xkkh, kcmc, kssj, jssj, cdmc}` | ⬜ |
| B4 | `items[].{kcdm, kcmc, jsxm, xf}` | ⬜ |
| B5 | `kbList[].{xkkh, kcb, jsxm, xqj, jcor}` | ⬜ |
| B6 | HTML 含 "第二课堂"、"第三课堂"、"第四课堂" + 数字 | ⬜ |

---

## C. Courses（学在浙大）

**前置：** 需 CAS 跳转链获取 session cookie

| # | 端点 | 数据用途 | curl |
|---|------|---------|------|
| C0 | 登录入口 | CAS 跳转链 | `curl -s -D - 'https://courses.zju.edu.cn/user/index'` |
| C1 | 课程列表 | `Course` 模型 | `curl -s -X POST 'https://courses.zju.edu.cn/api/my-courses' -H 'Content-Type: application/json' -H 'Cookie: ...'` |
| C2 | 活动详情 | 下载资料 | `curl -s 'https://courses.zju.edu.cn/api/courses/$CID/activities' -H 'Cookie: ...'` |
| C3 | 考试 | `Exam` 模型 (fallback) | `curl -s 'https://courses.zju.edu.cn/api/exams' -H 'Cookie: ...'` |
| C4 | 待办 | `TodoItem` | `curl -s 'https://courses.zju.edu.cn/api/todos' -H 'Cookie: ...'` |
| C5 | 签到检测 | 自动签到 | `curl -s 'https://courses.zju.edu.cn/api/radar/rollcalls' -H 'Cookie: ...'` |

**数据验证：**

| 端点 | 必须字段 | curl 结果 |
|------|---------|:---:|
| C1 | `courses[].{id, name, teacherName, credits}` | ⬜ |
| C3 | `exams[].{id, title, start_at, location}` | ⬜ |
| C4 | `todos[].{id, title, type, deadline}` | ⬜ |
| C5 | `rollcalls[].{rollcall_id, title, status}` | ⬜ |

---

## D. Classroom（智云课堂）

| # | 端点 | 数据用途 | curl |
|---|------|---------|------|
| D0 | OAuth 入口 | 登录链 | `curl -s -D - 'https://tgmedia.cmc.zju.edu.cn/index.php?r=auth%2Flogin&forward=https%3A%2F%2Fclassroom.zju.edu.cn%2F'` |
| D1 | 课程列表 | `ClassroomCourse` | `curl -s 'https://education.cmc.zju.edu.cn/personal/courseapi/vlabpassportapi/v1/account-profile/course?nowpage=1&per-page=100&force_mycourse=1' -H 'Cookie: ...'` |
| D2 | 视频列表 | `ClassroomVideo` | `curl -s 'https://yjapi.cmc.zju.edu.cn/courseapi/v2/course/catalogue?course_id=$CID' -H 'Cookie: ...'` |
| D3 | PPT 幻灯片 | `PptSlide` | `curl -s 'https://classroom.zju.edu.cn/pptnote/v1/schedule/search-ppt?course_id=$CID&sub_id=$SID&page=1&per_page=100' -H 'Cookie: ...'` |
| D4 | 字幕 | `Subtitle` | `curl -s 'https://yjapi.cmc.zju.edu.cn/courseapi/v3/web-socket/search-trans-result?sub_id=$SID&format=json' -H 'Cookie: ...'` |

**数据验证：**

| 端点 | 必须字段 | curl 结果 |
|------|---------|:---:|
| D1 | `params.result.data[].{Id, Title, Teacher}` | ⬜ |
| D2 | `result.data[].{sub_id, title, status, content}` | ⬜ |
| D3 | `list[].content`(内嵌 JSON: `pptimgurl`) | ⬜ |
| D4 | `list[].all_content[{BeginSec, Text}]` | ⬜ |

---

## E. Library（图书馆）— 功能暂停 ⚠️

> **现状：** `api.lib.zju.edu.cn` HTTPS 连接超时，HTTP 回退返回 404。
> API 端点可能已变更或废弃，待重新发现。

| # | 端点 | curl |
|---|------|------|
| E1 | 借阅 (HTTPS) | `curl -s 'https://api.lib.zju.edu.cn/aleph/bor-info' -H 'Cookie: iPlanetDirectoryPro=$SSO'` |
| E2 | 借阅 (HTTP 回退) | `curl -s 'http://api.lib.zju.edu.cn/aleph/bor-info' -H 'Cookie: iPlanetDirectoryPro=$SSO'` |
| E3 | 续借 | `curl -s 'https://api.lib.zju.edu.cn/aleph/renew?CON_LNG=chi&library=ZJU50&item_barcode=BARCODE' -H 'Cookie: ...'` |

**数据验证：** `loans[].{title, author, barcode, due_date}` → ⬜

---

## F. Ecard（一卡通）— 功能暂停 ⚠️

> **现状：** elife.zju.edu.cn 已迁移到 **慧新E校.新中新 (BlueWare)** 平台。
> API 使用独立 `synjones-auth: bearer <token>` 认证，与 ZJU SSO (`iPlanetDirectoryPro`) **不互通**。
> 详见 `docs/dev/ecard-auth-notes.md`。

**认证方式：** `synjones-auth: bearer <token>`（非 Cookie）
**Token 获取：** 需通过 `/plat/login` 页面登录后取得，存于 `localStorage['access_token']`

| # | 端点 | 认证方式 | curl |
|---|------|---------|------|
| F1 | 校园卡信息 + 余额 | `synjones-auth: bearer <token>` | `curl -s 'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc' -H 'synjones-auth: bearer $BWT' -H 'Referer: https://elife.zju.edu.cn/plat-pc/' -H 'X-Requested-With: XMLHttpRequest'` |

**辅助端点：**

| # | 端点 | 用途 | curl |
|---|------|------|------|
| F2 | 登录重定向入口 | 触发 CAS → BlueWare 链 | `curl -s -D - 'https://elife.zju.edu.cn/berserker-base/redirect?type=login&loginFrom=app' -H 'Cookie: iPlanetDirectoryPro=$SSO'` |
| F3 | BlueWare 登录页 | SPA 登录界面 | `curl -s 'https://elife.zju.edu.cn/plat/login?loginFrom=app&type=login'` |
| F4 | 门户主页 | 登录后的 SPA | `curl -s 'https://elife.zju.edu.cn/plat-pc/' -H 'Cookie: ...'` |

**响应格式：** `data.card[0].{name, db_balance(分), account}` → ⬜
**余额转换：** `db_balance / 100` = 元
**变量：** `$BWT` = BlueWare synjones-auth token（非 SSO cookie）

> ⚠️ **注意：** F2 重定向链不会返回 token，只会跳转到 F3 登录页。
> 需在浏览器中手动登录后从 `localStorage.access_token` 提取 `$BWT`。

---

## G. DeepSeek（AI）

| # | 端点 | curl |
|---|------|------|
| G1 | 聊天 | `curl -s -X POST 'https://api.deepseek.com/chat/completions' -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'` |
| G2 | 余额 | `curl -s 'https://api.deepseek.com/user/balance' -H 'Authorization: Bearer $KEY'` |

**数据验证：** G1: `choices[0].message.content` 非空 → ⬜ | G2: `balance` 字段 → ⬜

---

## H. Chalaoshi（查老师）

| # | 端点 | curl |
|---|------|------|
| H1 | 搜索 | `curl -s 'http://chalaoshi.top/?search_query=%E5%BC%A0%E4%B8%89&action=search' -H 'User-Agent: Mozilla/5.0 ...' -H 'Referer: http://chalaoshi.top/'` |
| H2 | 详情页 | `https://chalaoshi.click/t/{teacher_id}` (浏览器打开) |

**数据验证：** H1: HTML 含 `result-item` + `评分` → ⬜ | H2: 页面含教师名 + 评分 → ⬜

---

## I. PTA（Pintia）🆕

| # | 端点 | 数据用途 | curl |
|---|------|---------|------|
| I1 | 登录 | 获取 session cookie | `curl -s -X POST 'https://passport.pintia.cn/api/users/sessions' -H 'Content-Type: application/json' -d '{"phone":"+86188xxxxxxxx","password":"xxx","rememberMe":false}'` |
| I2 | 题目集列表 | 我的题目集 | `curl -s 'https://pintia.cn/api/problem-sets' -H 'Cookie: ...'` |
| I3 | 考试/作业列表 | 题目集内考试 | `curl -s 'https://pintia.cn/api/problem-sets/$PSID/exams' -H 'Cookie: ...'` |
| I4 | 考试题目 | 具体题目 | `curl -s 'https://pintia.cn/api/problem-sets/$PSID/exams/$EXAMID' -H 'Cookie: PTASession=$PTS'` |

> **注意：** Pintia 登录需要**腾讯云验证码 (Tencent Cloud CAPTCHA)**，纯 HTTP 无法绕过。
> 登录 API 始终返回 `GATEWAY_WRONG_CAPTCHA`。需在浏览器登录后手动粘贴 `PTASession` cookie。

**变量：** `$PTS` = PTASession cookie 值

**数据验证：**

| 端点 | 必须字段 | curl 结果 |
|------|---------|:---:|
| I1 | `Set-Cookie` 含 `PTASession` | ⬜ |
| I2 | `problemSets[].{id, name}` | ⬜ |
| I3 | `exams[].{id, title, startAt, endAt}` | ⬜ |
| I4 | `problems[].{id, title, score}` | ⬜

---

## J. Quick Connect（快速连接）

> 一键检查所有服务的连通性，由 `ConnectionManager` 统一管理。
> 自动登录也在启动时通过 `ConnectionManager.checkAll()` 执行。

| # | 服务 | 检查方式 | 依赖 |
|---|------|---------|------|
| J1 | ZDBK 教务网 | `ZdbkService.login()` | SSO cookie |
| J2 | Courses 学在浙大 | `AuthService.loginCourses()` | SSO cookie |
| J3 | Classroom 智云课堂 | `AuthService.loginClassroom()` | SSO cookie |
| J4 | PTA 编程题 | `PintiaService.hasValidSession()` | PTASession 配置 |
| J5 | DeepSeek AI | `AppConfig.deepseekApiKey` 存在性检查 | API Key 配置 |

**页面路径：** 侧边栏「系统」→「快速连接」或 `/quick-connect`

---

## K. 汇总检查清单

| 服务 | 端点 | 响应 OK | 数据字段正确 | 备注 |
|------|------|:---:|:---:|------|
| ZJUAM | A1-A3 | ⬜ | ⬜ | |
| ZDBK | B0-B6 | ⬜ | ⬜ | |
| Courses | C0-C5 | ⬜ | ⬜ | |
| Classroom | D0-D4 | ⬜ | ⬜ | |
| Library | E1-E3 | ⬜ | ⬜ | API 端点不可达，功能暂停 |
| Ecard | F1-F4 | ⬜ | ⬜ | 功能暂停 — BlueWare 平台认证待实现 |
| DeepSeek | G1-G2 | ⬜ | ⬜ | |
| Chalaoshi | H1-H2 | ⬜ | ⬜ | |
| PTA | I1-I4 | ⬜ | ⬜ | 需手动登录（腾讯云验证码） |
| Quick Connect | J1-J5 | ❌ | — | 启动时自动运行 / 侧边栏手动触发 |
