"""安卓长驻 HTTP 数据源示例（方案 A 验收用）。

放置到设备（adb push 到 app 私有目录，如
/data/data/com.example.evergreen_base/files/python_long_server_test.py），
由 DataSourceLoader 经 ChaquopyRunner.startLong 在 app 进程内后台线程执行。

协议（与桌面 .exe 数据源一致）：
  - 启动后打印 "PORT:<port>"（flush=True），供 DataSourceLoader 探测端口。
  - 暴露 GET /health 返回 200（健康检查）。
  - 其余路径返回 JSON，供 DataSourceLoader 注册的数据类型拉取。

仅用于端到端验收，非生产插件。
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class _Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8") if isinstance(payload, (dict, list)) else str(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
            return
        self._send(200, {"echo": self.path, "source": "chaquopy-long-server"})

    def log_message(self, *args):  # 静默默认日志，避免干扰 PORT: 行
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()

    server = HTTPServer(("127.0.0.1", args.port), _Handler)
    port = server.server_address[1]
    # 关键：按桌面协议打印 PORT: 行，DataSourceLoader 据此探测。
    print(f"PORT:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
