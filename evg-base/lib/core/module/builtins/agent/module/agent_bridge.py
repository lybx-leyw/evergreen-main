"""Agent Bridge — 薄代理，将渲染器请求转发到 core/agent HTTP Server。

不包含 LLM 逻辑，只做 HTTP 代理 + SSE 透传。
Agent 端口从 .agent_port 文件读取。
若 Agent 不可达（未配置 API Key 等），返回 setup_required 引导用户填写设置。

构建: pyinstaller --onefile agent_bridge.py --distpath . --name agent_bridge
"""
import json
import sys
import time
from http.client import HTTPConnection, HTTPException
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ═══════════════════════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════════════════════

AGENT_PORT_FILE = ".agent_port"
MAX_RETRIES = 5          # 启动时快速失败，不阻塞 ModuleLoader
RETRY_SEC = 0.5
HEALTH_RETRY_SEC = 2.0   # /health 探测时的重试间隔


def find_agent_port():
    """从 .agent_port 文件读取 Agent HTTP 端口。快速失败。"""
    for _ in range(MAX_RETRIES):
        try:
            with open(AGENT_PORT_FILE, "r") as f:
                port = int(f.read().strip())
                return port
        except (FileNotFoundError, ValueError):
            time.sleep(RETRY_SEC)
    return None


def try_connect_agent(port):
    """探测 Agent 是否可达。返回 (ok, agent_health_json)。"""
    try:
        conn = HTTPConnection("127.0.0.1", port, timeout=3)
        conn.request("GET", "/health")
        resp = conn.getresponse()
        if resp.status == 200:
            return True, json.loads(resp.read())
        conn.close()
    except Exception:
        pass
    return False, None


# ═══════════════════════════════════════════════════════════════════════════════
# HTTP 代理处理器
# ═══════════════════════════════════════════════════════════════════════════════

