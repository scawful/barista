#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
with tempfile.TemporaryDirectory() as work:
    p = pathlib.Path(work)
    (p / 'scripts').mkdir()
    (p / 'plugins').mkdir()
    shutil.copy(pathlib.Path(sys.argv[1]) / 'scripts/shortcut_menu_action.sh', p / 'scripts')
    def script(path, content):
        path.write_text(content)
        path.chmod(0o755)
    script(p/'scripts/toggle_yabai_shortcuts.sh', '#!/bin/bash\nif [[ "$TEST_FAIL" == 1 ]]; then echo "Shortcuts: permission denied" >&2; exit 7; fi\necho "skhd stopped"\n')
    script(p/'plugins/control_center.sh', '#!/bin/bash\nprintf "%s" "$NAME" > "$TEST_REFRESH"\n')
    script(p/'sketchybar', '#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ["TEST_BAR"],"w").write(json.dumps(sys.argv[1:]))\n')
    env = dict(os.environ, BARISTA_CONFIG_DIR=work, BARISTA_SKETCHYBAR_BIN=str(p/'sketchybar'), TEST_REFRESH=str(p/'refresh'), TEST_BAR=str(p/'bar'))
    for fail in ('0','1'):
        (p/'refresh').write_text('')
        r=subprocess.run(['bash',str(p/'scripts/shortcut_menu_action.sh'),'custom_center'], env=dict(env,TEST_FAIL=fail), capture_output=True, text=True)
        args=json.loads((p/'bar').read_text())
        assert args[-3:]==['--set','custom_center','popup.drawing=on']
        if fail=='0':
            assert r.returncode==0 and (p/'refresh').read_text()=='custom_center'
            assert args[:4]==['--set','cc.feedback','drawing=off','label=']
            assert args[-6:-3]==['--set','cc.settings','popup.drawing=on']
        else:
            assert r.returncode==7 and 'permission denied' in r.stderr
            assert not (p/'refresh').read_text()
            assert args[:4]==['--set','cc.feedback','drawing=on','label=Shortcuts: permission denied']
            assert args[-6:-3]==['--set','cc.settings','popup.drawing=off']
print('test_shortcut_menu_action.sh: ok')
PY
