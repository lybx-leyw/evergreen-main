"""Base64 Tool — encode/decode with url-safe option."""
import argparse
import base64


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-o", "--operation", type=str, required=True, choices=["encode", "decode"])
    parser.add_argument("-u", "--urlsafe", type=str, default="false")
    args = parser.parse_args()

    urlsafe = args.urlsafe.lower() in ("true", "1", "yes")

    try:
        if args.operation == "encode":
            data = args.text.encode("utf-8")
            if urlsafe:
                result = base64.urlsafe_b64encode(data).decode("utf-8")
            else:
                result = base64.b64encode(data).decode("utf-8")
            print(result)
        else:  # decode
            if urlsafe:
                data = base64.urlsafe_b64decode(args.text + "===")
            else:
                # Add padding if needed
                text = args.text
                missing = len(text) % 4
                if missing:
                    text += "=" * (4 - missing)
                data = base64.b64decode(text)
            print(data.decode("utf-8"))
    except Exception as e:
        print(f"错误: {e}")


if __name__ == "__main__":
    main()
