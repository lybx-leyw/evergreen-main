"""设置插件——从 ConfigHttpServer 拉取所有设置声明，动态渲染完整 HTML 设置页面。

访问 http://127.0.0.1:{PORT}/ 即可看到所有设置项并直接编辑保存。
同时保留 /api/* JSON 端点供 Flutter 端通过 HTTP 消费。
"""
import argparse, json, os, sys, urllib.request, urllib.error, html
from http.server import HTTPServer, BaseHTTPRequestHandler

# ═══════ 项目根路径 ═══════

_PROJECT_ROOT = ""

def _port_path(name):
    return os.path.join(_PROJECT_ROOT, name) if _PROJECT_ROOT else name

def _read_port(name):
    try:
        path = _port_path(name)
        if os.path.isfile(path):
            with open(path) as f:
                return f.read().strip()
    except:
        pass
    return None

CONFIG_BASE = None
THEME_BASE = None
AGENT_BASE = None

# ═══════ HTTP 工具 ═══════

def _get(url):
    try:
        return json.loads(urllib.request.urlopen(url, timeout=5))
    except Exception as e:
        return {"error": str(e)}

def _post(url, body):
    try:
        data = json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
        return json.loads(urllib.request.urlopen(req, timeout=5))
    except Exception as e:
        return {"error": str(e)}

# ═══════ HTML 渲染 ═══════

def _render_setting_control(item):
    """根据 setting type 生成对应的 HTML 表单控件。"""
    key = html.escape(item["key"])
    label = html.escape(item.get("label", key))
    value = html.escape(item.get("value", ""))
    hint = html.escape(item.get("hint", "")) if item.get("hint") else ""
    stype = item.get("type", "string")
    is_secure = item.get("isSecure", False)

    hint_html = f'<div class="hint">{hint}</div>' if hint else ""

    if stype == "bool":
        checked = "checked" if value.lower() == "true" else ""
        return f'''<div class="control-row">
    <label class="switch-label">{label}</label>
    <label class="switch">
        <input type="checkbox" data-key="{key}" data-type="bool" {checked}
               onchange="saveSetting('{key}', this.checked ? 'true' : 'false')">
        <span class="slider"></span>
    </label>
    {hint_html}
</div>'''

    elif stype == "option" and item.get("options"):
        options_html = ""
        for opt in item["options"]:
            opt_val = html.escape(opt["value"])
            opt_label = html.escape(opt["label"])
            sel = "selected" if opt_val == item.get("value", "") else ""
            options_html += f'<option value="{opt_val}" {sel}>{opt_label}</option>'
        return f'''<div class="control-row">
    <label class="field-label" for="s_{key}">{label}</label>
    <select id="s_{key}" data-key="{key}" data-type="option"
            onchange="saveSetting('{key}', this.value)">
        {options_html}
    </select>
    {hint_html}
</div>'''

    else:  # string / path
        input_type = "password" if is_secure else "text"
        return f'''<div class="control-row">
    <label class="field-label" for="s_{key}">{label}</label>
    <input type="{input_type}" id="s_{key}" data-key="{key}" data-type="string"
           value="{value}" placeholder="{hint}"
           onchange="saveSetting('{key}', this.value)">
    {hint_html}
</div>'''


