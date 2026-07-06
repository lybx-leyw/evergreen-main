"""showcase_data.exe — 数据源后端，提供丰富的模拟数据 + 抽奖机。"""
import json
import sys
import random
import math
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timedelta

QUOTES = [
    {"text": "简单是可靠的先决条件。", "author": "Edsger Dijkstra"},
    {"text": "代码是写给人看的，顺便给机器运行。", "author": "Abelson & Sussman"},
    {"text": "先让它工作，再让它正确，最后让它快。", "author": "Kent Beck"},
    {"text": "任何傻瓜都能写出计算机能懂的代码，好程序员写出人能读懂的代码。", "author": "Martin Fowler"},
    {"text": "软件就像熵：容易增长，难以控制。", "author": "Norman Augustine"},
    {"text": "永远不要停止学习。", "author": "未知"},
    {"text": "你今天写的最烂的代码，比昨天没写的代码强100倍。", "author": "匿名"},
    {"text": "编程是一门艺术，调试是一门科学。", "author": "匿名"},
    {"text": "最好的代码是没有代码。", "author": "某架构师"},
    {"text": "在软件领域，一周有三天：昨天、今天和明天。", "author": "项目经理"},
    {"text": "如果调试是移除 bug 的过程，那编程就是引入 bug 的过程。", "author": "Edsger Dijkstra"},
    {"text": "Talk is cheap. Show me the code.", "author": "Linus Torvalds"},
    {"text": "第一法则：不要写你自己不会用的代码。", "author": "未知"},
    {"text": "优秀的代码本身就是最好的文档。", "author": "Steve McConnell"},
    {"text": "程序必须是为了给人阅读而写，只是附带地给机器执行。", "author": "Abelson & Sussman"},
    {"text": "软件工程不是关于代码，而是关于人。", "author": "Tom DeMarco"},
    {"text": "过早优化是万恶之源。", "author": "Donald Knuth"},
    {"text": "代码重构就像是打扫房间——你知道该做，但总有更重要的事。", "author": "匿名"},
    {"text": "每一个优秀的软件都始于一个开发者挠自己的痒处。", "author": "Eric Raymond"},
    {"text": "Bug 不是错误，它们是未记录的特性。", "author": "某开发者"},
]

PLUGIN_LIST = [
    {"id": "ai-assistant", "name": "AI 助手", "type": "module", "status": "active"},
    {"id": "settings", "name": "设置", "type": "module", "status": "active"},
    {"id": "pomodoro", "name": "番茄钟", "type": "module", "status": "active"},
    {"id": "calculator", "name": "计算器", "type": "agent", "status": "active"},
    {"id": "dark", "name": "深色主题", "type": "theme", "status": "active"},
    {"id": "light", "name": "浅色主题", "type": "theme", "status": "active"},
    {"id": "showcase", "name": "展示大厅", "type": "module", "status": "active"},
    {"id": "base64", "name": "Base64编解码", "type": "agent", "status": "active"},
    {"id": "json-format", "name": "JSON格式化", "type": "agent", "status": "active"},
    {"id": "uuid-gen", "name": "UUID生成", "type": "agent", "status": "active"},
    {"id": "password-gen", "name": "密码生成", "type": "agent", "status": "active"},
    {"id": "qr-text", "name": "二维码", "type": "agent", "status": "active"},
    {"id": "word-count", "name": "字数统计", "type": "agent", "status": "active"},
    {"id": "color-convert", "name": "颜色转换", "type": "agent", "status": "active"},
    {"id": "url-encode", "name": "URL编解码", "type": "agent", "status": "active"},
    {"id": "unit-convert", "name": "单位转换", "type": "agent", "status": "active"},
    {"id": "text-utils", "name": "文本工具", "type": "agent", "status": "active"},
    {"id": "mkdir", "name": "创建目录", "type": "agent", "status": "active"},
]

# ===================== 抽奖机数据 =====================

