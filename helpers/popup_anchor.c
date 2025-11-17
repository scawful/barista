#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <limits.h>
#include <stdarg.h>
#include <sys/time.h>

static double CLOSE_DELAY = 0.18;
static char state_dir[PATH_MAX];
static char state_path[PATH_MAX];
static char parent_state_path[PATH_MAX];

static void ensure_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) == -1) {
    mkdir(path, 0700);
  }
}

static void set_state_path(const char *name) {
  snprintf(state_path, sizeof(state_path), "%s/%s.anchor", state_dir, name ? name : "item");
}

static void run_cmd(const char *fmt, ...) {
  char buffer[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  system(buffer);
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
    run_cmd("sketchybar --set %s popup.drawing=off", name);
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
    if (parsed > 0.0) CLOSE_DELAY = parsed;
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
    snprintf(token, sizeof(token), "%lld%06ld", (long long)tv.tv_sec, (long long)tv.tv_usec);
    write_token(token);
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
    schedule_close(name, token);
    return 0;
  }

  return 0;
}
