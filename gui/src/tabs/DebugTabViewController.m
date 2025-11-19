#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface DebugTabViewController : NSViewController
@property (strong) NSButton *verboseToggle;
@property (strong) NSButton *hotloadToggle;
@property (strong) NSButton *menuHoverToggle;
@property (strong) NSSlider *refreshSlider;
@property (strong) NSTextField *refreshLabel;
@property (strong) NSTextField *statusLabel;
@end

@implementation DebugTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  CGFloat x = 60;
  CGFloat y = 680;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y + 20, 400, 30)];
  title.stringValue = @"Debug & Diagnostics";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 40;

  NSTextField *togglesTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  togglesTitle.stringValue = @"Runtime Toggles";
  togglesTitle.font = [NSFont boldSystemFontOfSize:16];
  togglesTitle.editable = NO;
  togglesTitle.bezeled = NO;
  togglesTitle.backgroundColor = [NSColor clearColor];
  [self.view addSubview:togglesTitle];

  y -= 40;
  self.verboseToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
  self.verboseToggle.buttonType = NSButtonTypeSwitch;
  self.verboseToggle.title = @"Verbose logging";
  self.verboseToggle.identifier = @"verbose_logging";
  self.verboseToggle.target = self;
  self.verboseToggle.action = @selector(toggleDebugOption:);
  [self.view addSubview:self.verboseToggle];

  y -= 30;
  self.hotloadToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
  self.hotloadToggle.buttonType = NSButtonTypeSwitch;
  self.hotloadToggle.title = @"Enable hotload";
  self.hotloadToggle.identifier = @"hotload_enabled";
  self.hotloadToggle.target = self;
  self.hotloadToggle.action = @selector(toggleDebugOption:);
  [self.view addSubview:self.hotloadToggle];

  y -= 30;
  self.menuHoverToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
  self.menuHoverToggle.buttonType = NSButtonTypeSwitch;
  self.menuHoverToggle.title = @"Popup hover outline";
  self.menuHoverToggle.identifier = @"popup_debug";
  self.menuHoverToggle.target = self;
  self.menuHoverToggle.action = @selector(toggleDebugOption:);
  [self.view addSubview:self.menuHoverToggle];

  y -= 60;
  NSTextField *refreshLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 200, 24)];
  refreshLabel.stringValue = @"Widget Refresh (ms):";
  refreshLabel.editable = NO;
  refreshLabel.bezeled = NO;
  refreshLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:refreshLabel];

  self.refreshSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(x + 200, y, 200, 24)];
  self.refreshSlider.minValue = 100;
  self.refreshSlider.maxValue = 2000;
  self.refreshSlider.target = self;
  self.refreshSlider.action = @selector(refreshChanged:);
  [self.view addSubview:self.refreshSlider];

  self.refreshLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 420, y, 80, 24)];
  self.refreshLabel.editable = NO;
  self.refreshLabel.bezeled = NO;
  self.refreshLabel.backgroundColor = [NSColor clearColor];
  self.refreshLabel.stringValue = @"500 ms";
  [self.view addSubview:self.refreshLabel];

  CGFloat buttonY = 320;
  NSButton *rebuildButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 120, 200, 32)];
  [rebuildButton setButtonType:NSButtonTypeMomentaryPushIn];
  [rebuildButton setBezelStyle:NSBezelStyleRounded];
  rebuildButton.title = @"Rebuild & Reload";
  rebuildButton.target = self;
  rebuildButton.action = @selector(rebuildAndReload:);
  [self.view addSubview:rebuildButton];

  NSButton *logsButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 70, 200, 32)];
  [logsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [logsButton setBezelStyle:NSBezelStyleRounded];
  logsButton.title = @"Open Logs";
  logsButton.target = self;
  logsButton.action = @selector(openLogs:);
  [self.view addSubview:logsButton];

  NSButton *flushButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 20, 200, 32)];
  [flushButton setButtonType:NSButtonTypeMomentaryPushIn];
  [flushButton setBezelStyle:NSBezelStyleRounded];
  flushButton.title = @"Flush Menu Cache";
  flushButton.target = self;
  flushButton.action = @selector(flushMenuCache:);
  [self.view addSubview:flushButton];

  self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 180, 900, 24)];
  self.statusLabel.editable = NO;
  self.statusLabel.bezeled = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.stringValue = @"Ready.";
  [self.view addSubview:self.statusLabel];

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
    task.launchPath = @"/opt/homebrew/opt/sketchybar/bin/sketchybar";
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
  NSString *logScript = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scripts/bar_logs.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:logScript]) {
    self.statusLabel.stringValue = @"bar_logs.sh not found in ~/.config/scripts.";
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = logScript;
  task.arguments = @[@"sketchybar", @"80"];
  [task launch];
  self.statusLabel.stringValue = @"Streaming logs via bar_logs.sh (check Terminal).";
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

