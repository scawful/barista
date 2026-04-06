#import "IntegrationsTabViewController.h"
#import "ConfigurationManager.h"
#import "BaristaCommandBus.h"

@interface IntegrationsTabViewController ()
@property (strong) NSScrollView *scrollView;
@property (strong) NSView *contentView;
@property (strong) NSButton *yazeToggle;
@property (strong) NSTextField *yazeStatus;
@property (strong) NSButton *yazeLaunch;
@property (strong) NSButton *emacsToggle;
@property (strong) NSTextField *emacsStatus;
@property (strong) NSButton *emacsLaunch;
@property (strong) NSButton *halextToggle;
@property (strong) NSTextField *halextServerField;
@property (strong) NSSecureTextField *halextApiKeyField;
@property (strong) NSTextField *halextStatus;
@property (strong) NSButton *halextTestButton;
@end

@implementation IntegrationsTabViewController

- (NSString *)codeDir {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (config.codePath.length) {
    return config.codePath;
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
}

- (NSString *)envValue:(NSString *)key {
  return [[[NSProcessInfo processInfo] environment] objectForKey:key];
}

- (NSString *)yazeDir {
  NSString *override = [self envValue:@"BARISTA_YAZE_DIR"];
  if (override.length) {
    return [override stringByExpandingTildeInPath];
  }
  return [[self codeDir] stringByAppendingPathComponent:@"yaze"];
}

- (NSString *)yazeNightlyPrefix {
  NSString *prefix = [self envValue:@"BARISTA_YAZE_NIGHTLY_PREFIX"];
  if (!prefix.length) {
    prefix = [self envValue:@"YAZE_NIGHTLY_PREFIX"];
  }
  if (!prefix.length) {
    prefix = [NSHomeDirectory() stringByAppendingPathComponent:@".local/yaze/nightly"];
  }
  return [prefix stringByExpandingTildeInPath];
}

- (NSString *)resolveCommandPath:(NSString *)command {
  if (![command isKindOfClass:[NSString class]] || command.length == 0) {
    return nil;
  }
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/which";
  task.arguments = @[command];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = [NSPipe pipe];
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    return nil;
  }
  if (task.terminationStatus != 0) {
    return nil;
  }
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return trimmed.length ? trimmed : nil;
}

- (NSString *)resolveYazeLauncher {
  NSString *override = [self envValue:@"BARISTA_YAZE_LAUNCHER"];
  if (!override.length) {
    override = [self envValue:@"YAZE_LAUNCHER"];
  }
  if (override.length) {
    NSString *expanded = [override stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:expanded]) {
      return expanded;
    }
    NSString *resolved = [self resolveCommandPath:override];
    if (resolved.length) {
      return resolved;
    }
  }
  return [self resolveCommandPath:@"yaze-nightly"];
}

