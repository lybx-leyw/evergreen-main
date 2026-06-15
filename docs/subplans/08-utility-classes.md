# 08 — 工具类加固（细化版）

**阶段：** 一 | **估时：** 1.5 天 | **依赖：** 03 数据模型固化

---

## 1. 现状审计

### 1.1 四工具现状

| 工具 | 行数 | 核心问题 |
|------|:---:|------|
| `GpaCalculator` | 170 | ✅ 已有空列表守卫，但缺少边界测试 |
| `DateUtils` | 65 | ⚠️ `getSemesterLabel()` 一月份判断错误（1 月归到秋季而非上年秋季） |
| `HtmlParser` | 60 | ⚠️ CAS 过期检测只认 3 种模式，ZJU 其他子系统（图书馆/一卡通）可能不匹配 |
| `TokenEstimator` | 60 | 🔴 主循环计算了 `tokens` 但从不使用；未校准比例 |

### 1.2 具体 Bug

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | `getSemesterLabel()` 1 月 → 秋季但 `year` 已是新年 | L58-63 | 1 月显示 "2026-2027 秋冬" 而非 "2025-2026 秋冬" |
| 2 | `TokenEstimator.estimate()` 上半部分循环计算了 `tokens` 但被下半部分覆盖 | L18-36 | 死代码 + 性能浪费 |
| 3 | `isSessionExpired()` 只匹配 3 种文本 | L51-55 | 图书馆/一卡通子系统的 CAS 变体可能漏检 |
| 4 | 无 `GpaCalculator` 边界测试 | — | 零学分、全排除场景未验证 |

---

## 2. 执行计划

| 步骤 | 内容 | 估时 |
|------|------|------|
| **Step 1** | `DateUtils` 学期边界修复 | 0.2 天 |
| **Step 2** | `TokenEstimator` 死代码清理 + 校准 | 0.2 天 |
| **Step 3** | `HtmlParser` CAS 变体扩展 | 0.15 天 |
| **Step 4** | 四工具测试编写 | 0.3 天 |
| **Step 5** | 全量回归 | 0.1 天 |

---

## 3. 验收标准

- [ ] `DateUtils.getSemesterLabel()` 在 1 月返回正确跨年标签
- [ ] `TokenEstimator.estimate("hello")` ≈ 2（不是 0，不是 200）
- [ ] `HtmlParser.isSessionExpired()` 识别 ≥ 5 种 CAS 页面变体
- [ ] `GpaCalculator.calculateGpa([])` 返回全零
- [ ] 所有工具类测试通过
