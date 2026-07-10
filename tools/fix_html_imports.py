import os

base = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\components'
count = 0
for root, dirs, files in os.walk(base):
    for f in files:
        if f.startswith('_render') and f.endswith('.dart'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8') as fh:
                content = fh.read()
            rel = os.path.relpath(root, base)
            depth = len(rel.split(os.sep)) if rel != '.' else 0
            prefix = '../' * (depth + 1)  # up to renderer/ then html/
            imp = f"{prefix}html/html_helpers.dart"
            # Fix: replace wrong import with correct one
            content = content.replace(
                "import '../../../html/html_helpers.dart';",
                f"import '{imp}';"
            )
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(content)
            count += 1
            print(f"  Fixed: {rel}/{f} -> {imp}")

print(f"Total fixed: {count}")
