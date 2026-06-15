# 04 — 数据模型固化（细化版）

**阶段：** 一 | **估时：** 2 天 | **依赖：** 无

---

## 1. 现状审计

### 1.1 四模型安全性评估

| 模型 | fromJson 总字段 | 安全解析字段 | 裸访问字段 | 风险等级 |
|------|:---:|:---:|:---:|:---:|
| `Grade` | 5 | 5 | 0 | 🟢 低——全部 `?.toString()` + `tryParse` + `try/catch` |
| `CourseOffering` | 16 | 16 | 0 | 🟢 低——全部 `?.toString()` + `tryParse` |
| `Exam` | 6 | 4 | 2 | 🟡 中——`_parseKssj` 和 `_parseJssj` 中 `int.parse(group!)` 可能崩溃 |
| `TimetableSession` | 8 | 8 | 0 | 🟢 低——全部 `?.toString()` + `tryParse` |

### 1.2 具体问题

| 问题 | 位置 | 风险 |
|------|------|------|
| `int.parse(m.group(1)!)` 无 try/catch | `Exam._parseKssj` L15-19 | ZDBK 返回异常日期格式（如 `"2025年13月00日"`）→ `FormatException` |
| `int.parse(m.group(1)!)` 同上 | `Exam._parseJssj` L27-33 | 同上 |
| 无统一的类型化解析工具 | 四模型各自实现 | `double.tryParse(x?.toString() ?? '') ?? 0` 重复 6 次 |
| `Grade.fivePoint` 来源不明 | `Grade.fromJson` L42-48 | 调试时无法区分是 ZDBK 权威 `jd` 字段还是本地回退估算 |
| `courseName` 空字符串 | `CourseOffering.fromJson` L81 | `?? ''` 返回空字符串导致 UI 显示空白课程名 |
| `Grade.original` 可能为 null | `Grade.fromJson` L55 | 下游 `hundredPoint` 和 `isExcludedFromGpa` 依赖此字段 |
| 无测试覆盖 | 全部 | ZDBK 改版后无法快速验证模型容错性 |

---

## 2. 设计目标

1. **统一解析工具**：`SafeParse` 工具类，消除重复的 `double.tryParse(x?.toString() ?? '') ?? 0`
2. **来源标记**：`Grade.fivePoint` 区分"来自 ZDBK jd 字段"和"本地回退估算"
3. **容错优先**：空 `{}`、字段缺失、类型错误三种场景均不抛异常，返回默认值
4. **测试覆盖**：每种模型 4 类 fixture（合法 / 空 / 字段缺失 / 类型错误）

---

## 3. 核心设计

### 3.1 `SafeParse` — 统一解析工具

```dart
// lib/core/utils/safe_parse.dart

/// 安全解析工具——映射 JSON 到 Dart 类型，永不抛异常。
///
/// 所有 `tryParse` 失败返回默认值，null 返回默认值。
/// 用法：
/// ```dart
/// final name = SafeParse.string(json['kcmc'], default: '未命名');
/// final credits = SafeParse.double_(json['xf']);
/// ```
class SafeParse {
  SafeParse._();

