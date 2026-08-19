#!/usr/bin/env bash
# Regenerate MIGRATION_MATRIX.csv from .reasonix-ref/internal.
# Run from repository root:
#   ./evg-base/lib/core/agent/docs/migration/GENERATE_MATRIX.sh
set -euo pipefail
cd "$(dirname "$0")/../../../../../.."
python3 - <<'PY'
import os, csv
root = '.reasonix-ref/internal'
phase_map = {
    'ablation':'P1','nilutil':'P1','textutil':'P1','fileutil':'P1','frontmatter':'P1','diff':'P1','fileref':'P1','filelock':'P1','store':'P1','event':'P1','eventwire':'P1','trajectory':'P1','stats':'P1','outputstyle':'P1','testenv':'P1',
    'provider':'P2','tool':'P2','shellsafe':'P2','shellparse':'P2','shellrun':'P2','sandbox':'P2','proc':'P2','secrets':'P2','netclient':'P2','sysproxy':'P2','boundedllm':'P2','permission':'P2','hook':'P2',
    'instruction':'P3','memory':'P3','skill':'P3','command':'P3','sessioninbox':'P3','sessiontemp':'P3','agentpreset':'P3',
    'plancontract':'P4','planmode':'P4','taskcontract':'P4','goaleval':'P4','evidence':'P4','checkpoint':'P4','runtimepolicy':'P4','completion':'P4','jobs':'P4','workspacelease':'P4','guardian':'P4',
    'agent':'P5',
    'capability':'P9','extension':'P9','extensioncontract':'P9','plugin':'P9','pluginpkg':'P9','mcplaunch':'P9','mcpdiag':'P9',
    'control':'P10','config':'P10','recovery':'P10','retrieval':'P10','autoresearch':'P10','billing':'P10','migration':'P10','taskmonitor':'P10','i18n':'P10','productdocs':'P10',
    'acp':'P11','appidentity':'P11','boot':'P11','bot':'P11','botruntime':'P11','capdiag':'P11','cli':'P11','crashreport':'P11','desktoplauncher':'P11','doctor':'P11','environment':'P11','gitcmd':'P11','history':'P11','historycatalog':'P11','installlayout':'P11','installsource':'P11','lsp':'P11','mcpregistry':'P11','notify':'P11','projectiondb':'P11','releaseasset':'P11','remote':'P11','repair':'P11','serve':'P11','sessioncatalog':'P11','taskcatalog':'P11','telemetry':'P11','usagecatalog':'P11','worktree':'P11',
}
pkgs = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
rows = []
for top in pkgs:
    for dirpath, _, files in os.walk(os.path.join(root, top)):
        for fn in sorted(files):
            if not fn.endswith('.go'):
                continue
            src = os.path.relpath(os.path.join(dirpath, fn), root).replace(os.sep, '/')
            rel = src[:-3]
            if fn.endswith('_test.go'):
                kind = 'test'
                target = 'lib/core/agent/test/ref/' + rel[:-5] + '_test.dart'
            else:
                kind = 'impl'
                target = 'lib/core/agent/ref/' + rel + '.dart'
            notes = 'platform-adapter' if any(x in fn for x in ('_windows','_unix','_darwin','_linux','_other')) else ''
            rows.append([top, src, kind, target, phase_map.get(top, 'P11'), 'pending', notes])
out = 'evg-base/lib/core/agent/docs/migration/MIGRATION_MATRIX.csv'
with open(out, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['package','source_go','kind','target_dart','phase','status','notes'])
    w.writerows(rows)
print(f'wrote {len(rows)} rows -> {out}')
PY
