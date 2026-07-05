"""Color Convert Tool — HEX / RGB / HSL conversion with auto-detect input format."""
import argparse
import re
import math


def parse_hex(s):
    """Parse '#ff5733' or 'ff5733' -> (r,g,b)."""
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ValueError("HEX 需要 3 或 6 位十六进制")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def parse_rgb(s):
    """Parse 'rgb(255,87,51)' -> (r,g,b)."""
    m = re.findall(r"\d+", s)
    if len(m) != 3:
        raise ValueError("RGB 需要 3 个数字")
    return tuple(int(x) for x in m)


def parse_hsl(s):
    """Parse 'hsl(10,100%,60%)' -> (h,s%,l%)."""
    m = re.findall(r"[\d.]+", s)
    if len(m) != 3:
        raise ValueError("HSL 需要 3 个值")
    h, s, l = float(m[0]), float(m[1]), float(m[2])
    return (h % 360, s, l)


def rgb_to_hex(r, g, b):
    r, g, b = max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))
    return f"#{r:02x}{g:02x}{b:02x}"


def rgb_to_hsl(r, g, b):
    r, g, b = r / 255.0, g / 255.0, b / 255.0
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    l = (mx + mn) / 2

    if d == 0:
        h = s = 0
    else:
        s = d / (1 - abs(2 * l - 1)) if l != 0 else 0
        if mx == r:
            h = 60 * (((g - b) / d) % 6)
        elif mx == g:
            h = 60 * ((b - r) / d + 2)
        else:
            h = 60 * ((r - g) / d + 4)

    return (round(h % 360), round(s * 100, 1), round(l * 100, 1))


def hsl_to_rgb(h, s, l):
    h, s, l = h % 360, s / 100.0, l / 100.0
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = l - c / 2

    if h < 60:
        r, g, b = c, x, 0
    elif h < 120:
        r, g, b = x, c, 0
    elif h < 180:
        r, g, b = 0, c, x
    elif h < 240:
        r, g, b = 0, x, c
    elif h < 300:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x

    return (round((r + m) * 255), round((g + m) * 255), round((b + m) * 255))


def detect_format(s):
    s = s.strip()
    if s.startswith("#") or re.match(r"^[0-9a-fA-F]{3,6}$", s):
        return "hex"
    if "rgb" in s.lower():
        return "rgb"
    if "hsl" in s.lower():
        return "hsl"
    return "unknown"


def color_preview_ascii(r, g, b):
    """Simple ascii color preview."""
    # Print with ANSI color
    print(f"\n  \033[48;2;{r};{g};{b}m          \033[0m 预览 ")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--color", type=str, required=True)
    parser.add_argument("-t", "--target", type=str, default="all",
                        choices=["hex", "rgb", "hsl", "all"])
    args = parser.parse_args()

    try:
        fmt = detect_format(args.color)
        if fmt == "unknown":
            print(f"错误: 无法识别颜色格式 '{args.color}'")
            print("支持格式: #ff5733 / rgb(255,87,51) / hsl(10,100%,60%)")
            sys.exit(1)

        # Parse to RGB intermediary
        if fmt == "hex":
            r, g, b = parse_hex(args.color)
        elif fmt == "rgb":
            r, g, b = parse_rgb(args.color)
        else:  # hsl
            h, s, l = parse_hsl(args.color)
            r, g, b = hsl_to_rgb(h, s, l)

        h, s, lv = rgb_to_hsl(r, g, b)

        print(f"输入: {args.color} (检测格式: {fmt})")
        print(f"═══════════════════════════════")

        target = args.target
        if target in ("hex", "all"):
            print(f"HEX:  {rgb_to_hex(r, g, b)}")
        if target in ("rgb", "all"):
            print(f"RGB:  rgb({r}, {g}, {b})")
        if target in ("hsl", "all"):
            print(f"HSL:  hsl({h}, {s}%, {lv}%)")

        color_preview_ascii(r, g, b)

    except Exception as e:
        print(f"错误: {e}")


import sys

if __name__ == "__main__":
    main()
