# 20 — Library + Teachers

**层级：** 六 | **估时：** 3 天 | **依赖：** 09 登录, 10 ZDBK

## Library 
已撤销，暂时不实现

- [ ] 借阅到期提醒  dropout
- [ ] 一键续借      dropout
- [ ] 逾期天数高亮  dropout

## Teachers

- [x] 本地 JSON 加载 + 在线逐条更新 — `ChalaoshiService` 已实现
- [x] 在线/本地数据差异标记 — `TeacherResult.dataSource` 标记 `online`/`local`，UI 用「实时」/「缓存」徽标区分

## 验收

- [x] 搜索教师 → 本地秒出结果 → 在线数据后台更新
