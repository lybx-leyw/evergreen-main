"""Date Plugin — stdin 风格。"""
import sys
import json
from datetime import datetime, timezone, timedelta


def main():
    raw = sys.stdin.read()
    if raw.startswith("\ufeff"):  # Windows 控制台管道可能带 UTF-8 BOM
        raw = raw[1:]
    args = json.loads(raw) if raw.strip() else {}
    fmt = args.get("format", "iso")

    tz = timezone(timedelta(hours=8))
    today = datetime.now(tz)

    formats = {
        "iso": today.strftime("%Y-%m-%d"),
        "cn": today.strftime("%Y年%m月%d日"),
        "us": today.strftime("%m/%d/%Y"),
    }
    print(formats.get(fmt, formats["iso"]))


if __name__ == "__main__":
    main()