- (NSString *)resolveYazeApp {
  NSString *yazeDir = [self yazeDir];
  NSString *nightlyPrefix = [self yazeNightlyPrefix];
  NSString *explicitApp = [self envValue:@"BARISTA_YAZE_APP"];
  if (!explicitApp.length) {
    explicitApp = [self envValue:@"YAZE_APP"];
  }
  NSArray<NSString *> *candidates = @[
    explicitApp ?: @"",
    [nightlyPrefix stringByAppendingPathComponent:@"current/yaze.app"],
    [nightlyPrefix stringByAppendingPathComponent:@"yaze.app"],
    [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Yaze Nightly.app"],
    [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/yaze nightly.app"],
    [NSHomeDirectory() stringByAppendingPathComponent:@"applications/Yaze Nightly.app"],
    [NSHomeDirectory() stringByAppendingPathComponent:@"applications/yaze nightly.app"],
    @"/Applications/Yaze Nightly.app",
    @"/Applications/yaze nightly.app",
    [yazeDir stringByAppendingPathComponent:@"build_ai/bin/Debug/yaze.app"],
    [yazeDir stringByAppendingPathComponent:@"build_ai/bin/Release/yaze.app"],
    [yazeDir stringByAppendingPathComponent:@"build_ai/bin/yaze.app"],
    [yazeDir stringByAppendingPathComponent:@"build/bin/Release/yaze.app"],
    [yazeDir stringByAppendingPathComponent:@"build/bin/Debug/yaze.app"],
    [yazeDir stringByAppendingPathComponent:@"build/bin/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build_ai/bin/Debug/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build_ai/bin/Release/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build_ai/bin/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build/bin/Release/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build/bin/Debug/yaze.app"],
    [[self codeDir] stringByAppendingPathComponent:@"hobby/yaze/build/bin/yaze.app"]
  ];

  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *candidate in candidates) {
    if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0) {
      continue;
    }
    NSString *expanded = [candidate stringByExpandingTildeInPath];
    NSString *binary = [expanded stringByAppendingPathComponent:@"Contents/MacOS/yaze"];
    if ([fm isExecutableFileAtPath:binary]) {
      return expanded;
    }
  }
  return nil;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSStackView *rootStack = nil;
  self.scrollView = [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(28, 34, 34, 34) spacing:22];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"External Integrations";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *subtitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  subtitle.stringValue = @"Keep external tools connected without turning this panel into a second application launcher. Toggle integration presence, verify paths, and jump out when you need the real tool.";
  subtitle.font = [NSFont systemFontOfSize:12.5];
  subtitle.textColor = [NSColor secondaryLabelColor];
  subtitle.bordered = NO;
  subtitle.editable = NO;
  subtitle.backgroundColor = [NSColor clearColor];
  subtitle.usesSingleLineMode = NO;
  subtitle.lineBreakMode = NSLineBreakByWordWrapping;
  [rootStack addView:subtitle inGravity:NSStackViewGravityTop];

  // MARK: Yaze Integration
  NSBox *yazeBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  yazeBox.title = @"Yaze (ROM Hacking Tool)";
  yazeBox.titlePosition = NSAtTop;
  [rootStack addView:yazeBox inGravity:NSStackViewGravityTop];
  [yazeBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *yazeStack = [[NSStackView alloc] initWithFrame:NSInsetRect(yazeBox.bounds, 20, 20)];
  yazeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  yazeStack.alignment = NSLayoutAttributeLeading;
  yazeStack.spacing = 12;
  yazeBox.contentView = yazeStack;

  self.yazeToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.yazeToggle setButtonType:NSButtonTypeSwitch];
  self.yazeToggle.title = @"Enable Yaze Integration";
  self.yazeToggle.target = self;
  self.yazeToggle.action = @selector(yazeToggled:);
  BOOL yazeEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@NO] boolValue];
  self.yazeToggle.state = yazeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [yazeStack addView:self.yazeToggle inGravity:NSStackViewGravityTop];

  self.yazeStatus = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.yazeStatus.stringValue = @"Status: Checking...";
  self.yazeStatus.bordered = NO;
  self.yazeStatus.editable = NO;
  self.yazeStatus.backgroundColor = [NSColor clearColor];
  self.yazeStatus.font = [NSFont systemFontOfSize:13];
  [yazeStack addView:self.yazeStatus inGravity:NSStackViewGravityTop];

  NSStackView *yazeButtons = [[NSStackView alloc] initWithFrame:NSZeroRect];
  yazeButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  yazeButtons.spacing = 12;
  [yazeStack addView:yazeButtons inGravity:NSStackViewGravityTop];

  self.yazeLaunch = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.yazeLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.yazeLaunch setBezelStyle:NSBezelStyleRounded];
  self.yazeLaunch.title = @"Launch Yaze";
  self.yazeLaunch.target = self;
  self.yazeLaunch.action = @selector(launchYaze:);
  [yazeButtons addView:self.yazeLaunch inGravity:NSStackViewGravityLeading];

  NSButton *yazeRepoButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [yazeRepoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [yazeRepoButton setBezelStyle:NSBezelStyleRounded];
  yazeRepoButton.title = @"Open Repo";
  yazeRepoButton.target = self;
  yazeRepoButton.action = @selector(openYazeRepo:);
  [yazeButtons addView:yazeRepoButton inGravity:NSStackViewGravityLeading];

  [self updateYazeStatus];

  // MARK: Emacs Integration
  NSBox *emacsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  emacsBox.title = @"Emacs";
  emacsBox.titlePosition = NSAtTop;
  [rootStack addView:emacsBox inGravity:NSStackViewGravityTop];
  [emacsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *emacsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  emacsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  emacsStack.alignment = NSLayoutAttributeLeading;
  emacsStack.spacing = 12;
  emacsStack.edgeInsets = NSEdgeInsetsMake(15, 20, 15, 20);
  emacsBox.contentView = emacsStack;

  self.emacsToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.emacsToggle setButtonType:NSButtonTypeSwitch];
  self.emacsToggle.title = @"Enable Emacs Integration";
  self.emacsToggle.target = self;
  self.emacsToggle.action = @selector(emacsToggled:);
  BOOL emacsEnabled = [[config valueForKeyPath:@"integrations.emacs.enabled" defaultValue:@NO] boolValue];
  self.emacsToggle.state = emacsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [emacsStack addView:self.emacsToggle inGravity:NSStackViewGravityTop];

  self.emacsStatus = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.emacsStatus.stringValue = @"Status: Checking...";
  self.emacsStatus.bordered = NO;
  self.emacsStatus.editable = NO;
  self.emacsStatus.backgroundColor = [NSColor clearColor];
  self.emacsStatus.font = [NSFont systemFontOfSize:13];
  [emacsStack addView:self.emacsStatus inGravity:NSStackViewGravityTop];

  self.emacsLaunch = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.emacsLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.emacsLaunch setBezelStyle:NSBezelStyleRounded];
  self.emacsLaunch.title = @"Launch Emacs";
  self.emacsLaunch.target = self;
  self.emacsLaunch.action = @selector(launchEmacs:);
  [emacsStack addView:self.emacsLaunch inGravity:NSStackViewGravityTop];

  [self updateEmacsStatus];

  // MARK: halext-org Integration
  NSBox *halextBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  halextBox.title = @"halext-org Server (Tasks, Calendar, LLM)";
  halextBox.titlePosition = NSAtTop;
  [rootStack addView:halextBox inGravity:NSStackViewGravityTop];
  [halextBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *halextStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  halextStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  halextStack.alignment = NSLayoutAttributeLeading;
  halextStack.spacing = 12;
  halextStack.edgeInsets = NSEdgeInsetsMake(15, 20, 15, 20);
  halextBox.contentView = halextStack;

  self.halextToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.halextToggle setButtonType:NSButtonTypeSwitch];
  self.halextToggle.title = @"Enable halext-org Integration";
  self.halextToggle.target = self;
  self.halextToggle.action = @selector(halextToggled:);
  BOOL halextEnabled = [[config valueForKeyPath:@"integrations.halext.enabled" defaultValue:@NO] boolValue];
  self.halextToggle.state = halextEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [halextStack addView:self.halextToggle inGravity:NSStackViewGravityTop];

  NSGridView *halextGrid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  halextGrid.rowSpacing = 8;
  halextGrid.columnSpacing = 12;
  [halextStack addView:halextGrid inGravity:NSStackViewGravityTop];

  NSTextField *serverLabel = [self label:@"Server URL:"];
  self.halextServerField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  [self.halextServerField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
  [self.halextServerField setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.halextServerField.stringValue = [config valueForKeyPath:@"integrations.halext.server_url" defaultValue:@""];
  [halextGrid addRowWithViews:@[serverLabel, self.halextServerField]];

  NSTextField *apiKeyLabel = [self label:@"API Key:"];
  self.halextApiKeyField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
  [self.halextApiKeyField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
  [self.halextApiKeyField setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [halextGrid addRowWithViews:@[apiKeyLabel, self.halextApiKeyField]];

  NSString *savedApiKey = [config valueForKeyPath:@"integrations.halext.api_key" defaultValue:@""];
  if (savedApiKey.length > 0 && ![savedApiKey isEqualToString:@"*** stored in keychain ***"]) {
    self.halextApiKeyField.stringValue = savedApiKey;
  }

  self.halextStatus = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.halextStatus.stringValue = @"Status: Not configured";
  self.halextStatus.bordered = NO;
  self.halextStatus.editable = NO;
  self.halextStatus.backgroundColor = [NSColor clearColor];
  self.halextStatus.font = [NSFont systemFontOfSize:12];
  self.halextStatus.textColor = [NSColor secondaryLabelColor];
  [halextStack addView:self.halextStatus inGravity:NSStackViewGravityTop];

  NSStackView *halextButtons = [[NSStackView alloc] initWithFrame:NSZeroRect];
  halextButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  halextButtons.spacing = 12;
  [halextStack addView:halextButtons inGravity:NSStackViewGravityTop];

  self.halextTestButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.halextTestButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.halextTestButton setBezelStyle:NSBezelStyleRounded];
  self.halextTestButton.title = @"Test Connection";
  self.halextTestButton.target = self;
  self.halextTestButton.action = @selector(testHalextConnection:);
  [halextButtons addView:self.halextTestButton inGravity:NSStackViewGravityLeading];

  NSButton *halextSaveButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [halextSaveButton setButtonType:NSButtonTypeMomentaryPushIn];
  [halextSaveButton setBezelStyle:NSBezelStyleRounded];
  halextSaveButton.title = @"Save Configuration";
  halextSaveButton.target = self;
  halextSaveButton.action = @selector(saveHalextSettings:);
  [halextButtons addView:halextSaveButton inGravity:NSStackViewGravityLeading];

  // MARK: Quick Actions
  NSBox *quickBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  quickBox.title = @"Developer Quick Actions";
  quickBox.titlePosition = NSAtTop;
  [rootStack addView:quickBox inGravity:NSStackViewGravityTop];
  [quickBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *quickStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  quickStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  quickStack.alignment = NSLayoutAttributeLeading;
  quickStack.spacing = 16;
  quickStack.edgeInsets = NSEdgeInsetsMake(15, 20, 15, 20);
  quickBox.contentView = quickStack;

  NSStackView *row1 = [[NSStackView alloc] initWithFrame:NSZeroRect];
  row1.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row1.spacing = 12;
  [quickStack addView:row1 inGravity:NSStackViewGravityTop];

  for (NSString *title in @[@"Open AFS Repo", @"Launch AFS TUI"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title containsString:@"AFS Repo"]) btn.action = @selector(openHafsRepo:);
    else if ([title containsString:@"TUI"]) btn.action = @selector(openHafsTui:);
    [row1 addView:btn inGravity:NSStackViewGravityLeading];
  }

  NSStackView *row2 = [[NSStackView alloc] initWithFrame:NSZeroRect];
  row2.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row2.spacing = 12;
  [quickStack addView:row2 inGravity:NSStackViewGravityTop];

  for (NSString *title in @[@"Open halext-org Repo"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title containsString:@"halext"]) btn.action = @selector(openHalextRepo:);
    [row2 addView:btn inGravity:NSStackViewGravityLeading];
  }
}

- (NSTextField *)label:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text;
  label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  label.alignment = NSTextAlignmentRight;
  return label;
}

