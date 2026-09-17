#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="clock"
if [ "${1:-}" = "--full-refresh" ]; then
  MODE="full-refresh"
  shift
elif [ "${1:-}" = "--clock" ]; then
  shift
fi
ITERATIONS="${1:-$([ "$MODE" = "clock" ] && printf 200 || printf 10)}"
CC_BIN="${CC:-$(command -v cc 2>/dev/null || true)}"
PYTHON_BIN="${BARISTA_PYTHON:-$(command -v python3 2>/dev/null || true)}"
TMP_DIR="$(mktemp -d)"
PERF_CLOCK="$TMP_DIR/perf_clock"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

case "$ITERATIONS" in
  ""|*[!0-9]*) echo "usage: $0 [--clock|--full-refresh] [positive-iterations]" >&2; exit 64 ;;
esac
[ "$ITERATIONS" -gt 0 ] || { echo "iterations must be positive" >&2; exit 64; }
[ -n "$PYTHON_BIN" ] || {
  echo "benchmark requires python3" >&2
  exit 1
}

if [ "$MODE" = "full-refresh" ]; then
  REFRESH_SCRIPT="$ROOT_DIR/plugins/refresh_spaces.sh"
  [ -x "$REFRESH_SCRIPT" ] || {
    echo "full-refresh benchmark requires executable $REFRESH_SCRIPT" >&2
    exit 1
  }
  echo "Running $ITERATIONS serialized live full refreshes; this temporarily rebuilds the spaces strip." >&2
  "$PYTHON_BIN" - "$REFRESH_SCRIPT" "$ROOT_DIR" "$ITERATIONS" <<'PY'
import math
import os
import statistics
import subprocess
import sys
import time

script, root, raw_iterations = sys.argv[1:]
iterations = int(raw_iterations)
environment = os.environ.copy()
environment.update({
    "BARISTA_CONFIG_DIR": root,
    "CONFIG_DIR": root,
    "BARISTA_REASON": "space_topology_repair",
    "SENDER": "space_topology_repair",
    "BARISTA_TOPOLOGY_APPLY_RETRY": "1",
})
command = [script]

subprocess.run(command, check=True, env=environment, stdout=subprocess.DEVNULL)
samples = []
for _ in range(iterations):
    started = time.perf_counter_ns()
    subprocess.run(command, check=True, env=environment, stdout=subprocess.DEVNULL)
    samples.append((time.perf_counter_ns() - started) / 1_000_000)

ordered = sorted(samples)
p95 = ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)]
print(f"mode=full-refresh iterations={iterations} warmups=1")
print(f"wall: median={statistics.median(samples):.3f}ms p95={p95:.3f}ms")
PY
  exit $?
fi

[ -n "$CC_BIN" ] || {
  echo "clock benchmark requires a C compiler" >&2
  exit 1
}

"$CC_BIN" -O2 -std=c99 "$ROOT_DIR/helpers/perf_clock.c" -o "$PERF_CLOCK"
"$PYTHON_BIN" - "$PERF_CLOCK" "$ITERATIONS" <<'PY'
import math
import random
import statistics
import subprocess
import sys
import time

clock = sys.argv[1]
iterations = int(sys.argv[2])
commands = {
    "native": [clock, "ms"],
    "perl": ["perl", "-MTime::HiRes=time", "-e", 'printf("%d\\n", time() * 1000)'],
}
samples = {name: [] for name in commands}
rng = random.Random(0xBA7157A)

for command in commands.values():
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)

for _ in range(iterations):
    names = list(commands)
    rng.shuffle(names)
    for name in names:
        started = time.perf_counter_ns()
        output = subprocess.check_output(commands[name], text=True).strip()
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        if not output.isdigit():
            raise SystemExit(f"{name} emitted nonnumeric output: {output!r}")
        samples[name].append(elapsed_ms)

def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]

print(f"iterations={iterations} seed=0xBA7157A")
for name in ("native", "perl"):
    values = samples[name]
    print(
        f"{name}: median={statistics.median(values):.3f}ms "
        f"p95={percentile(values, 0.95):.3f}ms"
    )
PY
