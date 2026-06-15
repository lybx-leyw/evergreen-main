# 参考原始数据

此目录存放本项目中引用的第三方数据的**原始未修改版本**，仅供对照和审计。

## 文件说明

| 文件 | 来源 | 说明 |
|---|---|---|
| `teacher_ratings_original.json` | [Lazuli](https://github.com/ADSR1042/Lazuli) (GPL-3.0) | 浙大教师评分原始数据集 |

## 重要

- 这些文件**不会被应用代码读写**，仅作审计对照
- 应用运行时会对 `assets/data/teacher_ratings.json` 进行修改（更新评分和热度）
- 如需恢复原始数据：`cp docs/reference/teacher_ratings_original.json assets/data/teacher_ratings.json`
- 如需查看 app 对数据做了哪些修改：`git diff assets/data/teacher_ratings.json`
