#import <Foundation/Foundation.h>
#import <limits.h>
#import <unistd.h>

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

static NSData *RunTask(NSString *launchPath,
                       NSArray<NSString *> *arguments,
                       NSTimeInterval timeoutSeconds,
                       int *exitStatus) {
  NSTask *task = [[NSTask alloc] init];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.launchPath = launchPath;
  task.arguments = arguments;
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;

  @try {
    [task launch];
  } @catch (__unused NSException *exception) {
    if (exitStatus != NULL) {
      *exitStatus = 127;
    }
    return nil;
  }

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
  while (task.isRunning && [deadline timeIntervalSinceNow] > 0) {
    usleep(10000);
  }

  if (task.isRunning) {
    [task terminate];
    [task waitUntilExit];
    if (exitStatus != NULL) {
      *exitStatus = 124;
    }
    return nil;
  }

  [task waitUntilExit];
  if (exitStatus != NULL) {
    *exitStatus = task.terminationStatus;
  }
  return [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
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
