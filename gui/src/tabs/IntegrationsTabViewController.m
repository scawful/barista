#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface IntegrationsTabViewController : NSViewController <NSTextFieldDelegate>
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
@property (strong) NSButton *cortexToggle;
@property (strong) NSButton *cortexWidgetToggle;
@property (strong) NSPopUpButton *cortexLabelModeMenu;
@property (strong) NSTextField *cortexLabelPrefixField;
@property (strong) NSTextField *cortexUpdateFreqField;
@property (strong) NSTextField *cortexCacheTtlField;
@property (strong) NSPopUpButton *cortexPositionMenu;
@property (strong) NSTextField *cortexLabelTemplateField;
@property (strong) NSTextField *cortexActiveIconField;
@property (strong) NSTextField *cortexInactiveIconField;
@property (strong) NSTextField *cortexActiveIconPreview;
@property (strong) NSTextField *cortexInactiveIconPreview;
@property (strong) NSColorWell *cortexActiveColorWell;
@property (strong) NSTextField *cortexActiveColorHexField;
@property (strong) NSColorWell *cortexInactiveColorWell;
@property (strong) NSTextField *cortexInactiveColorHexField;
@property (strong) NSColorWell *cortexLabelColorWell;
@property (strong) NSTextField *cortexLabelColorHexField;
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

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];

  self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.autohidesScrollers = YES;
  self.scrollView.borderType = NSNoBorder;
  self.scrollView.drawsBackground = NO;
  [self.view addSubview:self.scrollView];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 30;
  rootStack.edgeInsets = NSEdgeInsetsMake(30, 40, 40, 40);
  self.scrollView.documentView = rootStack;
  [rootStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor].active = YES;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"External Integrations";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // MARK: Yaze Integration
  NSBox *yazeBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  yazeBox.title = @"Yaze (ROM Hacking Tool)";
  yazeBox.titlePosition = NSAtTop;
  [rootStack addView:yazeBox inGravity:NSStackViewGravityTop];
  [yazeBox.widthAnchor constraintEqualToConstant:700].active = YES;

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
  [emacsBox.widthAnchor constraintEqualToConstant:700].active = YES;

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

  // MARK: Cortex Integration
  NSBox *cortexBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  cortexBox.title = @"Cortex (AFS / Training)";
  cortexBox.titlePosition = NSAtTop;
  [rootStack addView:cortexBox inGravity:NSStackViewGravityTop];
  [cortexBox.widthAnchor constraintEqualToConstant:700].active = YES;

  NSStackView *cortexStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  cortexStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  cortexStack.alignment = NSLayoutAttributeLeading;
  cortexStack.spacing = 16;
  cortexStack.edgeInsets = NSEdgeInsetsMake(15, 20, 15, 20);
  cortexBox.contentView = cortexStack;

  self.cortexToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.cortexToggle setButtonType:NSButtonTypeSwitch];
  self.cortexToggle.title = @"Enable Cortex Integration";
  self.cortexToggle.target = self;
  self.cortexToggle.action = @selector(cortexToggled:);
  BOOL cortexEnabled = [[config valueForKeyPath:@"integrations.cortex.enabled" defaultValue:@NO] boolValue];
  self.cortexToggle.state = cortexEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [cortexStack addView:self.cortexToggle inGravity:NSStackViewGravityTop];

  self.cortexWidgetToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.cortexWidgetToggle setButtonType:NSButtonTypeSwitch];
  self.cortexWidgetToggle.title = @"Show Cortex Widget";
  self.cortexWidgetToggle.target = self;
  self.cortexWidgetToggle.action = @selector(cortexWidgetToggled:);
  BOOL cortexWidgetEnabled = [[config valueForKeyPath:@"integrations.cortex.widget.enabled" defaultValue:@YES] boolValue];
  self.cortexWidgetToggle.state = cortexWidgetEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [cortexStack addView:self.cortexWidgetToggle inGravity:NSStackViewGravityTop];

  NSGridView *cortexGrid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  cortexGrid.rowSpacing = 10;
  cortexGrid.columnSpacing = 12;
  [cortexStack addView:cortexGrid inGravity:NSStackViewGravityTop];

  NSTextField *modeLabel = [self label:@"Label Mode:"];
  self.cortexLabelModeMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  [self.cortexLabelModeMenu addItemsWithTitles:@[@"Training", @"AFS", @"Status", @"None"]];
  self.cortexLabelModeMenu.target = self;
  self.cortexLabelModeMenu.action = @selector(cortexLabelModeChanged:);
  [self.cortexLabelModeMenu.widthAnchor constraintEqualToConstant:180].active = YES;
  NSString *labelMode = [config valueForKeyPath:@"integrations.cortex.widget.label_mode" defaultValue:@"training"];
  [self.cortexLabelModeMenu selectItemAtIndex:([labelMode isEqualToString:@"afs"] ? 1 : ([labelMode isEqualToString:@"status"] ? 2 : ([labelMode isEqualToString:@"none"] ? 3 : 0)))];
  [cortexGrid addRowWithViews:@[modeLabel, self.cortexLabelModeMenu]];

  NSTextField *prefixLabel = [self label:@"Prefix:"];
  self.cortexLabelPrefixField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.cortexLabelPrefixField.placeholderString = @"AFS";
  self.cortexLabelPrefixField.target = self;
  self.cortexLabelPrefixField.action = @selector(cortexFieldChanged:);
  [self.cortexLabelPrefixField.widthAnchor constraintEqualToConstant:180].active = YES;
  self.cortexLabelPrefixField.stringValue = [config valueForKeyPath:@"integrations.cortex.widget.label_prefix" defaultValue:@"AFS"] ?: @"";
  [cortexGrid addRowWithViews:@[prefixLabel, self.cortexLabelPrefixField]];

  NSTextField *freqLabel = [self label:@"Update (sec):"];
  self.cortexUpdateFreqField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.cortexUpdateFreqField.target = self;
  self.cortexUpdateFreqField.action = @selector(cortexFieldChanged:);
  [self.cortexUpdateFreqField.widthAnchor constraintEqualToConstant:80].active = YES;
  self.cortexUpdateFreqField.stringValue = [NSString stringWithFormat:@"%@", [config valueForKeyPath:@"integrations.cortex.widget.update_freq" defaultValue:@180]];
  [cortexGrid addRowWithViews:@[freqLabel, self.cortexUpdateFreqField]];

  NSTextField *cacheLabel = [self label:@"Cache TTL:"];
  self.cortexCacheTtlField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.cortexCacheTtlField.target = self;
  self.cortexCacheTtlField.action = @selector(cortexFieldChanged:);
  [self.cortexCacheTtlField.widthAnchor constraintEqualToConstant:80].active = YES;
  self.cortexCacheTtlField.stringValue = [NSString stringWithFormat:@"%@", [config valueForKeyPath:@"integrations.cortex.widget.cache_ttl" defaultValue:@180]];
  [cortexGrid addRowWithViews:@[cacheLabel, self.cortexCacheTtlField]];

  // MARK: halext-org Integration
  NSBox *halextBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  halextBox.title = @"halext-org Server (Tasks, Calendar, LLM)";
  halextBox.titlePosition = NSAtTop;
  [rootStack addView:halextBox inGravity:NSStackViewGravityTop];
  [halextBox.widthAnchor constraintEqualToConstant:700].active = YES;

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
  [self.halextServerField.widthAnchor constraintEqualToConstant:400].active = YES;
  self.halextServerField.stringValue = [config valueForKeyPath:@"integrations.halext.server_url" defaultValue:@""];
  [halextGrid addRowWithViews:@[serverLabel, self.halextServerField]];

  NSTextField *apiKeyLabel = [self label:@"API Key:"];
  self.halextApiKeyField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
  [self.halextApiKeyField.widthAnchor constraintEqualToConstant:400].active = YES;
  [halextGrid addRowWithViews:@[apiKeyLabel, self.halextApiKeyField]];

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
  [quickBox.widthAnchor constraintEqualToConstant:700].active = YES;

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

  for (NSString *title in @[@"Open AFS Repo", @"Launch AFS TUI", @"Open Cortex Repo"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title containsString:@"AFS Repo"]) btn.action = @selector(openHafsRepo:);
    else if ([title containsString:@"TUI"]) btn.action = @selector(openHafsTui:);
    else btn.action = @selector(openCortexRepo:);
    [row1 addView:btn inGravity:NSStackViewGravityLeading];
  }

  NSStackView *row2 = [[NSStackView alloc] initWithFrame:NSZeroRect];
  row2.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row2.spacing = 12;
  [quickStack addView:row2 inGravity:NSStackViewGravityTop];

  for (NSString *title in @[@"Open halext-org Repo", @"Open Cortex App"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title containsString:@"halext"]) btn.action = @selector(openHalextRepo:);
    else btn.action = @selector(openCortexApp:);
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
}

