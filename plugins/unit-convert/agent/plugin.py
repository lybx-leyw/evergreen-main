"""Unit Convert Tool — supports 8 categories with auto-detection."""
import argparse

# ═══════ 单位换算表（以基础单位为基准） ═══════

LENGTH = {
    "km": 1000, "m": 1, "cm": 0.01, "mm": 0.001,
    "mi": 1609.344, "yd": 0.9144, "ft": 0.3048, "in": 0.0254,
    "里": 500, "尺": 0.3333, "寸": 0.03333,
}

WEIGHT = {
    "t": 1000, "kg": 1, "g": 0.001, "mg": 0.000001,
    "lb": 0.453592, "oz": 0.0283495,
    "斤": 0.5, "两": 0.05,
}

AREA = {
    "km2": 1_000_000, "ha": 10_000, "m2": 1, "cm2": 0.0001,
    "acre": 4046.86, "ft2": 0.092903,
    "亩": 666.667,
}

VOLUME = {
    "m3": 1000, "L": 1, "mL": 0.001,
    "gal": 3.78541, "qt": 0.946353, "pt": 0.473176, "cup": 0.236588, "fl_oz": 0.0295735,
}

SPEED = {
    "kmh": 1, "ms": 3.6, "mph": 1.60934, "knot": 1.852,
}

TIME = {
    "d": 86400, "h": 3600, "min": 60, "s": 1, "ms": 0.001,
    "week": 604800, "year": 31557600,
}

DATA = {
    "TB": 1_099_511_627_776, "GB": 1_073_741_824, "MB": 1_048_576,
    "KB": 1024, "B": 1, "bit": 0.125,
}

UNITS = {
    "length": LENGTH, "weight": WEIGHT, "area": AREA,
    "volume": VOLUME, "speed": SPEED, "time": TIME, "data": DATA,
}


def auto_detect_category(unit):
    for cat, units in UNITS.items():
        if unit in units:
            return cat
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--value", type=float, required=True)
    parser.add_argument("-f", "--from", type=str, required=True, dest="from_unit")
    parser.add_argument("-t", "--to", type=str, required=True, dest="to_unit")
    parser.add_argument("-c", "--category", type=str, default="")
    args = parser.parse_args()

    value = args.value
    from_unit = args.from_unit
    to_unit = args.to_unit

    # Auto-detect or use specified category
    cat = args.category if args.category else auto_detect_category(from_unit)
    if not cat or cat == "temperature":
        cat = auto_detect_category(to_unit)

    if not cat and args.category:
        cat = args.category

    if not cat:
        print(f"错误: 无法识别单位 '{from_unit}' 或 '{to_unit}'")
        print("请使用 --category 指定: length/weight/temperature/area/volume/speed/time/data")
        sys.exit(1)

    # Temperature is special (not linear)
    if cat == "temperature" or (from_unit in ("C", "F", "K") and to_unit in ("C", "F", "K")):
        # Celsius to base (Kelvin)
        def to_kelvin(v, u):
            if u == "K":
                return v
            if u == "C":
                return v + 273.15
            if u == "F":
                return (v - 32) * 5 / 9 + 273.15
            return v

        def from_kelvin(v, u):
            if u == "K":
                return v
            if u == "C":
                return v - 273.15
            if u == "F":
                return (v - 273.15) * 9 / 5 + 32
            return v

        k = to_kelvin(value, from_unit)
        result = from_kelvin(k, to_unit)
    else:
        units = UNITS.get(cat)
        if not units:
            print(f"错误: 不支持的类别 '{cat}'")
            sys.exit(1)

        if from_unit not in units:
            print(f"错误: 未知源单位 '{from_unit}'，可用: {list(units.keys())}")
            sys.exit(1)
        if to_unit not in units:
            print(f"错误: 未知目标单位 '{to_unit}'，可用: {list(units.keys())}")
            sys.exit(1)

        base_value = value * units[from_unit]
        result = base_value / units[to_unit]

    # Format result
    if abs(result) < 0.0001 or abs(result) >= 1_000_000_000:
        r = f"{result:.6e}"
    elif abs(result) >= 100:
        r = f"{result:,.4f}".rstrip("0").rstrip(".")
    else:
        r = f"{result:.6f}".rstrip("0").rstrip(".")

    print(f"{value} {from_unit} = {r} {to_unit}")


import sys

if __name__ == "__main__":
    main()
