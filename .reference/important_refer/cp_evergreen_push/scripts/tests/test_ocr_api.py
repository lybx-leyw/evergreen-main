"""
诊断 DeepSeek-OCR (DashScope) API 连通性。

用法:
  python scripts/tests/test_ocr_api.py --key 你的DashScope密钥
  python scripts/tests/test_ocr_api.py                 # 从 DASHSCOPE_API_KEY 环境变量读取
"""

import argparse
import json
import os
import sys

# 1×1 白色 PNG (base64)
MINI_PNG = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlE"
    "QVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"


def main() -> int:
    parser = argparse.ArgumentParser(description="诊断 OCR API 连通性")
    parser.add_argument("--key", help="DashScope API Key")
    args = parser.parse_args()

    api_key = args.key or os.getenv("DASHSCOPE_API_KEY", "")
    if not api_key:
        print("❌ 未提供 API Key。用法：")
        print("   python scripts/tests/test_ocr_api.py --key sk-ws-...")
        print("   或 set DASHSCOPE_API_KEY=sk-ws-... (cmd)")
        print("   或 $env:DASHSCOPE_API_KEY='sk-ws-...' (PowerShell)")
        return 1

    try:
        import requests
    except ImportError:
        print(f"❌ 缺少 requests 库，请安装：")
        print(f"   {sys.executable} -m pip install requests")
        return 1

    print(f"🔍 测试 DashScope OCR API...")
    print(f"   Key: {api_key[:8]}...{api_key[-4:]}")
    print(f"   URL: {BASE_URL}/chat/completions")

    try:
        resp = requests.post(
            f"{BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "vanchin/deepseek-ocr",
                "max_tokens": 10,
                "messages": [{
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{MINI_PNG}",
                                "detail": "low",
                            },
                        },
                        {"type": "text", "text": "Say OK"},
                    ],
                }],
            },
            timeout=15,
        )

        if resp.status_code == 200:
            data = resp.json()
            content = (data.get("choices", [{}])[0]
                       .get("message", {}).get("content", ""))
            model = data.get("model", "vanchin/deepseek-ocr")
            print(f"\n✅ API 连接成功！")
            print(f"   模型: {model}")
            print(f"   回复: {content[:100]}")
            return 0

        elif resp.status_code == 401:
            print(f"\n❌ API Key 无效 (401)")
            print(f"   请检查 DashScope API Key 是否正确")
            print(f"   获取地址: https://dashscope.aliyuncs.com/")
            return 1

        elif resp.status_code == 403:
            print(f"\n❌ 无权限 (403)")
            print(f"   请检查 API Key 是否有 OCR 模型权限")
            return 1

        else:
            body = resp.text[:500]
            print(f"\n❌ HTTP {resp.status_code}")
            print(f"   {body}")
            return 1

    except requests.ConnectionError:
        print(f"\n❌ 网络连接失败")
        print(f"   无法连接到 dashscope.aliyuncs.com，请检查网络/代理")
        return 1
    except requests.Timeout:
        print(f"\n❌ 连接超时")
        print(f"   15 秒内无响应，请检查网络或稍后重试")
        return 1
    except Exception as e:
        print(f"\n❌ 未知错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