- (void)emacsToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.emacs.enabled"];
}

- (void)halextToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.halext.enabled"];
}

- (void)cortexToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.cortex.enabled"];
  [config reloadSketchyBar];
}

- (void)cortexWidgetToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.cortex.widget.enabled"];
  [config reloadSketchyBar];
}

- (void)cortexLabelModeChanged:(NSPopUpButton *)sender {
  NSString *mode = @"training";
  switch (sender.indexOfSelectedItem) {
    case 1: mode = @"afs"; break;
    case 2: mode = @"status"; break;
    case 3: mode = @"none"; break;
    default: mode = @"training"; break;
  }
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:mode forKeyPath:@"integrations.cortex.widget.label_mode"];
  [config reloadSketchyBar];
}

- (void)cortexFieldChanged:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexLabelPrefixField) {
    NSString *value = [self.cortexLabelPrefixField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.label_prefix"];
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexUpdateFreqField) {
    NSInteger value = self.cortexUpdateFreqField.integerValue;
    if (value > 0) {
      [config setValue:@(value) forKeyPath:@"integrations.cortex.widget.update_freq"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (sender == self.cortexCacheTtlField) {
    NSInteger value = self.cortexCacheTtlField.integerValue;
    if (value >= 0) {
      [config setValue:@(value) forKeyPath:@"integrations.cortex.widget.cache_ttl"];
      [config reloadSketchyBar];
    }
    return;
  }
}

- (NSFont *)preferredIconFontWithSize:(CGFloat)size {
  NSArray<NSString *> *candidates = @[
    @"Hack Nerd Font",
    @"JetBrainsMono Nerd Font",
    @"FiraCode Nerd Font",
    @"SFMono Nerd Font",
    @"Symbols Nerd Font",
    @"MesloLGS NF"
  ];
  for (NSString *name in candidates) {
    NSFont *font = [NSFont fontWithName:name size:size];
    if (font) {
      return font;
    }
  }
  return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

- (NSColor *)colorFromHexString:(NSString *)hexString {
  if (!hexString || hexString.length < 8) return nil;
  NSString *hex = [hexString hasPrefix:@"0x"] ? [hexString substringFromIndex:2] : hexString;
  if (hex.length != 8) return nil;

  unsigned int alpha, red, green, blue;
  NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(0, 2)]];
  [scanner scanHexInt:&alpha];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(2, 2)]];
  [scanner scanHexInt:&red];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(4, 2)]];
  [scanner scanHexInt:&green];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(6, 2)]];
  [scanner scanHexInt:&blue];

  return [NSColor colorWithCalibratedRed:red/255.0 green:green/255.0 blue:blue/255.0 alpha:alpha/255.0];
}

