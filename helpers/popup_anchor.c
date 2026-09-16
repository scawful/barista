#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <limits.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>

static double CLOSE_DELAY = 0.18;
static double HOVER_TIMEOUT = 0.55;
static int OPEN_ON_ENTER = 0;
static char state_dir[PATH_MAX];
static char state_path[PATH_MAX];
static char shell_popup_state_path[PATH_MAX];
static char parent_state_path[PATH_MAX];
static char hover_state_path[PATH_MAX];
static char hover_lock_path[PATH_MAX];
static int hover_lock_fd = -1;

static double monotonic_seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}

static void release_hover_lock(void) {
  if (hover_lock_fd >= 0) close(hover_lock_fd);
  hover_lock_fd = -1;
}

static int acquire_hover_lock(int wait_ms) {
  hover_lock_fd = open(hover_lock_path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
  if (hover_lock_fd < 0) return 0;
  double deadline = monotonic_seconds() + (double)wait_ms / 1000.0;
  while (flock(hover_lock_fd, LOCK_EX | LOCK_NB) != 0) {
    if ((errno != EWOULDBLOCK && errno != EAGAIN && errno != EINTR)
        || wait_ms == 0 || monotonic_seconds() >= deadline) {
      release_hover_lock();
      return 0;
    }
    usleep(1000);
  }
  return 1;
}

static const char *sketchybar_bin(void) {
  const char *value = getenv("BARISTA_SKETCHYBAR_BIN");
  if (value && value[0] != '\0') return value;
  value = getenv("SKETCHYBAR_BIN");
  return value && value[0] != '\0' ? value : "sketchybar";
}

static void ensure_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) == -1) {
    char parent[PATH_MAX];
    if (snprintf(parent, sizeof(parent), "%s", path) >= (int)sizeof(parent)) return;
    for (char *p = parent + 1; *p; p++) {
      if (*p != '/') continue;
      *p = '\0';
      mkdir(parent, 0700);
      *p = '/';
    }
    mkdir(parent, 0700);
  }
}

static void set_state_path(const char *name) {
  snprintf(state_path, sizeof(state_path), "%s/%s.anchor", state_dir, name ? name : "item");
  snprintf(shell_popup_state_path, sizeof(shell_popup_state_path), "%s/%s.state", state_dir, name ? name : "item");
  char key[PATH_MAX];
  size_t length = 0;
  int invalid = 0;
  int needs_sanitize = 0;
  for (const unsigned char *p = (const unsigned char *)name; *p; p++) {
    if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')
          || (*p >= '0' && *p <= '9') || *p == '.' || *p == '_' || *p == '-')) {
      needs_sanitize = 1;
      break;
    }
  }
  for (const unsigned char *p = (const unsigned char *)name; *p && length + 1 < sizeof(key); p++) {
    int allowed = (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')
        || (*p >= '0' && *p <= '9') || *p == '.' || *p == '_' || *p == '-';
    char value = allowed ? (char)*p : '_';
    // The shell's rare-name tr -cs path squeezes existing underscores too.
    if ((allowed || !invalid) && !(needs_sanitize && value == '_'
          && length > 0 && key[length - 1] == '_')) key[length++] = value;
    invalid = !allowed;
  }
  key[length] = '\0';
  const char *directory = getenv("BARISTA_HOVER_STATE_DIR");
  char default_directory[PATH_MAX];
  if (!directory || !*directory) {
    const char *tmp = getenv("TMPDIR");
    snprintf(default_directory, sizeof(default_directory), "%s/sketchybar_hover_state", tmp && *tmp ? tmp : "/tmp");
    directory = default_directory;
  }
  ensure_dir(directory);
  snprintf(hover_state_path, sizeof(hover_state_path), "%s/%s.state", directory, key);
  snprintf(hover_lock_path, sizeof(hover_lock_path), "%s/%s.apply.lock", directory, key);
}

static int run_process(char *const argv[]) {
  pid_t pid = fork();
  if (pid < 0) {
    return -1;
  }
  if (pid == 0) {
    release_hover_lock();
    setpgid(0, 0);
    execvp(argv[0], argv);
    _exit(127);
  }

  setpgid(pid, pid);
  int status = 0;
  double deadline = monotonic_seconds() + 0.5;
  while (1) {
    pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid) break;
    if (waited < 0 && errno != EINTR) return -1;
    if (monotonic_seconds() >= deadline) {
      kill(-pid, SIGKILL);
      kill(pid, SIGKILL);
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
      return 124;
    }
    usleep(1000);
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  return -1;
}

static const char *first_nonempty_env(const char *const *names, size_t count, const char *fallback) {
  for (size_t i = 0; i < count; i++) {
    const char *value = getenv(names[i]);
    if (value && value[0] != '\0') {
      return value;
    }
  }
  return fallback;
}

