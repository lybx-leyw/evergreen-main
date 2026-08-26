#!/usr/bin/env python3
"""current_time —— 纯标准库一次性 Agent 工具（stdin JSON 模式）。

读取 stdin 的 JSON（可选 `tz_offset` 时区偏移小时），把当前时间打印到 stdout。

stdout 约定（`evg-base/lib/core/agent/docs/plugin-agent-tool.md`）：
- 成功：exit code 0，stdout 内容即返回给 Agent 的文本；
- 纯文本优先（Agent 直接展示给用户），中文输出 UTF-8；
- 一次性工具：进程打印后即退出（`"lifetime": "once"`）。

本脚本不依赖任何第三方库，Windows / Linux / macOS / 安卓（Chaquopy）通用。
"""

import json
import sys
from datetime import datetime, timedelta, timezone


def main() -> None:
    # 读 stdin JSON；空输入 / 非法 JSON 按空参数处理（未知字段静默忽略）。
    args = {}
    try:
        raw = sys.stdin.read()
        if raw.strip():
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                args = parsed
    except Exception:
        args = {}

    # 可选时区偏移（小时，东正西负），缺省 0 = UTC。
    try:
        offset_hours = int(args.get("tz_offset", 0))
    except (TypeError, ValueError):
        offset_hours = 0

    tz = timezone(timedelta(hours=offset_hours))
    now = datetime.now(tz)
    print(now.strftime("%Y-%m-%d %H:%M:%S %z"))
    print("时区偏移: {:d} 小时".format(offset_hours))


if __name__ == "__main__":
    main()