  /// 解析 String，null/非字符串 → [defaultValue]。
  static String string(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  /// 解析 double，null/非数字 → [defaultValue]。
  static double double_(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }

  /// 解析 int，null/非整数 → [defaultValue]。
  static int int_(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  /// 解析 bool，null/非布尔 → [defaultValue]。
  static bool bool_(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  /// 解析 DateTime（ISO 8601），null/失败 → null。
  static DateTime? dateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
```

### 3.2 `Grade` 修复——来源标记

**现状：**
```dart
double fp;
try {
  fp = double.parse(json['jd']?.toString() ?? '');
} catch (_) {
  fp = _scoreToFivePoint(json['cj']?.toString() ?? '');
}
```

**修复后：**
```dart
final jdStr = SafeParse.string(json['jd']);
double fp;
bool fromJd;
if (jdStr.isNotEmpty) {
  fp = SafeParse.double_(json['jd']);
  fromJd = true;
} else {
  fp = _scoreToFivePoint(SafeParse.string(json['cj']));
  fromJd = false;
}
// ...
return Grade(
  ...
  fivePoint: fp,
  fivePointSource: fromJd ? FivePointSource.jd : FivePointSource.fallback,
);
```

**新增字段：**
```dart
/// 标记 fivePoint 的来源。
enum FivePointSource { jd, fallback }  // jd = ZDBK 权威绩点, fallback = 本地估算

class Grade {
  // ...
  final double fivePoint;
  final FivePointSource fivePointSource;  // ← 新增
}
```

### 3.3 `Exam` 修复——正则防御

**现状（有崩溃风险）：**
```dart
int.parse(m.group(1)!),  // 如果 group(1) 是 "13" (非法月份) → FormatException
```

**修复后：**
```dart
final year = SafeParse.int_(m.group(1), defaultValue: DateTime.now().year);
final month = SafeParse.int_(m.group(2), defaultValue: 1).clamp(1, 12);
final day = SafeParse.int_(m.group(3), defaultValue: 1).clamp(1, 31);
final hour = SafeParse.int_(m.group(4), defaultValue: 0).clamp(0, 23);
final minute = SafeParse.int_(m.group(5), defaultValue: 0).clamp(0, 59);
return DateTime(year, month, day, hour, minute);
```

---

## 4. 模型迁移对照

### 4.1 `Grade.fromJson`

| 字段 | 旧代码 | 新代码 |
|------|--------|--------|
| `id` | `json['xkkh']?.toString() ?? ''` | `SafeParse.string(json['xkkh'])` |
| `name` | `json['kcmc']?.toString() ?? ''` | `SafeParse.string(json['kcmc'], default: '未命名课程')` |
| `credit` | `double.tryParse(json['xf']?.toString() ?? '') ?? 0.0` | `SafeParse.double_(json['xf'])` |
| `original` | `json['cj']?.toString() ?? ''` | `SafeParse.string(json['cj'])` |
| `fivePoint` | try/catch + fallback | `SafeParse.double_(json['jd'])` + `FivePointSource` |

### 4.2 `CourseOffering.fromJson`

| 字段 | 旧代码 | 新代码 |
|------|--------|--------|
| `courseName` | `json['kcmc']?.toString() ?? ''` | `SafeParse.string(json['kcmc'], default: '未命名课程')` |
| 其余 15 字段 | `?.toString()` / `tryParse` | 统一 `SafeParse.string()` / `double_()` / `int_()` |

### 4.3 `Exam.fromZdbk`

| 字段 | 旧代码 | 新代码 |
|------|--------|--------|
| `id` | `json['xkkh']?.toString() ?? ''` | `SafeParse.string(json['xkkh'])` |
| `startTime` | `_parseKssj(kssj)` | 内部 `SafeParse.int_()` + `clamp` |
| `endTime` | `_parseJssj(kssj, jssj)` | 内部 `SafeParse.int_()` + `clamp` |

### 4.4 `TimetableSession.fromZdbkJson`

| 字段 | 旧代码 | 新代码 |
|------|--------|--------|
| `dayOfWeek` | `int.tryParse(json['xqj']?.toString() ?? '') ?? 1` | `SafeParse.int_(json['xqj'], default: 1).clamp(1, 7)` |
| 其余字段 | `?.toString()` / `tryParse` | 统一 `SafeParse.string()` / `double_()` / `bool_()` |

---

## 5. 测试策略

### 5.1 Fixture 分类

每种模型准备 4 类 fixture：

```dart
// 1. 合法 JSON
const validGradeJson = {
  'xkkh': '(2024-2025-2)-CS101-001',
  'kcmc': '数据结构基础',
  'xf': '4.0',
  'cj': '92',
  'jd': '4.8',
};

// 2. 空 JSON
const emptyGradeJson = <String, dynamic>{};

// 3. 字段缺失
const partialGradeJson = {
  'kcmc': '操作系统',  // 缺 xkkh, xf, cj, jd
};

// 4. 类型错误
const brokenGradeJson = {
  'xkkh': 12345,          // 应为 String
  'kcmc': '编译原理',
  'xf': 'not_a_number',   // 应为数字字符串
  'cj': null,             // null
  'jd': ['array'],        // 应为数字字符串
};
```

### 5.2 测试用例矩阵

| # | 测试 | Grade | CourseOffering | Exam | TimetableSession |
|---|------|:---:|:---:|:---:|:---:|
| 1 | 合法 JSON → 所有字段正确 | ✅ | ✅ | ✅ | ✅ |
| 2 | 空 `{}` → 构造成功，字段为默认值 | ✅ | ✅ | ✅ | ✅ |
| 3 | 字段缺失 → 缺失字段为默认值 | ✅ | ✅ | ✅ | ✅ |
| 4 | 类型错误 → fallback 默认值，不抛异常 | ✅ | ✅ | ✅ | ✅ |
| 5 | `fivePointSource` 标记正确 | ✅ | — | — | — |
| 6 | `fivePointSource` = fallback 时 `jd` 缺 | ✅ | — | — | — |
| 7 | `courseName` 不为空字符串 | — | ✅ | — | — |
| 8 | 异常日期格式不崩溃 | — | — | ✅ | — |
| 9 | `dayOfWeek` clamp 到 1-7 | — | — | — | ✅ |

**合计约 24 个测试用例。**

### 5.3 测试示例

```dart
// test/core/models/grade_test.dart
group('Grade.fromJson', () {
  test('合法 JSON → 所有字段正确', () {
    final grade = Grade.fromJson(validGradeJson);
    expect(grade.id, '(2024-2025-2)-CS101-001');
    expect(grade.name, '数据结构基础');
    expect(grade.credit, 4.0);
    expect(grade.original, '92');
    expect(grade.fivePoint, 4.8);
    expect(grade.fivePointSource, FivePointSource.jd);
  });

  test('空 {} → 不抛异常，字段为默认值', () {
    final grade = Grade.fromJson({});
    expect(grade.id, '');
    expect(grade.name, '未命名课程');
    expect(grade.credit, 0.0);
    expect(grade.fivePoint, 0.0);
    expect(grade.fivePointSource, FivePointSource.fallback);
  });

  test('类型错误 → fallback 默认值', () {
    final grade = Grade.fromJson(brokenGradeJson);
    expect(grade.name, '编译原理');          // String → 正常
    expect(grade.credit, 0.0);               // "not_a_number" → 0.0
    expect(grade.original, '');              // null → ''
    expect(grade.fivePoint, 0.0);            // ["array"] → 0.0
    expect(grade.fivePointSource, FivePointSource.fallback);
  });
});
```

---

## 6. 回归影响范围

| 影响 | 位置 | 处理 |
|------|------|------|
| `Grade.fivePointSource` 新增字段 | `GpaCalculator`、所有 Grade 消费者 | 编译器报错引导迁移，新增字段不影响现有逻辑 |
| `SafeParse` 替代原有 tryParse | 4 模型 + `fromScoresJson` | 行为等价，不改变返回值 |
| `Grade(courseName: '未命名课程')` 默认值 | UI 层课程名展示 | 之前显示空字符串，现在显示"未命名课程"——体验提升 |
| `TimetableSession.dayOfWeek` clamp | 课表渲染 | 之前非法值（0 或 8）可能导致布局错误，现在 clamp 到 1-7 |

---

## 7. 执行计划

| 步骤 | 内容 | 产出物 | 估时 |
|------|------|--------|------|
| **Step 1** | 创建 `safe_parse.dart` | 5 个静态方法 | 0.25 天 |
| **Step 2** | 添加 `FivePointSource` + 改造 `Grade.fromJson` | grade.dart 修改 | 0.25 天 |
| **Step 3** | 改造 `CourseOffering.fromJson` | course_offering.dart 修改 | 0.25 天 |
| **Step 4** | 改造 `Exam._parseKssj` / `_parseJssj` | exam.dart 修改 | 0.25 天 |
| **Step 5** | 改造 `TimetableSession.fromZdbkJson` | timetable_session.dart 修改 | 0.15 天 |
| **Step 6** | 编写 4 个模型的测试 + fixture | `test/core/models/` | 0.5 天 |
| **Step 7** | `GpaCalculator` 适配 `fivePointSource` | gpa_calculator.dart 检查 | 0.15 天 |
| **Step 8** | 全量回归 | `flutter test` + `flutter run` | 0.2 天 |

---

## 8. 验收标准

- [ ] `SafeParse` 5 个方法全部通过单元测试
- [ ] `Grade.fromJson({})` 不抛异常，`fivePointSource == fallback`
- [ ] `CourseOffering.fromJson({})` 不抛异常，`courseName == '未命名课程'`
- [ ] `Exam.fromZdbk({})` 不抛异常，`startTime == null`
- [ ] `TimetableSession.fromZdbkJson({})` 不抛异常，`dayOfWeek == 1`
- [ ] 四个模型的 4 类 fixture 测试 100% 通过（~24 个用例）
- [ ] `Exam._parseKssj("2025年13月00日(14:00-16:40)")` 不崩溃，clamp 到合法日期
- [ ] `flutter analyze` 零新增警告
