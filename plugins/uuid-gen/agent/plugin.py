"""UUID Generator — POSITIONAL args mode, demonstrates position-based argument passing."""
import sys
import uuid


def main():
    # positional args: sys.argv[1] = version, sys.argv[2] = count
    version = 4
    count = 1
    uppercase = False

    if len(sys.argv) > 1:
        try:
            version = int(sys.argv[1])
        except ValueError:
            pass
    if len(sys.argv) > 2:
        try:
            count = int(sys.argv[2])
        except ValueError:
            pass
    if len(sys.argv) > 3:
        uppercase = sys.argv[3].lower() in ("true", "1", "yes")

    count = max(1, min(count, 20))
    if version not in (1, 4):
        version = 4

    print(f"UUID v{version} ({count}个):")

    for i in range(count):
        if version == 1:
            val = str(uuid.uuid1())
        else:
            val = str(uuid.uuid4())

        if uppercase:
            val = val.upper()

        print(f"  [{i+1}] {val}")


if __name__ == "__main__":
    main()
