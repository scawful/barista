#import <Foundation/Foundation.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <poll.h>
#import <signal.h>
#import <spawn.h>
#import <stdint.h>
#import <stdlib.h>
#import <sys/wait.h>
#import <time.h>
#import <unistd.h>

extern char **environ;

static const NSUInteger kMaxTaskOutputBytes = 1024 * 1024;

static NSString *StringFromEnv(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static BOOL IsExecutablePath(NSString *path) {
  if (path.length == 0) {
    return NO;
  }
  return access(path.fileSystemRepresentation, X_OK) == 0;
}

static NSString *YabaiLaunchPath(NSMutableArray<NSString *> **prefixArgs) {
  NSString *envPath = StringFromEnv("BARISTA_YABAI_BIN");
  if (IsExecutablePath(envPath)) {
    return envPath;
  }

  NSArray<NSString *> *candidates = @[
    @"/opt/homebrew/bin/yabai",
    @"/usr/local/bin/yabai",
    @"/usr/bin/yabai"
  ];
  for (NSString *candidate in candidates) {
    if (IsExecutablePath(candidate)) {
      return candidate;
    }
  }

  if (prefixArgs != NULL) {
    *prefixArgs = [NSMutableArray arrayWithObject:@"yabai"];
  }
  return @"/usr/bin/env";
}

static uint64_t MonotonicMilliseconds(void) {
  struct timespec value = {0};
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
    return 0;
  }
  return (uint64_t)value.tv_sec * 1000ULL +
         (uint64_t)value.tv_nsec / 1000000ULL;
}

static BOOL ProcessGroupExists(pid_t child) {
  if (kill(-child, 0) == 0) {
    return YES;
  }
  return errno == EPERM;
}

static void SignalProcessGroup(pid_t child, int signal, BOOL childNeedsReap) {
  if (kill(-child, signal) != 0 && errno == ESRCH && childNeedsReap) {
    kill(child, signal);
  }
}

static void StopAndReapChild(pid_t child,
                             BOOL childNeedsReap,
                             int *status) {
  if (child <= 0) {
    return;
  }

  SignalProcessGroup(child, SIGTERM, childNeedsReap);
  BOOL childReaped = !childNeedsReap;
  uint64_t graceStart = MonotonicMilliseconds();
  while (MonotonicMilliseconds() - graceStart < 25) {
    if (!childReaped) {
      pid_t waited = waitpid(child, status, WNOHANG);
      if (waited == child || (waited < 0 && errno == ECHILD)) {
        childReaped = YES;
      } else if (waited < 0 && errno != EINTR) {
        break;
      }
    }
    if (childReaped && !ProcessGroupExists(child)) {
      return;
    }
    usleep(1000);
  }

  SignalProcessGroup(child, SIGKILL, !childReaped);
  if (!childReaped) {
    while (waitpid(child, status, 0) < 0 && errno == EINTR) {
    }
  }
}

