"""
「带登录 + 视频流式声明」示例数据源 —— 模型 A（CLI 一次性脚本）。

==== 定位 ====
  本文件是「声明 + 契约」样板：演示 manifest.json 顶层 `auth` 声明 +
  dataTypes[].`stream` 声明在 Python 脚本侧如何落地，以及「可选 import evg_lib」模式。

==== 平台契约 ====
  平台执行: python fetch.py --type <typeArg> --project-root <root> --greenix-config <cfg>
  工作目录: <plugin>/data/
  stdout : 单个 JSON 对象（UTF-8），顶层必须是 Map —— 列表型数据包 {"items": [...]}
  失败   : 非零退出码，或 stdout JSON 含 "error" 字段（平台保留旧缓存）

==== 可选 import evg_lib（平台库，T5 提供，随 PYTHONPATH 注入）====
  - 优先 `from evg_lib.config import _get_config`（三级降级：.greenix/config.json
    → ConfigHttpServer → 环境变量），以及 `from evg_lib import jsonio`（emit/fail 助手）。
  - 平台库缺失（旧解释器 / 未分发）时回退到下方内联 `_get_config`（环境变量读取示意，
    完整三级降级见 evg_lib/config.py 或 scraper_exporter 内联锁定模板）。

==== 真实链路说明 ====
  本样板**不真实登录、不真实推流**：登录→会话→拉流属后续 T2/T7/T9 集成。
  此处仅把「可播放流地址」作为字段写入 stdout JSON，演示声明与契约格式。
"""

import argparse
import json
import os
import sys

# ── 可选 import evg_lib（try/except ImportError 优雅降级） ──
try:
    from evg_lib.config import _get_config
    from evg_lib import jsonio as _jsonio  # emit / fail / validate_and_output 助手

    _USING_EVG_LIB = True
except ImportError:
    _USING_EVG_LIB = False


def _get_config(key):
    """内联 fallback：仅读取环境变量（完整三级降级见 evg_lib.config / 锁定模板）。

    未安装 evg_lib 时兜底，保证脚本仍可独立运行。
    """
    val = os.environ.get(key)
    if not val:
        raise RuntimeError(
            '无法获取配置 "%s"：未安装 evg_lib 且环境变量未设置，请在设置面板注册。' % key
        )
    return val


def _emit(data):
    """stdout 顶层 Map JSON（UTF-8）。平台统一契约。"""
    print(json.dumps(data, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="示例：带登录 + 视频流式数据源（模型 A CLI）")
    parser.add_argument("--type", default="video_stream",
                        help="平台 dataType 的 typeArg（当前固定 video_stream）")
    parser.add_argument("--project-root", default=".",
                        help="平台项目根目录（本示例未使用，按契约接收）")
    parser.add_argument("--greenix-config", default=None,
                        help=".greenix/config.json 路径（evg_lib._get_config 三级降级使用）")
    args = parser.parse_args()

    # 演示读取凭据：auth.credentialKeys 引用的是 config.json 已声明的 key
    # （ZJU_USERNAME / ZJU_PASSWORD）。本样板不真实登录，凭据缺失不阻断（占位说明）。
    username = None
    try:
        username = _get_config("ZJU_USERNAME")
    except Exception as e:
        sys.stderr.write("未配置凭据（样板演示，非错误）：%s\n" % e)

    # 可播放流地址字段示例（占位；真实流地址由「登录 → 会话 → 推流」链路产出）。
    # 与 manifest dataTypes[].stream 声明对齐：protocol=hls / mime=application/vnd.apple.mpegurl。
    stream_url = "https://live.example.com/live/video_stream.m3u8"

    _emit({
        "items": [
            {
                "id": "video_stream",
                "title": "示例可播放视频流",
                "account": username or "<未配置>",
                "streamUrl": stream_url,
                "streamProtocol": "hls",
                "streamMime": "application/vnd.apple.mpegurl",
            }
        ]
    })


if __name__ == "__main__":
    main()