- (void)yazeToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.yaze.enabled"];
  [self.commandBus reloadSketchyBar];
}

- (void)emacsToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.emacs.enabled"];
  [self.commandBus reloadSketchyBar];
}

- (void)halextToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.halext.enabled"];
  [self.commandBus reloadSketchyBar];
}


- (void)updateYazeStatus {
  NSString *yazeDir = [self yazeDir];
  NSString *launcher = [self resolveYazeLauncher];
  NSString *appPath = [self resolveYazeApp];

  if (launcher.length || appPath.length) {
    self.yazeStatus.stringValue = @"Status: ✓ Installed and built";
    self.yazeStatus.textColor = [NSColor systemGreenColor];
  } else if ([[NSFileManager defaultManager] fileExistsAtPath:yazeDir]) {
    self.yazeStatus.stringValue = @"Status: ⚠ Installed but not built";
    self.yazeStatus.textColor = [NSColor systemOrangeColor];
  } else {
    self.yazeStatus.stringValue = @"Status: ✗ Not installed";
    self.yazeStatus.textColor = [NSColor systemRedColor];
  }
}

- (void)updateEmacsStatus {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *statusText = @"Status: ✗ Not found";
    NSColor *statusColor = [NSColor systemRedColor];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/pgrep";
    task.arguments = @[@"-x", @"Emacs"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    @try {
      [task launch];
      [task waitUntilExit];
      if (task.terminationStatus == 0) {
        statusText = @"Status: ✓ Running";
        statusColor = [NSColor systemGreenColor];
      } else {
        statusText = @"Status: Installed but not running";
        statusColor = [NSColor secondaryLabelColor];
      }
    } @catch (NSException *exception) {
      statusText = @"Status: ✗ Not found";
      statusColor = [NSColor systemRedColor];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      self.emacsStatus.stringValue = statusText;
      self.emacsStatus.textColor = statusColor;
    });
  });
}

