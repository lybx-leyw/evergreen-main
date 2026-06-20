# All Plans — 任务状态表

> 2026-06-13 · 内测版 · 🟢 已达到 · 🟡 勉强达到 · 🔴 未实现 · ⏸ 暂缓 · ⚪ 远期

---

## Bug 清单

| ID | 描述 | 严重度 | 子计划 | 状态 |
|---|---|---|---|---|
| BUG-01 | 一卡通平台 URL 错误 | 🔴 | 21 | ⏸ |
| BUG-02 | AI 笔记功能整体难以运行 | 🔴 | 19 | 🟡 |
| BUG-03 | AI 笔记闪卡渲染不美观 | 🟡 | 25 | 🟢 |
| BUG-04 | AI 辅导/课表推荐/培养方案爬取 | ⚪ | 29 | ⚪ |
| BUG-05 | AI 笔记无法保存到本地 | 🔴 | 22 | 🔴 |
| BUG-06 | 智云课堂"导入 AI 笔记"按钮不传 PPT | 🔴 | 18 | 🟡 |
| BUG-07 | OCR 识别错别字太多 | 🟡 | 19 | ⏸ |
| BUG-08 | OCR 太慢，token 消耗过高 | 🟡 | 19 | ⏸ |
| BUG-09 | 进度条等 UI 组件不美观 | 🟢 | 25 | 🟢 |
| BUG-10 | 主题风格选择重启后丢失 | 🟡 | 03, 24 | 🟢 |
| BUG-11 | 自动签到无测试/试运行机制 | 🟡 | 21 | ⏸ |
| BUG-12 | 无法支持手机端 | 🟡 | 29 | 🟡 (部分实现，不稳定) |
| BUG-13 | 单词背诵不支持批量导入 | 🟡 | 17 | ⏸ |
| BUG-14 | AI 助手不支持多会话 | 🟡 | 23 | 🟢 |
| BUG-15 | 暗色模式部分区域对比度不足 | 🟡 | 25 | 🟢 |
| BUG-16 | AI 记忆功能未实现 | 🔴 | 06, 23 | 🟢 |

---

## 子计划 1~25

| # | 子计划 | 状态 | 说明 |
|---|---|---|---|
| 01 | 统一错误处理体系 | 🟢 | `Result<T>` + `AppError`(13种) + `Log` 已全覆盖 |
| 02 | 测试基础设施 | 🟡 | mock 层就位，784 tests；CI 暂缓 |
| 03 | AppConfig 规范化 | 🟡 | `AppConfigData` 值对象就位，旧静态类仍在混用 |
| 04 | 数据模型固化 | 🟡 | `fromJson` 已有，`tryParse` 安全解析待加固 |
| 05 | 共享 Widget 标准化 | 🟢 | EmptyState/ErrorCard/LoadingIndicator/EvergreenProgress/MarkdownRenderer |
| 06 | 记忆系统架构 | 🟢 | 奥尔波特特质理论（首要/中心/次要/用户需求/关键事实）；MemoryAgent 每轮自动提取；read/write_global_memory 工具；全局记忆全屏管理页；MemoryRigor 已移除；.greenix 路径统一 |
| 07 | 网络层加固 | 🟡 | NetworkConfig 就位，AuthInterceptor 重登 + RetryInterceptor 完善 |
| 08 | 工具类加固 | 🟡 | GpaCalculator/DateUtils/HtmlParser/TokenEstimator 可用，边界测试缺 |
| 09 | 登录流程重构 | 🟡 | ConnectionManager 统一编排已抽离，app.dart 仍有内联登录逻辑 |
| 10 | ZDBK Service 加固 | 🟡 | 基本可用，HTML 解析脆弱，缓存 TTL + stale 策略缺 |
| 11 | 自动登录链 | 🟢 | ConnectionManager.checkAll() 串联 6 服务，独立失败 + 自动重试 |
| 12 | Provider 迁移 | 🟡 | `ref.read→ref.watch` 部分修复，`Result<T>` 已普及 |
| 13 | Scores 成绩 | 🟡 | 基本可用，懒加载/学期筛选/重考策略/图表交互缺 |
| 14 | Courses 课程 | 🟡 | 基本可用，课表周视图 + 自适应 + 深色模式已做 |
| 15 | Exams 考试 | 🟡 | 列表+日历双视图，自适应紧凑日历，倒计时精确到秒缺 |
| 16 | Todo 待办 | 🟡 | 基本可用，多源聚合/优先级/钉钉推送缺 |
| 17 | Word Pecker 背词 | ⏸ | FSRS + 词库已实现，UI 未完善，已从侧栏隐藏 |
| 18 | Classroom 智云课堂 | 🟡 | 视频播放可用，PPT→AI笔记数据传递断裂 |
| 19 | Tutor OCR + AI 笔记 | 🟢 | 两级 OCR Pipeline（DeepSeek-OCR → Tesseract）；PDF 拆页逐页识别；OCR API Key 掩码+连接测试；Markdown 导出已实现 |
| 20 | Library + Teachers | 🟡 | 查老师可用，图书馆 ⚠️ 暂停 |
| 21 | Ecard + Autosign | ⏸ | 一卡通 + 自动签到均暂停 |
| 22 | Downloads + Quiz + RVPN + Schedule | 🔴 | 下载进度 UI 已实现但整体未完工；Quiz 暂停；RVPN 暂停；Schedule 可用 |
| 23 | Agent 多会话 + Skill | 🟢 | 多会话 CRUD；会话持久化；MemoryAgent 自动提取；上下文压实；Skill 系统（热加载 + inline/subagent + 管理页）；全局记忆可视化；流式渲染稳定性修复 |
| 24 | Scheduler + Settings | 🟡 | Settings 基本完整（含 DeepSeek/OCR 连接测试）；Scheduler ⚠️ 暂停 |
| 25 | Theme + Nav + UI | 🟢 | 暗色模式/过渡动画/快捷键/命令面板/侧栏折叠/Toast/课表日历自适应；全局记忆全屏页；Skill 管理页；代码块安全渲染 |

## 26~30

| # | 子计划 | 状态 | 说明 |
|---|---|---|---|
| 26 | Engineering + Packaging | 🟡 | lint/Inno Setup/Android 签名配好；Windows 构建成功；Android 不稳定 |
| 27 | Test Coverage | 🟢 | 1006 tests (29 新增翻译)；OCR/Skill/记忆/渲染/翻译全覆盖 |
| 28 | Documentation + Release | 🟡 | 全部 .md 文档已同步 PDF 翻译功能更新；ATTRIBUTION 补齐 PDFMathTranslate-next |
| 29 | AI Tutoring + Mobile | ⚪ | 远期规划 |
| 30 | Wellness Agent | 🟢 | acceptance.md 已实现（借鉴 ACT）；Skill 热加载可用 |

---

## 统计

| 状态 | 含义 | 数量 | 项目 |
|---|---|---|---|
| 🟢 | 已达到预期 | 9 | 01, 05, 06, 11, 19, 23, 25, 27, 30 |
| 🟡 | 勉强达到预期 | 14 | 02, 03, 04, 07, 08, 09, 10, 12, 13, 14, 15, 16, 18, 20, 24, 26, 28 |
| 🔴 | 未实现 | 1 | 22(下载) |
| ⏸ | 暂缓 | 3 | 17, 21 |
| ⚪ | 远期 | 1 | 29 |

---

*最后更新: 2026-06-13 · 内测版*
