#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/time.h>

int main(void) {
  struct timeval now;

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
