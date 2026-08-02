"""设置插件——纯 API 代理服务器。

提供 /api/* JSON 端点，将请求转发给 ConfigHttpServer / ThemeHttpServer / AgentHttpServer。
UI 渲染由 Flutter 端（Dart SettingsView）负责，Python 端不包含任何 HTML/CSS/JS。
"""
import argparse, json, os, sys, urllib.request, urllib.error, http.client
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

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

def _http_request(method, url, body=None):
    """统一的 HTTP 请求函数，使用 http.client 直接控制请求。"""
    try:
        parsed = urlparse(url)
        conn = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=5)
        headers = {"Content-Type": "application/json"} if body is not None else {}
        body_bytes = json.dumps(body).encode("utf-8") if body is not None else None
        conn.request(method, parsed.path, body=body_bytes, headers=headers)
        resp = conn.getresponse()
        raw = resp.read().decode("utf-8")
        conn.close()
        return (resp.status, json.loads(raw))
    except Exception as e:
        return (0, {"error": str(e)})

def _get(url):
    _, data = _http_request("GET", url)
    return data

def _post(url, body):
    status, data = _http_request("POST", url, body)
    if status == 0:
        return data  # exception case, already {"error": ...}
    return data

# ═══════ HTTP Handler ═══════

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[settings] {fmt % args}\n")

    def _html(self, html, code=200):
        body = html.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    # ── GET ──

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/" or path == "":
            return self._html(HOMEPAGE_HTML)

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
        cl = self.headers.get("Content-Length")
        if cl:
            raw = self.rfile.read(int(cl))
        else:
            raw = b""
        body = json.loads(raw) if raw and raw.strip() else {}

        if path.startswith("/api/settings/") and CONFIG_BASE:
            key = path.rsplit("/", 1)[-1]
            result = _post(f"{CONFIG_BASE}/config/settings/{key}", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path.startswith("/api/permissions/") and CONFIG_BASE:
            pid = path.rsplit("/", 1)[-1]
            result = _post(f"{CONFIG_BASE}/config/permissions/{pid}", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path == "/api/sources" and CONFIG_BASE:
            result = _post(f"{CONFIG_BASE}/config/sources", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path == "/api/themes/active" and THEME_BASE:
            result = _post(f"{THEME_BASE}/theme/active", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path == "/api/memories" and AGENT_BASE:
            result = _post(f"{AGENT_BASE}/agent/memories", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path == "/api/styles" and AGENT_BASE:
            result = _post(f"{AGENT_BASE}/agent/styles", body)
            if "error" in result:
                return self._json(result, 502)
            return self._json(result)

        if path == "/api/import" and CONFIG_BASE:
            items = body.get("settings", [])
            count = 0
            for item in items:
                key = item.get("key", "")
                val = item.get("value", "")
                if key:
                    result = _post(f"{CONFIG_BASE}/config/settings/{key}", {"value": str(val)})
                    if "error" not in result:
                        count += 1
            return self._json({"imported": True, "count": count})

        return self._json({"endpoint": path, "available": False}, 404)

    # ── DELETE ──

    def do_DELETE(self):
        self._json({"deleted": True})


# ═══════ main ═══════

HOMEPAGE_HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>⚙ 设置</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;padding:40px;max-width:800px;margin:0 auto}
h1{font-size:1.8rem;color:#58a6ff;margin-bottom:4px}
.subtitle{color:#8b949e;margin-bottom:32px;font-size:0.85rem}
.group{margin-bottom:32px}
.group-title{font-size:0.8rem;text-transform:uppercase;color:#8b949e;letter-spacing:1px;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid #21262d}
.setting{display:flex;align-items:center;justify-content:space-between;padding:12px 0;border-bottom:1px solid #161b22}
.setting:last-child{border-bottom:none}
.setting-label{font-size:0.95rem}
.setting-desc{font-size:0.75rem;color:#8b949e;margin-top:2px}
.setting-value{display:flex;align-items:center;gap:8px}
input,select{background:#161b22;border:1px solid #30363d;color:#c9d1d9;padding:8px 12px;border-radius:6px;font-size:0.9rem;min-width:200px}
input:focus,select:focus{outline:none;border-color:#58a6ff}
.btn-save{background:#238636;color:#fff;border:none;padding:8px 16px;border-radius:6px;cursor:pointer;font-size:0.85rem}
.btn-save:hover{background:#2ea043}
.empty{text-align:center;color:#8b949e;padding:60px 0;font-size:0.9rem}
</style>
</head>
<body>
<h1>⚙ Evergreen 设置</h1>
<p class="subtitle">API Key · 模型 · 主题 · 全局配置</p>
<div id="groups"></div>
<script>
async function load(){
  try{
    const r=await fetch('/api/settings');
    const d=await r.json();
    const settings=d.settings||[];
    if(!settings.length){document.getElementById('groups').innerHTML='<div class="empty">暂无可用设置项</div>';return}
    const groups={};
    settings.forEach(s=>{const g=s.group||'通用';if(!groups[g])groups[g]=[];groups[g].push(s)});
    let html='';
    for(const[g,items]of Object.entries(groups)){
      html+='<div class="group"><div class="group-title">'+g+'</div>';
      items.forEach(s=>{
        const val=s.value||'';
        const isSecret=s.secret||s.type==='password';
        const inputType=isSecret?'password':'text';
        html+='<div class="setting"><div><div class="setting-label">'+s.label+'</div>';
        if(s.description)html+='<div class="setting-desc">'+s.description+'</div>';
        html+='</div><div class="setting-value">';
        html+='<input type="'+inputType+'" id="'+s.key+'" value="'+val.replace(/"/g,'&quot;')+'" placeholder="'+s.key+'">';
        html+='<button class="btn-save" onclick="save(\''+s.key+'\')">保存</button>';
        html+='</div></div>';
      });
      html+='</div>';
    }
    document.getElementById('groups').innerHTML=html;
  }catch(e){document.getElementById('groups').innerHTML='<div class="empty">无法加载设置: '+e.message+'</div>'}
}
async function save(key){
  const el=document.getElementById(key);
  const val=el.value;
  try{
    await fetch('/api/settings/'+key,{method:'POST',body:JSON.stringify({value:val})});
    el.style.borderColor='#238636';setTimeout(()=>el.style.borderColor='#30363d',1500);
  }catch(e){el.style.borderColor='#da3633';setTimeout(()=>el.style.borderColor='#30363d',1500)}
}
load();
</script>
</body>
</html>"""

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