static const char *hover_color(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_HOVER_BG",
    "BARISTA_HOVER_COLOR",
    "POPUP_HOVER_COLOR",
    "SUBMENU_HOVER_BG",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0x40f5c2e7");
}

static const char *hover_border_width(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_HOVER_BORDER_WIDTH",
    "POPUP_HOVER_BORDER_WIDTH",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "");
}

static const char *hover_border_color(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_HOVER_BORDER_COLOR",
    "POPUP_HOVER_BORDER_COLOR",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0x60cdd6f4");
}

static const char *idle_drawing(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_IDLE_DRAWING",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "off");
}

static const char *idle_color(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_IDLE_BG",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0x00000000");
}

static const char *idle_border_width(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_IDLE_BORDER_WIDTH",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0");
}

static const char *idle_border_color(void) {
  static const char *const names[] = {
    "BARISTA_ANCHOR_IDLE_BORDER_COLOR",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0x00000000");
}

static const char *animation_curve(void) {
  static const char *const names[] = {
    "BARISTA_HOVER_ANIMATION_CURVE",
    "POPUP_HOVER_ANIMATION_CURVE",
    "SUBMENU_ANIMATION_CURVE",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "sin");
}

static const char *animation_duration(void) {
  static const char *const names[] = {
    "BARISTA_HOVER_ANIMATION_DURATION",
    "POPUP_HOVER_ANIMATION_DURATION",
    "SUBMENU_ANIMATION_DURATION",
  };
  return first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "12");
}

static double hover_timeout_value(void) {
  static const char *const names[] = {
    "BARISTA_HOVER_TIMEOUT",
    "POPUP_HOVER_TIMEOUT",
    "SUBMENU_HOVER_TIMEOUT",
  };
  const char *value = first_nonempty_env(names, sizeof(names) / sizeof(names[0]), "0.55");
  return atof(value);
}

static int run_sketchybar_set(const char *name, const char *const props[], size_t prop_count, int animate) {
  if (!name || !props || prop_count == 0) return -1;

  char *argv[16];
  size_t argc = 0;
  argv[argc++] = (char *)sketchybar_bin();
  if (animate) {
    argv[argc++] = "--animate";
    argv[argc++] = (char *)animation_curve();
    argv[argc++] = (char *)animation_duration();
  }
  argv[argc++] = "--set";
  argv[argc++] = (char *)name;
  for (size_t i = 0; i < prop_count && argc + 1 < (sizeof(argv) / sizeof(argv[0])); i++) {
    argv[argc++] = (char *)props[i];
  }
  argv[argc] = NULL;
  return run_process(argv);
}

static void animate_set_item(const char *name, const char *const props[], size_t prop_count) {
  if (!name || !props || prop_count == 0) return;
  if (atoi(animation_duration()) <= 0) {
    run_sketchybar_set(name, props, prop_count, 0);
    return;
  }
  int status = run_sketchybar_set(name, props, prop_count, 1);
  if (status != 0 && status != 124) {
    run_sketchybar_set(name, props, prop_count, 0);
  }
}

static void clear_highlight(const char *name) {
  char drawing_prop[64];
  char border_width_prop[64];
  char border_color_prop[64];
  char color_prop[64];
  snprintf(drawing_prop, sizeof(drawing_prop), "background.drawing=%s", idle_drawing());
  snprintf(border_width_prop, sizeof(border_width_prop), "background.border_width=%s", idle_border_width());
  snprintf(border_color_prop, sizeof(border_color_prop), "background.border_color=%s", idle_border_color());
  snprintf(color_prop, sizeof(color_prop), "background.color=%s", idle_color());
  const char *props[] = {
    drawing_prop,
    border_width_prop,
    border_color_prop,
    color_prop,
  };
  animate_set_item(name, props, 4);
}

static void close_popup_and_clear(const char *name) {
  char drawing_prop[64];
  char border_width_prop[64];
  char border_color_prop[64];
  char color_prop[64];
  snprintf(drawing_prop, sizeof(drawing_prop), "background.drawing=%s", idle_drawing());
  snprintf(border_width_prop, sizeof(border_width_prop), "background.border_width=%s", idle_border_width());
  snprintf(border_color_prop, sizeof(border_color_prop), "background.border_color=%s", idle_border_color());
  snprintf(color_prop, sizeof(color_prop), "background.color=%s", idle_color());
  const char *props[] = {
    "popup.drawing=off",
    drawing_prop,
    border_width_prop,
    border_color_prop,
    color_prop,
  };
  run_sketchybar_set(name, props, 5, 0);
}

static void write_token(const char *token) {
  FILE *fp = fopen(state_path, "w");
  if (!fp) return;
  fputs(token, fp);
  fclose(fp);
}

static void write_event_token(char *token, size_t size) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  snprintf(token, size, "%lld%06ld-%ld", (long long)tv.tv_sec,
           (long)tv.tv_usec, (long)getpid());
  write_token(token);
}

