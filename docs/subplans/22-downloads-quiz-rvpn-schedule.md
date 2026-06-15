# 22 — Downloads + Quiz + RVPN + Schedule

**层级：** 六 | **估时：** 3 天 | **依赖：** 09 登录, 10 ZDBK | **关联 Bug：** BUG-05

---

## Downloads **[BUG-05]**

### 1. 下载路径配置对接

- [ ] `features/downloads/` 读取 `AppConfig.downloadPath`，未配置时弹窗引导
- [ ] 智云课堂下载路径：`classroom_viewer_screen.dart` 的下载按钮调用 `AppConfig.downloadPath`
- [ ] AI 笔记下载路径：`notes_screen.dart` 的保存按钮支持「导出为 PDF」→ 存入 `downloadPath`
- [x] 培养方案 PDF：`training_plan_screen.dart` 下载前自动复制一份到 `downloadPath`

### 2. 下载执行器

- [x] 创建 `DownloadService`（`features/downloads/services/download_service.dart`）
  - `download(url, destPath, onProgress)` — HTTP GET 流式写入，自动重试 ×3
  - `downloadToDir(url, dir, onProgress)` — 自动提取文件名
- [ ] 下载列表 UI：进度条 + 暂停/恢复/取消（StateNotifier + UI）

### 3. 培养方案 PDF 保存

- [x] PDF 下载后自动复制一份到 `AppConfig.downloadPath`
- [ ] 保存成功后 Toast「已保存到下载目录」+「打开文件夹」按钮

### 4. AI 笔记导出

- [ ] `notes_provider.dart` 新增 `exportAsPdf(noteContent, title)` 方法
- [ ] 存入 `downloadPath`，Toast 提示

---

## Quiz — 废除

- [x] 不实现（classrooms API 已废弃）

---

## RVPN

- [x] 侧栏标记「RVPN(开发中)」
- [x] AppBar 添加「实验性」角标 + 温馨提示卡片
- [x] 运行状态徽标（绿色「● 运行中」/ 灰色「○ 已停止」）

---

## Schedule (iCal)

- [x] 创建 `ScheduleScreen` — 自动导出 iCal + 显示文件路径
- [x] 「打开文件夹」按钮 → 跨平台 `openInFileManager()`
- [x] 侧栏添加「课表导出」导航项
- [ ] 导出成功 Toast（当前在页面内显示，后续可加 SnackBar）

---

## 新增文件

| 文件 | 说明 |
|------|------|
| `lib/core/utils/file_utils.dart` | `openInFileManager()` 跨平台打开文件管理器 |
| `lib/features/downloads/services/download_service.dart` | `DownloadService` + `DownloadTask` 模型 |
| `lib/features/schedule/screens/schedule_screen.dart` | iCal 导出页面 |

## 验收

- [x] RVPN 页面有实验性标记 + 运行状态可视化
- [x] 培养方案 PDF 自动保存到下载目录
- [x] 课表导出支持 iCal + 打开文件夹
- [ ] 下载进度管理 UI
- [ ] AI 笔记导出 PDF
