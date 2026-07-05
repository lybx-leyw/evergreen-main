"""Password Generator — flag args, random generation."""
import argparse
import random
import string


def generate_password(length, use_upper, use_lower, use_digits, use_symbols):
    """Generate a single password with specified character sets."""
    charset = ""
    if use_lower:
        charset += string.ascii_lowercase
    if use_upper:
        charset += string.ascii_uppercase
    if use_digits:
        charset += string.digits
    if use_symbols:
        charset += "!@#$%^&*()-_=+[]{};:,.<>?"

    if not charset:
        charset = string.ascii_lowercase + string.digits

    # Ensure at least one char from each requested set
    password = []
    if use_lower:
        password.append(random.choice(string.ascii_lowercase))
    if use_upper:
        password.append(random.choice(string.ascii_uppercase))
    if use_digits:
        password.append(random.choice(string.digits))
    if use_symbols:
        password.append(random.choice("!@#$%^&*()-_=+[]{};:,.<>?"))

    # Fill remaining
    while len(password) < length:
        password.append(random.choice(charset))

    random.shuffle(password)
    return "".join(password)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--length", type=int, default=16)
    parser.add_argument("-u", "--uppercase", type=str, default="true")
    parser.add_argument("-w", "--lowercase", type=str, default="true")
    parser.add_argument("-d", "--digits", type=str, default="true")
    parser.add_argument("-s", "--symbols", type=str, default="true")
    parser.add_argument("-c", "--count", type=int, default=1)
    args = parser.parse_args()

    def to_bool(v):
        return str(v).lower() in ("true", "1", "yes", "on")

    length = max(4, min(args.length, 128))
    count = max(1, min(args.count, 20))

    passwords = [
        generate_password(
            length,
            to_bool(args.uppercase),
            to_bool(args.lowercase),
            to_bool(args.digits),
            to_bool(args.symbols),
        )
        for _ in range(count)
    ]

    print(f"密码 ({length}位, {count}个):")
    for p in passwords:
        print(f"  {p}")
    print(f"\n熵值: ~{len(set(''.join(passwords))) * length // 8} bits")


if __name__ == "__main__":
    main()