- (void)launchYaze:(id)sender {
  NSString *launcher = [self resolveYazeLauncher];
  if (launcher.length) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launcher;
    task.arguments = @[];
    @try {
      [task launch];
    } @catch (NSException *exception) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = @"Yaze Launch Failed";
      alert.informativeText = @"Failed to launch Yaze via the configured launcher.";
      [alert runModal];
    }
    return;
  }

  NSString *appPath = [self resolveYazeApp];
  if (appPath.length) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:appPath]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    NSString *message = [NSString stringWithFormat:@"Build Yaze first: cd %@ && make", [self yazeDir]];
    [alert setInformativeText:message];
    [alert runModal];
  }
}

- (void)openYazeRepo:(id)sender {
  NSString *yazePath = [self yazeDir];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:yazePath]];
}

- (void)launchEmacs:(id)sender {
  NSArray *emacsLocations = @[
    @"/Applications/Emacs.app",
    @"/opt/homebrew/Cellar/emacs-plus@30/30.0.92/Emacs.app"
  ];

  for (NSString *location in emacsLocations) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:location]) {
      [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:location]];
      return;
    }
  }

  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Emacs Not Found"];
  [alert setInformativeText:@"Install Emacs first"];
  [alert runModal];
}

- (void)openHafsRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"afs"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openHafsTui:(id)sender {
  NSString *command = [NSString stringWithFormat:@"cd %@/afs && python3 -m tui.app", [self codeDir]];
  [self openTerminalCommand:command];
}