- (NSString *)hexStringFromColor:(NSColor *)color {
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  return [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];
}

- (void)cortexPositionChanged:(NSPopUpButton *)sender {
  NSString *position = sender.indexOfSelectedItem == 0 ? @"left" : @"right";
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:position forKeyPath:@"integrations.cortex.widget.position"];
  [config reloadSketchyBar];
}

- (void)cortexStyleFieldChanged:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexLabelTemplateField) {
    NSString *value = [self.cortexLabelTemplateField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.label_template"];
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexActiveIconField) {
    NSString *value = [self.cortexActiveIconField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.icon_active"];
    self.cortexActiveIconPreview.stringValue = value ?: @"";
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexInactiveIconField) {
    NSString *value = [self.cortexInactiveIconField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.icon_inactive"];
    self.cortexInactiveIconPreview.stringValue = value ?: @"";
    [config reloadSketchyBar];
    return;
  }
}

- (void)cortexColorChanged:(NSColorWell *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexActiveColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexActiveColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.color_active"];
  } else if (sender == self.cortexInactiveColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexInactiveColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.color_inactive"];
  } else if (sender == self.cortexLabelColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexLabelColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.label_color"];
  }
  [config reloadSketchyBar];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  id field = notification.object;
  if (field == self.cortexActiveIconField) {
    self.cortexActiveIconPreview.stringValue = self.cortexActiveIconField.stringValue ?: @"";
    return;
  }
  if (field == self.cortexInactiveIconField) {
    self.cortexInactiveIconPreview.stringValue = self.cortexInactiveIconField.stringValue ?: @"";
    return;
  }

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (field == self.cortexActiveColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexActiveColorHexField.stringValue];
    if (color) {
      self.cortexActiveColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.color_active"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (field == self.cortexInactiveColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexInactiveColorHexField.stringValue];
    if (color) {
      self.cortexInactiveColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.color_inactive"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (field == self.cortexLabelColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexLabelColorHexField.stringValue];
    if (color) {
      self.cortexLabelColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.label_color"];
      [config reloadSketchyBar];
    }
    return;
  }
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

- (void)openCortexRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"cortex"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openCortexApp:(id)sender {
  NSString *appPath = @"/Applications/Cortex.app";
  if ([[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:appPath]];
  } else {
    NSString *path = [[self codeDir] stringByAppendingPathComponent:@"cortex"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
  }
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
    [config setValue:@"*** stored in keychain ***" forKeyPath:@"integrations.halext.api_key_status"];
  }

  self.halextStatus.stringValue = @"Status: Settings saved";
  self.halextStatus.textColor = [NSColor systemGreenColor];
}

- (void)testHalextConnection:(id)sender {
  self.halextStatus.stringValue = @"Status: Testing connection...";
  self.halextStatus.textColor = [NSColor secondaryLabelColor];

  // TODO: Implement actual REST API test
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.halextStatus.stringValue = @"Status: Connection test not yet implemented";
    self.halextStatus.textColor = [NSColor systemOrangeColor];
  });
}

@end
