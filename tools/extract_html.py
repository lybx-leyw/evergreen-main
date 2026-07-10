"""Extract HTML render functions from html_components.dart to component folders."""
import re, os

SRC = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\html\html_components.dart'
BASE = r'c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\evg-base\lib\renderer\components'

# Helper functions that need to be shared (become public)
HELPERS = {
    '_esc', '_renderEmpty', '_renderPlaceholder', '_renderGeneric',
    '_renderDataTableHTML', '_renderDataCards', '_renderBarChart',
    '_renderPieChart', '_renderLineChart', '_sampleCell', '_langExt',
    '_lineDiff', '_jsStr',
}

# Constants/vars that need to be shared
SHARED_VARS = {'_codeSamples'}

# Render function -> component domain
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

with open(SRC, 'r', encoding='utf-8') as f:
    content = f.read()

# --- Step 1: Find all function and variable boundaries ---
def find_blocks(code, patterns):
    """Find function/var blocks by pattern, return (name, start, end)."""
    results = []
    for pat in patterns:
        for m in re.finditer(pat, code, re.MULTILINE):
            name = m.group(1)
            start = m.start()
            # Find matching brace for functions
            if '{' in m.group():
                depth = 1
                pos = m.end()
                while depth > 0 and pos < len(code):
                    if code[pos] == '{': depth += 1
                    elif code[pos] == '}': depth -= 1
                    pos += 1
                end = pos
            else:
                # Variable - find semicolon
                pos = code.find(';', m.end())
                end = pos + 1 if pos > 0 else m.end()
            results.append((name, start, end))
    return results

# Find all function blocks
func_blocks = find_blocks(content, [
    r'^String (_render\w+)\(Map<String, dynamic> comp\)\s*\{',
    r'^String (_render\w+)\(Map<String, dynamic> comp,\s*Map<String, dynamic> config\)\s*\{',
    r'^String (_render\w+)\(\w+\s+\w+(?:,\s*\w+\s+\w+)*\)\s*\{',
    r'^String (_\w+)\(',  # helpers like _esc, _sampleCell, _langExt
])

# Find variable blocks (like _codeSamples)
var_blocks = find_blocks(content, [
    r'^(final Map<String, String> _codeSamples\s*=\s*\{)',
    r'^(final Map<String, IconData> _\w+\s*=\s*\{)',
])

# --- Step 2: Identify render functions vs helpers ---
render_funcs = []
helper_funcs = []
helper_vars = []

for name, start, end in func_blocks:
    if name in HELPERS or not name.startswith('_render'):
        helper_funcs.append((name, start, end))
    else:
        render_funcs.append((name, start, end))

for name, start, end in var_blocks:
    if name in SHARED_VARS:
        helper_vars.append((name, start, end))

# Sort by position
all_helpers = sorted(helper_funcs + helper_vars, key=lambda x: x[1])

# --- Step 3: Create html_helpers.dart ---
helper_code = """/// Shared HTML rendering helpers.
library;

import 'dart:convert';
import 'dart:math' as math;

"""

# Collect helper bodies (dedicated)
for name, start, end in all_helpers:
    body = content[start:end]
    # Remove _ prefix from names within the body
    for old_name in HELPERS | SHARED_VARS:
        body = body.replace(old_name + '(', old_name[1:] + '(')
        body = body.replace(old_name + ' ', old_name[1:] + ' ')
    helper_code += body + '\n\n'

helper_path = SRC.replace('html_components.dart', 'html_helpers.dart')
with open(helper_path, 'w', encoding='utf-8') as f:
    f.write(helper_code)
print(f'Created html_helpers.dart with {len(all_helpers)} utilities')

# --- Step 4: Extract render functions to component folders ---
# Build name mapping for public helpers
pub_names = {}
for name in HELPERS:
    pub_names[name] = name[1:]  # remove _
for name in SHARED_VARS:
    pub_names[name] = name[1:]

# Need to compute relative path for each domain
for name, start, end in render_funcs:
    domain = FUNC_MAP.get(name)
    if not domain:
        continue
    body = content[start:end]
    # Replace private helper calls with public names
    for old, new in pub_names.items():
        body = re.sub(r'\b' + re.escape(old) + r'\b', new, body)
    
    folder = os.path.join(BASE, domain)
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, f'{name[1:]}.dart')  # remove leading _
    
    # Relative path from components/<domain>/ to html/
    imp = '../../../html/html_helpers.dart'
    if domain in ('document', 'data', 'interaction', 'creative', 'learning', 'controls'):
        imp = '../../html/html_helpers.dart'
    
    file_code = f"/// HTML render: {name}\nimport 'dart:convert';\nimport '{imp}';\n\n{body}\n"
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(file_code)
    print(f'  Extracted: {name} -> {domain}/{name[1:]}.dart')

print(f'Total render functions extracted: {len(render_funcs)}')
