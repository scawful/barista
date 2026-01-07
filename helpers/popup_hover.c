#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdarg.h>

/*
 * Popup Hover Handler
 *
 * Provides hover highlighting for popup menu items.
 * Handles mouse.entered and mouse.exited events.
 *
 * Features:
 * - Fast highlighting without shell overhead
 * - Tracks parent popup for submenu coordination
 * - Configurable highlight color
 */

static const char *DEFAULT_HIGHLIGHT = "0x40f5c2e7";
static const char *IDLE_COLOR = "0x00000000";
static const char *DEFAULT_BORDER_COLOR = "0x60cdd6f4";
static char state_dir[PATH_MAX];
static char parent_state_path[PATH_MAX];

static void ensure_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) == -1) {
    mkdir(path, 0700);
  }
}

static void run_cmd(const char *fmt, ...) {
  char buffer[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
}

static void set_parent(const char *parent_name) {
  if (!parent_name || parent_name[0] == '\0') {
    return;
  }
  FILE *fp = fopen(parent_state_path, "w");
  if (!fp) return;
  fputs(parent_name, fp);
  fclose(fp);
}

int main(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  snprintf(state_dir, sizeof(state_dir), "%s/sketchybar_popup_state", tmpdir);
  ensure_dir(state_dir);
  snprintf(parent_state_path, sizeof(parent_state_path), "%s/active_parent", state_dir);

  const char *name = getenv("NAME");
  if (!name || name[0] == '\0') {
    return 0;
  }

  const char *sender = getenv("SENDER");
  const char *highlight = getenv("POPUP_HOVER_COLOR");
  const char *border_color = getenv("POPUP_HOVER_BORDER_COLOR");
  const char *border_width = getenv("POPUP_HOVER_BORDER_WIDTH");
  if (!highlight || highlight[0] == '\0') {
    highlight = DEFAULT_HIGHLIGHT;
  }
  if (!border_color || border_color[0] == '\0') {
    border_color = DEFAULT_BORDER_COLOR;
  }

  if (!sender || strcmp(sender, "mouse.entered") == 0) {
    // Track submenu parent if specified
    const char *submenu_parent = getenv("SUBMENU_PARENT");
    if (submenu_parent && submenu_parent[0] != '\0') {
      set_parent(submenu_parent);
    }

    // Highlight on hover
    run_cmd("sketchybar --set %s background.drawing=on background.color=%s",
            name, highlight);
    if (border_width && border_width[0] != '\0') {
      run_cmd("sketchybar --set %s background.border_width=%s background.border_color=%s",
              name, border_width, border_color);
    }
    return 0;
  }

  if (strcmp(sender, "mouse.exited") == 0) {
    // Remove highlight
    run_cmd("sketchybar --set %s background.drawing=off background.color=%s",
            name, IDLE_COLOR);
    if (border_width && border_width[0] != '\0') {
      run_cmd("sketchybar --set %s background.border_width=0", name);
    }
    return 0;
  }

  return 0;
}
