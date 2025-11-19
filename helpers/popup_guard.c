#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

// Popup Guard - Prevents main popup from closing when submenus are open
// Usage: sketchybar --set apple_menu script=popup_guard --subscribe apple_menu mouse.exited mouse.exited.global

static char lock_file[PATH_MAX];

static int is_submenu_open() {
  FILE *fp = fopen(lock_file, "r");
  if (!fp) return 0;
  fclose(fp);
  return 1;
}

int main(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  snprintf(lock_file, sizeof(lock_file), "%s/sketchybar_parent_popup_lock", tmpdir);

  const char *name = getenv("NAME");
  const char *sender = getenv("SENDER");
  const char *sticky_env = getenv("POPUP_GUARD_STICKY");
  int is_sticky = sticky_env && strcmp(sticky_env, "1") == 0;

  if (!name || !sender) return 0;

  // On mouse.exited or mouse.exited.global
  if (strstr(sender, "exited")) {
    if (is_sticky) {
      // Sticky mode: ignore hover exits
      return 0;
    }
    // Only close if no submenu is open
    if (!is_submenu_open()) {
      char cmd[256];
      snprintf(cmd, sizeof(cmd), "sketchybar --set %s popup.drawing=off", name);
      system(cmd);
    }
    // If submenu is open, do nothing - let submenu control dismissal
  }

  return 0;
}