class ProxyHandler(BaseHTTPRequestHandler):
    """转发请求到 core/agent HTTP Server。Agent 不可达时返回 setup_required。"""

    ROUTES = {
        ("GET", "/health"):             "/health",
        ("GET", "/sessions"):           "/agent/sessions",
        ("POST", "/sessions"):          "/agent/sessions",
        ("POST", "/sessions/switch"):   "/agent/sessions/switch",
        ("GET", "/tools"):              "/agent/tools",
        ("POST", "/tools/toggle"):      "/agent/tools/toggle",
        ("POST", "/cancel"):            "/agent/cancel",
        ("POST", "/approve"):           "/agent/approve",
        ("POST", "/reject"):            "/agent/reject",
        ("GET", "/output_styles"):      "/agent/styles",
        ("POST", "/output_styles/set"): "/agent/styles",
        ("GET", "/config"):             "/agent/config",
        ("POST", "/chat"):              "/agent/chat",
    }

    def log_message(self, *args):
        sys.stderr.write(f"[bridge] {args[0]}\n")

    @property
    def _agent_port(self):
        return self.server.agent_port

    @property
    def _agent_ok(self):
        return self.server.agent_ok

    # ── 设置引导 ──

    def _setup_required_response(self):
        """返回引导用户填写设置的 JSON。"""
        return {
            "status": "setup_required",
            "message": "请先配置 API 密钥和相关设置",
            "setup_keys": ["DEEPSEEK_API_KEY", "DEEPSEEK_MODEL"],
            "config_module_id": "agent_from",
        }

    @staticmethod
    def _write_json(handler, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        handler.send_response(code)
        handler.send_header("Content-Type", "application/json; charset=utf-8")
        handler.send_header("Access-Control-Allow-Origin", "*")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)

    # ── 通用转发 ──

    def _proxy(self, agent_path):
        if not self._agent_ok:
            return self._write_json(self, 503, self._setup_required_response())

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        try:
            conn = HTTPConnection("127.0.0.1", self._agent_port, timeout=30)
            conn.request(self.command, agent_path, body=body,
                        headers={"Content-Type": "application/json; charset=utf-8"})
            resp = conn.getresponse()
            resp_body = resp.read()

            self.send_response(resp.status)
            self.send_header("Content-Type", resp.getheader("Content-Type", "application/json"))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            if resp_body:
                self.wfile.write(resp_body)
            conn.close()
        except (HTTPException, OSError) as e:
            self._write_json(self, 503, {
                **self._setup_required_response(),
                "detail": str(e),
            })

    # ── SSE 流式透传 ──

    def _proxy_stream(self, agent_path):
        if not self._agent_ok:
            err = json.dumps({"type": "error", **self._setup_required_response()}, ensure_ascii=False)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(f"data: {err}\n\n".encode())
            self.wfile.flush()
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        try:
            conn = HTTPConnection("127.0.0.1", self._agent_port, timeout=300)
            conn.request("POST", agent_path, body=body,
                        headers={"Content-Type": "application/json; charset=utf-8"})
            resp = conn.getresponse()
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break
            conn.close()
        except (HTTPException, OSError) as e:
            err = json.dumps({"type": "error", **self._setup_required_response(), "detail": str(e)}, ensure_ascii=False)
            try:
                self.wfile.write(f"data: {err}\n\n".encode())
                self.wfile.flush()
            except Exception:
                pass

    # ── health（增强版——含 setup 检测）──

    def _health(self):
        """返回 bridge 自身状态 + Agent 健康信息。"""
        if self._agent_ok:
            ok, agent_health = try_connect_agent(self._agent_port)
            if ok and agent_health:
                return self._write_json(self, 200, {
                    "status": agent_health.get("status", "ok"),
                    "agent": agent_health,
                })

        # Agent 不可达 → 试试重新发现端口
        port = find_agent_port()
        if port:
            self.server.agent_port = port
            ok, agent_health = try_connect_agent(port)
            if ok:
                self.server.agent_ok = True
                return self._write_json(self, 200, {
                    "status": agent_health.get("status", "ok") if agent_health else "ok",
                    "agent": agent_health,
                })

        self.server.agent_ok = False
        return self._write_json(self, 200, self._setup_required_response())

    # ── 路由分发 ──

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/health":
            return self._health()

        if path.startswith("/sessions/") and len(path) > len("/sessions/"):
            return self._proxy(f"/agent/sessions/{path.split('/')[-1]}")

        agent_path = self.ROUTES.get(("GET", path))
        if agent_path:
            return self._proxy(agent_path)

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/chat/stream":
            return self._proxy_stream("/agent/chat/stream")

        agent_path = self.ROUTES.get(("POST", path))
        if agent_path:
            return self._proxy(agent_path)

        self.send_response(404)
        self.end_headers()

    def do_DELETE(self):
        path = urlparse(self.path).path
        if path.startswith("/sessions/") and len(path) > len("/sessions/"):
            return self._proxy(f"/agent/sessions/{path.split('/')[-1]}")
        self.send_response(404)
        self.end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


# ═══════════════════════════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    agent_port = find_agent_port()
    agent_ok = False

    if agent_port is not None:
        ok, health = try_connect_agent(agent_port)
        agent_ok = ok
        if ok:
            sys.stderr.write(f"[bridge] agent → 127.0.0.1:{agent_port} (已连接)\n")
        else:
            sys.stderr.write(f"[bridge] agent → 127.0.0.1:{agent_port} (不可达，等待设置...)\n")
    else:
        sys.stderr.write("[bridge] agent 未启动，等待 API Key 配置...\n")
        agent_port = 0  # 占位

    server = HTTPServer(("127.0.0.1", 0), ProxyHandler)
    server.agent_port = agent_port
    server.agent_ok = agent_ok

    # 必须！平台靠这行知道端口（bridge 即使 agent 未就绪也会启动）
    print(f"PORT:{server.server_port}", flush=True)
    sys.stderr.write(f"[bridge] http://127.0.0.1:{server.server_port}\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
