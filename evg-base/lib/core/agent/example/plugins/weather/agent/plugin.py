"""Weather Plugin — args + flag 风格，自定义短 flag。"""
import argparse
import random


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--city", type=str, required=True)
    parser.add_argument("-d", "--days", type=int, default=1)
    args = parser.parse_args()

    conditions = ["晴", "多云", "小雨", "阴", "晴转多云"]
    print(f"{args.city}未来{args.days}天：")
    for i in range(args.days):
        h, l = random.randint(15, 35), random.randint(5, 20)
        print(f"  第{i+1}天：{random.choice(conditions)}，{l}°C ~ {h}°C")
    print("(模拟数据)")


if __name__ == "__main__":
    main()
