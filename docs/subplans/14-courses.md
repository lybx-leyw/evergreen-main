# 14 — Courses 课程

**层级：** 四 | **估时：** 4 天 | **依赖：** 10 ZDBK

---

## 1. 现状

课程页面已实现基础的课程列表展示，数据源来自 `coursesListProvider`（学在浙大 `courses.zju.edu.cn`）。

### 1.1 已实现

| 功能 | 状态 |
|------|:----:|
| 课程列表（搜索框 + 过滤） | ✅ |
| 教师评分跳转（查老师） | ✅ |
| 课程资料下载跳转 | ✅ |
| loading / empty / error / data 四态 | ✅ |

### 1.2 数据源说明

| 数据 | 来源 | Provider | 用途 |
|------|------|----------|------|
| 课程列表 | `courses.zju.edu.cn` | `coursesListProvider` | 课程页面展示 |
| 课表（周视图） | ZDBK 教务网 | `zdbkTimetableProvider` | 课表周视图 |
| 课程活动/作业 | `courses.zju.edu.cn` | `courseFullDataProvider` | 待办事项 |
| 课程开课情况 | ZDBK 教务网 | `courseOfferingsProvider` | 开课查询 |

### 1.3 待实现

| 优先级 | 功能 | 说明 |
|:------:|------|------|
| **P0** | **课表周视图** | 整合 ZDBK 课表数据，展示每周课程时间表 |
| **P0** | **课程详情页** | 点击课程进入详情：显示活动/作业/课件列表 |
| P1 | 搜索增强 | 支持按学期、课程类型、教师筛选 |
| P1 | 一键导出 | iCal / Excel 格式导出课表 |
| P2 | 成绩趋势 | 课程内成绩变化折线图 |

---

## 2. 技术方案

### 2.1 课表周视图

使用 `zdbkTimetableProvider`（ZDBK 课表数据）绘制类似课程表的周视图网格。

```dart
// 数据格式：TimetableSession 包含 dayOfWeek, periods, weekRange, courseName, location
final sessions = await ref.read(zdbkTimetableProvider.future);
```

**布局方案：**

```
    周一    周二    周三    周四    周五
1-2 | 高数 |      | 英语 |      |      |
3-4 |      | 物理 |      | 政治 |      |
5-6 | 体育 |      |      | 实验 |      |
```

使用 `Table` 或 `GridView` 渲染，7 列（星期）× 12 行（节次）。每个格子内显示课程名 + 教室。

**参考实现：**

```dart
// 课表网格核心逻辑
final grid = List.generate(12, (_) => List.generate(7, (_) => <TimetableSession>[]));
for (final s in sessions) {
  for (final p in s.periods) {
    if (p >= 1 && p <= 12) grid[p - 1][s.dayOfWeek - 1].add(s);
  }
}
```

### 2.2 课程详情页

从 `courses.zju.edu.cn` 获取课程活动数据：

```dart
final activities = await ref.read(courseFullDataProvider(courseId).future);
```

**详情页包含：**
- 课程基本信息（名称、教师、学分、类型）
- 作业列表（带截止日期、提交状态）
- 考试安排
- 课件下载入口
- 成绩（如有）

### 2.3 一键导出

使用 `share_plus` 或 `path_provider` 生成文件：

```dart
// iCal 格式
final ical = sessions.map((s) => _toVEvent(s)).join('\n');
await File(path).writeAsString(ical);
// Excel 格式（使用 csv 或 openpyxl 风格）
```

### 2.4 路由设计

```
/courses                  → 课程列表（当前）
/courses/:id              → 课程详情（新增）
/courses/timetable        → 课表周视图（新增）
/courses/export           → 导出设置（新增）
```

---

## 3. 实现顺序

| 步骤 | 内容 | 估时 |
|:----:|------|:----:|
| 1 | 课表周视图基础网格 | 1 天 |
| 2 | 课程详情页：活动 + 作业 | 1 天 |
| 3 | 课表周跳转课程详情 | 0.3 天 |
| 4 | 搜索增强（学期/类型筛选） | 0.3 天 |
| 5 | iCal / CSV 导出 | 0.5 天 |
| 6 | 课程内成绩趋势 | 0.5 天 |

---

## 4. 验收标准

- [ ] 课表周视图正确显示每周课程时间表
- [ ] 课程详情页显示活动/作业列表
- [ ] 点击课表中的课程跳转到课程详情
- [ ] 搜索支持按学期/类型筛选
- [ ] 导出文件可被日历/Excel 打开
- [ ] loading / empty / error / data 四态覆盖
- [ ] 全部现有 200+ 测试通过
