# Reasonix internal → lib/core/agent 全量迁移

本目录是迁移计划的事实源：

- `PLAN.md` — 总计划、批次顺序、验收标准、红线
- `MIGRATION_MATRIX.csv` — 源文件的逐文件追踪表（权威 checklist，进度以 `grep -c done` 为准）
- `GENERATE_MATRIX.sh` — 重新扫描 `.reasonix-ref/internal` 并生成追踪表的脚本

状态语义：`pending` = 未开始；`in_progress` = 已开始；`done` = Dart 镜像 + 测试迁移完成。

## 当前状态（2026-08-25 清点）

- CSV 进度：以 `MIGRATION_MATRIX.csv` 为准（done/pending 计数与 `PROGRESS.md` 一致）。
- 磁盘镜像：`ref/` 下已落 P1 叶子包 + P2 sysproxy/secrets/shellparse/netclient 的实现镜像
  （event/eventwire 等有合并文件，故文件数小于 CSV done 行数）。
- 注意：`test/ref/` 目录**当前不存在**——P1/P2 的镜像测试未随实现提交，`PROGRESS.md`/`HANDOVER.md`
  中关于 `test/ref/<pkg>/` 的描述与磁盘现状不一致。恢复迁移时需先对账 CSV 与磁盘。
- 迁移当前处于暂停状态；继续推进见 `HANDOVER.md` §8 的建议顺序（shellsafe 起步）。
