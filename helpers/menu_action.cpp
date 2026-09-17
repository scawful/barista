#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <cmath>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

static double RESET_DELAY = 0.04;
static const char *DEFAULT_HILITE = "0x60cba6f7";
static const size_t MAX_ITEM_LENGTH = 255;
static const size_t MAX_PATH_LENGTH = 4096;
static const size_t MAX_COMMAND_LENGTH = 65535;

static const char* sketchybar_bin(void) {
  const char* val = getenv("BARISTA_SKETCHYBAR_BIN");
  if (val && *val) return val;
  val = getenv("SKETCHYBAR_BIN");
  return (val && *val) ? val : "sketchybar";
}

static bool bounded(const char *value, size_t maximum) {
  return value && strnlen(value, maximum + 1) <= maximum;
}

static int run_argv(const std::vector<std::string>& arguments) {
  if (arguments.empty()) return 1;
  pid_t pid = fork();
  if (pid < 0) return 1;
  if (pid == 0) {
    std::vector<char *> argv;
    argv.reserve(arguments.size() + 1);
    for (const std::string& argument : arguments) {
      argv.push_back(const_cast<char *>(argument.c_str()));
    }
    argv.push_back(nullptr);
    execvp(argv[0], argv.data());
    _exit(127);
  }

  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) return 1;
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static void run_async(const char *command) {
  if (!command || command[0] == '\0' || !bounded(command, MAX_COMMAND_LENGTH)) return;
  pid_t pid = fork();
  if (pid == 0) {
    execl("/bin/bash", "bash", "-lc", command, (char *)NULL);
    _exit(127);
  }
}

static void reset_background_async(const char *item) {
  if (!item || item[0] == '\0') return;
  pid_t pid = fork();
  if (pid == 0) {
    if (RESET_DELAY > 0.0) {
      usleep((useconds_t)(RESET_DELAY * 1000000.0));
    }
    std::vector<std::string> arguments = {
      sketchybar_bin(), "--set", item, "background.drawing=off"
    };
    std::vector<char *> argv;
    for (std::string& argument : arguments) {
      argv.push_back(const_cast<char *>(argument.c_str()));
    }
    argv.push_back(nullptr);
    execvp(argv[0], argv.data());
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
    char *end = nullptr;
    double parsed = strtod(delay_env, &end);
    if (end && *end == '\0' && std::isfinite(parsed) && parsed >= 0.0 && parsed <= 10.0) {
      RESET_DELAY = parsed;
    }
  }

  const char *sbar = sketchybar_bin();
  if (!bounded(item, MAX_ITEM_LENGTH) || !bounded(popup, MAX_ITEM_LENGTH)
      || !bounded(highlight, MAX_ITEM_LENGTH) || !bounded(sbar, MAX_PATH_LENGTH)) {
    return 64;
  }

  std::vector<std::string> sketchybar_arguments = { sbar, "-m" };
  if (item && item[0] != '\0' && popup && popup[0] != '\0') {
    sketchybar_arguments.insert(sketchybar_arguments.end(), {
      "--set", item, "background.drawing=on",
      std::string("background.color=") + highlight,
      "--set", popup, "popup.drawing=off"
    });
  } else if (item && item[0] != '\0') {
    sketchybar_arguments.insert(sketchybar_arguments.end(), {
      "--set", item, "background.drawing=on",
      std::string("background.color=") + highlight
    });
  } else if (popup && popup[0] != '\0') {
    sketchybar_arguments.insert(sketchybar_arguments.end(), {
      "--set", popup, "popup.drawing=off"
    });
  }
  if (sketchybar_arguments.size() > 2) {
    run_argv(sketchybar_arguments);
  }

  run_async(command ? command : "");
  reset_background_async(item);

  return 0;
}
