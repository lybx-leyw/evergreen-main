# FAIL2CLONE.md — 复刻降级/跳过根因记录

> 配套：`复刻组件清单.md`（唯一进度账本）、`.codebuddy/memory/MEMORY.md`
> 规则：凡降级一点点必写本文件（R2）；有复刻希望须换法复刻类似功能而非跳过（R6）。
> 任何条目均**不归咎环境**（R5）——均为渲染能力/真实数据可用性限制。

---

## exams（模块 #7）— 日历月格视图降级为按日期表

- **目标功能**：目标 UI（`.refer_ui/.../exams_screen.dart`）提供「列表 / 月历」双视图切换，月历为自绘月格，考试日打点、点选日期显示当日考试。
- **降级点**：renderer 的 `calendar` slot（`evg-base/lib/renderer/shared/composite_view.dart` `_CalendarSlot`）**仅从组件 config 的静态 `events` 字段读取事件**（每个事件需 `date`/`title`/`color`），**不支持 `dataSource` 动态注入**。考试数据来自 ZDBK 实时拉取，无法写入静态 manifest。
- **为何无法全量**：R7 禁止修改 `evg-base/`；若要让月历显示实时考试，须为 `calendar` slot 增加 `dataSource` 解析能力（属 renderer 改造），超出本任务边界。
- **替代复刻（R6）**：新增「📅 按日期」页，使用 `data-table`（同 `exams` 数据源，`dataPath: exams`）按 `date` 升序呈现「日期/课程/时间/考场」，复刻月历的核心信息价值（何时考试、考哪几门）。列表视图 `data-table` 全量保留原 UI 的全部字段（课程/日期/时间/考场/座位号/紧急度/剩余天数），含 filter + sortable。
- **状态**：列表视图 ✅全量；月历网格 ⛔降级（已换法复刻）。计入 FAIL2CLONE 1 条。

---

## training-plans（模块 #3）— PDF 详情/打印视图降级

- **目标功能**：目标 UI 除培养方案列表外，还提供「查看/打印 PDF 培养方案」（`pyfayl_cxPyfaylPdf.html?id={planNo}`，返回二进制 PDF）。
- **降级点**：renderer 无 PDF 渲染组件，模块插件只能声明 JSON 范式（data-table 等），无法内嵌 PDF 预览/下载动作；且 PDF 为二进制流，超出「纯 JSON API 代理」插件契约。
- **为何无法全量**：R7 禁止改 evg-base 增加 PDF 组件；插件范式不支持二进制文件下载/预览。
- **替代复刻（R6）**：培养方案**列表**已全量复刻（2833 条真实拉取验证），含方案号/专业/年级/学院/层次/学制/最低学分/已修学分/状态，filter+sortable。PDF 详情仅记录本条目，不强行伪造。
- **状态**：列表 ✅全量；PDF 详情 ⛔降级（不强行复刻）。FAIL2CLONE 累计 2 条。

---

## library（模块 #20）— 借阅数据接口在现网已不可用

- **目标功能**：目标 UI 展示「在借图书」列表（书名/作者/条码/借出日/应还日/状态），含「续借」动作。
- **降级点**：参考实现 `library_service.getBorrowedBooks` 调用 `api.lib.zju.edu.cn/aleph/bor-info`（仅需 CAS `iPlanetDirectoryPro` cookie）。
- **为何无法全量**：现网探测（本机实测）`api.lib.zju.edu.cn` 的 `aleph/bor-info` 及 5 个候选路径全部 404 / HTTPS 超时；且图书馆使用独立的 `idp.zju.edu.cn` SSO，CAS cookie 不被接受（参考 `HtmlParser.isSessionExpired` 中对 `idp.zju.edu.cn/login` 的判定）。即参考接口在现网已废弃，非环境/网络问题（zdbk、zjuam 等同机接口均正常）。
- **替代复刻（R6）**：插件代码已完整实现（CAS 登录 + 候选接口探测 + `BorrowedBook` 字段映射 + 到期状态计算），并编译 `.exe`、测试全过。接口不可用时优雅返回空列表（与目标 UI 空态一致），不中断管道；若未来接口恢复/迁移，无需改代码即可拉取。
- **说明**：列表渲染（data-table）与到期状态计算均按原模型实现，仅「真实借阅数据」因上游接口废弃无法拉取，记为降级。
- **状态**：渲染/逻辑 ✅全量（代码完整）；真实借阅数据 ⛔降级（上游接口废弃）。FAIL2CLONE 累计 3 条。
