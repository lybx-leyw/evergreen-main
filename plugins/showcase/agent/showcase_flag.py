"""showcase_flag — args + flag 模式，CLI flag 风格，模拟趣味天气预言机。
支持 --data-port <port> 从 Data 服务获取格言/冷知识点缀预报。"""
import argparse
import random
import json
import os
import urllib.request
from datetime import datetime, timedelta


WEATHER_EMOJI = {
    "晴": "☀️", "多云": "⛅", "阴": "☁️", "小雨": "🌧️", "大雨": "🌊",
    "雷阵雨": "⛈️", "雪": "❄️", "雾": "🌫️", "晴转多云": "🌤️", "风": "💨",
}

FUNNY_COMMENTS = [
    "适合写代码☕", "适合摸鱼🎣", "记得带伞🌂", "适合晒太阳😎",
    "室内最佳🏠", "通勤友好🚇", "注意保暖🧣", "可以穿短袖👕",
    "适合发呆🤔", "完美一天✨",
]


def _read_port_file(name):
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.isfile(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _fetch_from_data(data_port, endpoint):
    try:
        url = f"http://127.0.0.1:{data_port}{endpoint}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def _get_data_bonus(data_port):
    """从 data 服务获取有趣数据作为天气彩蛋"""
    if not data_port:
        data_port = _read_port_file(".data_port")
    if not data_port:
        return None

    data = _fetch_from_data(data_port, "/api/quotes")
    if data and "quote" in data:
        return f'💬 "{data["quote"]}"'

    data = _fetch_from_data(data_port, "/api/plugin-usage")
    if data and "usage" in data and data["usage"]:
        top = data["usage"][0]
        return f'📊 最热门插件: {top["name"]} (今日 {top["calls_today"]} 次调用)'

    return None


def generate_poem(city, forecast, bonus):
    today = forecast[0]
    poem = [
        f"《{city}天气赋》",
        "",
        f"{city}城里走一走，",
        f"今日天气{today['weather']}秀。",
        f"高温{today['high']}度低{today['low']}度，",
        f"出门记得{random.choice(['多穿衣', '带把伞', '涂防晒', '加件衣'])}。",
    ]
    if bonus:
        poem.append("")
        poem.append(bonus)
    poem.extend(["", "—— AI 天气预言机 敬上"])
    return "\n".join(poem)


def main():
    parser = argparse.ArgumentParser(description="趣味天气预言机")
    parser.add_argument("-c", "--city", type=str, required=True, help="城市名")
    parser.add_argument("-d", "--days", type=int, default=3, help="预报天数")
    parser.add_argument("-s", "--style", type=str, default="normal",
                        choices=["normal", "poem", "funny"])
    parser.add_argument("--data-port", type=str, default=None,
                        help="Data 服务端口")
    args = parser.parse_args()

    days = max(1, min(7, args.days))
    conditions = list(WEATHER_EMOJI.keys())

    # 生成预报数据
    forecast = []
    for i in range(days):
        date = (datetime.now() + timedelta(days=i)).strftime("%m/%d")
        weather = random.choice(conditions)
        high = random.randint(18, 38)
        low = random.randint(high - 12, high - 2)
        forecast.append({
            "date": date,
            "weather": weather,
            "high": high,
            "low": low,
        })

    # 从 data 获取彩蛋
    bonus = _get_data_bonus(args.data_port)

    if args.style == "poem":
        print(generate_poem(args.city, forecast, bonus))
        return

    if args.style == "funny":
        print(f"🎭 欢迎来到「{args.city}」天气小剧场！")
        print("━" * 36)
        for f in forecast:
            emoji = WEATHER_EMOJI.get(f["weather"], "🌡️")
            comment = random.choice(FUNNY_COMMENTS)
            print(f"  {f['date']} | {emoji} {f['weather']} | {f['low']}°C ~ {f['high']}°C | {comment}")
        if bonus:
            print("━" * 36)
            print(f"  🎁 彩蛋: {bonus}")
        print("━" * 36)
        print("(以上预报由 AI 随机生成，准确率 ≈ 掷硬币 🪙)")
        return

    # normal 风格
    print(f"📍 {args.city} 未来{days}天天气预报：")
    print("─" * 40)
    for f in forecast:
        emoji = WEATHER_EMOJI.get(f["weather"], "🌡️")
        print(f"  {f['date']}  {emoji} {f['weather']}  {f['low']}°C ~ {f['high']}°C")
    if bonus:
        print("─" * 40)
        print(f"  {bonus}")
    print("─" * 40)
    print("(模拟数据，仅供参考)")


if __name__ == "__main__":
    main()
