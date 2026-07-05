"""设置内置模块——代理到 ConfigHttpServer/ThemeHttpServer/AgentHttpServer 的 8 端点。

启动: PORT:0 自动分配 → 读取 .config_port + .theme_port + .agent_port → 代理 CRUD。
"""
import argparse, json, os, sys, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

# ═══════ 项目根路径（由 ModuleLoader 通过 --project-root 传入） ═══════

_PROJECT_ROOT = ""

def _port_path(name):
    # type: (str) -> str
    """返回端口文件的完整路径（基于 _PROJECT_ROOT）。"""
    return os.path.join(_PROJECT_ROOT, name) if _PROJECT_ROOT else name


def _read_port(name):
    try:
        path = _port_path(name)
        if os.path.isfile(path):
            with open(path) as f: return f.read().strip()
    except: pass
    return None

# 端口变量——在 __main__ 中通过 global 赋值（_PROJECT_ROOT 设置之后）
CONFIG_PORT = None  # type: str | None
THEME_PORT = None  # type: str | None
AGENT_PORT = None  # type: str | None
CONFIG_BASE = None  # type: str | None
THEME_BASE = None  # type: str | None
AGENT_BASE = None  # type: str | None

def _get(url):
    try:
        return json.loads(urllib.request.urlopen(url, timeout=5))
    except Exception as e:
        return {"error": str(e)}

def _post(url, body):
    try:
        data = json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, headers={"Content-Type":"application/json"}, method="POST")
        return json.loads(urllib.request.urlopen(req, timeout=5))
    except Exception as e:
        return {"error": str(e)}

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        sys.stderr.write(f"[settings] {args[0]}\n")

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/health":
            self._json({"status":"ok","config":CONFIG_BASE is not None,"theme":THEME_BASE is not None,"agent":AGENT_BASE is not None})
        elif path.startswith("/settings/") and CONFIG_BASE:
            key = path.split("/")[-1]
            self._json(_get(f"{CONFIG_BASE}/config/settings/{key}"))
        elif path.startswith("/permissions/") and CONFIG_BASE:
            pid = path.split("/")[-1]
            self._json(_get(f"{CONFIG_BASE}/config/permissions/{pid}"))
        elif path == "/sources" and CONFIG_BASE:
            self._json(_get(f"{CONFIG_BASE}/config/sources"))
        elif path == "/themes" and THEME_BASE:
            self._json(_get(f"{THEME_BASE}/theme/themes"))
        elif path == "/memories" and AGENT_BASE:
            self._json(_get(f"{AGENT_BASE}/agent/memories"))
        elif path == "/styles" and AGENT_BASE:
            self._json(_get(f"{AGENT_BASE}/agent/styles"))
        elif path == "/about":
            self._json({"app":"Evergreen Base","version":"1.0.0","license":"MIT"})
        else:
            self._json({"endpoint":path,"available":False}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))) if self.headers.get("Content-Length") else b""
        body = json.loads(raw) if raw else {}

        if path.startswith("/settings/") and CONFIG_BASE:
            key = path.split("/")[-1]
            self._json(_post(f"{CONFIG_BASE}/config/settings/{key}", body))
        elif path.startswith("/permissions/") and CONFIG_BASE:
            pid = path.split("/")[-1]
            self._json(_post(f"{CONFIG_BASE}/config/permissions/{pid}", body))
        elif path == "/sources" and CONFIG_BASE:
            self._json(_post(f"{CONFIG_BASE}/config/sources", body))
        elif path == "/themes/active" and THEME_BASE:
            self._json(_post(f"{THEME_BASE}/theme/active", body))
        elif path == "/memories" and AGENT_BASE:
            self._json(_post(f"{AGENT_BASE}/agent/memories", body))
        elif path == "/styles" and AGENT_BASE:
            self._json(_post(f"{AGENT_BASE}/agent/styles", body))
        elif path == "/export" and CONFIG_BASE:
            settings = _get(f"{CONFIG_BASE}/config/settings")
            self._json({"format":"evgconfig","version":1,"settings":settings})
        elif path == "/import" and CONFIG_BASE:
            for key, value in body.get("settings", {}).items():
                _post(f"{CONFIG_BASE}/config/settings/{key}", {"value": str(value)})
            self._json({"imported": True})
        else:
            self._json({"endpoint":path,"available":False}, 404)

    def do_DELETE(self):
        path = self.path.split("?")[0]
        self._json({"deleted": True})

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd(), help="Flutter project root directory")
    args = parser.parse_args()
    # __main__ 块在模块作用域内，直接赋值模块级变量即可（无需 global）
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    CONFIG_PORT = _read_port(".config_port")
    THEME_PORT = _read_port(".theme_port")
    AGENT_PORT = _read_port(".agent_port")
    CONFIG_BASE = f"http://127.0.0.1:{CONFIG_PORT}" if CONFIG_PORT else None
    THEME_BASE = f"http://127.0.0.1:{THEME_PORT}" if THEME_PORT else None
    AGENT_BASE = f"http://127.0.0.1:{AGENT_PORT}" if AGENT_PORT else None

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[settings] http://127.0.0.1:{port}\n")
    if CONFIG_BASE: sys.stderr.write(f"[settings] config → {CONFIG_BASE}\n")
    if THEME_BASE: sys.stderr.write(f"[settings] theme → {THEME_BASE}\n")
    if AGENT_BASE: sys.stderr.write(f"[settings] agent → {AGENT_BASE}\n")
    server.serve_forever()
