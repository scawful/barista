#import "BaristaPanelState.h"

#import "ConfigurationManager.h"

static NSString *const BaristaPanelLastTabKeyPath = @"control_panel.window.last_tab";
static NSString *const BaristaPanelModeKeyPath = @"control_panel.window_mode";
static NSString *const BaristaPanelAutosaveName = @"BaristaControlPanelWindow";

static BOOL BaristaShouldPersistAsGeneralTab(NSString *identifier) {
  return [identifier isKindOfClass:[NSString class]] && identifier.length > 0;
}

@implementation BaristaPanelState

+ (instancetype)sharedState {
  static BaristaPanelState *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[BaristaPanelState alloc] init];
  });
  return instance;
}

- (NSString *)lastSelectedTabIdentifier {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *identifier = [config valueForKeyPath:BaristaPanelLastTabKeyPath defaultValue:nil];
  if (!BaristaShouldPersistAsGeneralTab(identifier)) {
    return nil;
  }
  return identifier;
}

- (void)setLastSelectedTabIdentifier:(NSString *)identifier {
  if (!BaristaShouldPersistAsGeneralTab(identifier)) {
    return;
  }
  [[ConfigurationManager sharedManager] setValue:identifier forKeyPath:BaristaPanelLastTabKeyPath];
}

- (NSString *)windowAutosaveName {
  return BaristaPanelAutosaveName;
}

- (NSString *)windowMode {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *mode = [config valueForKeyPath:BaristaPanelModeKeyPath defaultValue:@"standard"];
  if (![mode isKindOfClass:[NSString class]] || mode.length == 0) {
    return @"standard";
  }
  return [[mode lowercaseString] isEqualToString:@"standard"] ? @"standard" : @"utility";
}

- (void)setWindowMode:(NSString *)windowMode {
  NSString *mode = [[windowMode lowercaseString] isEqualToString:@"standard"] ? @"standard" : @"utility";
  [[ConfigurationManager sharedManager] setValue:mode forKeyPath:BaristaPanelModeKeyPath];
}

- (BOOL)prefersUtilityWindowMode {
  return ![[self windowMode] isEqualToString:@"standard"];
}

@end
