"""架构示意图 HTML → PNG 截图脚本（Chrome headless CLI）。

需要系统安装 Chrome。无需额外 Python 依赖。
输出: plugins/showcase-v3/module/arch.png

用法:
    python convert_arch_to_png.py
"""

import subprocess
import sys
from pathlib import Path


def main():
    project_root = Path(__file__).resolve().parents[1]
    html_path = project_root / "架构示意图.html"
    output_path = project_root / "plugins" / "showcase-v3" / "module" / "arch.png"

    if not html_path.exists():
        print(f"[ERROR] 源文件不存在: {html_path}", file=sys.stderr)
        sys.exit(1)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # 尝试找 Chrome 或 Edge
    chrome_paths = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]

    chrome = None
    for p in chrome_paths:
        if Path(p).exists():
            chrome = p
            break

    if not chrome:
        print("[ERROR] 未找到 Chrome 或 Edge", file=sys.stderr)
        sys.exit(1)

    url = f"file:///{html_path.as_posix()}"
    result = subprocess.run([
        chrome,
        "--headless",
        "--disable-gpu",
        "--window-size=1080,700",
        "--force-device-scale-factor=2",
        f"--screenshot={output_path}",
        url,
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[ERROR] 截图失败: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    size_kb = output_path.stat().st_size / 1024
    print(f"[OK] 截图完成: {output_path} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
