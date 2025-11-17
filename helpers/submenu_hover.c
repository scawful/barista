#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdarg.h>

static const char *HOVER_BG = "0x80cba6f7";
static const char *IDLE_BG = "0x00000000";
static const char *SUBMENUS[] = {
  "menu.sketchybar.styles",
  "menu.sketchybar.tools",
  "menu.yabai.section",
  "menu.windows.section",
  "menu.rom.section",
  "menu.emacs.section",
  "menu.apps.section",
  "menu.dev.section",
  "menu.help.section"
};
static const size_t SUBMENU_COUNT = sizeof(SUBMENUS) / sizeof(SUBMENUS[0]);

static double CLOSE_DELAY = 0.25;
static char state_file[PATH_MAX];

static void run_cmd(const char *fmt, ...) {
  char buffer[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
}

static void record_active(const char *name) {
  FILE *fp = fopen(state_file, "w");
  if (!fp) return;
  fputs(name, fp);
  fclose(fp);
}

static int read_active(char *buffer, size_t size) {
  FILE *fp = fopen(state_file, "r");
  if (!fp) return 0;
  if (!fgets(buffer, (int)size, fp)) {
    fclose(fp);
    return 0;
  }
  buffer[strcspn(buffer, "\n")] = '\0';
  fclose(fp);
  return 1;
}

static void clear_active() {
  unlink(state_file);
}

static void close_other_submenus(const char *current) {
  for (size_t i = 0; i < SUBMENU_COUNT; i++) {
    const char *submenu = SUBMENUS[i];
    if (strcmp(submenu, current) == 0) continue;
    run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
            submenu, IDLE_BG);
  }
}

static void schedule_close(const char *name) {
  pid_t pid = fork();
  if (pid != 0) {
    return;
  }
  usleep((useconds_t)(CLOSE_DELAY * 1000000.0));
  char current[256];
  if (!read_active(current, sizeof(current)) || strcmp(current, name) != 0) {
    run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
            name, IDLE_BG);
  }
  _exit(0);
}

int main(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  snprintf(state_file, sizeof(state_file), "%s/sketchybar_submenu_active", tmpdir);

  const char *delay_env = getenv("SUBMENU_CLOSE_DELAY");
  if (delay_env && delay_env[0] != '\0') {
    double parsed = atof(delay_env);
    if (parsed > 0.0) CLOSE_DELAY = parsed;
  }

  const char *name = getenv("NAME");
  if (!name || name[0] == '\0') {
    return 0;
  }
  const char *sender = getenv("SENDER");

  if (!sender || strcmp(sender, "mouse.entered") == 0) {
    close_other_submenus(name);
    record_active(name);
    run_cmd("sketchybar --set %s popup.drawing=on background.drawing=on "
            "background.color=%s background.corner_radius=6 "
            "background.padding_left=4 background.padding_right=4",
            name, HOVER_BG);
    return 0;
  }

  if (strcmp(sender, "mouse.exited") == 0) {
    schedule_close(name);
    return 0;
  }

  if (strcmp(sender, "mouse.exited.global") == 0) {
    clear_active();
    run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
            name, IDLE_BG);
    return 0;
  }

  return 0;
}
