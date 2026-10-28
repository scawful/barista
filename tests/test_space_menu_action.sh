#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='barista-space-action-') as directory:
    work = Path(directory)
    config = work / 'config with spaces'
    plugins = config / 'plugins'
    scripts = config / 'scripts'
    plugins.mkdir(parents=True)
    scripts.mkdir()
    (config / 'state.json').write_text('{}')
    bar_log = work / 'bar.jsonl'
    backend_log = work / 'backend'
    refresh_log = work / 'refresh'

    def executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    executable(work / 'sketchybar', '#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["TEST_BAR_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
    backend = '#!/bin/bash\nprintf "%s|%s|%s|%s\\n" "$*" "$BARISTA_CONFIG_DIR" "$BARISTA_TARGET_SPACE_INDEX" "$BARISTA_TARGET_SPACE_ID" >> "$TEST_BACKEND_LOG"\nif [ "${TEST_FAIL:-0}" != 0 ]; then printf "%s\\n" "${TEST_ERROR:-Space identity changed}" >&2; exit "$TEST_FAIL"; fi\n'
    executable(plugins / 'set_space_mode.sh', backend)
    executable(scripts / 'yabai_control.sh', backend)
    executable(plugins / 'control_center.sh', '#!/bin/bash\nprintf "%s|%s|%s\\n" "$NAME" "$SENDER" "$BARISTA_CONTROL_CENTER_LAYOUT_ROWS" >> "$TEST_REFRESH_LOG"\n')
    env = dict(os.environ, BARISTA_CONFIG_DIR=str(config), BARISTA_SKETCHYBAR_BIN=str(work / 'sketchybar'),
               TEST_BAR_LOG=str(bar_log), TEST_BACKEND_LOG=str(backend_log), TEST_REFRESH_LOG=str(refresh_log))

    def run(kind='layout', value='bsp', index='4', identity='1234', **overrides):
        for path in (bar_log, backend_log, refresh_log):
            path.write_text('')
        result = subprocess.run(['bash', str(root / 'scripts/space_menu_action.sh'), kind, index, identity, value, 'status_hub'],
                                env=dict(env, **overrides), text=True, capture_output=True)
        calls = [json.loads(line) for line in bar_log.read_text().splitlines()]
        rows = {}
        for call in calls:
            item = None
            i = 0
            while i < len(call):
                if call[i] == '--set':
                    item = call[i + 1]
                    rows.setdefault(item, {})
                    i += 2
                else:
                    key, val = call[i].split('=', 1)
                    rows[item][key] = val
                    i += 1
        return result, rows

    result, rows = run()
    assert result.returncode == 0, result.stderr
    assert backend_log.read_text().strip() == f'4 bsp|{config}|4|1234'
    assert refresh_log.read_text().strip() == 'status_hub|popup_refresh|1'
    assert rows['cc.feedback']['drawing'] == 'off'
    assert rows['status_hub']['popup.drawing'] == 'on'
    assert rows['cc.more']['popup.drawing'] == rows['cc.settings']['popup.drawing'] == 'off'
    print('PASS: successful layout refreshes selection, clears feedback, and retains visible root')

    result, rows = run(kind='arrange', value='space-rotate')
    assert result.returncode == 0, result.stderr
    assert backend_log.read_text().strip() == f'space-rotate|{config}|4|1234'
    assert rows['status_hub']['popup.drawing'] == 'on'
    print('PASS: arrangement targets captured index and stable identity')

    result, rows = run(TEST_FAIL='7', TEST_ERROR='Space identity changed\nMore details')
    assert result.returncode == 7
    assert result.stderr == 'Space identity changed\nMore details\n'
    assert refresh_log.read_text() == '', 'failed command must not publish a success refresh'
    assert rows['cc.feedback'] == {'drawing': 'on', 'label': 'Space identity changed'}
    assert rows['status_hub']['popup.drawing'] == 'on'
    print('PASS: failed action preserves exact stderr and shows failure in the open root')

    result, rows = run(TEST_FAIL='2', TEST_ERROR='x' * 2000)
    assert result.returncode == 2
    assert len(rows['cc.feedback']['label']) == 160
    print('PASS: long failure text is bounded for menu display')

    for parameters in (dict(index='0'), dict(identity='bad'), dict(kind='arrange', value='destroy')):
        result, rows = run(**parameters)
        assert result.returncode != 0
        assert backend_log.read_text() == ''
        assert not rows
    print('PASS: invalid identity and unsupported actions never reach the backend')
PY
