# Reasonix internal → lib/core/agent 全量迁移

本目录是迁移计划的事实源：

- `PLAN.md` — 总计划、批次顺序、验收标准、红线
- `MIGRATION_MATRIX.csv` — 2086 个源文件的逐文件追踪表（权威 checklist）
- `GENERATE_MATRIX.sh` — 重新扫描 `.reasonix-ref/internal` 并生成追踪表的脚本

状态语义：`pending` = 未开始；`in_progress` = 已开始；`done` = Dart 镜像 + 测试迁移完成。
