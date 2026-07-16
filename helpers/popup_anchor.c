#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <limits.h>
#include <sys/time.h>
#include <sys/wait.h>

static double CLOSE_DELAY = 0.18;
static double HOVER_TIMEOUT = 0.55;
static int OPEN_ON_ENTER = 0;
static char state_dir[PATH_MAX];
static char state_path[PATH_MAX];
static char parent_state_path[PATH_MAX];

static const char *sketchybar_bin(void) {
  const char *value = getenv("BARISTA_SKETCHYBAR_BIN");
  if (value && value[0] != '\0') return value;
  value = getenv("SKETCHYBAR_BIN");
  return value && value[0] != '\0' ? value : "sketchybar";
}

static void ensure_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) == -1) {
    mkdir(path, 0700);
  }
}

static void set_state_path(const char *name) {
  snprintf(state_path, sizeof(state_path), "%s/%s.anchor", state_dir, name ? name : "item");
}

static int run_process(char *const argv[]) {
  pid_t pid = fork();
  if (pid < 0) {
    return -1;
  }
  if (pid == 0) {
    execvp(argv[0], argv);
    _exit(127);
  }

  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    return -1;
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
  if (run_sketchybar_set(name, props, prop_count, 1) != 0) {
    run_sketchybar_set(name, props, prop_count, 0);
  }
}

static void set_popup_visible(const char *name, int visible) {
  const char *props[] = { visible ? "popup.drawing=on" : "popup.drawing=off" };
  run_sketchybar_set(name, props, 1, 0);
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
  pid_t pid = fork();
  if (pid != 0) return;
  usleep((useconds_t)(CLOSE_DELAY * 1000000.0));
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
  usleep((useconds_t)(HOVER_TIMEOUT * 1000000.0));
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

  if (!sender || strcmp(sender, "mouse.entered") == 0) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    char token[64];
    char color_prop[64];
    char border_width_prop[64];
    char border_color_prop[64];
    const char *props[4];
    size_t prop_count = 2;
    snprintf(token, sizeof(token), "%lld%06ld", (long long)tv.tv_sec, (long)tv.tv_usec);
    write_token(token);
    snprintf(color_prop, sizeof(color_prop), "background.color=%s", hover_color());
    props[0] = "background.drawing=on";
    props[1] = color_prop;
    if (hover_border_width()[0] != '\0') {
      snprintf(border_width_prop, sizeof(border_width_prop), "background.border_width=%s", hover_border_width());
      snprintf(border_color_prop, sizeof(border_color_prop), "background.border_color=%s", hover_border_color());
      props[prop_count++] = border_width_prop;
      props[prop_count++] = border_color_prop;
    }
    animate_set_item(name, props, prop_count);
    schedule_highlight_clear(name, token);
    if (OPEN_ON_ENTER) {
      set_popup_visible(name, 1);
    }
    return 0;
  }

  if (strcmp(sender, "mouse.exited") == 0) {
    clear_highlight(name);
    return 0;
  }

  if (strcmp(sender, "mouse.exited.global") == 0) {
    if (parent_matches(name)) {
      return 0;
    }
    char token[256];
    if (!read_token(token, sizeof(token))) {
      return 0;
    }
    clear_highlight(name);
    schedule_close(name, token);
    return 0;
  }

  return 0;
}
