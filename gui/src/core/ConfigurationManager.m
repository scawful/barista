#import <Cocoa/Cocoa.h>

// MARK: - Configuration Manager (Shared Singleton)

@interface ConfigurationManager : NSObject
@property (copy, nonatomic) NSString *statePath;
@property (copy, nonatomic) NSString *configPath;
@property (copy, nonatomic) NSString *scriptsPath;
@property (copy, nonatomic) NSString *codePath;
@property (strong, nonatomic) NSMutableDictionary *state;
@property (strong, nonatomic) dispatch_block_t reloadWorkItem;

+ (instancetype)sharedManager;
- (BOOL)loadState;
- (BOOL)saveState;
- (id)valueForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath;
- (void)reloadSketchyBar;
- (void)runScript:(NSString *)scriptName arguments:(NSArray *)args;
@end

@implementation ConfigurationManager

+ (instancetype)sharedManager {
  static ConfigurationManager *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[ConfigurationManager alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSString *home = NSHomeDirectory();
    NSString *configOverride = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_CONFIG_DIR"];
    NSString *configPath = [self expandedPath:configOverride];
    if (!configPath.length) {
      configPath = [home stringByAppendingPathComponent:@".config/sketchybar"];
    }
    self.configPath = configPath;
    self.statePath = [configPath stringByAppendingPathComponent:@"state.json"];
    [self loadState];
  }
  return self;
}

- (NSString *)expandedPath:(NSString *)path {
  if (!path.length) {
    return nil;
  }
  if ([path hasPrefix:@"~/"]) {
    return [NSHomeDirectory() stringByAppendingPathComponent:[path substringFromIndex:2]];
  }
  return path;
}

- (NSString *)scriptsOverrideFromState {
  if (![self.state isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id paths = self.state[@"paths"];
  if (![paths isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *override = paths[@"scripts_dir"];
  if (!override.length) {
    override = paths[@"scripts"];
  }
  return [self expandedPath:override];
}

- (NSString *)codeOverrideFromState {
  if (![self.state isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id paths = self.state[@"paths"];
  if (![paths isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *override = paths[@"code_dir"];
  if (!override.length) {
    override = paths[@"code"];
  }
  return [self expandedPath:override];
}

- (BOOL)pathHasScripts:(NSString *)path {
  if (!path.length) {
    return NO;
  }
  BOOL isDir = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
    return YES;
  }
  NSString *probe = [path stringByAppendingPathComponent:@"yabai_control.sh"];
  return [[NSFileManager defaultManager] isExecutableFileAtPath:probe];
}

- (NSString *)resolveScriptsPath {
  NSString *envPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_SCRIPTS_DIR"];
  if (envPath.length) {
    return [self expandedPath:envPath];
  }

  NSString *stateOverride = [self scriptsOverrideFromState];
  if (stateOverride.length) {
    return stateOverride;
  }

  NSString *configScripts = [self.configPath stringByAppendingPathComponent:@"scripts"];
  if ([self pathHasScripts:configScripts]) {
    return configScripts;
  }

  NSString *legacyScripts = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scripts"];
  if ([self pathHasScripts:legacyScripts]) {
    return legacyScripts;
  }

  return configScripts;
}

- (NSString *)resolveCodePath {
  NSString *envPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_CODE_DIR"];
  if (envPath.length) {
    return [self expandedPath:envPath];
  }

  NSString *stateOverride = [self codeOverrideFromState];
  if (stateOverride.length) {
    return stateOverride;
  }

  NSString *srcPath = [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
  BOOL isDir = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:srcPath isDirectory:&isDir] && isDir) {
    return srcPath;
  }

  return srcPath;
}

- (void)refreshPaths {
  self.scriptsPath = [self resolveScriptsPath];
  self.codePath = [self resolveCodePath];
}

- (BOOL)loadState {
  NSData *data = [NSData dataWithContentsOfFile:self.statePath];
  if (!data) {
    self.state = [NSMutableDictionary dictionary];
    [self refreshPaths];
    return NO;
  }

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];

  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    self.state = [NSMutableDictionary dictionary];
    [self refreshPaths];
    return NO;
  }

  self.state = [(NSDictionary *)json mutableCopy];
  [self refreshPaths];
  return YES;
}

- (BOOL)saveState {
  // Atomic write: write to temp file, then rename
  NSString *tempPath = [self.statePath stringByAppendingString:@".tmp"];
  
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:self.state
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:&error];
  if (error || !data) {
    NSLog(@"Failed to serialize state: %@", error);
    return NO;
  }

  if (![data writeToFile:tempPath atomically:YES]) {
    return NO;
  }
  
  // Atomic rename
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm moveItemAtPath:tempPath toPath:self.statePath error:&error]) {
    NSLog(@"Failed to rename temp file: %@", error);
    [fm removeItemAtPath:tempPath error:nil];
    return NO;
  }

  [self refreshPaths];
  return YES;
}

- (id)valueForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue {
  id value = [self.state valueForKeyPath:keyPath];
  return value ?: defaultValue;
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
  if (!keyPath || !value) return;

  NSArray *components = [keyPath componentsSeparatedByString:@"."];
  NSMutableDictionary *current = self.state;

  for (NSInteger i = 0; i < components.count - 1; i++) {
    NSString *key = components[i];
    if (!current[key] || ![current[key] isKindOfClass:[NSDictionary class]]) {
      current[key] = [NSMutableDictionary dictionary];
    }
    current = current[key];
  }

  current[components.lastObject] = value;
  [self saveState];
}

- (void)removeValueForKeyPath:(NSString *)keyPath {
  if (!keyPath) return;

  NSArray *components = [keyPath componentsSeparatedByString:@"."];
  NSMutableDictionary *current = self.state;

  for (NSInteger i = 0; i < components.count - 1; i++) {
    NSString *key = components[i];
    if (!current[key] || ![current[key] isKindOfClass:[NSDictionary class]]) {
      return;
    }
    current = current[key];
  }

  [current removeObjectForKey:components.lastObject];
  [self saveState];
}

- (void)reloadSketchyBar {
  if (self.reloadWorkItem) {
    dispatch_block_cancel(self.reloadWorkItem);
    self.reloadWorkItem = nil;
  }

  __weak typeof(self) weakSelf = self;
  dispatch_block_t work = dispatch_block_create(0, ^{
    system("/opt/homebrew/opt/sketchybar/bin/sketchybar --reload");
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf) {
      strongSelf.reloadWorkItem = nil;
    }
  });
  self.reloadWorkItem = work;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 work);
}

- (void)runScript:(NSString *)scriptName arguments:(NSArray *)args {
  NSString *scriptPath = [self.scriptsPath stringByAppendingPathComponent:scriptName];

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  NSMutableArray *taskArgs = [NSMutableArray arrayWithObject:scriptPath];
  if (args) [taskArgs addObjectsFromArray:args];
  task.arguments = taskArgs;

  @try {
    [task launch];
  } @catch (NSException *exception) {
    NSLog(@"Failed to run script %@: %@", scriptName, exception);
  }
}

@end
