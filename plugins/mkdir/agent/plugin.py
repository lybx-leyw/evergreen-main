"""Mkdir Tool — 创建目录 (write-allowed 示例)."""
import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--path", type=str, required=True)
    parser.add_argument("-r", "--parents", type=str, default="true")
    args = parser.parse_args()

    path = args.path
    parents = args.parents.lower() in ("true", "1", "yes")

    try:
        if os.path.exists(path):
            if os.path.isdir(path):
                print(f"目录已存在: {path}")
            else:
                print(f"错误: {path} 已存在且不是目录")
                sys.exit(1)
        else:
            if parents:
                os.makedirs(path, exist_ok=True)
                print(f"已创建目录(含父目录): {path}")
            else:
                os.mkdir(path)
                print(f"已创建目录: {path}")

        # Show what was created
        print(f"绝对路径: {os.path.abspath(path)}")
    except PermissionError:
        print(f"错误: 没有权限创建 {path}")
        sys.exit(1)
    except OSError as e:
        print(f"错误: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