static int read_token(char *buffer, size_t size) {
  FILE *fp = fopen(state_path, "r");
  if (!fp) return 0;
  if (!fgets(buffer, (int)size, fp)) {
    fclose(fp);
    return 0;
  }
  buffer[strcspn(buffer, "\n")] = '\0';
  fclose(fp);
  return 1;
}

static int parent_matches(const char *name) {
  FILE *fp = fopen(parent_state_path, "r");
  if (!fp) return 0;
  char buffer[256];
  if (!fgets(buffer, sizeof(buffer), fp)) {
    fclose(fp);
    return 0;
  }
  buffer[strcspn(buffer, "\n")] = '\0';
  fclose(fp);
  return strcmp(buffer, name) == 0;
}

static void schedule_close(const char *name, const char *token) {
  if (CLOSE_DELAY <= 0.0) {
    close_popup_and_clear(name);
    return;
  }
  pid_t pid = fork();
  if (pid != 0) return;
  release_hover_lock();
  usleep((useconds_t)(CLOSE_DELAY * 1000000.0));
  if (!acquire_hover_lock(0)) _exit(0);
  char current[256];
  if (read_token(current, sizeof(current)) && strcmp(current, token) == 0) {
    close_popup_and_clear(name);
  }
  _exit(0);
}

static void schedule_highlight_clear(const char *name, const char *token) {
  if (HOVER_TIMEOUT <= 0.0) return;
  pid_t pid = fork();
  if (pid != 0) return;
  release_hover_lock();
  usleep((useconds_t)(HOVER_TIMEOUT * 1000000.0));
  if (!acquire_hover_lock(0)) _exit(0);
  char current[256];
  if (read_token(current, sizeof(current)) && strcmp(current, token) == 0) {
    clear_highlight(name);
  }
  _exit(0);
}

int main(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  snprintf(state_dir, sizeof(state_dir), "%s/sketchybar_popup_state", tmpdir);
  ensure_dir(state_dir);
  snprintf(parent_state_path, sizeof(parent_state_path), "%s/active_parent", state_dir);

  const char *delay_env = getenv("POPUP_CLOSE_DELAY");
  if (delay_env && delay_env[0] != '\0') {
    double parsed = atof(delay_env);
    if (parsed >= 0.0) CLOSE_DELAY = parsed;
  }
  HOVER_TIMEOUT = hover_timeout_value();
  const char *open_env = getenv("POPUP_OPEN_ON_ENTER");
  if (open_env && strcmp(open_env, "1") == 0) {
    OPEN_ON_ENTER = 1;
  }

  const char *name = getenv("NAME");
  if (!name || name[0] == '\0') {
    return 0;
  }
  set_state_path(name);
  const char *sender = getenv("SENDER");
  if (sender && strcmp(sender, "mouse.entered") != 0
      && strcmp(sender, "mouse.exited") != 0
      && strcmp(sender, "mouse.exited.global") != 0) return 0;
  if (!acquire_hover_lock(1200)) return 0;
  // A shell event and a native event share one lock; cancel the other backend's
  // generation before applying this event so old timers cannot cross a reload.
  unlink(hover_state_path);
  unlink(shell_popup_state_path);

  if (!sender || strcmp(sender, "mouse.entered") == 0) {
    char token[64];
    char color_prop[64];
    char border_width_prop[64];
    char border_color_prop[64];
    const char *props[5];
    size_t prop_count = 2;
    write_event_token(token, sizeof(token));
    snprintf(color_prop, sizeof(color_prop), "background.color=%s", hover_color());
    props[0] = "background.drawing=on";
    props[1] = color_prop;
    if (hover_border_width()[0] != '\0') {
      snprintf(border_width_prop, sizeof(border_width_prop), "background.border_width=%s", hover_border_width());
      snprintf(border_color_prop, sizeof(border_color_prop), "background.border_color=%s", hover_border_color());
      props[prop_count++] = border_width_prop;
      props[prop_count++] = border_color_prop;
    }
    if (OPEN_ON_ENTER) props[prop_count++] = "popup.drawing=on";
    animate_set_item(name, props, prop_count);
    schedule_highlight_clear(name, token);
    return 0;
  }

  if (strcmp(sender, "mouse.exited") == 0) {
    char token[64];
    // Invalidate the enter timer while retaining state for a later global exit.
    write_event_token(token, sizeof(token));
    clear_highlight(name);
    return 0;
  }

  if (strcmp(sender, "mouse.exited.global") == 0) {
    if (parent_matches(name)) {
      return 0;
    }
    char token[256];
    if (!read_token(token, sizeof(token))) return 0;
    write_event_token(token, sizeof(token));
    if (CLOSE_DELAY <= 0.0) {
      close_popup_and_clear(name);
    } else {
      clear_highlight(name);
      schedule_close(name, token);
    }
    return 0;
  }

  return 0;
}
