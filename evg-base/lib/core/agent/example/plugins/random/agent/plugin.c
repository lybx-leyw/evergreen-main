/**
 * Random Plugin — C 语言 + args + flag 风格示例。
 *
 * 构建（MSVC）：  cl /Fe:random.exe plugin.c
 * 构建（GCC）：    gcc -o random.exe plugin.c
 * 构建（Clang）：  clang -o random.exe plugin.c
 *
 * 命令行：./random.exe --min 1 --max 100
 * stdout：42
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char *argv[]) {
    int min = 1;
    int max = 100;

    // 解析 --key value
    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], "--min") == 0) {
            min = atoi(argv[i + 1]);
        } else if (strcmp(argv[i], "--max") == 0) {
            max = atoi(argv[i + 1]);
        }
    }

    // 边界保护
    if (min > max) { int t = min; min = max; max = t; }

    srand((unsigned)time(NULL));
    int result = min + rand() % (max - min + 1);
    printf("%d\n", result);
    return 0;
}
