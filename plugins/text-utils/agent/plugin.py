"""Text Utils Tool — flag args mode, multiple operations."""
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-o", "--operation", type=str, required=True,
                        choices=["upper", "lower", "reverse", "count", "trim", "capitalize_words"])
    args = parser.parse_args()

    text = args.text
    op = args.operation

    if op == "upper":
        print(text.upper())
    elif op == "lower":
        print(text.lower())
    elif op == "reverse":
        print(text[::-1])
    elif op == "count":
        chars = len(text)
        chars_no_space = len(text.replace(" ", ""))
        words = len(text.split())
        lines = text.count("\n") + 1
        print(f"字符数: {chars}")
        print(f"字符数(不含空格): {chars_no_space}")
        print(f"单词数: {words}")
        print(f"行数: {lines}")
    elif op == "trim":
        print(text.strip())
    elif op == "capitalize_words":
        print(" ".join(w.capitalize() for w in text.split()))


if __name__ == "__main__":
    main()
