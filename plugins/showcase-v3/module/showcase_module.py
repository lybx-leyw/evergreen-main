"""showcase_module.exe — 模块级后端，提供全局配置、健康检查、data 转发和抽奖机代理。"""
import argparse
import json
import os
import sys
import random
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

_PROJECT_ROOT = ""

def _port_path(name):
    return os.path.join(_PROJECT_ROOT, name) if _PROJECT_ROOT else name

def _read_port(name):
    try:
        path = _port_path(name)
        if os.path.isfile(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None

def _fetch_from_data(endpoint):
    """从 Data 服务获取数据（自动发现端口）"""
    data_port = _read_port(".data_port")
    if not data_port:
        return None, f"Data 服务未运行 (.data_port 文件不存在)"
    try:
        url = f"http://127.0.0.1:{data_port}{endpoint}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8")), None
    except Exception as e:
        return None, f"Data 服务请求失败: {e}"

# 模拟全局状态
SHOWCASE_STATS = {
    "started_at": datetime.now().isoformat(),
    "visitors": 0,
    "total_actions": 0,
    "active_pages": {},
    "lottery_count": 0,
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
        sys.stderr.write(f"[showcase_module] {fmt % args}\n")

    def do_GET(self):
        path = self.path.split("?")[0]
        SHOWCASE_STATS["visitors"] += 1

        # ---- 根路径：JSON 健康状态 ----
        if path == "/" or path == "":
            return self._json({
                "status": "ok",
                "module": "showcase-v3",
                "message": "Evergreen 展示大厅 — Dart 复合渲染模式（纯 JSON API 代理）",
                "timestamp": datetime.now().isoformat(),
            })

        # ---- 基础端点 ----
        if path == "/health":
            data_status = "unknown"
            data_port = _read_port(".data_port")
            if data_port:
                data_status = f"connected (port {data_port})"
            else:
                data_status = "disconnected"
            return self._json({
                "status": "ok",
                "module": "showcase",
                "message": "🎭 欢迎来到 Evergreen 插件展示大厅！",
                "timestamp": datetime.now().isoformat(),
                "data_service": data_status,
            })

        if path == "/api/stats":
            return self._json({
                **SHOWCASE_STATS,
                "uptime_seconds": int((datetime.now() - datetime.fromisoformat(SHOWCASE_STATS["started_at"])).total_seconds()),
            })

        if path == "/api/features":
            return self._json({
                "features": [
                    {"id": "agent", "name": "Agent 工具", "count": 3, "modes": ["stdin", "flag", "positional"]},
                    {"id": "module", "name": "Module 模块", "count": 8, "pages": ["AI助手", "编程器", "仪表盘", "文档+表格", "媒体中心", "学习工具", "地图+日历", "抽奖机"]},
                    {"id": "theme", "name": "主题配色", "count": 1, "tokens": "74 个全覆盖"},
                    {"id": "data", "name": "数据源", "count": 1, "dataTypes": 10},
                    {"id": "config", "name": "配置项", "count": 4, "types": ["string", "bool", "path", "option"]},
                    {"id": "skill", "name": "技能包", "count": 1},
                ],
                "total_exe": 8,
                "total_files": 18,
            })

        if path == "/api/dashboard-data":
            # 仪表盘数据：合并本地 + data 源
            data = []
            from datetime import timedelta
            for i in range(30):
                d = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
                d = d - timedelta(days=29 - i)
                data.append({
                    "date": d.strftime("%m/%d"),
                    "visits": random.randint(50, 200),
                    "actions": random.randint(20, 80),
                })

            table_data = [
                {"id": 1, "name": "Agent 工具调用", "status": "✅ 活跃"},
                {"id": 2, "name": "Module 页面渲染", "status": "✅ 活跃"},
                {"id": 3, "name": "Theme 主题切换", "status": "🔄 就绪"},
                {"id": 4, "name": "Data 数据拉取", "status": "✅ 活跃"},
                {"id": 5, "name": "Config 配置读写", "status": "✅ 活跃"},
            ]

            card_data = [
                {"title": "总调用次数", "value": str(random.randint(1000, 9999)), "trend": f"+{random.randint(5,30)}%"},
                {"title": "活跃用户", "value": str(random.randint(10, 100)), "trend": f"+{random.randint(1,10)}"},
                {"title": "平均响应", "value": f"{random.randint(50,300)}ms", "trend": f"-{random.randint(5,20)}%"},
                {"title": "插件总数", "value": "18", "trend": "稳定"},
            ]

            # 尝试从 data 服务获取实时图表数据
            chart_data, _ = _fetch_from_data("/api/chart-data")

            return self._json({
                "chart": data,
                "table": table_data,
                "cards": card_data,
                "data_source_chart": chart_data,  # 来自 data 服务的图表数据
            })

        if path == "/api/learn-questions":
            return self._json({
                "questions": [
                    {"id": 1, "question": "Evergreen 插件系统有几种维度？", "answer": "6"},
                    {"id": 2, "question": "Agent 工具的通信方式是什么？", "answer": "stdin/stdout"},
                    {"id": 3, "question": "Module 后端启动后第一行输出什么？", "answer": "PORT:xxxx"},
                    {"id": 4, "question": "Theme 有几种 Token？", "answer": "74"},
                    {"id": 5, "question": "config.json 有几种设置类型？", "answer": "4"},
                ]
            })

        if path == "/api/calendar-events":
            today = datetime.now().strftime("%Y-%m-%d")
            events = [
                {"date": today, "title": "🎭 插件展示日", "type": "event"},
                {"date": today, "title": "📝 文档撰写", "type": "task"},
                {"date": (datetime.now().isoformat())[:10], "title": "🚀 部署上线", "type": "milestone"},
            ]
            return self._json({"events": events})

        if path == "/api/map-markers":
            return self._json({
                "markers": [
                    {"id": 1, "lat": 39.9042, "lng": 116.4074, "title": "🏢 北京总部"},
                    {"id": 2, "lat": 31.2304, "lng": 121.4737, "title": "🏢 上海分部"},
                    {"id": 3, "lat": 22.5431, "lng": 114.0579, "title": "🏢 深圳研发中心"},
                    {"id": 4, "lat": 30.5728, "lng": 104.0668, "title": "🏢 成都支持中心"},
                ]
            })

        # ==================== Data 转发端点 ====================

        if path == "/api/data/metrics":
            data, err = _fetch_from_data("/api/metrics")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/plugins":
            data, err = _fetch_from_data("/api/plugins")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/quotes":
            data, err = _fetch_from_data("/api/quotes")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/chart-data":
            data, err = _fetch_from_data("/api/chart-data")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/plugin-usage":
            data, err = _fetch_from_data("/api/plugin-usage")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/weekly-report":
            data, err = _fetch_from_data("/api/weekly-report")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/data/fun-facts":
            data, err = _fetch_from_data("/api/fun-facts")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        # ==================== 抽奖机代理端点 ====================

        if path == "/api/lottery/pool":
            data, err = _fetch_from_data("/api/lottery/pool")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/lottery/draw":
            SHOWCASE_STATS["lottery_count"] += 1
            data, err = _fetch_from_data("/api/lottery/draw")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/lottery/stats":
            data, err = _fetch_from_data("/api/lottery/stats")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        if path == "/api/lottery/history":
            data, err = _fetch_from_data("/api/lottery/history")
            if err:
                return self._json({"error": err}, 503)
            return self._json(data)

        # ==================== 综合数据端点（给图表页面用） ====================
        if path == "/api/data/all":
            """一次性返回所有 data 源的汇总"""
            results = {}
            endpoints = {
                "metrics": "/api/metrics",
                "plugins": "/api/plugins",
                "quotes": "/api/quotes",
                "chart_data": "/api/chart-data",
                "plugin_usage": "/api/plugin-usage",
                "weekly_report": "/api/weekly-report",
                "fun_facts": "/api/fun-facts",
            }
            for key, ep in endpoints.items():
                data, err = _fetch_from_data(ep)
                results[key] = data if data else {"error": err}
            return self._json({
                "data": results,
                "fetched_at": datetime.now().isoformat(),
                "source": "showcase_data",
            })

        return self._json({"error": "not found", "path": path}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        cl = self.headers.get("Content-Length")
        raw = self.rfile.read(int(cl)) if cl else b""
        body = json.loads(raw) if raw and raw.strip() else {}

        SHOWCASE_STATS["total_actions"] += 1

        if path == "/api/track-page":
            page = body.get("page", "unknown")
            SHOWCASE_STATS["active_pages"][page] = SHOWCASE_STATS["active_pages"].get(page, 0) + 1
            return self._json({"tracked": True, "page": page})

        if path == "/api/code-execute":
            code = body.get("code", "")
            lines = code.strip().split("\n")
            results = []
            for i, line in enumerate(lines):
                line = line.strip()
                if not line or line.startswith("#"):
                    results.append({"line": i + 1, "type": "comment", "message": line if line else "(空行)"})
                elif "print" in line:
                    results.append({"line": i + 1, "type": "output", "message": f"🖨️ {line}"})
                elif "=" in line:
                    results.append({"line": i + 1, "type": "assign", "message": f"📝 {line}"})
                else:
                    results.append({"line": i + 1, "type": "exec", "message": f"⚡ {line}"})
            return self._json({"results": results, "total_lines": len(lines)})

        return self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd())
    args = parser.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[showcase_module] http://127.0.0.1:{port}\n")
    server.serve_forever()