def _render_page(settings_data):
    """渲染完整的 HTML 设置页面。"""
    items = settings_data.get("settings", [])
    error = settings_data.get("error", "")

    if error:
        body = f'<div class="error-box"><h2>加载失败</h2><p>{html.escape(error)}</p><button onclick="location.reload()">重试</button></div>'
    elif not items:
        body = '<div class="empty">暂无设置项。<br>请在 config.json 中声明设置。</div>'
    else:
        controls = "\n".join(_render_setting_control(it) for it in items)
        body = f'<form id="settings-form" onsubmit="return false">{controls}</form>'

    return f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Evergreen 设置</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #0f1116; color: #e1e4e8; min-height: 100vh;
}}
.header {{
    background: linear-gradient(135deg, #1a73e8 0%, #6c5ce7 100%);
    padding: 28px 32px; margin-bottom: 24px;
}}
.header h1 {{ font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }}
.header p {{ font-size: 13px; opacity: 0.8; margin-top: 4px; }}
.container {{ max-width: 720px; margin: 0 auto; padding: 0 24px 40px; }}
.control-row {{
    background: #181a21; border: 1px solid #2d3039; border-radius: 10px;
    padding: 16px 20px; margin-bottom: 10px;
    display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
}}
.control-row:hover {{ border-color: #3d4049; }}
.field-label {{
    font-size: 13px; font-weight: 600; color: #c4c8d0; min-width: 120px;
}}
.hint {{ font-size: 11px; color: #6a6f7a; width: 100%; margin-top: 2px; }}
input[type="text"], input[type="password"], select {{
    flex: 1; min-width: 200px;
    background: #22252e; border: 1px solid #2d3039; border-radius: 6px;
    color: #e1e4e8; padding: 8px 12px; font-size: 13px;
    font-family: "Cascadia Code", "Fira Code", monospace;
}}
input:focus, select:focus {{ outline: none; border-color: #1a73e8; box-shadow: 0 0 0 3px rgba(26,115,232,0.15); }}
select {{ cursor: pointer; font-family: inherit; }}

/* Switch */
.switch-label {{ font-size: 13px; font-weight: 600; color: #c4c8d0; min-width: 120px; }}
.switch {{ position: relative; display: inline-block; width: 44px; height: 24px; flex-shrink: 0; }}
.switch input {{ opacity: 0; width: 0; height: 0; }}
.slider {{
    position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0;
    background: #3a3d46; border-radius: 24px; transition: .25s;
}}
.slider:before {{
    content: ""; position: absolute; height: 18px; width: 18px; left: 3px; bottom: 3px;
    background: #fff; border-radius: 50%; transition: .25s;
}}
input:checked + .slider {{ background: #1a73e8; }}
input:checked + .slider:before {{ transform: translateX(20px); }}

/* Toast */
.toast {{
    position: fixed; bottom: 32px; left: 50%; transform: translateX(-50%);
    background: #2e7d32; color: #fff; padding: 10px 24px; border-radius: 8px;
    font-size: 13px; font-weight: 600; opacity: 0; transition: opacity .3s;
    pointer-events: none; z-index: 999;
}}
.toast.show {{ opacity: 1; }}
.toast.error {{ background: #c62828; }}

/* 操作栏 */
.actions {{
    display: flex; gap: 10px; margin-top: 20px; flex-wrap: wrap;
}}
.btn {{
    padding: 10px 20px; border-radius: 8px; font-size: 13px; font-weight: 600;
    border: none; cursor: pointer; transition: all .2s;
}}
.btn-primary {{ background: #1a73e8; color: #fff; }}
.btn-primary:hover {{ background: #1557b0; }}
.btn-outline {{ background: transparent; border: 1px solid #3d4049; color: #c4c8d0; }}
.btn-outline:hover {{ border-color: #1a73e8; color: #1a73e8; }}

.error-box, .empty {{
    text-align: center; padding: 60px 20px; color: #6a6f7a;
}}
.error-box h2 {{ color: #c62828; margin-bottom: 8px; }}
</style>
</head>
<body>
<div class="header">
    <h1>Evergreen 设置</h1>
    <p>所有可配置项</p>
</div>
<div class="container">
    {body}
    <div class="actions">
        <button class="btn btn-primary" onclick="location.reload()">刷新</button>
        <button class="btn btn-outline" onclick="exportSettings()">导出</button>
        <button class="btn btn-outline" onclick="document.getElementById('import-file').click()">导入</button>
        <input type="file" id="import-file" accept=".json" style="display:none" onchange="importSettings(this)">
    </div>
</div>
<div class="toast" id="toast"></div>
<script>
let toastTimer;
function showToast(msg, isError) {{
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.className = 'toast show' + (isError ? ' error' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.className = 'toast', 2000);
}}

async function saveSetting(key, value) {{
    try {{
        const resp = await fetch('/api/settings/' + encodeURIComponent(key), {{
            method: 'POST',
            headers: {{'Content-Type': 'application/json'}},
            body: JSON.stringify({{value: String(value)}})
        }});
        if (resp.ok) {{
            showToast('已保存: ' + key);
        }} else {{
            showToast('保存失败: ' + resp.status, true);
        }}
    }} catch(e) {{
        showToast('保存异常: ' + e.message, true);
    }}
}}

async function exportSettings() {{
    try {{
        const resp = await fetch('/api/export');
        const data = await resp.json();
        const blob = new Blob([JSON.stringify(data, null, 2)], {{type: 'application/json'}});
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'evergreen-settings-' + new Date().toISOString().slice(0,10) + '.json';
        a.click();
        showToast('已导出');
    }} catch(e) {{ showToast('导出失败', true); }}
}}

async function importSettings(input) {{
    try {{
        const file = input.files[0];
        if (!file) return;
        const text = await file.text();
        const data = JSON.parse(text);
        await fetch('/api/import', {{
            method: 'POST',
            headers: {{'Content-Type': 'application/json'}},
            body: JSON.stringify(data)
        }});
        showToast('已导入，刷新中...');
        setTimeout(() => location.reload(), 800);
    }} catch(e) {{ showToast('导入失败: ' + e.message, true); }}
}}
</script>
</body>
</html>'''


# ═══════ HTTP Handler ═══════

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
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
        sys.stderr.write(f"[settings] {fmt % args}\n")

    # ── GET ──

    def do_GET(self):
        path = self.path.split("?")[0]

        # 主页：动态渲染完整设置 HTML 页面
        if path == "/" or path == "/settings":
            return self._serve_settings_page()

        # JSON API 端点
        if path == "/health":
            return self._json({"status": "ok",
                "config": CONFIG_BASE is not None,
                "theme": THEME_BASE is not None,
                "agent": AGENT_BASE is not None})

        if path == "/api/settings" and CONFIG_BASE:
            return self._json(_get(f"{CONFIG_BASE}/config/settings"))

        if path.startswith("/api/settings/") and CONFIG_BASE:
            key = path.rsplit("/", 1)[-1]
            return self._json(_get(f"{CONFIG_BASE}/config/settings/{key}"))

        if path.startswith("/api/permissions/") and CONFIG_BASE:
            pid = path.rsplit("/", 1)[-1]
            return self._json(_get(f"{CONFIG_BASE}/config/permissions/{pid}"))

        if path == "/api/sources" and CONFIG_BASE:
            return self._json(_get(f"{CONFIG_BASE}/config/sources"))

        if path == "/api/themes" and THEME_BASE:
            return self._json(_get(f"{THEME_BASE}/theme/themes"))

        if path == "/api/memories" and AGENT_BASE:
            return self._json(_get(f"{AGENT_BASE}/agent/memories"))

        if path == "/api/styles" and AGENT_BASE:
            return self._json(_get(f"{AGENT_BASE}/agent/styles"))

        if path == "/api/export" and CONFIG_BASE:
            data = _get(f"{CONFIG_BASE}/config/settings")
            return self._json({"format": "evgconfig", "version": 1, "settings": data.get("settings", [])})

        if path == "/api/about":
            return self._json({"app": "Evergreen Base", "version": "1.0.0", "license": "MIT"})

        return self._json({"endpoint": path, "available": False}, 404)

    # ── POST ──

    def do_POST(self):
        path = self.path.split("?")[0]
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))) if self.headers.get("Content-Length") else b""
        body = json.loads(raw) if raw else {}

        if path.startswith("/api/settings/") and CONFIG_BASE:
            key = path.rsplit("/", 1)[-1]
            return self._json(_post(f"{CONFIG_BASE}/config/settings/{key}", body))

        if path.startswith("/api/permissions/") and CONFIG_BASE:
            pid = path.rsplit("/", 1)[-1]
            return self._json(_post(f"{CONFIG_BASE}/config/permissions/{pid}", body))

        if path == "/api/sources" and CONFIG_BASE:
            return self._json(_post(f"{CONFIG_BASE}/config/sources", body))

        if path == "/api/themes/active" and THEME_BASE:
            return self._json(_post(f"{THEME_BASE}/theme/active", body))

        if path == "/api/memories" and AGENT_BASE:
            return self._json(_post(f"{AGENT_BASE}/agent/memories", body))

        if path == "/api/styles" and AGENT_BASE:
            return self._json(_post(f"{AGENT_BASE}/agent/styles", body))

        if path == "/api/import" and CONFIG_BASE:
            items = body.get("settings", [])
            count = 0
            for item in items:
                key = item.get("key", "")
                val = item.get("value", "")
                if key:
                    _post(f"{CONFIG_BASE}/config/settings/{key}", {"value": str(val)})
                    count += 1
            return self._json({"imported": True, "count": count})

        return self._json({"endpoint": path, "available": False}, 404)

    # ── DELETE ──

    def do_DELETE(self):
        self._json({"deleted": True})

    # ── 设置页面渲染 ──

    def _serve_settings_page(self):
        """从 ConfigHttpServer 拉取设置数据，渲染完整 HTML 页面。"""
        if CONFIG_BASE is None:
            return self._html(_render_page({"error": "ConfigHttpServer 未启动（.config_port 未找到）"}), 503)
        data = _get(f"{CONFIG_BASE}/config/settings")
        return self._html(_render_page(data))


# ═══════ main ═══════

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd(), help="Flutter project root directory")
    args = parser.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    config_port = _read_port(".config_port")
    theme_port = _read_port(".theme_port")
    agent_port = _read_port(".agent_port")
    CONFIG_BASE = f"http://127.0.0.1:{config_port}" if config_port else None
    THEME_BASE = f"http://127.0.0.1:{theme_port}" if theme_port else None
    AGENT_BASE = f"http://127.0.0.1:{agent_port}" if agent_port else None

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[settings] http://127.0.0.1:{port}\n")
    if CONFIG_BASE: sys.stderr.write(f"[settings] config → {CONFIG_BASE}\n")
    if THEME_BASE:  sys.stderr.write(f"[settings] theme → {THEME_BASE}\n")
    if AGENT_BASE:  sys.stderr.write(f"[settings] agent → {AGENT_BASE}\n")
    server.serve_forever()
