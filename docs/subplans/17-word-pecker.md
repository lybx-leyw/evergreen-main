# 17 — WordPecker 背词

**层级：** 五（轻依赖） | **估时：** 4 天 | **依赖：** 03 AppConfig | **关联 Bug：** BUG-13

## 任务

- [ ] **[BUG-13]** 批量导入：CSV / JSON / Anki `.apkg` 格式
- [ ] **[BUG-13]** 词库持久化到 `getApplicationSupportDirectory()`，卸载不丢
- [ ] FSRS 参数可视化调参
- [ ] 错词本导出
- [ ] 每日目标进度环

## 验收

- [ ] 拖入 `.apkg` 文件 → 自动解析并导入词库
- [ ] 卸载重装 App → 词库和进度仍在
