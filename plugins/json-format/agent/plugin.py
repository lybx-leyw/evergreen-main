"""JSON Format Tool — beautify / minify / validate."""
import argparse
import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-o", "--operation", type=str, required=True,
                        choices=["beautify", "minify", "validate"])
    parser.add_argument("-i", "--indent", type=int, default=2)
    parser.add_argument("-s", "--sort_keys", type=str, default="false")
    args = parser.parse_args()

    sort = args.sort_keys.lower() in ("true", "1", "yes")
    indent = max(0, min(10, args.indent))

    try:
        obj = json.loads(args.text)

        if args.operation == "validate":
            print(f"✓ 有效 JSON ({type(obj).__name__})")
            if isinstance(obj, dict):
                print(f"  键数量: {len(obj)}")
            elif isinstance(obj, list):
                print(f"  元素数量: {len(obj)}")
            print(f"  大小: {len(args.text)} bytes")
        elif args.operation == "beautify":
            print(json.dumps(obj, ensure_ascii=False, indent=indent, sort_keys=sort))
        else:  # minify
            print(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))

    except json.JSONDecodeError as e:
        print(f"✗ 无效 JSON: {e}")
        sys.exit(1)


import sys

if __name__ == "__main__":
    main()