static NSData *RunTask(NSString *launchPath,
                       NSArray<NSString *> *arguments,
                       NSTimeInterval timeoutSeconds,
                       int *exitStatus) {
  if (exitStatus != NULL) {
    *exitStatus = 127;
  }
  if (launchPath.length == 0 || arguments.count > 32 ||
      timeoutSeconds <= 0) {
    return nil;
  }

  const char *path = launchPath.fileSystemRepresentation;
  if (path == NULL || path[0] == '\0') {
    return nil;
  }

  size_t argumentCount = arguments.count;
  char **argv = calloc(argumentCount + 2, sizeof(char *));
  if (argv == NULL) {
    return nil;
  }
  argv[0] = (char *)path;
  for (NSUInteger i = 0; i < argumentCount; i++) {
    const char *value = arguments[i].UTF8String;
    if (value == NULL) {
      free(argv);
      return nil;
    }
    argv[i + 1] = (char *)value;
  }

  int pipeFDs[2] = {-1, -1};
  if (pipe(pipeFDs) != 0) {
    free(argv);
    return nil;
  }
  if (fcntl(pipeFDs[0], F_SETFD, FD_CLOEXEC) != 0 ||
      fcntl(pipeFDs[1], F_SETFD, FD_CLOEXEC) != 0) {
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }
  int readFlags = fcntl(pipeFDs[0], F_GETFL, 0);
  if (readFlags < 0 ||
      fcntl(pipeFDs[0], F_SETFL, readFlags | O_NONBLOCK) != 0) {
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }

  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) {
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }
  int actionError = 0;
  actionError |= posix_spawn_file_actions_addclose(&actions, pipeFDs[0]);
  actionError |= posix_spawn_file_actions_adddup2(&actions, pipeFDs[1],
                                                   STDOUT_FILENO);
  actionError |= posix_spawn_file_actions_addclose(&actions, pipeFDs[1]);
  actionError |= posix_spawn_file_actions_addopen(
      &actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  if (actionError != 0) {
    posix_spawn_file_actions_destroy(&actions);
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }

  posix_spawnattr_t attributes;
  if (posix_spawnattr_init(&attributes) != 0) {
    posix_spawn_file_actions_destroy(&actions);
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }
  short spawnFlags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP;
  if (posix_spawnattr_setpgroup(&attributes, 0) != 0 ||
      posix_spawnattr_setflags(&attributes, spawnFlags) != 0) {
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    free(argv);
    return nil;
  }

  pid_t child = -1;
  int spawnError = posix_spawn(&child, path, &actions, &attributes, argv,
                               environ);
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  close(pipeFDs[1]);
  free(argv);
  if (spawnError != 0) {
    close(pipeFDs[0]);
    return nil;
  }

  int timeoutMilliseconds = (int)(timeoutSeconds * 1000.0);
  if (timeoutMilliseconds < 1) {
    timeoutMilliseconds = 1;
  }
  uint64_t startedAt = MonotonicMilliseconds();
  NSMutableData *output = [NSMutableData data];
  BOOL childDone = NO;
  BOOL eof = NO;
  BOOL timedOut = NO;
  BOOL overflow = NO;
  BOOL ioFailed = NO;
  int childStatus = 0;

  while (!childDone || !eof) {
    uint64_t now = MonotonicMilliseconds();
    uint64_t elapsed = now >= startedAt ? now - startedAt : 0;
    if (elapsed >= (uint64_t)timeoutMilliseconds) {
      timedOut = YES;
      break;
    }
    int remaining = timeoutMilliseconds - (int)elapsed;
    if (remaining > 25) {
      remaining = 25;
    }

    struct pollfd descriptor = {
      .fd = pipeFDs[0],
      .events = POLLIN | POLLHUP,
      .revents = 0,
    };
    int pollResult = poll(&descriptor, 1, remaining);
    if (pollResult < 0 && errno != EINTR) {
      ioFailed = YES;
      break;
    }
    if (pollResult > 0 &&
        (descriptor.revents & (POLLIN | POLLHUP)) != 0) {
      while (YES) {
        uint8_t chunk[4096];
        ssize_t count = read(pipeFDs[0], chunk, sizeof(chunk));
        if (count > 0) {
          if (output.length + (NSUInteger)count > kMaxTaskOutputBytes) {
            overflow = YES;
            break;
          }
          [output appendBytes:chunk length:(NSUInteger)count];
          continue;
        }
        if (count == 0) {
          eof = YES;
        } else if (errno != EAGAIN && errno != EWOULDBLOCK &&
                   errno != EINTR) {
          ioFailed = YES;
          eof = YES;
        }
        break;
      }
    }
    if (pollResult > 0 &&
        (descriptor.revents & (POLLERR | POLLNVAL)) != 0) {
      ioFailed = YES;
    }

    if (!childDone) {
      pid_t waited = waitpid(child, &childStatus, WNOHANG);
      if (waited == child) {
        childDone = YES;
      } else if (waited < 0 && errno != EINTR) {
        ioFailed = YES;
        childDone = YES;
      }
    }
    if (overflow || ioFailed) {
      break;
    }
  }

  if (timedOut || overflow || ioFailed) {
    StopAndReapChild(child, !childDone, &childStatus);
    childDone = YES;
  } else if (!childDone) {
    StopAndReapChild(child, YES, &childStatus);
    childDone = YES;
  }
  close(pipeFDs[0]);

  if (timedOut) {
    if (exitStatus != NULL) {
      *exitStatus = 124;
    }
    return nil;
  }
  if (overflow || ioFailed || !childDone) {
    if (exitStatus != NULL) {
      *exitStatus = 74;
    }
    return nil;
  }

  // A wrapper may exit after spawning a same-group descendant that has
  // already closed stdout. The leader is reaped, but its process group must
  // never escape this bounded synchronous query.
  StopAndReapChild(child, NO, &childStatus);

  if (exitStatus != NULL) {
    if (WIFEXITED(childStatus)) {
      *exitStatus = WEXITSTATUS(childStatus);
    } else if (WIFSIGNALED(childStatus)) {
      *exitStatus = 128 + WTERMSIG(childStatus);
    } else {
      *exitStatus = 1;
    }
  }
  return [output copy];
}

