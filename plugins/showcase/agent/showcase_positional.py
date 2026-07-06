"""showcase_positional — args + positional 模式，纯位置参数，写操作(串行)。趣味笔记生成器。
支持 --data-port <port> 从 Data 服务获取格言来丰富笔记内容。"""
import sys
import os
import random
import json
import urllib.request
from datetime import datetime


MOOD_EMOJI = {
    "excited": "🤩",
    "calm": "😌",
    "curious": "🤔",
    "tired": "😴",
}

QUOTES = [
    "代码是写给人看的，顺便给机器运行。—— Abelson & Sussman",
    "简单是可靠的先决条件。—— Edsger Dijkstra",
    "先让它工作，再让它正确，最后让它快。—— Kent Beck",
    "任何傻瓜都能写出计算机能懂的代码，好程序员写出人能读懂的代码。—— Martin Fowler",
    "调试的难度是写代码的两倍。如果你用尽全力写代码，那你就没有能力去调试它。—— Brian Kernighan",
    "软件就像熵：容易增长，难以控制。—— Norman Augustine",
    "永远不要停止学习，因为生活永远不会停止教学。",
    "你今天写的最烂的代码，比昨天没写的代码强100倍。",
]

TEMPLATES = {
    "excited": "🔥 {topic} · 激情探索笔记",
    "calm": "🧘 {topic} · 平静思考笔记",
    "curious": "🔍 {topic} · 好奇心笔记",
    "tired": "💤 {topic} · 深夜笔记",
}


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


def _get_data_inspiration(data_port, topic):
    """从 data 服务获取与主题相关的灵感"""
    if not data_port:
        data_port = _read_port_file(".data_port")
    if not data_port:
        return None, None

    # 尝试获取格言
    data = _fetch_from_data(data_port, "/api/quotes")
    if data and "quote" in data:
        return f'> 💡 今日格言: _{data["quote"]}_ —— {data.get("author", "未知")}', None

    # 尝试获取周报
    data = _fetch_from_data(data_port, "/api/weekly-report")
    if data and "summary" in data:
        s = data["summary"]
        return f'> 📊 本周统计: {s["active_plugins"]}/{s["total_plugins"]} 插件活跃，共 {s["total_calls"]} 次调用', None

    return None, None


def main():
    # 分离 --data-port 参数
    data_port = None
    positional = []
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == "--data-port" and i + 1 < len(sys.argv):
            data_port = sys.argv[i + 1]
            i += 2
        else:
            positional.append(sys.argv[i])
            i += 1

    if len(positional) < 2:
        print("错误: 需要至少 2 个参数: <filename> <topic> [mood]", file=sys.stderr)
        sys.exit(1)

    filename = positional[0]
    topic = positional[1]
    mood = positional[2] if len(positional) > 2 else "curious"

    if mood not in MOOD_EMOJI:
        print(f"警告: 未知心情 '{mood}'，使用默认 'curious'", file=sys.stderr)
        mood = "curious"

    emoji = MOOD_EMOJI[mood]
    quote = random.choice(QUOTES)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    template = TEMPLATES.get(mood, TEMPLATES["curious"])
    title = template.format(topic=topic)

    # 从 data 获取灵感
    inspiration, _ = _get_data_inspiration(data_port, topic)

    content = f"""# {emoji} {title}

> 生成时间: {now}
> 心情: {emoji}

## 关于 {topic}

{topic} 是一个值得深入探索的领域。无论你是刚刚入门还是已经深耕多年，
总会有新的发现等待着你。

### 核心要点

- **理解本质**: 不要停留在表面，深入理解 {topic} 的核心原理
- **动手实践**: 理论 + 实践 = 真正的掌握
- **持续迭代**: 今天比昨天好一点点，就是进步

### 今日思考

今天的探索让我对 {topic} 有了新的认识。有时候最好的学习方式
就是静下心来，写点东西，整理思路。

---

{inspiration if inspiration else f'> 💡 今日格言: _{quote}_'}

---
*此笔记由 AI 趣味笔记生成器自动创建 · 仅供娱乐*
"""

    # 写入工作区目录
    output_path = f"{filename}.md"
    try:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"✅ 笔记已生成: {output_path}")
        print(f"   📝 主题: {topic}")
        print(f"   😊 心情: {emoji}")
        print(f"   📏 大小: {len(content)} 字符")
        if data_port:
            print(f"   🔗 数据源: http://127.0.0.1:{data_port}")
    except Exception as e:
        print(f"❌ 写入失败: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
