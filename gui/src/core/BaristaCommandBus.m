#import "BaristaCommandBus.h"

#import "ConfigurationManager.h"

@implementation BaristaCommandBus

- (BOOL)launchConfigScript:(NSString *)relativePath arguments:(NSArray<NSString *> *)arguments error:(NSError **)error {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *scriptPath = [config.configPath stringByAppendingPathComponent:relativePath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:scriptPath]) {
    if (error) {
      *error = [NSError errorWithDomain:@"BaristaCommandBus"
                                   code:404
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected executable at: %@", scriptPath]}];
    }
    return NO;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  NSMutableArray<NSString *> *taskArguments = [NSMutableArray arrayWithObject:scriptPath];
  [taskArguments addObjectsFromArray:arguments ?: @[]];
  task.arguments = taskArguments;

  @try {
    [task launch];
    return YES;
  } @catch (NSException *exception) {
    if (error) {
      *error = [NSError errorWithDomain:@"BaristaCommandBus"
                                   code:500
                               userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to launch command"}];
    }
    return NO;
  }
}

+ (instancetype)sharedBus {
  static BaristaCommandBus *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[BaristaCommandBus alloc] init];
  });
  return instance;
}

- (void)reloadSketchyBar {
  [[ConfigurationManager sharedManager] reloadSketchyBar];
}

- (void)runScriptNamed:(NSString *)scriptName arguments:(NSArray<NSString *> *)arguments {
  [[ConfigurationManager sharedManager] runScript:scriptName arguments:arguments ?: @[]];
}

- (BOOL)openControlPanelForTab:(NSString *)tabIdentifier error:(NSError **)error {
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  if ([tabIdentifier isKindOfClass:[NSString class]] && tabIdentifier.length > 0) {
    [arguments addObjectsFromArray:@[@"--tab", tabIdentifier]];
  }
  return [self launchConfigScript:@"bin/open_control_panel.sh" arguments:arguments error:error];
}

- (BOOL)openOracleAgentManagerWithError:(NSError **)error {
  return [self launchConfigScript:@"bin/open_oracle_agent_manager.sh" arguments:nil error:error];
}

@end
