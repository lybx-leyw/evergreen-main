"""Word Count Tool — text statistics with top-N frequency."""
import argparse
import re
from collections import Counter


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--text", type=str, required=True)
    parser.add_argument("-n", "--top_n", type=int, default=10)
    args = parser.parse_args()

    text = args.text
    chars = len(text)
    chars_no_space = len(text.replace(" ", "").replace("\n", "").replace("\t", ""))
    words = re.findall(r"[\w\u4e00-\u9fff]+", text.lower())
    word_count = len(words)
    sentences = len(re.findall(r"[.!?。！？]+", text)) or 1
    paragraphs = len([p for p in text.split("\n\n") if p.strip()]) or 1
    lines = text.count("\n") + 1

    # Reading time (200 wpm average)
    minutes = max(1, word_count // 200)
    reading_time = f"{minutes} 分钟" if minutes < 60 else f"{minutes // 60}小时{minutes % 60}分钟"

    print(f"═══════ 文本统计 ═══════")
    print(f"总字符数:     {chars}")
    print(f"字符数(无空格): {chars_no_space}")
    print(f"单词数:       {word_count}")
    print(f"句子数:       {sentences}")
    print(f"段落数:       {paragraphs}")
    print(f"行数:         {lines}")
    print(f"预估阅读时间:  {reading_time}")
    print()

    if word_count > 0:
        counter = Counter(words)
        top = counter.most_common(min(args.top_n, 50))
        print(f"词频 TOP-{len(top)}:")
        for w, c in top:
            bar = "█" * min(30, c * 30 // max(1, top[0][1]))
            print(f"  {w:20s} {c:4d}  {bar}")


if __name__ == "__main__":
    main()
