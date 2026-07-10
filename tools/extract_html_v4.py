"""Extract HTML render functions — v4: body starts AFTER opening brace."""
import re, os

SRC = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\html\html_components.dart'
BASE = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\components'

FUNC_MAP = {
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

RENAMES = {
    '_esc(': 'esc(', '_renderEmpty(': 'renderEmpty(', '_renderPlaceholder(': 'renderPlaceholder(',
    '_renderGeneric(': 'renderGeneric(', '_renderBarChart(': 'renderBarChart(',
    '_renderPieChart(': 'renderPieChart(', '_renderLineChart(': 'renderLineChart(',
    '_renderDataTableHTML(': 'renderDataTableHTML(', '_renderDataCards(': 'renderDataCards(',
    '_sampleCell(': 'sampleCell(', '_langExt(': 'langExt(',
    '_lineDiff(': 'lineDiff(', '_jsStr(': 'jsStr(',
    '_codeSamples': 'codeSamples',
}

with open(SRC, 'r', encoding='utf-8') as f:
    lines = f.readlines()

func_starts = []
for i, line in enumerate(lines):
    m = re.match(r'^String (_render\w+)\(Map<String, dynamic> comp\)', line)
    if m and m.group(1) in FUNC_MAP:
        func_starts.append((i, m.group(1)))

extracted = {}
for start_line, name in func_starts:
    # Find opening brace line - skip signature to get to body start
    open_line = start_line
    while open_line < len(lines) and '{' not in lines[open_line]:
        open_line += 1
    # Body starts from line AFTER the opening brace line
    body_start = open_line + 1
    
    body_lines = []
    depth = 1  # we've already passed the opening {
    for j in range(body_start, len(lines)):
        line = lines[j]
        depth += line.count('{') - line.count('}')
        if depth <= 0:
            break
        body_lines.append(line)
    
    body = ''.join(body_lines)
    
    for old, new in RENAMES.items():
        body = body.replace(old, new)
    
    domain = FUNC_MAP[name]
    new_name = name[1:]
    folder = os.path.join(BASE, domain)
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, f'{new_name}.dart')
    
    imp = '../../html/html_helpers.dart'
    code = f"/// HTML render: {new_name}\nimport 'dart:convert';\nimport '{imp}';\n\nString {new_name}(Map<String, dynamic> comp) {{\n{body}}}\n"
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(code)
    extracted[name] = new_name
    print(f'  {name} -> {domain}/{new_name}.dart ({len(body_lines)} lines)')

print(f'\nExtracted {len(extracted)} functions')
