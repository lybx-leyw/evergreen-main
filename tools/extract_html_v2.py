"""Extract HTML render functions — v2: correct brace matching, proper name replacement."""
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

# Find all render function lines
func_starts = []
for i, line in enumerate(lines):
    m = re.match(r'^String (_render\w+)\(', line)
    if m and m.group(1) in FUNC_MAP:
        func_starts.append((i, m.group(1)))

# Extract each function body
extracted = {}
for idx, (start_line, name) in enumerate(func_starts):
    # Find the function body
    body_lines = []
    depth = 0
    found_open = False
    for j in range(start_line, len(lines)):
        line = lines[j]
        if not found_open:
            if '{' in line:
                found_open = True
                depth = line.count('{') - line.count('}')
        else:
            depth += line.count('{') - line.count('}')
        
        if found_open:
            body_lines.append(line)
            if depth <= 0:
                break
    
    body = ''.join(body_lines)
    
    # Apply name replacements within body ONLY
    for old, new in RENAMES.items():
        body = body.replace(old, new)
    
    domain = FUNC_MAP[name]
    new_name = name[1:]  # remove _
    folder = os.path.join(BASE, domain)
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, f'{new_name}.dart')
    
    imp = '../../html/html_helpers.dart'
    code = f"/// HTML render: {new_name}\nimport 'dart:convert';\nimport '{imp}';\n\nString {new_name}(Map<String, dynamic> comp) {body}\n"
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(code)
    extracted[name] = new_name
    print(f'  {name} -> {domain}/{new_name}.dart')

print(f'\nExtracted {len(extracted)} render functions')
