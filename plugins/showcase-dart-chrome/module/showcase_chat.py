"""showcase_chat.exe — 栏位级后端，AI 对话代理（模拟 SSE 流式响应）。"""
import argparse
import json
import os
import sys
import time
import random
from http.server import HTTPServer, BaseHTTPRequestHandler

_PROJECT_ROOT = ""

CHAT_RESPONSES = {
    "default": "🎭 你好！我是展示 AI 助手。我可以演示：\n\n1. **流式响应** (SSE) — 逐字输出\n2. **思考过程** — 透明展示推理\n3. **工具调用** — 调用 Agent 工具\n4. **附件上传** — 图片/PDF/文本\n5. **语音输入** — 语音转文字\n6. **斜杠命令** — /help /clear /export\n\n试试问我任何问题吧！",
    "功能列表": "📋 **我能做什么？**\n\n| 功能 | 状态 | 说明 |\n|------|------|------|\n| 流式输出 | ✅ | SSE 逐字推送 |\n| 思考展示 | ✅ | 透明推理链 |\n| 工具调用 | ✅ | 3 种 argMode |\n| 附件处理 | ✅ | 图片/PDF/文本 |\n| 语音输入 | ✅ | 语音→文字 |\n| 快捷回复 | ✅ | 一键发送 |\n| 斜杠命令 | ✅ | /help 等 |\n\n这就是 Evergreen 插件系统的能力展示！",
}

JOKES = [
    "为什么程序员总是分不清万圣节和圣诞节？因为 Oct 31 == Dec 25！🎃",
    "一个 SQL 查询走进酒吧，看到两张表，他走过去问：'我可以 JOIN 你们吗？' 🍻",
    "程序员最讨厌的两件事：1. 写文档 2. 别人不写文档 📝",
    "Debug 就像侦探小说，你是侦探，bug 是凶手，而你就是凶手 🔍",
    "世界上有 10 种人：懂二进制的和不懂的 🤓",
    "如果代码能跑，就别碰它 —— 薛定谔的程序员 🐱",
    "最好的代码是没有代码，其次是注释比代码多的代码 📖",
]


class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _sse(self, data):
        self.wfile.write(f"data: {json.dumps(data, ensure_ascii=False)}\n\n".encode("utf-8"))
        self.wfile.flush()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[showcase_chat] {fmt % args}\n")

    def do_GET(self):
        if self.path == "/health":
            return self._json({"status": "ok", "module": "showcase_chat"})
        return self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        cl = self.headers.get("Content-Length")
        raw = self.rfile.read(int(cl)) if cl else b""
        body = json.loads(raw) if raw and raw.strip() else {}

        if path == "/chat":
            return self._handle_chat(body)

        return self._json({"error": "not found"}, 404)

    def _handle_chat(self, body):
        user_msg = body.get("message", "").strip()
        stream = body.get("stream", True)

        # 检查是否匹配预设响应
        response_text = CHAT_RESPONSES.get("default", CHAT_RESPONSES["default"])
        for key in CHAT_RESPONSES:
            if key in user_msg:
                response_text = CHAT_RESPONSES[key]
                break

        # 如果问笑话
        if "笑话" in user_msg or "joke" in user_msg.lower():
            response_text = random.choice(JOKES)

        # 如果不流式，直接返回
        if not stream:
            return self._json({
                "message": response_text,
                "role": "assistant",
                "thinking": "用户问了一个问题，我直接给出了回答。",
            })

        # SSE 流式响应
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        # 发送 thinking
        thinking_text = "🤔 让我想想...\n分析用户意图 → 匹配知识库 → 生成回答"
        for char in thinking_text:
            self._sse({"type": "thinking", "content": char})
            time.sleep(0.02)

        self._sse({"type": "thinking_done"})
        time.sleep(0.1)

        # 模拟工具调用
        self._sse({
            "type": "tool_call",
            "tool": "showcase_stdin",
            "args": {"role": "frontend", "name": "展示助手"},
        })
        time.sleep(0.3)
        self._sse({
            "type": "tool_result",
            "tool": "showcase_stdin",
            "result": "角色卡片已生成",
        })
        time.sleep(0.1)

        # 流式输出正文
        for char in response_text:
            self._sse({"type": "text", "content": char})
            time.sleep(0.015)

        self._sse({"type": "done"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd())
    args = parser.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[showcase_chat] http://127.0.0.1:{port}\n")
    server.serve_forever()
