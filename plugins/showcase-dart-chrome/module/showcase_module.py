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

    def _html(self, content, code=200):
        body = content.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[showcase_module] {fmt % args}\n")

    def do_GET(self):
        path = self.path.split("?")[0]
        SHOWCASE_STATS["visitors"] += 1

        # ---- 根路径：HTML 主页 ----
        if path == "/" or path == "":
            return self._html(HOMEPAGE_HTML)

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


# ═══════════════════════════════════════════════════════════════════
# HTML 主页 — 外置浏览器渲染（Dart 后端管理，Python HTTP 直出）
# ═══════════════════════════════════════════════════════════════════

HOMEPAGE_HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🎭 Evergreen 展示大厅</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; overflow: hidden; }
body {
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: #0d1117; color: #c9d1d9;
}
#app { display: flex; flex-direction: column; height: 100vh; }

/* ── 顶栏 ── */
.topbar {
  display: flex; align-items: center; gap: 16px;
  padding: 0 20px; height: 48px; flex-shrink: 0;
  background: #161b22; border-bottom: 1px solid #30363d;
}
.topbar-title { font-size: 15px; font-weight: 700; color: #c9d1d9; }
.topbar-badge {
  font-size: 11px; padding: 2px 8px; border-radius: 12px;
  background: #1f6feb22; color: #58a6ff; border: 1px solid #1f6feb44;
}
.topbar-status { margin-left: auto; display: flex; align-items: center; gap: 8px; }
.topbar-dot { width: 8px; height: 8px; border-radius: 50%; }
.topbar-dot.online { background: #3fb950; }
.topbar-dot.offline { background: #f85149; }
.topbar-text { font-size: 12px; color: #8b949e; }

/* ── Shell: 侧边栏 + 内容区 ── */
.shell { display: flex; flex: 1; overflow: hidden; }
.sidebar {
  width: 200px; flex-shrink: 0; background: #161b22;
  border-right: 1px solid #30363d; overflow-y: auto;
}
.sidebar-section {
  padding: 12px 12px 4px; font-size: 11px; font-weight: 700;
  color: #58a6ff; text-transform: uppercase; letter-spacing: .5px;
}
.nav-item {
  display: block; padding: 8px 16px; color: #8b949e;
  text-decoration: none; font-size: 13px;
  border-left: 2px solid transparent; cursor: pointer; transition: all .15s;
}
.nav-item:hover, .nav-item.active { color: #c9d1d9; border-left-color: #58a6ff; background: #1c2128; }

.main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }

/* ── 内容区 ── */
.content { flex: 1; overflow-y: auto; padding: 32px; }
.welcome { text-align: center; padding: 60px 0; }
.welcome h1 { font-size: 28px; font-weight: 700; margin-bottom: 8px; }
.welcome p { color: #8b949e; font-size: 14px; max-width: 500px; margin: 0 auto; line-height: 1.6; }

/* ── 六维矩阵卡片 ── */
.matrix {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 16px; margin-top: 32px;
}
.card {
  background: #161b22; border: 1px solid #30363d; border-radius: 8px;
  padding: 20px; transition: border-color .15s;
}
.card:hover { border-color: #58a6ff; }
.card-header { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; }
.card-icon {
  width: 40px; height: 40px; border-radius: 8px; display: flex;
  align-items: center; justify-content: center; font-size: 20px;
}
.card-icon.agent { background: #1f6feb22; }
.card-icon.module { background: #3fb95022; }
.card-icon.theme { background: #a475f922; }
.card-icon.data { background: #f0883e22; }
.card-icon.config { background: #e85dad22; }
.card-icon.skill { background: #539bf522; }
.card-title { font-size: 15px; font-weight: 600; }
.card-desc { font-size: 12px; color: #8b949e; line-height: 1.5; }

/* ── 状态栏脚 ── */
.footer {
  height: 28px; flex-shrink: 0; background: #161b22;
  border-top: 1px solid #30363d; display: flex; align-items: center;
  padding: 0 16px; font-size: 11px; color: #484f58;
}
.footer span { margin-right: 24px; }
.footer .right { margin-left: auto; }
</style>
</head>
<body>
<div id="app">
  <!-- 顶栏 -->
  <div class="topbar">
    <span class="topbar-title">🎭 Evergreen 展示大厅</span>
    <span class="topbar-badge">HTML 直出模式</span>
    <div class="topbar-status">
      <span id="visitor-count" class="topbar-text">访问: ...</span>
      <span class="topbar-dot online"></span>
      <span class="topbar-text" id="uptime">运行中</span>
    </div>
  </div>

  <!-- 主体 -->
  <div class="shell">
    <nav class="sidebar">
      <div class="sidebar-section">展示</div>
      <a class="nav-item active" href="#" onclick="showPage('home')">🏠 首页</a>
      <a class="nav-item" href="#" onclick="showPage('features')">📊 能力矩阵</a>
      <a class="nav-item" href="#" onclick="showPage('stats')">📋 系统状态</a>
    </nav>

    <div class="main">
      <div class="content" id="content">
        <!-- JS 动态填充 -->
      </div>
      <div class="footer">
        <span>Evergreen 2.0 · Dart 后端管理</span>
        <span>Python HTTP 直出 HTML</span>
        <span class="right" id="footer-time"></span>
      </div>
    </div>
  </div>
</div>

<script>
var API = window.location.origin;

// ═══ 页面切换 ═══
async function showPage(name) {
  document.querySelectorAll('.nav-item').forEach(function(el) { el.classList.remove('active'); });
  event.target.classList.add('active');
  var c = document.getElementById('content');
  if (name === 'home') c.innerHTML = await renderHome();
  else if (name === 'features') c.innerHTML = await renderFeatures();
  else if (name === 'stats') c.innerHTML = await renderStats();
}

async function renderHome() {
  try {
    var resp = await fetch(API + '/health');
    var data = await resp.json();
    return '<div class="welcome"><h1>' + (data.message || '欢迎来到 Evergreen') + '</h1>' +
      '<p>Evergreen 是一个 Flutter 桌面微工具平台——无账号、无服务端、本地优先、AI 原生。<br>' +
      '支持 Agent / Module / Theme / Data / Config / Skill 六维插件生态。</p></div>' +
      '<div class="matrix" id="matrix"></div>';
  } catch(e) {
    return '<div class="welcome"><h1>Evergreen 展示大厅</h1><p style="color:#f85149">后端连接失败: ' + e.message + '</p></div>';
  }
}

async function renderFeatures() {
  try {
    var resp = await fetch(API + '/api/features');
    var data = await resp.json();
    var icons = {agent:'',module:'',theme:'',data:'',config:'',skill:''};
    var html = '<h2 style="margin-bottom:16px;font-size:18px;">六维能力矩阵</h2><div class="matrix">';
    data.features.forEach(function(f) {
      html += '<div class="card"><div class="card-header"><div class="card-icon ' + f.id + '">' + (icons[f.id]||'') + '</div><div class="card-title">' + f.name + '</div></div><div class="card-desc">';
      if (f.modes) html += '模式: ' + f.modes.join(', ');
      else if (f.pages) html += '页面: ' + f.pages.join(', ');
      else if (f.tokens) html += 'Token: ' + f.tokens;
      else if (f.dataTypes) html += '类型: ' + f.dataTypes + '种';
      else if (f.types) html += '类型: ' + f.types.join(', ');
      html += '</div><div class="card-desc" style="margin-top:8px">已注册: ' + f.count + ' 项</div></div>';
    });
    return html + '</div>';
  } catch(e) {
    return '<h2>能力矩阵</h2><p style="color:#f85149">加载失败: ' + e.message + '</p>';
  }
}

async function renderStats() {
  try {
    var resp = await fetch(API + '/api/stats');
    var s = await resp.json();
    var min = Math.floor(s.uptime_seconds / 60);
    var sec = s.uptime_seconds % 60;
    return '<h2 style="margin-bottom:16px;font-size:18px;">系统状态</h2><div class="matrix">' +
      '<div class="card"><div class="card-header"><div class="card-title">运行时长</div></div><div class="card-desc">' + min + ' 分 ' + sec + ' 秒</div></div>' +
      '<div class="card"><div class="card-header"><div class="card-title">访问次数</div></div><div class="card-desc">' + s.visitors + '</div></div>' +
      '<div class="card"><div class="card-header"><div class="card-title">操作总数</div></div><div class="card-desc">' + s.total_actions + '</div></div>' +
      '<div class="card"><div class="card-header"><div class="card-title">抽奖次数</div></div><div class="card-desc">' + s.lottery_count + '</div></div>' +
      '</div>';
  } catch(e) {
    return '<h2>系统状态</h2><p style="color:#f85149">加载失败: ' + e.message + '</p>';
  }
}

// ═══ 初始化 ═══
(async function init() {
  await showPage('home');

  // 更新状态栏
  fetch(API + '/api/stats').then(function(r) { return r.json(); }).then(function(s) {
    document.getElementById('visitor-count').textContent = '访问: ' + s.visitors;
  }).catch(function(){});

  // 时钟
  function tick() {
    document.getElementById('footer-time').textContent = new Date().toLocaleString('zh-CN');
  }
  tick();
  setInterval(tick, 1000);

  // 矩阵首页数据
  fetch(API + '/api/features').then(function(r) { return r.json(); }).then(function(data) {
    var icons = {agent:'',module:'',theme:'',data:'',config:'',skill:''};
    var html = '';
    data.features.forEach(function(f) {
      html += '<div class="card"><div class="card-header"><div class="card-icon ' + f.id + '">' + (icons[f.id]||'') + '</div><div class="card-title">' + f.name + '</div></div><div class="card-desc">' + f.count + ' 项已注册</div></div>';
    });
    document.getElementById('matrix').innerHTML = html;
  }).catch(function(){});
})();
</script>
</body>
</html>"""


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
