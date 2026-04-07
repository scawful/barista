#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <signal.h>
#import <unistd.h>

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int signum) {
  (void)signum;
  keep_running = 0;
}

static NSString *sanitize_value(NSString *value) {
  if (value == nil) {
    return @"";
  }
  return [[[value stringByReplacingOccurrencesOfString:@"\t" withString:@" "]
      stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
      stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
}

static NSString *env_value(NSString *key) {
  NSString *value = NSProcessInfo.processInfo.environment[key];
  return value.length > 0 ? value : nil;
}

static NSString *default_config_dir(void) {
  NSString *configDir = env_value(@"BARISTA_CONFIG_DIR");
  if (configDir.length > 0) {
    return configDir;
  }
  configDir = env_value(@"CONFIG_DIR");
  if (configDir.length > 0) {
    return configDir;
  }
  NSString *home = NSHomeDirectory();
  return [home stringByAppendingPathComponent:@".config/sketchybar"];
}

static NSString *state_dir(void) {
  NSString *custom = env_value(@"BARISTA_RUNTIME_CONTEXT_DIR");
  if (custom.length > 0) {
    return custom;
  }
  return [[default_config_dir() stringByAppendingPathComponent:@"cache"] stringByAppendingPathComponent:@"runtime_context"];
}

static NSString *front_app_file(void) {
  return [state_dir() stringByAppendingPathComponent:@"front_app.tsv"];
}

static NSString *yabai_bin(void) {
  NSString *value = env_value(@"BARISTA_YABAI_BIN");
  if (value.length > 0) {
    return value;
  }
  return @"yabai";
}

static NSTimeInterval task_timeout_seconds(void) {
  NSString *value = env_value(@"BARISTA_RUNTIME_CONTEXT_QUERY_TIMEOUT");
  double seconds = value.length > 0 ? value.doubleValue : 1.0;
  if (seconds <= 0.0) {
    seconds = 1.0;
  }
  return seconds;
}

static NSString *run_task(NSString *launchPath, NSArray<NSString *> *arguments) {
  if (launchPath.length == 0) {
    return nil;
  }

  @try {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = launchPath;
    task.arguments = arguments ?: @[];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    [task launch];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:task_timeout_seconds()];
    while (task.isRunning && deadline.timeIntervalSinceNow > 0.0) {
      [NSThread sleepForTimeInterval:0.01];
    }
    if (task.isRunning) {
      [task terminate];
      [NSThread sleepForTimeInterval:0.05];
      if (task.isRunning) {
        kill((pid_t)task.processIdentifier, SIGKILL);
      }
      [task waitUntilExit];
      return nil;
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (data.length == 0 || task.terminationStatus != 0) {
      return nil;
    }

    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

static id parse_json(NSString *json) {
  if (json.length == 0) {
    return nil;
  }
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data.length == 0) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSDictionary *query_object(NSArray<NSString *> *arguments) {
  id value = parse_json(run_task(yabai_bin(), arguments));
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *query_array(NSArray<NSString *> *arguments) {
  id value = parse_json(run_task(yabai_bin(), arguments));
  return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static BOOL bool_value(id value);

static NSNumber *number_value(id value) {
  return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static BOOL bool_value(id value) {
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSString *string_value(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  return nil;
}

static NSArray *all_space_records(void) {
  return query_array(@[@"-m", @"query", @"--spaces"]);
}

static NSDictionary *current_space_record_from_array(NSArray *spaces) {
  NSDictionary *firstVisible = nil;

  for (id candidate in spaces) {
    if (![candidate isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *space = (NSDictionary *)candidate;
    if (bool_value(space[@"has-focus"])) {
      return space;
    }
    if (firstVisible == nil && bool_value(space[@"is-visible"])) {
      firstVisible = space;
    }
  }

  return firstVisible;
}

static NSDictionary *space_record_for_index(NSArray *spaces, NSNumber *index) {
  if (index == nil) {
    return nil;
  }

  for (id candidate in spaces) {
    if (![candidate isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *space = (NSDictionary *)candidate;
    NSNumber *candidateIndex = number_value(space[@"index"]);
    if (candidateIndex != nil && [candidateIndex isEqualToNumber:index]) {
      return space;
    }
  }

  return nil;
}

static NSString *frontmost_app_name(void) {
  NSString *override = env_value(@"BARISTA_RUNTIME_CONTEXT_FRONT_APP_NAME");
  if (override.length > 0) {
    return override;
  }

  NSRunningApplication *frontmost = NSWorkspace.sharedWorkspace.frontmostApplication;
  NSString *workspaceName = frontmost.localizedName;
  NSDictionary *focusedWindow = query_object(@[@"-m", @"query", @"--windows", @"--window"]);
  NSString *focusedApp = string_value(focusedWindow[@"app"]);
  if (focusedApp.length > 0 && !bool_value(focusedWindow[@"is-minimized"])) {
    if (workspaceName.length > 0 && [focusedApp caseInsensitiveCompare:workspaceName] == NSOrderedSame) {
      return workspaceName;
    }
    return focusedApp;
  }
  if (workspaceName.length > 0) {
    return workspaceName;
  }
  return @"";
}

static NSInteger window_rank(NSDictionary *window, NSString *appName, NSNumber *spaceIndex, NSNumber *displayIndex) {
  NSInteger rank = 0;
  if (![string_value(window[@"app"]) isEqualToString:appName]) {
    rank += 1000;
  }
  if (bool_value(window[@"is-minimized"])) {
    rank += 100;
  }
  if (!bool_value(window[@"has-focus"])) {
    rank += 10;
  }
  if (spaceIndex && ![number_value(window[@"space"]) isEqualToNumber:spaceIndex]) {
    rank += 2;
  }
  if (displayIndex && ![number_value(window[@"display"]) isEqualToNumber:displayIndex]) {
    rank += 1;
  }
  rank += [number_value(window[@"id"]) integerValue];
  return rank;
}

static NSDictionary *select_matching_window(NSString *appName, NSNumber *spaceIndex, NSNumber *displayIndex) {
  if (appName.length == 0) {
    return nil;
  }

  NSDictionary *focusedWindow = query_object(@[@"-m", @"query", @"--windows", @"--window"]);
  if (focusedWindow && [string_value(focusedWindow[@"app"]) isEqualToString:appName] && !bool_value(focusedWindow[@"is-minimized"])) {
    return focusedWindow;
  }

  NSArray *windows = query_array(@[@"-m", @"query", @"--windows"]);
  NSDictionary *best = nil;
  NSInteger bestRank = NSIntegerMax;
  for (id candidate in windows) {
    if (![candidate isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *window = (NSDictionary *)candidate;
    if (![string_value(window[@"app"]) isEqualToString:appName] || bool_value(window[@"is-minimized"])) {
      continue;
    }
    NSInteger rank = window_rank(window, appName, spaceIndex, displayIndex);
    if (best == nil || rank < bestRank) {
      best = window;
      bestRank = rank;
    }
  }
  return best;
}

static NSDictionary<NSString *, NSString *> *build_front_app_record(void) {
  NSString *appName = frontmost_app_name();
  NSArray *spaces = all_space_records();
  NSDictionary *currentSpace = current_space_record_from_array(spaces);
  NSNumber *spaceIndex = number_value(currentSpace[@"index"]);
  NSNumber *displayIndex = number_value(currentSpace[@"display"]);
  BOOL spaceVisible = bool_value(currentSpace[@"is-visible"]);

  NSString *stateIcon = @"󰋽";
  NSString *stateLabel = @"No managed window";
  NSString *locationLabel = [NSString stringWithFormat:@"Space %@ · Display %@",
                             spaceIndex ? spaceIndex.stringValue : @"?",
                             displayIndex ? displayIndex.stringValue : @"?"];

  NSDictionary *window = select_matching_window(appName, spaceIndex, displayIndex);
  if (window != nil) {
    BOOL floating = bool_value(window[@"is-floating"]);
    BOOL sticky = bool_value(window[@"is-sticky"]);
    BOOL fullscreen = bool_value(window[@"has-fullscreen-zoom"]) || bool_value(window[@"is-native-fullscreen"]);
    NSString *layer = string_value(window[@"layer"]) ?: @"normal";

    if (fullscreen) {
      stateIcon = @"󰊓";
      stateLabel = @"Fullscreen";
    } else if (floating) {
      stateIcon = @"󰒄";
      stateLabel = @"Floating";
    } else {
      stateIcon = @"󰆾";
      stateLabel = @"Tiled";
    }

    NSNumber *windowSpace = number_value(window[@"space"]);
    NSNumber *windowDisplay = number_value(window[@"display"]);
    NSDictionary *windowSpaceRecord = space_record_for_index(spaces, windowSpace ?: spaceIndex);
    NSString *spaceType = string_value(windowSpaceRecord[@"type"]) ?: string_value(currentSpace[@"type"]);

    if (sticky) {
      stateLabel = [stateLabel stringByAppendingString:@" · Sticky"];
    }
    if ([layer isEqualToString:@"above"]) {
      stateLabel = [stateLabel stringByAppendingString:@" · Above"];
    } else if ([layer isEqualToString:@"below"]) {
      stateLabel = [stateLabel stringByAppendingString:@" · Below"];
    }
    if ([spaceType isEqualToString:@"float"]) {
      stateLabel = [stateLabel stringByAppendingString:@" · Float Space"];
    } else if (floating && ([spaceType isEqualToString:@"bsp"] || [spaceType isEqualToString:@"stack"])) {
      stateLabel = [stateLabel stringByAppendingString:@" · Managed Space"];
    }

    if (spaceIndex == nil && windowSpace != nil) {
      spaceIndex = windowSpace;
    }
    if (displayIndex == nil && windowDisplay != nil) {
      displayIndex = windowDisplay;
    }
    if (!spaceVisible && bool_value(window[@"has-focus"])) {
      spaceVisible = YES;
    }
    locationLabel = [NSString stringWithFormat:@"Space %@ · Display %@",
                     windowSpace ? windowSpace.stringValue : (spaceIndex ? spaceIndex.stringValue : @"?"),
                     windowDisplay ? windowDisplay.stringValue : (displayIndex ? displayIndex.stringValue : @"?")];
  }

  return @{
    @"app_name": sanitize_value(appName),
    @"state_icon": sanitize_value(stateIcon),
    @"state_label": sanitize_value(stateLabel),
    @"location_label": sanitize_value(locationLabel),
    @"space_index": sanitize_value(spaceIndex ? spaceIndex.stringValue : @""),
    @"display_index": sanitize_value(displayIndex ? displayIndex.stringValue : @""),
    @"space_visible": spaceVisible ? @"true" : @"false"
  };
}

static NSString *record_to_tsv(NSDictionary<NSString *, NSString *> *record) {
  NSArray<NSString *> *order = @[
    @"app_name",
    @"state_icon",
    @"state_label",
    @"location_label",
    @"space_index",
    @"display_index",
    @"space_visible"
  ];
  NSMutableString *content = [NSMutableString string];
  for (NSString *key in order) {
    [content appendFormat:@"%@\t%@\n", key, sanitize_value(record[key] ?: @"")];
  }
  return content;
}

static BOOL ensure_state_dir(void) {
  NSError *error = nil;
  return [[NSFileManager defaultManager] createDirectoryAtPath:state_dir()
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error];
}

static int refresh_front_app_cache(void) {
  if (!ensure_state_dir()) {
    return 1;
  }

  NSString *content = record_to_tsv(build_front_app_record());
  NSError *error = nil;
  BOOL ok = [content writeToFile:front_app_file() atomically:YES encoding:NSUTF8StringEncoding error:&error];
  return ok ? 0 : 1;
}

static int print_front_app_cache(void) {
  NSString *path = front_app_file();
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data.length == 0 && refresh_front_app_cache() != 0) {
    return 1;
  }

  NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if (content.length == 0) {
    return 1;
  }
  printf("%s", content.UTF8String);
  return 0;
}

static int daemon_loop(void) {
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);

  NSString *intervalText = env_value(@"BARISTA_RUNTIME_CONTEXT_INTERVAL") ?: @"1";
  double intervalSeconds = intervalText.doubleValue;
  if (intervalSeconds <= 0.0) {
    intervalSeconds = 1.0;
  }

  while (keep_running) {
    refresh_front_app_cache();
    useconds_t sleepMicros = (useconds_t)(intervalSeconds * 1000000.0);
    usleep(sleepMicros > 0 ? sleepMicros : 1000000);
  }

  return 0;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "Usage: %s <refresh-front-app|front-app|focused-space|daemon>\n", argv[0]);
      return 1;
    }

    NSString *command = [NSString stringWithUTF8String:argv[1]];
    if ([command isEqualToString:@"refresh-front-app"]) {
      return refresh_front_app_cache();
    }
    if ([command isEqualToString:@"front-app"]) {
      return print_front_app_cache();
    }
    if ([command isEqualToString:@"focused-space"]) {
      if (refresh_front_app_cache() != 0) {
        return 1;
      }
      return print_front_app_cache();
    }
    if ([command isEqualToString:@"daemon"]) {
      return daemon_loop();
    }

    fprintf(stderr, "Unknown command: %s\n", argv[1]);
    return 1;
  }
}
