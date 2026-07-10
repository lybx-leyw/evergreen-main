import re, os

src = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\html\html_components.dart'
base = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\components'

func_map = {
    '_renderMarkdown': 'document', '_renderVideo': 'document', '_renderAudioPlayer': 'document',
    '_renderImageGallery': 'document', '_renderDocument': 'document', '_renderCodeEditor': 'document',
    '_renderNotepad': 'document', '_renderDiffViewer': 'document', '_renderPresentation': 'document',
    '_renderDataTable': 'data', '_renderChart': 'data', '_renderStatTile': 'data',
    '_renderCardList': 'data', '_renderKanban': 'data', '_renderTree': 'data',
    '_renderTimeline': 'data', '_renderMap': 'data', '_renderCalendar': 'data',
    '_renderDataDashboard': 'data', '_renderTimetable': 'data',
    '_renderChat': 'interaction', '_renderForm': 'interaction', '_renderSettings': 'interaction',
    '_renderPromptBuilder': 'interaction',
    '_renderSpreadsheet': 'creative', '_renderMindmap': 'creative', '_renderWhiteboard': 'creative',
    '_renderTerminal': 'creative',
    '_renderTypeCheck': 'learning', '_renderFlashcards': 'learning', '_renderQuiz': 'learning',
    '_renderCrossword': 'learning', '_renderPronunciation': 'learning',
    '_renderButton': 'controls', '_renderNavButton': 'controls', '_renderDivider': 'controls',
    '_renderLotteryWheel': 'controls', '_renderCustom': 'controls', '_renderWebView': 'controls',
}

with open(src, 'r', encoding='utf-8') as f:
    content = f.read()

funcs = list(re.finditer(r'String (_render\w+)\(Map<String, dynamic> comp\)\s*\{', content))
funcs.sort(key=lambda m: m.start())

extracted = {}
for m in funcs:
    name = m.group(1)
    start = m.start()
    depth = 1
    pos = m.end()
    while depth > 0 and pos < len(content):
        if content[pos] == '{': depth += 1
        elif content[pos] == '}': depth -= 1
        pos += 1
    end = pos
    body = content[start:end]
    domain = func_map.get(name)
    if domain:
        folder = os.path.join(base, domain)
        os.makedirs(folder, exist_ok=True)
        filepath = os.path.join(folder, f'{name}.dart')
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(f'/// HTML render function\n')
            f.write("import 'dart:convert';\n\n")
            f.write(body)
        extracted[name] = (start, end)
        print(f'  Extracted: {name} -> {domain}/{name}.dart')

print(f'Total extracted: {len(extracted)}')