LOTTERY_POOL = [
    {"id": 1, "name": "🧸 小黄鸭调试器", "rarity": "common", "weight": 40, "desc": "放在桌上，bug 自动远离"},
    {"id": 2, "name": "☕ 无限续杯咖啡券", "rarity": "common", "weight": 30, "desc": "程序员的生命之源"},
    {"id": 3, "name": "🎧 降噪耳机(虚拟)", "rarity": "common", "weight": 25, "desc": "进入心流状态的必需品"},
    {"id": 4, "name": "📝 手写代码笔记本", "rarity": "common", "weight": 20, "desc": "面试专用，虽然从来没用过"},
    {"id": 5, "name": "🖥️ 双屏显示器支架", "rarity": "rare", "weight": 12, "desc": "生产力 ×2"},
    {"id": 6, "name": "⌨️ 机械键盘(青轴)", "rarity": "rare", "weight": 10, "desc": "吵死同事的快乐"},
    {"id": 7, "name": "🪑 人体工学椅", "rarity": "rare", "weight": 8, "desc": "腰不好的救星"},
    {"id": 8, "name": "📚 《代码大全》签名版", "rarity": "rare", "weight": 6, "desc": "镇桌之宝"},
    {"id": 9, "name": "🚀 CI/CD 一键部署令牌", "rarity": "epic", "weight": 4, "desc": "周五下午 5 点也能部署"},
    {"id": 10, "name": "💎 无 Bug 光环(1天)", "rarity": "epic", "weight": 3, "desc": "今天写的代码零 bug！"},
    {"id": 11, "name": "🔮 需求预言水晶球", "rarity": "epic", "weight": 2, "desc": "提前知道 PM 下周要改什么"},
    {"id": 12, "name": "🐉 驯龙高手·Git 分支合并术", "rarity": "legendary", "weight": 1, "desc": "永远没有 merge conflict"},
    {"id": 13, "name": "🌟 完美代码之石", "rarity": "legendary", "weight": 0.5, "desc": "一次 code review 直接通过"},
    {"id": 14, "name": "🎰 再来一次", "rarity": "special", "weight": 5, "desc": "再抽一次！"},
]

RARITY_COLORS = {
    "common": "#9E9E9E",
    "rare": "#2196F3",
    "epic": "#9C27B0",
    "legendary": "#FF9800",
    "special": "#E91E63",
}

RARITY_EFFECTS = {
    "common": "✨ 普通品质",
    "rare": "💫 稀有品质！",
    "epic": "🌟 史诗品质！！",
    "legendary": "🔥 传说品质！！！",
    "special": "💖 特殊奖励",
}


