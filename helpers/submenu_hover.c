#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <signal.h>
#include <errno.h>

static const char *HOVER_BG = "0x80cba6f7";
static const char *IDLE_BG = "0x00000000";
static const char *SUBMENUS[] = {
  "menu.sketchybar.styles",
  "menu.sketchybar.tools",
  "menu.yabai.section",
  "menu.windows.section",
  "menu.rom.section",
  "menu.emacs.section",
  "menu.halext.section",
  "menu.apps.section",
  "menu.dev.section",
  "menu.help.section"
};
static const size_t SUBMENU_COUNT = sizeof(SUBMENUS) / sizeof(SUBMENUS[0]);

static double CLOSE_DELAY = 0.25;  // Increased default for better reliability
static char state_file[PATH_MAX];
static char parent_state_file[PATH_MAX];
static char pid_file[PATH_MAX];  // Track pending close PIDs
static const char *PARENT_POPUP = "apple_menu";  // Main menu that contains submenus

static void run_cmd(const char *fmt, ...) {
  char buffer[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
}

// Atomic file operations with flock
static void record_active(const char *name) {
  int fd = open(state_file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;

  // Get exclusive lock
  if (flock(fd, LOCK_EX) < 0) {
    close(fd);
    return;
  }

  write(fd, name, strlen(name));
  flock(fd, LOCK_UN);
  close(fd);
}

static int read_active(char *buffer, size_t size) {
  int fd = open(state_file, O_RDONLY);
  if (fd < 0) return 0;

  // Get shared lock for reading
  if (flock(fd, LOCK_SH) < 0) {
    close(fd);
    return 0;
  }

  ssize_t n = read(fd, buffer, size - 1);
  flock(fd, LOCK_UN);
  close(fd);

  if (n <= 0) return 0;
  buffer[n] = '\0';
  buffer[strcspn(buffer, "\n")] = '\0';
  return 1;
}

static void clear_active() {
  unlink(state_file);
  unlink(parent_state_file);  // Also clear parent state
}

static void record_parent_open() {
  int fd = open(parent_state_file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;

  if (flock(fd, LOCK_EX) < 0) {
    close(fd);
    return;
  }

  write(fd, "open", 4);
  flock(fd, LOCK_UN);
  close(fd);
}

static int is_parent_open() {
  int fd = open(parent_state_file, O_RDONLY);
  if (fd < 0) return 0;
  close(fd);
  return 1;
}

// Kill any pending close process for this submenu
static void cancel_pending_close(const char *name) {
  char submenu_pid_file[PATH_MAX];
  snprintf(submenu_pid_file, sizeof(submenu_pid_file), "%s.%s", pid_file, name);

  int fd = open(submenu_pid_file, O_RDONLY);
  if (fd < 0) return;

  char pid_str[32];
  ssize_t n = read(fd, pid_str, sizeof(pid_str) - 1);
  close(fd);

  if (n > 0) {
    pid_str[n] = '\0';
    pid_t old_pid = (pid_t)atoi(pid_str);
    if (old_pid > 0) {
      kill(old_pid, SIGTERM);  // Cancel the pending close
    }
  }
  unlink(submenu_pid_file);
}

// Record the PID of a pending close
static void record_pending_close(const char *name, pid_t pid) {
  char submenu_pid_file[PATH_MAX];
  snprintf(submenu_pid_file, sizeof(submenu_pid_file), "%s.%s", pid_file, name);

  int fd = open(submenu_pid_file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;

  char pid_str[32];
  snprintf(pid_str, sizeof(pid_str), "%d", pid);
  write(fd, pid_str, strlen(pid_str));
  close(fd);
}

static void close_other_submenus(const char *current) {
  // Build a single batched command for efficiency
  char cmd[4096] = "sketchybar";

  for (size_t i = 0; i < SUBMENU_COUNT; i++) {
    const char *submenu = SUBMENUS[i];
    if (strcmp(submenu, current) == 0) continue;

    char part[256];
    snprintf(part, sizeof(part),
             " --set %s popup.drawing=off background.drawing=off background.color=%s",
             submenu, IDLE_BG);
    strncat(cmd, part, sizeof(cmd) - strlen(cmd) - 1);
  }

  system(cmd);
}

static void schedule_close(const char *name) {
  // Cancel any existing pending close for this submenu
  cancel_pending_close(name);

  pid_t pid = fork();
  if (pid > 0) {
    // Parent: record the child PID for potential cancellation
    record_pending_close(name, pid);
    return;
  }
  if (pid < 0) {
    // Fork failed
    return;
  }

  // Child process: wait then close
  usleep((useconds_t)(CLOSE_DELAY * 1000000.0));

  // Check if still active (with proper locking)
  char current[256];
  if (!read_active(current, sizeof(current)) || strcmp(current, name) != 0) {
    // Close submenu and reset background
    run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
            name, IDLE_BG);
  }

  // Clean up our PID file
  char submenu_pid_file[PATH_MAX];
  snprintf(submenu_pid_file, sizeof(submenu_pid_file), "%s.%s", pid_file, name);
  unlink(submenu_pid_file);

  _exit(0);
}

int main(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  snprintf(state_file, sizeof(state_file), "%s/sketchybar_submenu_active", tmpdir);
  snprintf(parent_state_file, sizeof(parent_state_file), "%s/sketchybar_parent_popup_lock", tmpdir);
  snprintf(pid_file, sizeof(pid_file), "%s/sketchybar_submenu_pid", tmpdir);

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
    // Cancel any pending close for this submenu (user re-entered)
    cancel_pending_close(name);
    close_other_submenus(name);
    record_active(name);
    record_parent_open();  // Lock parent popup from closing
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
    // Global exit: close everything
    clear_active();
    close_other_submenus(name);  // Close all submenus
    run_cmd("sketchybar --set %s popup.drawing=off background.drawing=off background.color=%s",
            name, IDLE_BG);
    // Also close parent popup
    run_cmd("sketchybar --set %s popup.drawing=off", PARENT_POPUP);
    return 0;
  }

  return 0;
}