- (void)openHalextRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"halext-org"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openTerminalCommand:(NSString *)command {
  NSString *escaped = [command stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\" to do script \"%@\"", escaped];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/osascript";
  task.arguments = @[@"-e", script];
  [task launch];
}

- (void)saveHalextSettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *serverUrl = self.halextServerField.stringValue;
  [config setValue:serverUrl forKeyPath:@"integrations.halext.server_url"];

  NSString *apiKey = self.halextApiKeyField.stringValue;
  if ([apiKey length] > 0) {
    [config setValue:apiKey forKeyPath:@"integrations.halext.api_key"];
  }

  self.halextStatus.stringValue = @"Status: Settings saved";
  self.halextStatus.textColor = [NSColor systemGreenColor];
}

- (void)testHalextConnection:(id)sender {
  NSString *serverUrl = self.halextServerField.stringValue;
  if (!serverUrl.length) {
    self.halextStatus.stringValue = @"Status: No server URL configured";
    self.halextStatus.textColor = [NSColor systemOrangeColor];
    return;
  }
  self.halextStatus.stringValue = @"Status: Testing connection...";
  self.halextStatus.textColor = [NSColor secondaryLabelColor];

  NSURL *url = [NSURL URLWithString:serverUrl];
  if (!url) {
    self.halextStatus.stringValue = @"Status: Invalid URL";
    self.halextStatus.textColor = [NSColor systemRedColor];
    return;
  }
  NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
          self.halextStatus.stringValue = [NSString stringWithFormat:@"Status: Failed - %@", error.localizedDescription];
          self.halextStatus.textColor = [NSColor systemRedColor];
        } else {
          NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
          if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
            self.halextStatus.stringValue = [NSString stringWithFormat:@"Status: Connected (HTTP %ld)", (long)httpResponse.statusCode];
            self.halextStatus.textColor = [NSColor systemGreenColor];
          } else {
            self.halextStatus.stringValue = [NSString stringWithFormat:@"Status: HTTP %ld", (long)httpResponse.statusCode];
            self.halextStatus.textColor = [NSColor systemOrangeColor];
          }
        }
      });
    }];
  [task resume];
}

@end