class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

    # ---- 辅助方法 ----
    def _weighted_choice(self, pool):
        """加权随机选择"""
        total = sum(item["weight"] for item in pool)
        r = random.uniform(0, total)
        cumulative = 0
        for item in pool:
            cumulative += item["weight"]
            if r <= cumulative:
                return item
        return pool[-1]

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/health":
            return self._json({
                "status": "ok",
                "service": "showcase_data",
                "endpoints": [
                    "/api/metrics", "/api/plugins", "/api/quotes",
                    "/api/chart-data", "/api/lottery/pool", "/api/lottery/draw",
                    "/api/lottery/stats", "/api/lottery/history",
                    "/api/plugin-usage", "/api/weekly-report", "/api/fun-facts",
                ]
            })

        # ---- 原有端点 ----
        if path == "/api/metrics":
            t = datetime.now()
            return self._json({
                "timestamp": t.isoformat(),
                "cpu": round(random.uniform(10, 80), 1),
                "memory": round(random.uniform(30, 90), 1),
                "disk": round(random.uniform(20, 70), 1),
                "network_in": random.randint(100, 10000),
                "network_out": random.randint(50, 5000),
                "active_connections": random.randint(1, 50),
                # 新增：用于图表展示的时间序列数据
                "history": [
                    {
                        "time": (t - timedelta(minutes=i)).strftime("%H:%M"),
                        "cpu": round(random.uniform(15, 75), 1),
                        "memory": round(random.uniform(35, 85), 1),
                    }
                    for i in range(12, -1, -1)
                ]
            })

        if path == "/api/plugins":
            return self._json({
                "plugins": PLUGIN_LIST,
                "total": len(PLUGIN_LIST),
                "by_type": {
                    "module": sum(1 for p in PLUGIN_LIST if p["type"] == "module"),
                    "agent": sum(1 for p in PLUGIN_LIST if p["type"] == "agent"),
                    "theme": sum(1 for p in PLUGIN_LIST if p["type"] == "theme"),
                },
            })

        if path == "/api/quotes":
            quote = random.choice(QUOTES)
            return self._json({
                "quote": quote["text"],
                "author": quote["author"],
                "date": datetime.now().strftime("%Y-%m-%d"),
            })

        # ---- 新增：图表数据端点 ----
        if path == "/api/chart-data":
            """返回多种图表数据，供 module 画图使用"""
            days = 14
            base_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

            # 折线图：插件调用趋势
            line_data = []
            for i in range(days):
                d = base_date - timedelta(days=days - 1 - i)
                line_data.append({
                    "date": d.strftime("%m/%d"),
                    "agent_calls": random.randint(20, 150),
                    "module_views": random.randint(50, 300),
                    "data_fetches": random.randint(10, 80),
                })

            # 饼图：插件类型分布
            type_counts = {}
            for p in PLUGIN_LIST:
                type_counts[p["type"]] = type_counts.get(p["type"], 0) + 1
            pie_data = [
                {"name": "Agent 工具", "value": type_counts.get("agent", 0), "color": "#FF6B6B"},
                {"name": "Module 模块", "value": type_counts.get("module", 0), "color": "#4ECDC4"},
                {"name": "Theme 主题", "value": type_counts.get("theme", 0), "color": "#FFE66D"},
            ]

            # 柱状图：各时段活跃度
            bar_data = []
            for h in range(24):
                active = random.randint(0, 100)
                if 9 <= h <= 12:
                    active = random.randint(60, 100)
                elif 14 <= h <= 18:
                    active = random.randint(50, 90)
                elif 0 <= h <= 6:
                    active = random.randint(0, 15)
                bar_data.append({
                    "hour": f"{h:02d}:00",
                    "active_users": active,
                    "is_peak": 9 <= h <= 12 or 14 <= h <= 18,
                })

            # 雷达图：插件能力评分
            radar_data = [
                {"name": "易用性", "score": random.randint(85, 98)},
                {"name": "扩展性", "score": random.randint(80, 95)},
                {"name": "性能", "score": random.randint(75, 92)},
                {"name": "稳定性", "score": random.randint(82, 96)},
                {"name": "文档", "score": random.randint(70, 90)},
                {"name": "社区", "score": random.randint(60, 85)},
            ]

            return self._json({
                "line": line_data,
                "pie": pie_data,
                "bar": bar_data,
                "radar": radar_data,
            })

        # ---- 新增：插件使用统计 ----
        if path == "/api/plugin-usage":
            usage = []
            for p in PLUGIN_LIST:
                usage.append({
                    "id": p["id"],
                    "name": p["name"],
                    "type": p["type"],
                    "calls_today": random.randint(0, 200),
                    "calls_total": random.randint(100, 10000),
                    "avg_latency_ms": random.randint(5, 500),
                    "success_rate": round(random.uniform(90, 100), 1),
                })
            usage.sort(key=lambda x: x["calls_today"], reverse=True)
            return self._json({"usage": usage})

        # ---- 新增：周报数据 ----
        if path == "/api/weekly-report":
            return self._json({
                "week": datetime.now().strftime("%Y年第%W周"),
                "summary": {
                    "total_plugins": len(PLUGIN_LIST),
                    "active_plugins": sum(1 for p in PLUGIN_LIST if p["status"] == "active"),
                    "total_calls": random.randint(5000, 20000),
                    "avg_uptime_pct": round(random.uniform(98.0, 99.99), 2),
                },
                "top_plugins": random.sample(PLUGIN_LIST, min(5, len(PLUGIN_LIST))),
                "trend": random.choice(["上升 📈", "稳定 ➡️", "波动 📊"]),
            })

        # ---- 新增：趣味冷知识 ----
        if path == "/api/fun-facts":
            facts = [
                {"fact": "第一个计算机 bug 是一只真正的飞蛾", "category": "历史"},
                {"fact": "GitHub 上最多的 commit 消息是 'update'", "category": "统计"},
                {"fact": "程序员平均每天写 10 行有效代码", "category": "日常"},
                {"fact": "世界上第一个程序员是女性——Ada Lovelace", "category": "历史"},
                {"fact": "命名是编程中最难的两件事之一", "category": "哲学"},
                {"fact": "JavaScript 诞生只用了 10 天", "category": "历史"},
                {"fact": "程序员花 50% 时间在调试上", "category": "统计"},
                {"fact": "Stack Overflow 最热门的回答是 'How to undo a git commit'", "category": "日常"},
                {"fact": "Python 名字来自喜剧团体 Monty Python，不是蛇", "category": "冷知识"},
                {"fact": "空格和 Tab 的战争至今未结束", "category": "战争"},
            ]
            return self._json({
                "facts": random.sample(facts, min(5, len(facts))),
                "total_known": len(facts),
            })

        # ---- 抽奖机 ----
        if path == "/api/lottery/pool":
            return self._json({
                "pool": [
                    {k: v for k, v in item.items() if k != "weight"}
                    for item in LOTTERY_POOL
                ],
                "total_items": len(LOTTERY_POOL),
                "rarity_distribution": {
                    rarity: sum(1 for i in LOTTERY_POOL if i["rarity"] == rarity)
                    for rarity in ["common", "rare", "epic", "legendary", "special"]
                }
            })

        if path == "/api/lottery/draw":
            """抽一次奖"""
            result = self._weighted_choice(LOTTERY_POOL)
            color = RARITY_COLORS.get(result["rarity"], "#9E9E9E")
            effect = RARITY_EFFECTS.get(result["rarity"], "✨")

            # 如果是"再来一次"，自动追加一次
            extra = None
            if result["id"] == 14:
                extra_item = self._weighted_choice([i for i in LOTTERY_POOL if i["id"] != 14])
                extra = {
                    "item": {k: v for k, v in extra_item.items() if k != "weight"},
                    "color": RARITY_COLORS.get(extra_item["rarity"], "#9E9E9E"),
                    "effect": RARITY_EFFECTS.get(extra_item["rarity"], "✨"),
                }

            return self._json({
                "draw_time": datetime.now().isoformat(),
                "item": {k: v for k, v in result.items() if k != "weight"},
                "rarity": result["rarity"],
                "color": color,
                "effect": effect,
                "is_special": result["id"] == 14,
                "extra_draw": extra,
            })

        if path == "/api/lottery/stats":
            """抽奖统计（模拟）"""
            total_draws = random.randint(100, 9999)
            return self._json({
                "total_draws": total_draws,
                "by_rarity": {
                    "common": random.randint(total_draws // 2, total_draws),
                    "rare": random.randint(total_draws // 5, total_draws // 3),
                    "epic": random.randint(total_draws // 20, total_draws // 10),
                    "legendary": random.randint(0, total_draws // 50),
                    "special": random.randint(total_draws // 30, total_draws // 15),
                },
                "lucky_streak": random.randint(0, 5),
                "best_pull": random.choice([i for i in LOTTERY_POOL if i["rarity"] in ("epic", "legendary")])["name"],
            })

        if path == "/api/lottery/history":
            """模拟抽奖历史"""
            history = []
            for _ in range(20):
                item = self._weighted_choice(LOTTERY_POOL)
                history.append({
                    "time": (datetime.now() - timedelta(
                        hours=random.randint(0, 72),
                        minutes=random.randint(0, 59)
                    )).isoformat(),
                    "item": item["name"],
                    "rarity": item["rarity"],
                })
            history.sort(key=lambda x: x["time"], reverse=True)
            return self._json({"history": history, "count": len(history)})

        return self._json({"error": "not found", "path": path}, 404)


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[showcase_data] http://127.0.0.1:{port}\n")
    server.serve_forever()
