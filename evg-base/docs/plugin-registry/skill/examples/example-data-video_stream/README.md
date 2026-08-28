# 示例：带登录 + 视频流式声明数据源（`example-data-video_stream`）

> 本示例是「声明 + 契约」样板，演示 **T1 新 manifest 契约**（可选 `auth` / `stream`）与
> **T5 平台库 evg_lib** 的可选导入模式在插件侧如何落地。**不真实登录、不真实推流**——
> 登录→会话→拉流属后续 T2/T7/T9 集成。

## 目录结构

```
example-data-video_stream/
├── config/
│   └── config.json          ← 凭据声明（settings[]，ZJU_USERNAME / ZJU_PASSWORD，password 用 type:string + isSecure:true）
├── data/
│   ├── manifest.json        ← 数据源清单（模型 A + 顶层 auth + dataTypes[].stream）
│   └── fetch.py             ← CLI 脚本（可选 import evg_lib + 常规 stdout JSON）
└── README.md
```

> 结构对齐 `example-data-zju_grades`：`config/config.json` 与 `data/` 同处于插件根目录。

## manifest 契约要点（严格符合 T1，可被 `DataSourceManifest.fromJson` 解析）

| 段 | 字段 | 说明 |
|----|------|------|
| 顶层 | `auth` | **可选**：`{sessionProvider: "zju", credentialKeys: ["ZJU_USERNAME","ZJU_PASSWORD"]}`。仅**引用** `config/config.json` 已声明的凭据 key（复用 `isSecure`），不在此重复声明凭据值（避免双真相源）。缺省零行为变化。 |
| 顶层 | `script` + `runtime` | 模型 A：CLI 一次性脚本，`script:"fetch.py"`，`runtime:"python"`。 |
| dataTypes[] | `stream` | **可选**：`{enabled:true, protocol:"hls", mime:"application/vnd.apple.mpegurl", credentialed:true}`。声明该类型为「可播放视频流」，拉流需携带凭据头。 |

### 协议取值说明（本示例选 `hls`）

`stream.protocol` 可选值（T1 契约）：`hls` / `mp4` / `http-flv` / `sse` / `stdio-jsonl`。

- **HLS（本示例采用）**：`protocol:"hls"` + `mime:"application/vnd.apple.mpegurl"`
  （`.m3u8` 播放列表，媒体播放器 `<video>` / media_kit 直连播放的最常见形态）；
- **FLV over HTTP**：`protocol:"http-flv"` + `mime:"video/x-flv"`（低延迟直播流替代）；
- **SSE**：`protocol:"sse"` + `mime:"text/event-stream"`（事件流，非媒体）。

> 注意：任务派单中给出的示例字面 `protocol:"http-flv"` 与
> `mime:"application/vnd.apple.mpegurl"` 二者不匹配（http-flv 的 MIME 应为 `video/x-flv`），
> 本示例归一为自洽的 **HLS + mpegurl** 组合，并在 fetch.py 输出字段与之一致。

## fetch.py 要点

- **可选 import evg_lib**：
  ```python
  try:
      from evg_lib.config import _get_config
      from evg_lib import jsonio
      _USING_EVG_LIB = True
  except ImportError:
      _USING_EVG_LIB = False
  ```
  缺失时回退到内联 `_get_config`（环境变量读取示意），保证脚本独立可运行。
- **stdout 顶层 Map JSON**：`{"items": [{"streamUrl": "...", ...}]}`，含「可播放流地址」字段示例。

## 独立验证

```bash
# 1) manifest 可被统一 typed model 解析（见 T6 验证脚本）
# 2) fetch.py 冒烟（未配置凭据时 account 显示 <未配置>，仍输出合法 JSON）
python3 data/fetch.py --type video_stream --project-root . --greenix-config .greenix/config.json
# 期望 stdout：{"items": [{"id": "video_stream", ..., "streamUrl": "https://live.example.com/live/video_stream.m3u8", ...}]}

# 3) 设置凭据后（evg_lib 缺失时走环境变量 fallback）
ZJU_USERNAME=3230000000 python3 data/fetch.py --type video_stream
```
