#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <limits.h>

/*
 * Global Popup Manager
 *
 * Handles automatic dismissal of all popups on events like:
 * - space_changed (Yabai space switching)
 * - display_changed (Display configuration changes)
 * - mission_control_enter (macOS Mission Control/Spaces overview)
 * - window_focused (Window focus changes)
 *
 * Usage:
 *   Set as script for items that should dismiss popups on these events
 *   Subscribe items with: sketchybar --subscribe popup_manager <events>
 */

/* Hardcoded fallback lists */
static const char *FALLBACK_POPUP_ITEMS[] = {
  "apple_menu", "front_app", "clock", "system_info", "yabai_status"
};
static const size_t FALLBACK_POPUP_COUNT = sizeof(FALLBACK_POPUP_ITEMS) / sizeof(FALLBACK_POPUP_ITEMS[0]);

static const char *FALLBACK_SUBMENU_PARENTS[] = {
  "menu.sketchybar.styles", "menu.sketchybar.tools", "menu.yabai.section",
  "menu.windows.section", "menu.rom.section", "menu.emacs.section",
  "menu.apps.section", "menu.dev.section", "menu.help.section"
};
static const size_t FALLBACK_SUBMENU_COUNT = sizeof(FALLBACK_SUBMENU_PARENTS) / sizeof(FALLBACK_SUBMENU_PARENTS[0]);

/* Dynamic lists loaded from TMPDIR files */
#define MAX_ITEMS 64
static char popup_names[MAX_ITEMS][256];
static const char *POPUP_ITEMS[MAX_ITEMS];
static size_t POPUP_COUNT = 0;

static char submenu_names[MAX_ITEMS][256];
static const char *SUBMENU_PARENTS[MAX_ITEMS];
static size_t SUBMENU_COUNT = 0;

static size_t load_list(const char *path, char storage[][256], const char *ptrs[], size_t max,
                        const char *fallback[], size_t fallback_count) {
  size_t count = 0;
  FILE *fp = fopen(path, "r");
  if (fp) {
    char line[256];
    while (count < max && fgets(line, sizeof(line), fp)) {
      line[strcspn(line, "\n\r")] = '\0';
      if (line[0] == '\0') continue;
      strncpy(storage[count], line, sizeof(storage[0]) - 1);
      ptrs[count] = storage[count];
      count++;
    }
    fclose(fp);
  }
  if (count == 0) {
    for (size_t i = 0; i < fallback_count && i < max; i++) {
      ptrs[i] = fallback[i];
    }
    count = fallback_count < max ? fallback_count : max;
  }
  return count;
}

static void load_lists() {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "%s/sketchybar_popup_list", tmpdir);
  POPUP_COUNT = load_list(path, popup_names, POPUP_ITEMS, MAX_ITEMS,
                          FALLBACK_POPUP_ITEMS, FALLBACK_POPUP_COUNT);
  snprintf(path, sizeof(path), "%s/sketchybar_submenu_list", tmpdir);
  SUBMENU_COUNT = load_list(path, submenu_names, SUBMENU_PARENTS, MAX_ITEMS,
                            FALLBACK_SUBMENU_PARENTS, FALLBACK_SUBMENU_COUNT);
}

static void run_cmd(const char *fmt, ...) {
  char buffer[2048];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
}

static void clear_state_files() {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";

  // Clear popup anchor state
  char popup_dir[512];
  snprintf(popup_dir, sizeof(popup_dir), "%s/sketchybar_popup_state", tmpdir);
  char cmd[1024];
  snprintf(cmd, sizeof(cmd), "rm -rf \"%s\" 2>/dev/null", popup_dir);
  system(cmd);

  // Clear submenu hover state
  char submenu_file[512];
  snprintf(submenu_file, sizeof(submenu_file), "%s/sketchybar_submenu_active", tmpdir);
  unlink(submenu_file);
}

static void dismiss_all_popups() {
  // Build a single sketchybar command to dismiss all popups
  char cmd[4096] = "sketchybar";

  // Add all popup items
  for (size_t i = 0; i < POPUP_COUNT; i++) {
    char part[256];
    snprintf(part, sizeof(part), " --set %s popup.drawing=off", POPUP_ITEMS[i]);
    strncat(cmd, part, sizeof(cmd) - strlen(cmd) - 1);
  }

  // Add all submenu parents
  for (size_t i = 0; i < SUBMENU_COUNT; i++) {
    char part[256];
    snprintf(part, sizeof(part),
             " --set %s popup.drawing=off background.drawing=off background.color=0x00000000",
             SUBMENU_PARENTS[i]);
    strncat(cmd, part, sizeof(cmd) - strlen(cmd) - 1);
  }

  // Execute the batched command
  system(cmd);

  // Clear state files to prevent reopening
  clear_state_files();
}

static int should_dismiss_on_event(const char *sender) {
  if (!sender || sender[0] == '\0') {
    return 0;
  }

  // Dismiss on space changes
  if (strcmp(sender, "space_change") == 0 ||
      strcmp(sender, "space_changed") == 0 ||
      strcmp(sender, "display_changed") == 0 ||
      strcmp(sender, "display_added") == 0 ||
      strcmp(sender, "display_removed") == 0) {
    return 1;
  }

  // Dismiss on mission control
  if (strcmp(sender, "mission_control_enter") == 0 ||
      strcmp(sender, "mission_control_exit") == 0) {
    return 1;
  }

  // Dismiss on system sleep/wake
  if (strcmp(sender, "system_woke") == 0) {
    return 1;
  }

  // Dismiss on front app switch (optional, can be configured)
  const char *dismiss_on_app_switch = getenv("DISMISS_ON_APP_SWITCH");
  if (dismiss_on_app_switch && strcmp(dismiss_on_app_switch, "1") == 0) {
    if (strcmp(sender, "front_app_switched") == 0) {
      return 1;
    }
  }

  return 0;
}

int main(void) {
  load_lists();
  const char *sender = getenv("SENDER");

  if (should_dismiss_on_event(sender)) {
    dismiss_all_popups();
  }

  return 0;
}
