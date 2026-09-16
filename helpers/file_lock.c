#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#define _DEFAULT_SOURCE

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/file.h>
#include <time.h>

enum {
  EXIT_USAGE_ERROR = 64,
  EXIT_OS_ERROR = 74,
  EXIT_LOCK_CONTENDED = 75,
  MAX_WAIT_MILLISECONDS = 60000,
  RETRY_INTERVAL_MILLISECONDS = 2,
};

static int64_t monotonic_milliseconds(void) {
  struct timespec timestamp;
  if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0) {
    return -1;
  }
  return (int64_t)timestamp.tv_sec * 1000 + timestamp.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
  char *end = NULL;
  long fd_value;
  long wait_milliseconds = 0;

  if (argc < 2 || argc > 3) {
    return EXIT_USAGE_ERROR;
  }

  errno = 0;
  fd_value = strtol(argv[1], &end, 10);
  if (errno == ERANGE || end == argv[1] || *end != '\0' || fd_value < 0 ||
      fd_value > INT_MAX) {
    return EXIT_USAGE_ERROR;
  }

  if (argc == 3) {
    errno = 0;
    wait_milliseconds = strtol(argv[2], &end, 10);
    if (errno == ERANGE || end == argv[2] || *end != '\0' ||
        wait_milliseconds < 0 || wait_milliseconds > MAX_WAIT_MILLISECONDS) {
      return EXIT_USAGE_ERROR;
    }
  }

  int64_t deadline = 0;
  while (1) {
    if (flock((int)fd_value, LOCK_EX | LOCK_NB) == 0) {
      return 0;
    }
    if (errno != EWOULDBLOCK && errno != EAGAIN) {
      return EXIT_OS_ERROR;
    }
    if (wait_milliseconds == 0) {
      return EXIT_LOCK_CONTENDED;
    }

    int64_t now = monotonic_milliseconds();
    if (now < 0) {
      return EXIT_OS_ERROR;
    }
    if (deadline == 0) {
      deadline = now + wait_milliseconds;
    }
    int64_t remaining = deadline - now;
    if (remaining <= 0) {
      return EXIT_LOCK_CONTENDED;
    }
    if (remaining > RETRY_INTERVAL_MILLISECONDS) {
      remaining = RETRY_INTERVAL_MILLISECONDS;
    }
    struct timespec delay = { .tv_sec = 0, .tv_nsec = remaining * 1000000 };
    if (nanosleep(&delay, NULL) != 0 && errno != EINTR) {
      return EXIT_OS_ERROR;
    }
  }
}
