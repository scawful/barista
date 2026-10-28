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
with tempfile.TemporaryDirectory(prefix='barista-control-center-') as directory:
    work = Path(directory)
    binaries = work / 'bin'
    binaries.mkdir()
    config = work / 'config with spaces'
    (config / 'plugins').mkdir(parents=True)
    (config / 'scripts').mkdir()
    (config / 'state.json').write_text('{"modes":{"window_manager":"required"}}')
    log = work / 'calls.jsonl'
    query_log = work / 'queries'
    action_log = work / 'actions'

    def executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    executable(binaries / 'sketchybar', '#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["TEST_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
    executable(binaries / 'yabai', '#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_QUERIES"\n[ "${TEST_QUERY_FAIL:-0}" = 0 ] || exit 1\nprintf "%s\\n" "$TEST_SPACE"\n')
    executable(binaries / 'skhd', '#!/bin/bash\nexit 0\n')
    executable(binaries / 'pgrep', '#!/bin/bash\n[ "${TEST_SERVICES_RUNNING:-1}" = 1 ]\n')
    executable(config / 'scripts' / 'space_menu_action.sh', '#!/bin/bash\nprintf "%s|%s|%s|%s|%s|%s\\n" "$BARISTA_CONFIG_DIR" "$1" "$2" "$3" "$4" "$5" >> "$TEST_ACTIONS"\n')
    env = dict(os.environ, PATH=f'{binaries}:{os.environ["PATH"]}',
               BARISTA_CONFIG_DIR=str(config), BARISTA_SKETCHYBAR_BIN=str(binaries / 'sketchybar'),
               BARISTA_YABAI_BIN=str(binaries / 'yabai'), BARISTA_CONTROL_CENTER_LAYOUT_ROWS='1',
               TEST_LOG=str(log), TEST_QUERIES=str(query_log), TEST_ACTIONS=str(action_log),
               TEST_SPACE=json.dumps({'index': 6, 'display': 2, 'type': 'bsp', 'id': 9993}),
               NAME='status_hub', SENDER='popup_refresh', TMPDIR=str(work),
               BARISTA_AGENT_PLIST=str(work / 'dev.barista.agent.plist'))

    def run(**overrides):
        log.write_text('')
        query_log.write_text('')
        subprocess.run(['bash', str(root / 'plugins/control_center.sh')], env=dict(env, **overrides), check=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        return calls

    def properties(calls):
        result = {}
        for call in calls:
            item = None
            index = 0
            while index < len(call):
                if call[index] == '--set':
                    item = call[index + 1]
                    result.setdefault(item, {})
                    index += 2
                else:
                    key, value = call[index].split('=', 1)
                    result[item][key] = value
                    index += 1
        return result

    calls = run()
    assert len(calls) == 1, 'refresh must publish one coherent SketchyBar batch'
    assert query_log.read_text().splitlines() == ['-m query --spaces --space'], 'one query must own both label and action'
    rows = properties(calls)
    assert rows['cc.header']['label'] == 'Space 6 · Display 2'
    assert rows['status_hub']['label'] == 'Tile'
    assert rows['cc.layout.bsp']['label'] == '● Tile'
    assert rows['cc.layout.float']['label'] == '○ Manual'
    assert rows['cc.mode.required']['label'] == '● Always'
    assert not any(name.startswith('cc.defaults.') for name in rows), 'app defaults must be absent'
    assert 'arrange 6 9993 balance status_hub' in rows['cc.layout_ops.balance']['click_script']
    action = rows['cc.layout.stack']['click_script']
    assert 'layout 6 9993 stack status_hub' in action
    subprocess.run(['bash', '-c', action], env=env, check=True)
    assert action_log.read_text().strip() == f'{config}|layout|6|9993|stack|status_hub', 'action must preserve exact config path, displayed space, identity, and root'
    print('PASS: one snapshot, selected layout, pinned numeric action, stable identity, and custom parent')

    for layout, label in [('float', 'Manual'), ('stack', 'Stack')]:
        rows = properties(run(TEST_SPACE=json.dumps({'index': 3, 'display': 1, 'type': layout, 'id': 9558})))
        assert rows[f'cc.layout.{layout}']['label'] == f'● {label}'
        assert rows['status_hub']['label'] == label
    print('PASS: Manual and Stack reflect live state')

    run()
    calls = run(SENDER='space_active_refresh')
    assert [call[1] for call in calls] == ['status_hub'], 'background refresh must not resend unchanged rows'
    calls = run(SENDER='routine', TEST_SPACE=json.dumps({'index': 2, 'display': 1, 'type': 'float', 'id': 4}))
    assert [call[1] for call in calls] == ['status_hub', 'cc.header'], 'anchor must publish before changed rows'
    assert properties(calls)['cc.header']['label'] == 'Space 2 · Display 1'
    print('PASS: background refresh publishes anchor first and only changed rows')

    assert properties(run())['cc.dock']['label'] == 'Dock: macOS'
    (work / 'dev.barista.agent.plist').write_text('')
    assert properties(run())['cc.dock']['label'] == 'Dock: Barista'
    print('PASS: dock row reflects the installed agent')

    invalid = [dict(TEST_QUERY_FAIL='1'), dict(TEST_SPACE='not json'),
               dict(TEST_SPACE='{"index":"6; bad","display":2,"type":"bsp"}'),
               dict(TEST_SPACE='{"index":6,"display":2,"type":"unknown"}'),
               dict(TEST_SPACE='{"index":6.5,"display":2,"type":"float"}')]
    for overrides in invalid:
        rows = properties(run(**overrides))
        assert rows['cc.header']['label'] == 'Space unavailable'
        assert rows['status_hub']['label'] == '---'
        for mode in ('float', 'bsp', 'stack'):
            assert rows[f'cc.layout.{mode}']['label'].startswith('○ ')
            assert rows[f'cc.layout.{mode}']['click_script'] == ''
        for operation in ('balance', 'rotate', 'toggle', 'flipx', 'flipy'):
            assert rows[f'cc.layout_ops.{operation}']['click_script'] == ''
    print('PASS: failed, malformed, unsupported, and nonnumeric queries clear selections and actions')

    rows = properties(run(BARISTA_WINDOW_MANAGER_MODE='auto'))
    assert rows['cc.mode.auto']['label'] == '● Auto Detect'
    assert rows['cc.mode.required']['label'] == '○ Always'
    print('PASS: auto mode has a selected choice')

    rows = properties(run(BARISTA_WINDOW_MANAGER_MODE='disabled', BARISTA_CONTROL_CENTER_LAYOUT_ROWS='0'))
    assert query_log.read_text() == ''
    assert rows['status_hub']['label'] == 'Bar'
    assert rows['cc.mode.disabled']['label'] == '● Hidden'
    assert not any(name.startswith('cc.layout.') for name in rows)
    print('PASS: disabled mode retains settings without querying or updating missing space rows')

    rows = properties(run(SENDER='mouse.clicked', BARISTA_CONTROL_CENTER_LAYOUT_ROWS='0'))
    assert rows['status_hub']['popup.drawing'] == 'toggle'
    assert rows['cc.settings']['popup.drawing'] == 'off'
    assert 'cc.more' not in rows
    assert query_log.read_text() == ''
    print('PASS: fallback toggle resets settings without missing child or synchronous query')

    rows = properties(run(SENDER='mouse.exited.global')[:1])
    assert all(row['popup.drawing'] == 'off' for name, row in rows.items() if name in ('cc.settings', 'cc.more', 'status_hub'))
    print('PASS: global exit closes root and both children')
PY
