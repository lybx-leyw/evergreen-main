"""showcase_stdin — stdin 模式，接收嵌套 JSON 参数，生成有趣的团队角色卡片。
支持 --data-port <port> 从 Data 服务获取格言来丰富卡片内容。"""
import sys
import json
import random
import os
import urllib.request


ROLE_DESCRIPTIONS = {
    "frontend": {"zh": "🎨 前端魔法师", "en": "🎨 Frontend Wizard"},
    "backend":  {"zh": "⚙️ 后端炼金术士", "en": "⚙️ Backend Alchemist"},
    "designer": {"zh": "🖌️ 设计艺术家", "en": "🖌️ Design Artist"},
    "devops":   {"zh": "🚀 DevOps 指挥官", "en": "🚀 DevOps Commander"},
    "pm":       {"zh": "📋 产品航海家", "en": "📋 Product Navigator"},
}

LEVEL_PREFIX = {
    "junior":    {"zh": "初级·", "en": "Jr. "},
    "mid":       {"zh": "中级·", "en": "Mid. "},
    "senior":    {"zh": "高级·", "en": "Sr. "},
    "principal": {"zh": "首席·", "en": "Principal "},
}

POWERS = {
    "frontend": ["像素级还原", "CSS 黑魔法", "响应式布局术", "动画炼成阵", "组件化合体"],
    "backend":  ["API 锻造术", "数据库通灵", "缓存时光倒流", "并发分身术", "微服务指挥"],
    "designer": ["色彩感知力", "留白结界", "字体选择眼", "动效时间操控", "品牌灵魂注入"],
    "devops":   ["一键部署术", "容器召唤", "监控天眼", "日志溯流", "自愈结界"],
    "pm":       ["需求翻译", "优先级排序眼", "会议压缩术", "风险预言", "里程碑加速"],
}


def _read_port_file(name):
    """从 .xxx_port 文件读取端口"""
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.isfile(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _fetch_from_data(data_port, endpoint):
    """从 Data 服务获取数据"""
    try:
        url = f"http://127.0.0.1:{data_port}{endpoint}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def _get_inspiration(data_port):
    """尝试从 data 服务获取格言/冷知识作为卡片灵感"""
    # 先尝试从 .data_port 文件发现端口
    if not data_port:
        data_port = _read_port_file(".data_port")

    if not data_port:
        return None

    # 随机选一个端点获取有趣数据
    endpoints = ["/api/quotes", "/api/fun-facts", "/api/lottery/stats"]
    endpoint = random.choice(endpoints)
    data = _fetch_from_data(data_port, endpoint)

    if not data:
        return None

    if "quote" in data:
        return f'💡 今日格言: "{data["quote"]}" —— {data.get("author", "未知")}'
    if "facts" in data and data["facts"]:
        fact = random.choice(data["facts"])
        return f'📚 冷知识: {fact["fact"]}'
    if "best_pull" in data:
        return f'🎰 欧皇认证: 最佳抽奖 = {data["best_pull"]} (共{data.get("total_draws", "?")}次)'

    return None


def main():
    # 解析 --data-port 参数
    data_port = None
    clean_args = []
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == "--data-port" and i + 1 < len(sys.argv):
            data_port = sys.argv[i + 1]
            i += 2
        else:
            clean_args.append(sys.argv[i])
            i += 1

    try:
        raw = sys.stdin.buffer.read().decode("utf-8-sig")
        args = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, Exception):
        args = {}

    role = args.get("role", "frontend")
    name = args.get("name", "无名英雄")
    level = args.get("level", "mid")
    opts = args.get("options", {})
    use_emoji = opts.get("emoji", True)
    lang = opts.get("language", "zh")

    role_info = ROLE_DESCRIPTIONS.get(role, ROLE_DESCRIPTIONS["frontend"])
    level_tag = LEVEL_PREFIX.get(level, LEVEL_PREFIX["mid"])
    powers = random.sample(POWERS.get(role, POWERS["frontend"]), 3)

    # 尝试从 data 服务获取灵感
    inspiration = _get_inspiration(data_port)

    if use_emoji:
        header = "╔══════════════════════════════════════╗"
        footer = "╚══════════════════════════════════════╝"
    else:
        header = "+--------------------------------------+"
        footer = "+--------------------------------------+"

    if lang == "en":
        title = level_tag["en"] + role_info["en"]
        lines = [
            header,
            f"  {title}",
            f"  Name: {name}",
            f"  Special Powers:",
        ]
        for p in powers:
            lines.append(f"    * {p}")
        lines.append(footer)
    else:
        title = level_tag["zh"] + role_info["zh"]
        lines = [
            header,
            f"  {title}",
            f"  姓名: {name}",
            f"  专属技能:",
        ]
        for p in powers:
            lines.append(f"    ✦ {p}")
        if inspiration:
            lines.append("")
            lines.append(f"  {inspiration}")
        lines.append(footer)

    print("\n".join(lines))


if __name__ == "__main__":
    main()
