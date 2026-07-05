# .plugin 包格式规范 v1.0

> **面向：** 插件开发者 / 插件商城工程师 / Core 工程师
> **关联：** `PluginInstaller.install()`（消费方）、插件商城（产出方）

---

## 一、概述

`.plugin` 是 Evergreen 平台的插件分发格式。它是一个 ZIP 压缩包，包含插件元数据、数字签名以及各能力类型的子目录。

平台启动时 `PluginInstaller.install()` 负责下载 → 签名校验 → 解压 → 注册。

---

## 二、包结构

```
<plugin-name>.plugin  (ZIP 压缩包)
│
├── manifest.json       # 顶层元数据（必填）
├── .signature          # 数字签名（必填）
├── icon.png            # 插件图标（可选，建议 256×256）
│
├── agent/              # Agent 工具（可选）
│   ├── manifest.json   #   工具声明
│   └── <name>.exe      #   可执行文件
│
├── module/             # UI 模块（可选）
│   └── manifest.json   #   模块声明
│
├── data/               # 数据源（可选）
│   ├── manifest.json   #   数据源声明
│   └── <name>.exe      #   可执行文件
│
├── theme/              # 主题（可选）
│   └── theme.json      #   主题声明
│
├── config/             # 设置项（可选）
│   └── config.json     #   设置声明
│
└── skill/              # AI Skill（可选）
    └── <name>.md       #   Skill 提示词
```

**规则：**
- `manifest.json` 和 `.signature` 必须在 ZIP 根目录
- 至少包含一个能力子目录（agent / module / data / theme / config / skill）
- 子目录内的清单格式遵循各模块已有的 manifest 规范
- 所有文件路径使用正斜杠 `/`

---

## 三、manifest.json 格式

### 必填字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定值 `"plugin"` |
| `id` | `string` | 全局唯一标识，建议与目录名一致（snake_case） |
| `name` | `string` | 展示名称 |
| `version` | `string` | 语义化版本号，如 `"1.0.0"` |

### 可选字段

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `author` | `string` | — | 作者/组织名 |
| `description` | `string` | `""` | 插件描述 |
| `homepage` | `string` | — | 项目主页 URL |
| `updateUrl` | `string` | — | 更新检查 URL（返回 `{version, downloadUrl}`） |
| `permissions` | `array` | `[]` | 权限声明数组 |
| `minAppVersion` | `string` | `"0.0.0"` | 最低宿主版本要求 |

### 权限声明格式

```json
"permissions": [
  {
    "key": "NETWORK",
    "label": "网络访问",
    "description": "允许插件访问互联网获取数据",
    "defaultGranted": true
  }
]
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | `string` | ✓ | 权限标识（大写蛇形） |
| `label` | `string` | ✓ | 简短标签 |
| `description` | `string` | ✓ | 详细说明（将展示在授权弹窗） |
| `defaultGranted` | `boolean` | 否 | 默认是否授权，默认 `true` |

### 完整示例

```json
{
  "type": "plugin",
  "id": "exam_review",
  "name": "期末复习助手",
  "version": "1.2.0",
  "author": "CampusTools",
  "description": "苏格拉底式追问复习，支持自定义题库和错题本",
  "homepage": "https://github.com/CampusTools/exam-review",
  "updateUrl": "https://plugins.example.com/exam-review/latest.json",
  "minAppVersion": "1.0.0",
  "permissions": [
    {
      "key": "FILE_READ",
      "label": "读取文件",
      "description": "读取题库文件导入题目",
      "defaultGranted": true
    },
    {
      "key": "NETWORK",
      "label": "网络访问",
      "description": "联网搜索补充资料",
      "defaultGranted": true
    }
  ]
}
```

---

## 四、签名规范

### 签名算法

- **算法：** SHA-256
- **签名字符串：** hex 编码（小写，64 字符）
- **签名内容：** `manifest.json` 的原始字节（不包含其他文件）

### 生成签名

```bash
# Linux/macOS
sha256sum manifest.json | cut -d' ' -f1 > .signature

# Windows PowerShell
(Get-FileHash -Algorithm SHA256 manifest.json).Hash.ToLower() | Out-File -Encoding ascii .signature
```

### 校验流程（PluginInstaller 内部）

1. 从 ZIP 中读取 `.signature` 文件内容，得到期望签名 `S1`
2. 从 ZIP 中读取 `manifest.json` 原始字节 `B`
3. 计算 `SHA256(B)`，得到实际签名 `S2`
4. 常数时间比较 `S1` 与 `S2`
5. 不匹配 → 拒绝安装，返回 `InstallErrorType.signatureInvalid`

### 安全约束

- 签名采用常数时间比较（防时序攻击）
- 任何字节级差异均导致拒绝
- 签名文件空白或缺失 → 拒绝

---

## 五、安装流程

```
下载 .plugin (URL → 3 次重试)
  → 本地 .plugin 文件
    → 解析 ZIP
      → 读取 manifest.json → 校验 type/id/name/version
        → 读取 .signature → SHA-256 校验
          → 解压到 plugins/<id>/
            → 写入 .manifest + .signature 元数据
              → onInstall 回调 → 通知各 Registry
```

### 安装后目录

```
plugins/<id>/
  ├── .manifest           # manifest.json 副本（用于 verifyAll）
  ├── .signature          # 签名副本（用于 verifyAll）
  ├── agent/              # 各能力子目录（按 .plugin 原样）
  ├── module/
  ├── data/
  ├── theme/
  ├── config/
  └── skill/
```

---

## 六、版本兼容

| 规范版本 | 宿主最低版本 | 变更 |
|---------|------------|------|
| 1.0 | 1.0.0 | 初始版本 |

- 格式向后兼容：新宿主可安装旧格式 .plugin
- PluginInstaller 遇到未知字段静默忽略（不崩溃）
