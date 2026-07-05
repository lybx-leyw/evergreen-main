"""URL Encode/Decode Tool."""
import argparse
from urllib.parse import quote, unquote, quote_plus, unquote_plus


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-o", "--operation", type=str, required=True, choices=["encode", "decode"])
    parser.add_argument("-c", "--component", type=str, default="false")
    args = parser.parse_args()

    component = args.component.lower() in ("true", "1", "yes")

    try:
        if args.operation == "encode":
            if component:
                result = quote(args.text, safe="")
            else:
                result = quote_plus(args.text)
        else:  # decode
            if component:
                result = unquote(args.text)
            else:
                result = unquote_plus(args.text)
        print(result)
    except Exception as e:
        print(f"错误: {e}")


if __name__ == "__main__":
    main()