static NSString *SanitizeField(NSString *value) {
  if (value.length == 0) {
    return @"";
  }
  NSMutableString *mutable = [value mutableCopy];
  [mutable replaceOccurrencesOfString:@"\t"
                            withString:@" "
                               options:0
                                 range:NSMakeRange(0, mutable.length)];
  [mutable replaceOccurrencesOfString:@"\n"
                            withString:@" "
                               options:0
                                 range:NSMakeRange(0, mutable.length)];
  return mutable;
}

static NSString *BestAppFromWindowsData(NSData *data) {
  if (data.length == 0) {
    return nil;
  }

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error != nil || ![json isKindOfClass:[NSArray class]]) {
    return nil;
  }

  NSDictionary *bestWindow = nil;
  BOOL bestFocused = NO;
  long long bestID = LLONG_MIN;

  for (id candidate in (NSArray *)json) {
    if (![candidate isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *window = (NSDictionary *)candidate;
    if ([window[@"is-minimized"] respondsToSelector:@selector(boolValue)] &&
        [window[@"is-minimized"] boolValue]) {
      continue;
    }

    NSString *app = [window[@"app"] isKindOfClass:[NSString class]] ? window[@"app"] : nil;
    if (app.length == 0) {
      continue;
    }

    BOOL focused = [window[@"has-focus"] respondsToSelector:@selector(boolValue)] &&
                   [window[@"has-focus"] boolValue];
    long long windowID = [window[@"id"] respondsToSelector:@selector(longLongValue)]
                           ? [window[@"id"] longLongValue]
                           : 0;

    if (bestWindow == nil ||
        (focused && !bestFocused) ||
        (focused == bestFocused && windowID > bestID)) {
      bestWindow = window;
      bestFocused = focused;
      bestID = windowID;
    }
  }

  if (bestWindow == nil) {
    return nil;
  }
  return [bestWindow[@"app"] isKindOfClass:[NSString class]] ? bestWindow[@"app"] : nil;
}

static int PrintVisibleApps(int argc, const char *argv[]) {
  NSMutableArray<NSString *> *prefixArgs = nil;
  NSString *yabai = YabaiLaunchPath(&prefixArgs);
  BOOL hadFailure = NO;

  for (int i = 2; i < argc; i++) {
    NSString *spaceIndex = [NSString stringWithUTF8String:argv[i]];
    if (spaceIndex.length == 0) {
      continue;
    }

    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    if (prefixArgs != nil) {
      [arguments addObjectsFromArray:prefixArgs];
    }
    [arguments addObjectsFromArray:@[@"-m", @"query", @"--windows", @"--space", spaceIndex]];

    int status = 0;
    NSData *data = RunTask(yabai, arguments, 1.0, &status);
    if (status != 0 || data == nil) {
      hadFailure = YES;
      continue;
    }

    NSString *app = BestAppFromWindowsData(data);
    if (app.length > 0) {
      printf("%s\t%s\n", spaceIndex.UTF8String, SanitizeField(app).UTF8String);
    }
  }

  return hadFailure ? 1 : 0;
}

static void PrintUsage(const char *program) {
  fprintf(stderr, "Usage: %s visible-apps <space-index> [space-index...]\n", program);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc >= 2 && strcmp(argv[1], "visible-apps") == 0) {
      return PrintVisibleApps(argc, argv);
    }

    PrintUsage(argv[0]);
    return 64;
  }
}
