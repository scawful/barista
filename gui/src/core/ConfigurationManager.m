#import <Cocoa/Cocoa.h>

// MARK: - Configuration Manager (Shared Singleton)

@interface ConfigurationManager : NSObject
@property (copy, nonatomic) NSString *statePath;
@property (copy, nonatomic) NSString *configPath;
@property (copy, nonatomic) NSString *scriptsPath;
@property (strong, nonatomic) NSMutableDictionary *state;

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
    self.statePath = [home stringByAppendingPathComponent:@".config/sketchybar/state.json"];
    self.configPath = [home stringByAppendingPathComponent:@".config/sketchybar"];
    self.scriptsPath = [home stringByAppendingPathComponent:@".config/scripts"];
    [self loadState];
  }
  return self;
}

- (BOOL)loadState {
  NSData *data = [NSData dataWithContentsOfFile:self.statePath];
  if (!data) {
    self.state = [NSMutableDictionary dictionary];
    return NO;
  }

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];

  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    self.state = [NSMutableDictionary dictionary];
    return NO;
  }

  self.state = [(NSDictionary *)json mutableCopy];
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

- (void)reloadSketchyBar {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    system("/opt/homebrew/opt/sketchybar/bin/sketchybar --reload");
  });
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

