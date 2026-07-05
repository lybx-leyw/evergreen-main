"""Time Plugin — args + flag 风格。"""
import argparse
from datetime import datetime, timedelta, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offset", type=int, default=8)
    parser.add_argument("--format", type=str, default="24h")
    args = parser.parse_args()

    tz = timezone(timedelta(hours=args.offset))
    now = datetime.now(tz)
    fmt = "%I:%M:%S %p" if args.format == "12h" else "%H:%M:%S"
    print(now.strftime(fmt))


if __name__ == "__main__":
    main()
