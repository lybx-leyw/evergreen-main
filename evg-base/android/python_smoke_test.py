# P1b 安卓 Chaquopy 冒烟测试脚本。
# 用法：adb push 到模拟器后，由 Dart 侧 `ChaquopyRunner.runOnce('<设备绝对路径>', [...])` 调用。
# 该脚本模拟一个一次性数据源插件：
#   - 从 sys.stdin 读取 JSON（对应桌面 stdio 协议，原生桥已注入）
#   - 把 argv 与 stdin 回显，打印 JSON 到 stdout（原生桥捕获后回传 Dart）
#   - 正常退出（exitCode 0）
import sys
import json


def main() -> None:
    raw = ""
    try:
        raw = sys.stdin.read()
    except Exception as exc:  # pragma: no cover
        sys.stderr.write("read stdin failed: %s" % exc)

    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {"raw": raw}

    out = {
        "ok": True,
        "argv": sys.argv[1:],
        "received": payload,
        "python_version": sys.version.split()[0],
    }
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
