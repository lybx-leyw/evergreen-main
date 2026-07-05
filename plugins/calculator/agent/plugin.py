"""Calculator Tool — stdin mode, JSON schema with enum."""
import sys
import json


def main():
    # Use sys.stdin.buffer for binary-safe read (no BOM issues)
    raw = sys.stdin.buffer.read().decode("utf-8-sig")
    args = json.loads(raw) if raw.strip() else {}

    op = args.get("operation", "add")
    a = float(args.get("a", 0))
    b = float(args.get("b", 0))

    if op == "add":
        result = a + b
        symbol = "+"
    elif op == "sub":
        result = a - b
        symbol = "-"
    elif op == "mul":
        result = a * b
        symbol = "*"
    elif op == "div":
        if b == 0:
            print("错误：除数不能为0")
            sys.exit(1)
        result = a / b
        symbol = "/"
    elif op == "pow":
        result = a ** b
        symbol = "^"
    elif op == "mod":
        if b == 0:
            print("错误：模运算除数不能为0")
            sys.exit(1)
        result = a % b
        symbol = "%"
    else:
        print(f"错误：不支持的运算类型 '{op}'")
        sys.exit(1)

    # 输出计算结果
    if isinstance(result, float) and result == int(result):
        result = int(result)
    print(f"{a} {symbol} {b} = {result}")


if __name__ == "__main__":
    main()
