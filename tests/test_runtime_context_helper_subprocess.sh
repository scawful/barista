#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test_runtime_context_helper_subprocess.sh: skipped (Darwin only)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/runtime_context_helper.m"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [[ -z "$CC_BIN" ]]; then
  printf 'test_runtime_context_helper_subprocess.sh: skipped (Objective-C compiler unavailable)\n'
  exit 0
fi

cat > "$TMP_DIR/probe.m" <<EOF_PROBE
#define main barista_runtime_context_helper_main
#include "$SOURCE"
#undef main

static int open_descriptor_count(void) {
  int count = 0;
  for (int descriptor = 0; descriptor < 512; descriptor++) {
    if (fcntl(descriptor, F_GETFD) >= 0) count++;
  }
  return count;
}

int main(int argc, const char **argv) {
  if (argc < 3) return 64;
  @autoreleasepool {
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (int i = 2; i < argc; i++) {
      [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    if ([arguments[0] isEqualToString:@"repeat"]) {
      // Warm Foundation before measuring descriptor retention.
      if (run_task(path, @[@"small"]) == nil) return 1;
      int before = open_descriptor_count();
      for (int attempt = 0; attempt < 80; attempt++) {
        @autoreleasepool {
          if (run_task(path, @[@"small"]) == nil) return 1;
        }
      }
      return open_descriptor_count() == before ? 0 : 2;
    }
    NSString *output = run_task(path, arguments);
    if (output == nil) return 1;
    fputs(output.UTF8String, stdout);
    return 0;
  }
}
EOF_PROBE
"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror -framework Cocoa -framework Foundation \
  "$TMP_DIR/probe.m" -o "$TMP_DIR/probe"

cat > "$TMP_DIR/worker.c" <<'EOF_WORKER'
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void record_pid(void) {
  const char *path = getenv("BARISTA_TEST_PID_LOG");
  if (!path) exit(65);
  int descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0600);
  if (descriptor < 0) exit(66);
  dprintf(descriptor, "%d\n", getpid());
  close(descriptor);
}

static void write_bytes(int descriptor, size_t count) {
  char buffer[8192];
  memset(buffer, 'x', sizeof(buffer));
  while (count > 0) {
    size_t length = count < sizeof(buffer) ? count : sizeof(buffer);
    ssize_t written = write(descriptor, buffer, length);
    if (written <= 0) exit(67);
    count -= (size_t)written;
  }
}

int main(int argc, char **argv) {
  if (argc < 2) return 64;
  const char *mode = argv[1];
  if (!strcmp(mode, "large")) {
    write_bytes(STDOUT_FILENO, 512 * 1024);
  } else if (!strcmp(mode, "overflow")) {
    write_bytes(STDOUT_FILENO, 4 * 1024 * 1024 + 1);
  } else if (!strcmp(mode, "stderr")) {
    write_bytes(STDERR_FILENO, 512 * 1024);
    puts("ready");
  } else if (!strcmp(mode, "arguments")) {
    if (argc != 3) return 64;
    puts(argv[2]);
  } else if (!strcmp(mode, "empty")) {
    return 0;
  } else if (!strcmp(mode, "nonzero")) {
    puts("not a valid result");
    return 2;
  } else if (!strcmp(mode, "invalid-utf8")) {
    const unsigned char invalid[] = {0xff, 0xfe};
    if (write(STDOUT_FILENO, invalid, sizeof(invalid)) < 0) return 67;
  } else if (!strcmp(mode, "closed-pipe")) {
    puts("ready");
    fflush(stdout);
    close(STDOUT_FILENO);
    usleep(100000);
  } else if (!strcmp(mode, "timeout") || !strcmp(mode, "orphan") ||
             !strcmp(mode, "descendant") || !strcmp(mode, "failed-descendant")) {
    record_pid();
    signal(SIGTERM, SIG_IGN);
    pid_t child = fork();
    if (child < 0) return 68;
    if (child == 0) {
      record_pid();
      if (!strcmp(mode, "descendant") || !strcmp(mode, "failed-descendant")) {
        close(STDOUT_FILENO);
      }
      while (1) pause();
    }
    // Give the child enough time to register its PID before parent cleanup.
    usleep(10000);
    if (!strcmp(mode, "timeout")) {
      while (1) pause();
    }
    if (!strcmp(mode, "failed-descendant")) return 2;
    puts("ready");
  } else if (!strcmp(mode, "small")) {
    puts("ready");
  } else {
    return 64;
  }
  return 0;
}
EOF_WORKER
"$CC_BIN" -Wall -Wextra -Werror "$TMP_DIR/worker.c" -o "$TMP_DIR/query worker"

python3 - "$TMP_DIR" <<'PY_TEST'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
probe = root / "probe"
worker = root / "query worker"
pid_log = root / "pids"
env = {**os.environ, "BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT": "0.2",
       "BARISTA_TEST_PID_LOG": str(pid_log)}

def run(mode, expected_status=0, expected_output=b"ready", *arguments):
    pid_log.write_text("")
    started = time.monotonic()
    process = subprocess.Popen([str(probe), str(worker), mode, *arguments],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise AssertionError(f"{mode}: query exceeded the outer two-second bound")
    finally:
        # Regression failures must not leave the fixture descendants alive.
        pids = [int(value) for value in pid_log.read_text().splitlines()]
        deadline = time.monotonic() + 0.5
        alive = []
        while True:
            alive = []
            for pid in pids:
                try:
                    os.kill(pid, 0)
                    alive.append(pid)
                except ProcessLookupError:
                    pass
            if not alive or time.monotonic() >= deadline:
                break
            time.sleep(0.01)
        for pid in alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    assert not alive, f"{mode}: query left fixture processes alive: {alive}"
    assert process.returncode == expected_status, (mode, process.returncode, stderr)
    assert not stderr, (mode, stderr[:120])
    assert stdout == expected_output, (mode, len(stdout), stdout[:120])
    if mode in {"timeout", "orphan"}:
        assert len(pids) == 2, (mode, pids)
        assert time.monotonic() - started < 1.0, mode

run("small")
run("large", 0, b"x" * (512 * 1024))
run("stderr")
run("arguments", 0, b"literal 'quoted' $(value) ; spaced", "literal 'quoted' $(value) ; spaced")
run("closed-pipe")
for mode in ("empty", "nonzero", "invalid-utf8", "overflow", "timeout", "orphan", "failed-descendant"):
    run(mode, 1, b"")
run("descendant")
run("repeat", 0, b"")
result = subprocess.run([str(probe), str(root / "missing"), "small"], env=env,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1)
assert result.returncode == 1 and not result.stdout, result
print("runtime-context subprocess cases: 15 passed")
PY_TEST

printf 'test_runtime_context_helper_subprocess.sh: ok\n'
