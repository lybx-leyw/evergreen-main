# Evergreen 插件 · 学在浙大自动签到（zju_autosign）

自动监控并应答**学在浙大**（courses.zju.edu.cn）的课堂点名：雷达点名（GPS 坐标提交）与
数字点名（数字码穷举），签到结果实时推送钉钉。逻辑移植自
[ZJU-live-better](https://github.com/cubicYYY/ZJU-live-better) 的 `courses.zju/autosign.js`，
并严格遵循 Evergreen 插件协议（凭证三级降级、stdout 纯 JSON、零硬编码）。

> **安全边界**：本插件不收集、不上传任何数据。凭证只保存在本机 Evergreen 设置中，
> 由脚本按平台契约三级降级读取。签到行为与手动在手机上签到相同（提交 GPS 坐标 / 数字码），
> 请自行确认符合学校与课程要求。

---

## 一、插件结构

```
plugins/zju_autosign/
├── module/
│   ├── manifest.json      # module 声明（HTML 仪表盘 + 长驻 worker 进程）
│   ├── index.html         # 仪表盘页（platform.process：启动/状态/立即签到/地点切换）
│   ├── worker.py          # 长驻监控进程（module.process，scope=long, protocol=stdio）
│   └── autosign_core.py   # 核心：CAS 登录 / 雷达+数字点名 / 钉钉 / 状态持久化
└── config/
    └── config.json        # 新增设置项声明（AUTOSIGN_*）
```

**架构**：本插件是**纯 module + 后端进程**形态（**不是** data-source）：

| 角色 | 机制 | 何时生效 |
|---|---|---|
| worker 常驻监控 | `module.process`（scope=long, protocol=stdio）+ 模块页 `platform.process.start('autosign-worker')` 主动拉起，后台线程按轮询间隔检查并应答，状态经 stdout 逐行（`process:output` 事件）实时推送 | 打开模块页后（页面主动拉起 worker，无需 Evergreen 全局进程管理） |

> **架构说明**：Evergreen 的 HTML 模板（`template:"html"`）不会自动启动 `module.process`，
> 常驻进程须由页面经 `platform.process.start` 主动拉起（stdio 双向流）。这是本插件
> worker 采用 `protocol:"stdio"` 而非 `http` 的原因；也因此**不注册 data-source**
> （签到是持续监控动作，不是「按需取数」的数据源语义）。

---

## 二、安装

1. 将整个 `plugins/zju_autosign` 目录复制到 Evergreen 的插件目录 `plugins/` 下
   （或用市场安装 `.plugin` 包——见「打包」）。
2. **重启 Evergreen**（要求 Python 可用；平台内嵌 Python 即可，本插件零第三方依赖）。
3. 打开侧边栏「校园 → 学在浙大自动签到」——模块页会经 `platform.process.start`
   自动拉起常驻 worker（stdio 常驻终端）。

> 平台要求：Evergreen v2.0（市场为本地扫描，manifest 带 `schemaVersion: "2.0"`）。

### 打包（可选）

```powershell
# 以插件 id 为根目录打 zip，改名为 zju_autosign.plugin 即可
Compress-Archive -Path plugins/zju_autosign -DestinationPath zju_autosign.plugin
```

---

## 三、配置（设置面板）

**复用平台内置 key（无需新增）**：

| key | 说明 |
|---|---|
| `ZJU_USERNAME` | 学号（统一认证账号），**必填** |
| `ZJU_PASSWORD` | 统一认证密码（secure），**必填** |
| `DINGTALK_WEBHOOK` | 钉钉机器人 Webhook（可选，填写后签到结果自动推送） |
| `DINGTALK_SECRET` | 钉钉加签密钥（可选） |

**插件新增设置项（config/config.json 已声明）**：

| key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `AUTOSIGN_ENABLED` | bool | `"true"` | 总开关；关闭后 worker 保持运行但不应答 |
| `AUTOSIGN_RADAR_LOCATION` | option | `"ZJGD1"` | 雷达签到地点（12 个校区点位），失败自动遍历全部点位 → 三点定位 |
| `AUTOSIGN_POLL_INTERVAL` | option | `"4"` | 轮询间隔（2/4/8/15 秒） |

---

## 四、工作流程

```
打开模块页（index.html）
   ├─ platform.process.start('autosign-worker') → 拉起 worker.py（stdio 常驻）
   ├─ platform.onOutput → 接收 worker stdout 逐行 JSON（state/event/notice）
   └─ worker 后台监控线程：
       读配置（三级降级）→ 登录 CAS → 循环：
         GET /api/radar/rollcalls
         ├─ 雷达点名 → 配置地点 → 12 个已知点位 → 球面三点定位
         ├─ 数字点名 → 读现成码 → 0000-9999 并发穷举
         └─ 结果经 stdout 逐行推送 + 推送钉钉
模块页交互：
   「立即签到」→ platform.process.write('autosign-worker', 'checkin\n')
   「暂停/恢复」→ platform.settings.set('AUTOSIGN_ENABLED', ...) → worker 每轮重读
   切换地点 → platform.settings.set('AUTOSIGN_RADAR_LOCATION', ...)
```

**已实现的能力**（对照 autosign.js）：✅ 雷达点名（配置地点优先） ✅ 雷达点位遍历
✅ 三点定位（球面高斯-牛顿最小二乘） ✅ 数字点名（并发穷举 + 现成码读取）
✅ 已应答点名跳过 ✅ 钉钉通知（含加签） ✅ 会话失效自动重登。

---

## 五、上架清单（自检）

- [x] module：`module/manifest.json` 含 `type`/`id`/`name` + `schemaVersion: "2.0"`
- [x] 后端进程：`module/worker.py`（scope=long, protocol=stdio，由页面 `platform.process.start` 拉起）
- [x] 新增设置项：`config/config.json` 声明（key 带 `AUTOSIGN_` 前缀，全局唯一）
- [x] 凭证：全部走 `_get_config` 三级降级（文件 → ConfigHttpServer → 环境变量），零硬编码
- [x] stdout 契约：worker 逐行输出状态/事件 JSON（stdio 常驻终端）；日志全走 stderr
- [x] 失败收敛：任何异常输出 `{"error": "..."}`，进程不崩、不吐堆栈到 stdout
- [x] 依赖：**纯 Python 标准库**（urllib/threading/ThreadPoolExecutor），无需 `requirements`
- [x] registry：`registry-entry.example.json`（manifest.source=github，path 指向资源目录 `plugins/zju_autosign`）

### 已知边界

- 「自动」范围 = **Evergreen 运行期间**。应用退出后无后台任务（平台无跨应用常驻能力）。
- 数字点名穷举 0000-9999 需要若干秒到数分钟（取决于服务端限速），期间页面轮询不受影响。
- 雷达点名成功率依赖已知点位坐标库的时效性；新校区/新楼栋可自行向
  `autosign_core.py` 的 `RADAR_LOCATIONS` 补充坐标。

---

## 六、平台支持

| 平台 | 状态 | 说明 |
|------|------|------|
| **Windows / macOS / Linux（桌面）** | ✅ 已实现，验证于 Windows | worker 经 `platform.process.start` 走 stdio 常驻终端，双向 stdin 命令（status/checkin/stop）正常 |
| **Android** | ⚠️ **未实验，不承诺有效** | 见下方说明 |

> ⚠️ **重要**：本插件**只在桌面端（Windows）验证过**。**Android 尚未经过任何真机/模拟器
> 实验，无法承诺可用**。原因如下（静态自查结论，非实测）：

1. **常驻进程的 stdin 双向交互在 Android 不受支持**——本插件 worker 是 `scope=long,
   protocol=stdio` 的常驻终端，依赖「页面经 `platform.process.write` 向 worker stdin
   发命令（`checkin`/`status`）」。而 Evergreen 的 Android 进程内 Python 桥
   （Chaquopy，`ChaquopyLongProcess`）**不支持运行中写 stdin**（`stdin` 直接抛
   `UnsupportedError`），命令无法送达 worker，签到/查询会静默失效。
2. **worker 的 stdin 命令循环在 Android 无法持续**——`runScript` 的 stdin 是一次性
   `StringIO`，`for line in sys.stdin` 会立即 EOF 使 worker 退出。
3. **TLS/证书兼容性未验证**——`autosign_core.py` 针对 ZJU 旧式 TLS（小 DH 参数）做了
   `set_ciphers("DEFAULT:@SECLEVEL=0")` 降级，该行为在 Android CPython（Chaquopy）下
   未验证。

若后续需要 Android 支持，需先解决平台侧的「常驻进程 stdin 双向流」能力（当前缺失），
再行实测。在此之前，**请勿在 Android 上依赖本插件**。

---

## 七、许可

MIT。代码参考自 [ZJU-live-better](https://github.com/cubicYYY/ZJU-live-better)
（GPL-3.0，本项目为独立重实现，仅借鉴接口协议与坐标数据）。
