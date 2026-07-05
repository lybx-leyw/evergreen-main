"""QR Text Tool — ASCII QR code in terminal (stdlib only, simple QR encoding)."""
import argparse


def binary_to_qr(bits, size):
    """Convert bit matrix to ASCII art."""
    # Simple QR-like pattern using unicode blocks
    lines = []
    for y in range(size):
        row = ""
        for x in range(size):
            idx = y * size + x
            if idx < len(bits) and bits[idx]:
                row += "██"
            else:
                row += "  "
        lines.append(row)
    return "\n".join(lines)


def generate_pattern(text, version=1):
    """Generate a simplified QR-like pattern.
    This is a minimal ASCII QR code generator using pattern-based encoding.
    For real QR, use qrcode library. This is for demo/agent-tool purposes.
    """
    size = 21 + (version - 1) * 4  # QR module size

    # Create matrix
    matrix = [[False] * size for _ in range(size)]

    # Position markers (top-left, top-right, bottom-left)
    for mx, my in [(0, 0), (0, size - 7), (size - 7, 0)]:
        for i in range(7):
            for j in range(7):
                if i in (0, 6) or j in (0, 6) or (2 <= i <= 4 and 2 <= j <= 4):
                    if 0 <= mx + j < size and 0 <= my + i < size:
                        matrix[my + i][mx + j] = True

    # Timing patterns
    for i in range(8, size - 8):
        matrix[6][i] = (i % 2 == 0)
        matrix[i][6] = (i % 2 == 0)

    # Encode data region with a simple hash pattern
    data_chars = [ord(c) for c in text]
    idx = 0
    for y in range(0, size):
        for x in range(0, size):
            if matrix[y][x]:
                continue
            if idx < len(data_chars) * 8:
                byte = data_chars[idx // 8]
                bit = (byte >> (7 - (idx % 8))) & 1
                if bit:
                    matrix[y][x] = True
                idx += 1

    return matrix, size


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-s", "--size", type=int, default=1)
    args = parser.parse_args()

    text = args.text[:100]  # Limit for ASCII display
    version = max(1, min(10, args.size))

    matrix, size = generate_pattern(text, version)

    # Add quiet zone
    print()
    print("  " + "▄" * (size * 2 + 4))
    for row in matrix:
        s = "  █ "
        for cell in row:
            s += "██" if cell else "  "
        s += " █"
        print(s)
    print("  " + "▀" * (size * 2 + 4))
    print()
    print(f"  文本: {text}")
    print(f"  长度: {len(text)} 字符, 版本: {version}")


if __name__ == "__main__":
    main()
