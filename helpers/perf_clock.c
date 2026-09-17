#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>

int main(int argc, char **argv) {
  struct timeval now;

  if (argc > 2 || (argc == 2 && strcmp(argv[1], "ms") != 0)) {
    fprintf(stderr, "usage: perf_clock [ms]\n");
    return 64;
  }

  if (gettimeofday(&now, NULL) != 0) {
    perror("gettimeofday");
    return 1;
  }

  const int64_t milliseconds =
      ((int64_t)now.tv_sec * INT64_C(1000)) + (now.tv_usec / 1000);
  if (printf("%" PRId64 "\n", milliseconds) < 0) {
    return 1;
  }

  return 0;
}
