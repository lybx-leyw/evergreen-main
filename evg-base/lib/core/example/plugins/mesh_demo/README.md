# Mesh Demo — 微服务网格完整演示

> 展示插件 .exe 如何通过**端口文件**发现平台全部 6 个微服务，
> 无需硬编码 URL、无需捆绑平台能力。

## 核心理念

```
插件 .exe 启动 → 读取 .core_port .data_port .agent_port ...
                → HTTP GET /core/health  /data/health  /agent/health ...
                → 获得全部平台能力（OCR、配置、数据、AI、模块、主题）
```

**插件不需要做的事情：**
- ❌ 不需要捆绑 Tesseract（调 `POST /core/ocr` 即可）
- ❌ 不需要硬编码数据源 URL（读 `.data_port` 即可）
- ❌ 不需要自己管理 SharedPreferences（调 `/config/*` 即可）
- ❌ 不需要实现 LLM 调用（调 `/agent/*` 即可）

## 文件结构

```
plugins/mesh_demo/
  data/
    manifest.json         ← 数据源声明
    mesh_server.py        ← Python HTTP 后端
      ├── 扫描 6 个 .xxx_port 文件
      ├── GET /health       → 自检 + 已发现服务列表
      └── GET /mesh/status  → 全网格健康状态报告
  agent/
    manifest.json         ← 工具声明 (PluginBridge)
    mesh_discover.py      ← 工具入口
      └── mesh_discover --service core → 单服务检查
      └── mesh_discover               → 全网格报告
  module/
    manifest.json         ← 页面声明 (ui=dashboard, data→mesh_status)
```

## 端口文件发现机制

| 端口文件 | 写入者 | 启动管线步骤 | 包含的服务端点 |
|---------|--------|------------|-------------|
| `.core_port` | CoreHttpServer | 第 4 步 | install/uninstall/ocr/update/plugins |
| `.config_port` | ConfigHttpServer | 第 3 步 | settings/permissions/sources |
| `.data_port` | DataHttpServer | 第 6 步 | data types/status/connectivity |
| `.module_port` | ModuleHttpServer | 第 7 步 | modules/search/nav/routes |
| `.agent_port` | AgentHttpServer | 第 8 步 | chat/sessions/tools/memory/skills |
| `.theme_port` | ThemeHttpServer | 第 10 步 | themes/tokens |

## 运行

```bash
# 启动 core 示例 → 自动启动 CoreHttpServer → 写入 .core_port
dart run example/example.dart

# mesh_demo 的 data 和 agent 组件在被示例菜单 4/5 调用时自动启动
# 也可以在命令行直接测试：
python example/plugins/mesh_demo/data/mesh_server.py
# → PORT:XXXX → http://127.0.0.1:XXXX/mesh/status
```

## 数据流

```
mesh_server.py 启动
  ├── 扫描 .core_port .data_port .agent_port .config_port .module_port .theme_port
  ├── 发现 3/6 服务 → stderr 输出已发现列表
  ├── stdout PORT:XXXX → 平台 DataSourceLoader 注册
  └── GET /mesh/status
        ├── GET /core/health   → {"status":"ok","pluginsCount":0}
        ├── GET /data/health   → {"status":"ok"}
        └── GET /agent/health  → 不可达（未启动）

mesh_discover.py
  ├── 扫描全部 6 个端口文件
  ├── 对每个已发现服务调用 /health
  └── stdout JSON → Agent → 自然语言回复
```
