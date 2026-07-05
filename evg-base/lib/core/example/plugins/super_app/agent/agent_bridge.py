"""Agent Tool 桥梁——演示微服务网格中的工具如何发现并调用平台服务。

Agent 调用时 PluginBridge 通过 args 模式传入参数。
本脚本：
  1. 读取 .data_port / .core_port / .agent_port 发现平台服务
  2. HTTP GET 数据源 → 本地过滤排序 → stdout JSON
  3. 演示插件 .exe 不需要私有数据库——通过端口文件发现一切

端口文件发现优先级：.data_port（数据源）> 命令行 --data-port > 硬编码回退
"""
import json
import os
import sys
import urllib.request


# ═══════ 端口发现 ═══════

def _read_port_file(name):
    """读取平台端口文件。"""
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        return None


def discover_services():
    """发现平台微服务网格中的所有可用服务。"""
    services = {}
    for name, port_file, path in [
        ("data",   ".data_port",   "/data"),
        ("core",   ".core_port",   "/core/health"),
        ("agent",  ".agent_port",  "/agent/health"),
        ("config", ".config_port", "/config/health"),
        ("module", ".module_port", "/module/health"),
        ("theme",  ".theme_port",  "/theme/health"),
    ]:
        port = _read_port_file(port_file)
        if port:
            services[name] = f"http://127.0.0.1:{port}{path}"
    return services


# ═══════ 工具入口 ═══════

def parse_args(argv):
    """解析 --key value 格式的命令行参数。"""
    args = {}
    i = 1
    while i < len(argv):
        if argv[i].startswith("--"):
            key = argv[i][2:]
            # 下一个非 -- 参数是 value
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                args[key] = argv[i + 1]
                i += 2
            else:
                args[key] = "true"
                i += 1
        else:
            i += 1
    return args


if __name__ == "__main__":
    args = parse_args(sys.argv)
    query = args.get("query", "")
    sort = args.get("sort", "name")
    order = args.get("order", "asc")

    # 1. 发现平台服务
    services = discover_services()

    # 2. 发现数据源地址
    data_source = args.get("data-port")
    if not data_source:
        data_port = _read_port_file(".data_port")
        if data_port:
            data_source = f"http://127.0.0.1:{data_port}/data"
    if not data_source:
        # 最终回退：尝试已知的 super_app 数据源
        data_source = "http://127.0.0.1:0/data"

    # 3. 从数据源获取数据
    try:
        url = f"{data_source}?sort={sort}&order={order}"
        resp = urllib.request.urlopen(url, timeout=5)
        data = json.loads(resp.read())
    except Exception as e:
        print(json.dumps({
            "error": f"数据源不可用: {e}",
            "hint": "请先启动 super_app 数据源，确保 .data_port 存在",
            "discovered_services": list(services.keys()),
        }, ensure_ascii=False))
        sys.exit(1)

    # 4. 本地过滤
    if query:
        q = query.lower()
        data = [d for d in data if q in d.get("name", "").lower() or q in str(d.get("score", ""))]

    # 5. 返回结果
    result = {
        "results": data,
        "total": len(data),
        "discovered_services": list(services.keys()),
    }
    print(json.dumps(result, ensure_ascii=False))
