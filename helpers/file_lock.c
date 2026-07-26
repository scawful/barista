#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/file.h>

enum {
  EXIT_USAGE_ERROR = 64,
  EXIT_OS_ERROR = 74,
  EXIT_LOCK_CONTENDED = 75,
};

int main(int argc, char **argv) {
  char *end = NULL;
  long fd_value;

  if (argc != 2) {
    return EXIT_USAGE_ERROR;
  }

  errno = 0;
  fd_value = strtol(argv[1], &end, 10);
  if (errno == ERANGE || end == argv[1] || *end != '\0' || fd_value < 0 ||
      fd_value > INT_MAX) {
    return EXIT_USAGE_ERROR;
  }

  if (flock((int)fd_value, LOCK_EX | LOCK_NB) == 0) {
    return 0;
  }

  if (errno == EWOULDBLOCK || errno == EAGAIN) {
    return EXIT_LOCK_CONTENDED;
  }

  return EXIT_OS_ERROR;
}
