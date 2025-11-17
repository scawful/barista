#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/stat.h>

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

// List of all popup items to manage
static const char *POPUP_ITEMS[] = {
  "apple_menu",
  "front_app",
  "clock",
  "system_info",
  "yabai_status"
};
static const size_t POPUP_COUNT = sizeof(POPUP_ITEMS) / sizeof(POPUP_ITEMS[0]);

// List of all submenu parent items
static const char *SUBMENU_PARENTS[] = {
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
static const size_t SUBMENU_COUNT = sizeof(SUBMENU_PARENTS) / sizeof(SUBMENU_PARENTS[0]);

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
  const char *sender = getenv("SENDER");

  if (should_dismiss_on_event(sender)) {
    dismiss_all_popups();
  }

  return 0;
}
