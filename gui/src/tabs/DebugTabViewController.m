#import "ConfigurationManager.h"
#import "BaristaTabBaseViewController.h"

@interface DebugTabViewController : BaristaTabBaseViewController
@property (strong) NSButton *verboseToggle;
@property (strong) NSButton *hotloadToggle;
@property (strong) NSButton *menuHoverToggle;
@property (strong) NSSlider *refreshSlider;
@property (strong) NSTextField *refreshLabel;
@property (strong) NSTextField *statusLabel;
@end

@implementation DebugTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(28, 34, 34, 34) spacing:20];

  [rootStack addView:[self titleLabel:@"Debug & Diagnostics"] inGravity:NSStackViewGravityTop];
  [rootStack addView:[self helperLabel:@"Keep raw diagnostics contained here. Use these controls when you are validating runtime behavior, debugging menu cache issues, or restarting window-manager helpers."] inGravity:NSStackViewGravityTop];

  NSStackView *runtimeSection = nil;
  NSBox *runtimeBox = [self sectionBoxWithTitle:@"Runtime Toggles"
                                       subtitle:@"Low-level switches for verbose logging, hotload behavior, popup debugging, and refresh cadence."
                                    contentStack:&runtimeSection];
  [rootStack addView:runtimeBox inGravity:NSStackViewGravityTop];
  [runtimeBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.verboseToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.verboseToggle.buttonType = NSButtonTypeSwitch;
  self.verboseToggle.title = @"Verbose logging";
  self.verboseToggle.identifier = @"verbose_logging";
  self.verboseToggle.target = self;
  self.verboseToggle.action = @selector(toggleDebugOption:);
  [runtimeSection addView:self.verboseToggle inGravity:NSStackViewGravityTop];

  self.hotloadToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.hotloadToggle.buttonType = NSButtonTypeSwitch;
  self.hotloadToggle.title = @"Enable hotload";
  self.hotloadToggle.identifier = @"hotload_enabled";
  self.hotloadToggle.target = self;
  self.hotloadToggle.action = @selector(toggleDebugOption:);
  [runtimeSection addView:self.hotloadToggle inGravity:NSStackViewGravityTop];

  self.menuHoverToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.menuHoverToggle.buttonType = NSButtonTypeSwitch;
  self.menuHoverToggle.title = @"Popup hover outline";
  self.menuHoverToggle.identifier = @"popup_debug";
  self.menuHoverToggle.target = self;
  self.menuHoverToggle.action = @selector(toggleDebugOption:);
  [runtimeSection addView:self.menuHoverToggle inGravity:NSStackViewGravityTop];

  NSStackView *refreshRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  refreshRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  refreshRow.spacing = 12;
  [runtimeSection addView:refreshRow inGravity:NSStackViewGravityTop];

  NSTextField *refreshLabel = [self fieldLabel:@"Widget refresh"];
  [refreshRow addView:refreshLabel inGravity:NSStackViewGravityLeading];

  self.refreshSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.refreshSlider.minValue = 100;
  self.refreshSlider.maxValue = 2000;
  self.refreshSlider.target = self;
  self.refreshSlider.action = @selector(refreshChanged:);
  [self.refreshSlider.widthAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
  [refreshRow addView:self.refreshSlider inGravity:NSStackViewGravityLeading];

  self.refreshLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.refreshLabel.editable = NO;
  self.refreshLabel.bezeled = NO;
  self.refreshLabel.backgroundColor = [NSColor clearColor];
  self.refreshLabel.stringValue = @"500 ms";
  [self.refreshLabel.widthAnchor constraintEqualToConstant:80].active = YES;
  [refreshRow addView:self.refreshLabel inGravity:NSStackViewGravityLeading];

  NSStackView *opsSection = nil;
  NSBox *opsBox = [self sectionBoxWithTitle:@"Panel Operations"
                                   subtitle:@"Actions that rebuild, inspect, or clear local runtime state."
                                contentStack:&opsSection];
  [rootStack addView:opsBox inGravity:NSStackViewGravityTop];
  [opsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *opsButtons = [[NSStackView alloc] initWithFrame:NSZeroRect];
  opsButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  opsButtons.spacing = 12;
  [opsSection addView:opsButtons inGravity:NSStackViewGravityTop];

  NSButton *rebuildButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [rebuildButton setButtonType:NSButtonTypeMomentaryPushIn];
  [rebuildButton setBezelStyle:NSBezelStyleRounded];
  rebuildButton.title = @"Rebuild & Reload";
  rebuildButton.target = self;
  rebuildButton.action = @selector(rebuildAndReload:);
  [opsButtons addView:rebuildButton inGravity:NSStackViewGravityLeading];

  NSButton *logsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [logsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [logsButton setBezelStyle:NSBezelStyleRounded];
  logsButton.title = @"Open Logs";
  logsButton.target = self;
  logsButton.action = @selector(openLogs:);
  [opsButtons addView:logsButton inGravity:NSStackViewGravityLeading];

  NSButton *flushButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [flushButton setButtonType:NSButtonTypeMomentaryPushIn];
  [flushButton setBezelStyle:NSBezelStyleRounded];
  flushButton.title = @"Flush Menu Cache";
  flushButton.target = self;
  flushButton.action = @selector(flushMenuCache:);
  [opsButtons addView:flushButton inGravity:NSStackViewGravityLeading];

  NSStackView *wmSection = nil;
  NSBox *wmBox = [self sectionBoxWithTitle:@"Window Manager"
                                  subtitle:@"Run health checks or restart yabai/skhd helpers when the bar and spaces drift out of sync."
                               contentStack:&wmSection];
  [rootStack addView:wmBox inGravity:NSStackViewGravityTop];
  [wmBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *wmButtons = [[NSStackView alloc] initWithFrame:NSZeroRect];
  wmButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  wmButtons.spacing = 12;
  [wmSection addView:wmButtons inGravity:NSStackViewGravityTop];

  NSButton *doctorButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [doctorButton setButtonType:NSButtonTypeMomentaryPushIn];
  [doctorButton setBezelStyle:NSBezelStyleRounded];
  doctorButton.title = @"Run Yabai Doctor";
  doctorButton.target = self;
  doctorButton.action = @selector(runYabaiDoctor:);
  [wmButtons addView:doctorButton inGravity:NSStackViewGravityLeading];

  NSButton *restartYabaiButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [restartYabaiButton setButtonType:NSButtonTypeMomentaryPushIn];
  [restartYabaiButton setBezelStyle:NSBezelStyleRounded];
  restartYabaiButton.title = @"Restart Yabai";
  restartYabaiButton.target = self;
  restartYabaiButton.action = @selector(restartYabai:);
  [wmButtons addView:restartYabaiButton inGravity:NSStackViewGravityLeading];

  NSButton *restartShortcutsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [restartShortcutsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [restartShortcutsButton setBezelStyle:NSBezelStyleRounded];
  restartShortcutsButton.title = @"Restart Shortcuts";
  restartShortcutsButton.target = self;
  restartShortcutsButton.action = @selector(restartShortcuts:);
  [wmButtons addView:restartShortcutsButton inGravity:NSStackViewGravityLeading];

  self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.statusLabel.editable = NO;
  self.statusLabel.bezeled = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.stringValue = @"Ready.";
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  self.statusLabel.textColor = [NSColor secondaryLabelColor];
  [rootStack addView:self.statusLabel inGravity:NSStackViewGravityTop];

  [self loadDebugDefaults];
}

- (void)loadDebugDefaults {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSMutableDictionary *debug = config.state[@"debug"];
  if (!debug) {
    debug = [NSMutableDictionary dictionary];
    config.state[@"debug"] = debug;
  }

  BOOL verbose = [debug[@"verbose_logging"] boolValue];
  BOOL hotload = [debug[@"hotload_enabled"] boolValue];
  BOOL popup = [debug[@"popup_debug"] boolValue];
  double refresh = debug[@"widget_refresh_ms"] ? [debug[@"widget_refresh_ms"] doubleValue] : 500.0;

  self.verboseToggle.state = verbose ? NSControlStateValueOn : NSControlStateValueOff;
  self.hotloadToggle.state = hotload ? NSControlStateValueOn : NSControlStateValueOff;
  self.menuHoverToggle.state = popup ? NSControlStateValueOn : NSControlStateValueOff;
  self.refreshSlider.doubleValue = refresh;
  self.refreshLabel.stringValue = [NSString stringWithFormat:@"%.0f ms", refresh];
}

- (void)toggleDebugOption:(NSButton *)sender {
  if (!sender.identifier) return;
  BOOL enabled = (sender.state == NSControlStateValueOn);
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSMutableDictionary *debug = config.state[@"debug"];
  if (!debug) {
    debug = [NSMutableDictionary dictionary];
    config.state[@"debug"] = debug;
  }
  debug[sender.identifier] = @(enabled);
  [config saveState];
  self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ %@", sender.title, enabled ? @"enabled" : @"disabled"];

  if ([sender.identifier isEqualToString:@"hotload_enabled"]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self.config resolveSketchyBarBinary];
    task.arguments = @[@"--hotload", enabled ? @"on" : @"off"];
    [task launch];
  }
}

- (void)refreshChanged:(id)sender {
  double value = self.refreshSlider.doubleValue;
  self.refreshLabel.stringValue = [NSString stringWithFormat:@"%.0f ms", value];
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSMutableDictionary *debug = config.state[@"debug"];
  if (!debug) {
    debug = [NSMutableDictionary dictionary];
    config.state[@"debug"] = debug;
  }
  debug[@"widget_refresh_ms"] = @(value);
  [config saveState];
}

- (void)rebuildAndReload:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *helpersDir = [config.configPath stringByAppendingPathComponent:@"helpers"];
  NSString *guiDir = [config.configPath stringByAppendingPathComponent:@"gui"];
  NSMutableArray *messages = [NSMutableArray array];

  if ([[NSFileManager defaultManager] fileExistsAtPath:helpersDir]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/make";
    task.arguments = @[@"-C", helpersDir, @"all"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (output.length > 0) [messages addObject:output];
  }

  if ([[NSFileManager defaultManager] fileExistsAtPath:guiDir]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/make";
    task.arguments = @[@"-C", guiDir, @"all"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (output.length > 0) [messages addObject:output];
  }

  [config reloadSketchyBar];
  self.statusLabel.stringValue = [messages componentsJoinedByString:@" • "] ?: @"Rebuild complete.";
}

- (void)openLogs:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *pluginScript = [config.configPath stringByAppendingPathComponent:@"plugins/bar_logs.sh"];
  NSString *legacyScript = [config.scriptsPath stringByAppendingPathComponent:@"bar_logs.sh"];
  NSString *logScript = pluginScript;

  if (![[NSFileManager defaultManager] isExecutableFileAtPath:logScript]) {
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:legacyScript]) {
      logScript = legacyScript;
    } else {
      self.statusLabel.stringValue = @"bar_logs.sh not found in plugins or scripts.";
      return;
    }
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = logScript;
  task.arguments = @[@"sketchybar", @"80"];
  [task launch];
  self.statusLabel.stringValue = @"Streaming logs via bar_logs.sh (check Terminal).";
}

- (NSString *)runTask:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = launchPath;
  task.arguments = arguments;
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  [task launch];
  [task waitUntilExit];
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)runYabaiDoctor:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *script = [config.scriptsPath stringByAppendingPathComponent:@"yabai_control.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    self.statusLabel.stringValue = @"yabai_control.sh not found in scripts directory.";
    return;
  }
  NSString *output = [self runTask:script arguments:@[@"doctor"]];
  NSString *summary = [[output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" • "];
  if (summary.length == 0) {
    summary = @"Yabai doctor completed.";
  }
  if (summary.length > 200) {
    summary = [[summary substringToIndex:200] stringByAppendingString:@"…"];
  }
  self.statusLabel.stringValue = summary;
}

- (void)restartYabai:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *script = [config.scriptsPath stringByAppendingPathComponent:@"yabai_control.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    self.statusLabel.stringValue = @"yabai_control.sh not found in scripts directory.";
    return;
  }
  NSString *output = [self runTask:script arguments:@[@"restart"]];
  self.statusLabel.stringValue = output.length ? output : @"Yabai restarted.";
}

- (void)restartShortcuts:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *script = [config.scriptsPath stringByAppendingPathComponent:@"toggle_yabai_shortcuts.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    self.statusLabel.stringValue = @"toggle_yabai_shortcuts.sh not found in scripts directory.";
    return;
  }
  NSString *output = [self runTask:script arguments:@[@"restart"]];
  self.statusLabel.stringValue = output.length ? output : @"Shortcuts restarted.";
}

- (void)flushMenuCache:(id)sender {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[@"-lc", @"rm -f /tmp/sketchybar_menu_*.cache 2>/dev/null || true"];
  [task launch];
  [task waitUntilExit];
  self.statusLabel.stringValue = @"Cleared cached menu render files.";
}

@end
