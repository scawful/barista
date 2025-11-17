#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <stdarg.h>

static double RESET_DELAY = 0.18;
static const char *DEFAULT_HILITE = "0x60cba6f7";

static void run_cmd(const char *fmt, ...) {
  char buffer[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
}

static void run_async(const char *command) {
  if (!command || command[0] == '\0') return;
  pid_t pid = fork();
  if (pid == 0) {
    execl("/bin/bash", "bash", "-lc", command, (char *)NULL);
    _exit(127);
  }
}

int main(int argc, char *argv[]) {
  if (argc < 3) {
    return 1;
  }

  const char *item = argv[1];
  const char *popup = argv[2];
  const char *command = getenv("MENU_ACTION_CMD");
  const char *highlight = getenv("MENU_ACTION_HILITE");
  if (!highlight || highlight[0] == '\0') {
    highlight = DEFAULT_HILITE;
  }
  const char *delay_env = getenv("MENU_ACTION_RESET_DELAY");
  if (delay_env && delay_env[0] != '\0') {
    double parsed = atof(delay_env);
    if (parsed > 0.0) RESET_DELAY = parsed;
  }

  if (item && item[0] != '\0') {
    run_cmd("sketchybar --set %s background.drawing=on background.color=%s", item, highlight);
  }

  run_async(command ? command : "");

  if (popup && popup[0] != '\0') {
    run_cmd("sketchybar -m --set %s popup.drawing=off", popup);
  }

  usleep((useconds_t)(RESET_DELAY * 1000000.0));

  if (item && item[0] != '\0') {
    run_cmd("sketchybar --set %s background.drawing=off", item);
  }

  return 0;
}
