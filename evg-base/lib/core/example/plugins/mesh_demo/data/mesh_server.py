"""Mesh Demo 数据源——演示插件如何发现并调用平台微服务网格。

启动后：
  1. 绑定 localhost:0 → stdout PORT:<N>
  2. 扫描全部 6 个 .xxx_port 文件
  3. 对每个已发现的服务调用 /health
  4. 暴露 /mesh/status 端点 → 返回整个网格的健康状态

核心理念：插件不捆绑能力，通过端口文件发现平台服务即可。
"""
import json
import os
import sys
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

# ═══════ 端口文件发现 ═══════

SERVICE_MAP = {
    "core":   (".core_port",   "/core/health"),
    "data":   (".data_port",   "/data/health"),
    "agent":  (".agent_port",  "/agent/health"),
    "config": (".config_port", "/config/health"),
    "module": (".module_port", "/module/health"),
    "theme":  (".theme_port",  "/theme/health"),
}


def _read_port_file(name):
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def discover_all_services():
    """扫描全部 6 个端口文件，发现平台微服务网格。"""
    services = {}
    for name, (port_file, health_path) in SERVICE_MAP.items():
        port = _read_port_file(port_file)
        if port:
            services[name] = {
                "port": int(port),
                "health_url": f"http://127.0.0.1:{port}{health_path}",
            }
    return services


def check_service_health(health_url):
    """调用 /health 端点检查服务状态。"""
    try:
        resp = urllib.request.urlopen(health_url, timeout=2)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e), "reachable": False}


# ═══════ HTTP Handler ═══════

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        sys.stderr.write(f"[mesh_demo] {args[0]}\n")

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/health":
            services = discover_all_services()
            self._json({
                "status": "ok",
                "plugin": "mesh_demo",
                "discovered_services": list(services.keys()),
            })

        elif path == "/mesh/status":
            services = discover_all_services()
            result = {
                "plugin": "mesh_demo",
                "total_services": len(SERVICE_MAP),
                "discovered": len(services),
                "services": {},
            }
            for name, info in services.items():
                health = check_service_health(info["health_url"])
                result["services"][name] = {
                    "port": info["port"],
                    "healthy": "error" not in health,
                    "health": health,
                }
            self._json(result)

        else:
            self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    # 端口发现
    services = discover_all_services()
    sys.stderr.write(f"[mesh_demo] 发现 {len(services)}/{len(SERVICE_MAP)} 个平台服务\n")
    for name, info in services.items():
        sys.stderr.write(f"[mesh_demo]   {name} → {info['health_url']}\n")

    # 绑定 0 → 平台自动分配
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[mesh_demo] http://127.0.0.1:{port}\n")
    server.serve_forever()
