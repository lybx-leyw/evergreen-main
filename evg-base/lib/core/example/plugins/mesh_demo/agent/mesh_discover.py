"""Mesh Discover 工具——完整演示插件 .exe 的端口文件发现流程。

Agent 调用时通过 PluginBridge args 模式传入参数。
本脚本：
  1. 扫描全部 6 个 .xxx_port 文件
  2. 对已发现服务调用 /health
  3. stdout 输出 JSON——完整网格状态报告

证明：插件 .exe 不需要任何硬编码配置，
     通过读取端口文件即可发现并调用平台全部能力。
"""
import json
import os
import sys
import urllib.request


# ═══════ 端口发现 + 健康检查 ═══════

SERVICE_MAP = {
    "core":   (".core_port",   "/core/health"),
    "data":   (".data_port",   "/data/health"),
    "agent":  (".agent_port",  "/agent/health"),
    "config": (".config_port", "/config/health"),
    "module": (".module_port", "/module/health"),
    "theme":  (".theme_port",  "/theme/health"),
}


def _read_port(name):
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        return None


def discover_and_check(service_filter=None):
    """发现并健康检查平台微服务。"""
    result = {
        "platform": "Evergreen",
        "total_services": len(SERVICE_MAP),
        "discovered": 0,
        "healthy": 0,
        "services": {},
    }

    for name, (port_file, health_path) in SERVICE_MAP.items():
        if service_filter and name != service_filter:
            continue

        port = _read_port(port_file)
        if not port:
            result["services"][name] = {"status": "undiscovered", "port_file": port_file}
            continue

        result["discovered"] += 1
        health_url = f"http://127.0.0.1:{port}{health_path}"

        try:
            resp = urllib.request.urlopen(health_url, timeout=2)
            health = json.loads(resp.read())
            result["services"][name] = {
                "status": "healthy",
                "port": int(port),
                "health": health,
            }
            result["healthy"] += 1
        except Exception as e:
            result["services"][name] = {
                "status": "unreachable",
                "port": int(port),
                "error": str(e),
            }

    return result


# ═══════ CLI 入口 ═══════

if __name__ == "__main__":
    # 解析 --service <name> 参数
    service = None
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        if arg == "--service" and i + 1 < len(argv):
            service = argv[i + 1]

    result = discover_and_check(service)
    print(json.dumps(result, ensure_ascii=False, indent=2))
