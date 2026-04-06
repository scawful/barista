#import "BaristaTabBaseViewController.h"
#import "BaristaCommandBus.h"
#import "BaristaPanelState.h"
#import "BaristaStyle.h"
#import "ConfigurationManager.h"

@interface AdvancedTabViewController : BaristaTabBaseViewController <NSTextViewDelegate, NSTextFieldDelegate>
@property (strong) NSTextView *jsonEditor;
@property (strong) NSButton *saveButton;
@property (strong) NSButton *reloadButton;
@property (strong) NSTextField *statusLabel;
@property (strong) NSTextField *scriptsField;
@property (strong) NSTextField *scriptsResolvedLabel;
@property (strong) NSTextField *codeField;
@property (strong) NSTextField *codeResolvedLabel;
@property (strong) NSPopUpButton *controlPanelModeSelector;
@property (strong) NSTextField *controlPanelCommandField;
@property (strong) NSPopUpButton *controlPanelWindowModeSelector;
@end

@implementation AdvancedTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(24, 24, 28, 24) spacing:18];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Advanced Settings";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // JSON Editor Section
  NSTextField *editorLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  editorLabel.stringValue = @"RAW STATE JSON";
  editorLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  editorLabel.textColor = [NSColor secondaryLabelColor];
  editorLabel.bordered = NO;
  editorLabel.editable = NO;
  editorLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:editorLabel inGravity:NSStackViewGravityTop];

  NSScrollView *editorScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  editorScroll.hasVerticalScroller = YES;
  editorScroll.autohidesScrollers = YES;
  editorScroll.borderType = NSBezelBorder;
  [editorScroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
  NSLayoutConstraint *preferred = [editorScroll.heightAnchor constraintEqualToConstant:500];
  preferred.priority = NSLayoutPriorityDefaultLow;
  preferred.active = YES;

  self.jsonEditor = [[NSTextView alloc] initWithFrame:NSZeroRect];
  self.jsonEditor.font = [[BaristaStyle sharedStyle] monoFontOfSize:13 weight:NSFontWeightRegular];
  self.jsonEditor.delegate = self;
  self.jsonEditor.minSize = NSMakeSize(0.0, 250);
  self.jsonEditor.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
  self.jsonEditor.verticallyResizable = YES;
  self.jsonEditor.horizontallyResizable = NO;
  self.jsonEditor.autoresizingMask = NSViewWidthSizable;
  editorScroll.documentView = self.jsonEditor;
  [rootStack addView:editorScroll inGravity:NSStackViewGravityTop];
  [editorScroll.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  [self loadJSON];

  // Scripts Path Section
  NSBox *scriptsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  scriptsBox.title = @"Scripts Directory Override";
  [rootStack addView:scriptsBox inGravity:NSStackViewGravityTop];
  [scriptsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *scriptsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  scriptsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  scriptsStack.alignment = NSLayoutAttributeLeading;
  scriptsStack.spacing = 8;
  scriptsStack.edgeInsets = NSEdgeInsetsMake(10, 15, 15, 15);
  scriptsBox.contentView = scriptsStack;

  NSStackView *scriptsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  scriptsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  scriptsRow.spacing = 8;
  [scriptsStack addView:scriptsRow inGravity:NSStackViewGravityTop];

  self.scriptsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.scriptsField.placeholderString = @"Auto (uses ~/.config/sketchybar/scripts)";
  [self.scriptsField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
  [self.scriptsField setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [scriptsRow addView:self.scriptsField inGravity:NSStackViewGravityLeading];

  for (NSString *title in @[@"Apply", @"Auto", @"Open"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title isEqualToString:@"Apply"]) btn.action = @selector(applyScriptsPath:);
    else if ([title isEqualToString:@"Auto"]) btn.action = @selector(resetScriptsPath:);
    else btn.action = @selector(openScriptsFolder:);
    [scriptsRow addView:btn inGravity:NSStackViewGravityLeading];
  }

  self.scriptsResolvedLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.scriptsResolvedLabel.bordered = NO;
  self.scriptsResolvedLabel.editable = NO;
  self.scriptsResolvedLabel.backgroundColor = [NSColor clearColor];
  self.scriptsResolvedLabel.font = [NSFont systemFontOfSize:11];
  self.scriptsResolvedLabel.textColor = [NSColor secondaryLabelColor];
  [scriptsStack addView:self.scriptsResolvedLabel inGravity:NSStackViewGravityTop];

  [self loadScriptsPath];

  // --- Code Directory Override ---
  NSStackView *codeStack = nil;
  NSBox *codeBox = [self sectionBoxWithTitle:@"Code Directory Override"
                                   subtitle:@"Override the default code path used by Barista for project resolution."
                               contentStack:&codeStack];
  [rootStack addView:codeBox inGravity:NSStackViewGravityTop];
  [codeBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.codeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.codeField.placeholderString = @"Auto (uses default code path)";
  self.codeField.delegate = self;
  [self.codeField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
  [self.codeField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [codeStack addView:self.codeField inGravity:NSStackViewGravityTop];

  self.codeResolvedLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.codeResolvedLabel.stringValue = @"Resolved: (loading...)";
  self.codeResolvedLabel.font = [NSFont systemFontOfSize:11];
  self.codeResolvedLabel.textColor = [NSColor secondaryLabelColor];
  self.codeResolvedLabel.bordered = NO;
  self.codeResolvedLabel.editable = NO;
  self.codeResolvedLabel.backgroundColor = [NSColor clearColor];
  [codeStack addView:self.codeResolvedLabel inGravity:NSStackViewGravityTop];

  NSStackView *codeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  codeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  codeRow.spacing = 10;
  for (NSString *title in @[@"Apply", @"Auto", @"Open"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    btn.bezelStyle = NSBezelStyleRounded;
    btn.title = title;
    btn.target = self;
    if ([title isEqualToString:@"Apply"]) btn.action = @selector(applyCodePath:);
    else if ([title isEqualToString:@"Auto"]) btn.action = @selector(resetCodePath:);
    else btn.action = @selector(openCodeFolder:);
    [codeRow addView:btn inGravity:NSStackViewGravityLeading];
  }
  [codeStack addView:codeRow inGravity:NSStackViewGravityTop];

  [self loadCodePath];

  // Control Panel Routing Section
  NSBox *routingBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  routingBox.title = @"Control Panel Implementation";
  [rootStack addView:routingBox inGravity:NSStackViewGravityTop];
  [routingBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *routingStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  routingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  routingStack.alignment = NSLayoutAttributeLeading;
  routingStack.spacing = 12;
  routingStack.edgeInsets = NSEdgeInsetsMake(10, 15, 15, 15);
  routingBox.contentView = routingStack;

  NSStackView *routingRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  routingRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  routingRow.spacing = 12;
  [routingStack addView:routingRow inGravity:NSStackViewGravityTop];

  self.controlPanelModeSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  [self.controlPanelModeSelector addItemsWithTitles:@[@"Native (Cocoa)", @"ImGui (barista_config)", @"Custom Command"]];
  self.controlPanelModeSelector.target = self;
  self.controlPanelModeSelector.action = @selector(controlPanelModeChanged:);
  [self.controlPanelModeSelector.widthAnchor constraintEqualToConstant:220].active = YES;
  [routingRow addView:self.controlPanelModeSelector inGravity:NSStackViewGravityLeading];

  NSButton *openPanelBtn = [[NSButton alloc] initWithFrame:NSZeroRect];
  [openPanelBtn setButtonType:NSButtonTypeMomentaryPushIn];
  [openPanelBtn setBezelStyle:NSBezelStyleRounded];
  openPanelBtn.title = @"Test Launch";
  openPanelBtn.target = self;
  openPanelBtn.action = @selector(openControlPanelNow:);
  [routingRow addView:openPanelBtn inGravity:NSStackViewGravityLeading];

  self.controlPanelCommandField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.controlPanelCommandField.placeholderString = @"Enter custom command...";
  self.controlPanelCommandField.delegate = self;
  [self.controlPanelCommandField setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [routingStack addView:self.controlPanelCommandField inGravity:NSStackViewGravityTop];
  [self.controlPanelCommandField.widthAnchor constraintEqualToAnchor:routingStack.widthAnchor constant:-30].active = YES;

  NSStackView *windowModeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  windowModeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  windowModeRow.spacing = 12;
  [routingStack addView:windowModeRow inGravity:NSStackViewGravityTop];

  NSTextField *windowModeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  windowModeLabel.stringValue = @"Window Mode";
  windowModeLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  windowModeLabel.bordered = NO;
  windowModeLabel.editable = NO;
  windowModeLabel.backgroundColor = [NSColor clearColor];
  [windowModeRow addView:windowModeLabel inGravity:NSStackViewGravityLeading];

  self.controlPanelWindowModeSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  [self.controlPanelWindowModeSelector addItemsWithTitles:@[@"Utility Floating", @"Standard Window"]];
  self.controlPanelWindowModeSelector.target = self;
  self.controlPanelWindowModeSelector.action = @selector(controlPanelWindowModeChanged:);
  [self.controlPanelWindowModeSelector.widthAnchor constraintEqualToConstant:180].active = YES;
  [windowModeRow addView:self.controlPanelWindowModeSelector inGravity:NSStackViewGravityLeading];

  NSTextField *windowModeHint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  windowModeHint.stringValue = @"Utility keeps the panel floating over tiled apps without behaving like an aggressive always-on-top window.";
  windowModeHint.font = [NSFont systemFontOfSize:11];
  windowModeHint.textColor = [NSColor secondaryLabelColor];
  windowModeHint.bordered = NO;
  windowModeHint.editable = NO;
  windowModeHint.backgroundColor = [NSColor clearColor];
  [routingStack addView:windowModeHint inGravity:NSStackViewGravityTop];

  [self loadControlPanelSettings];

  // Footer Action Bar
  NSStackView *footer = [[NSStackView alloc] initWithFrame:NSZeroRect];
  footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  footer.spacing = 12;
  [rootStack addView:footer inGravity:NSStackViewGravityTop];

  for (NSString *title in @[@"Save JSON", @"Reload Disk", @"Open Config", @"Reload Bar"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    btn.target = self;
    if ([title isEqualToString:@"Save JSON"]) btn.action = @selector(saveJSON:);
    else if ([title isEqualToString:@"Reload Disk"]) btn.action = @selector(reloadJSON:);
    else if ([title isEqualToString:@"Open Config"]) btn.action = @selector(openConfigFolder:);
    else btn.action = @selector(reloadBar:);
    [footer addView:btn inGravity:NSStackViewGravityLeading];
  }

  // Status Label
  self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.statusLabel.stringValue = @"";
  self.statusLabel.bordered = NO;
  self.statusLabel.editable = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  [rootStack addView:self.statusLabel inGravity:NSStackViewGravityTop];
}

- (void)loadScriptsPath {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *override = [config valueForKeyPath:@"paths.scripts_dir" defaultValue:@""];
  if (![override isKindOfClass:[NSString class]]) {
    override = @"";
  }
  self.scriptsField.stringValue = override;
  self.scriptsResolvedLabel.stringValue = [NSString stringWithFormat:@"Resolved: %@", config.scriptsPath ?: @"(unknown)"];
}

- (void)loadCodePath {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *override = [config valueForKeyPath:@"paths.code_dir" defaultValue:@""];
  if (![override isKindOfClass:[NSString class]] || override.length == 0) {
    override = [config valueForKeyPath:@"paths.code" defaultValue:@""];
  }
  if (![override isKindOfClass:[NSString class]]) {
    override = @"";
  }
  self.codeField.stringValue = override;
  self.codeResolvedLabel.stringValue = [NSString stringWithFormat:@"Resolved: %@", config.codePath ?: @"(unknown)"];
}

- (void)loadJSON {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config loadState];

  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config.state
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:&error];
  if (!error && jsonData) {
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    self.jsonEditor.string = jsonString;
  } else {
    self.jsonEditor.string = @"{}";
  }
}

- (void)saveJSON:(id)sender {
  NSString *jsonString = self.jsonEditor.string;

  NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  id parsedJSON = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];

  if (error || ![parsedJSON isKindOfClass:[NSDictionary class]]) {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"❌ Invalid JSON: %@", error.localizedDescription];
    self.statusLabel.textColor = [NSColor systemRedColor];
    NSBeep();
    return;
  }

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  config.state = [parsedJSON mutableCopy];

  if ([config saveState]) {
    self.statusLabel.stringValue = @"✓ Saved successfully";
    self.statusLabel.textColor = [NSColor systemGreenColor];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      self.statusLabel.stringValue = @"";
    });
  } else {
    self.statusLabel.stringValue = @"❌ Failed to save";
    self.statusLabel.textColor = [NSColor systemRedColor];
  }
}

- (void)reloadJSON:(id)sender {
  [self loadJSON];
  self.statusLabel.stringValue = @"✓ Reloaded from disk";
  self.statusLabel.textColor = [NSColor systemGreenColor];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.statusLabel.stringValue = @"";
  });
}

- (void)openConfigFolder:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:config.configPath]];
}

- (void)openMenuData:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *path = [config.configPath stringByAppendingPathComponent:@"data"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)loadControlPanelSettings {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BaristaPanelState *panelState = [BaristaPanelState sharedState];
  NSString *preferred = [config valueForKeyPath:@"control_panel.preferred" defaultValue:@"native"];
  NSString *command = [config valueForKeyPath:@"control_panel.command" defaultValue:@""];

  NSInteger index = 0;
  if ([preferred isEqualToString:@"imgui"]) {
    index = 1;
  } else if ([preferred isEqualToString:@"custom"]) {
    index = 2;
  }
  [self.controlPanelModeSelector selectItemAtIndex:index];
  self.controlPanelCommandField.stringValue = command ?: @"";
  [self.controlPanelWindowModeSelector selectItemAtIndex:[[panelState windowMode] isEqualToString:@"standard"] ? 1 : 0];
  [self updateControlPanelCommandField];
}

- (void)updateControlPanelCommandField {
  BOOL custom = self.controlPanelModeSelector.indexOfSelectedItem == 2;
  self.controlPanelCommandField.enabled = custom;
  self.controlPanelCommandField.textColor = custom ? [NSColor labelColor] : [NSColor secondaryLabelColor];
}

- (void)controlPanelModeChanged:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSInteger index = self.controlPanelModeSelector.indexOfSelectedItem;
  NSString *value = @"native";
  if (index == 1) {
    value = @"imgui";
  } else if (index == 2) {
    value = @"custom";
  }
  [config setValue:value forKeyPath:@"control_panel.preferred"];
  [self updateControlPanelCommandField];
}

- (void)controlPanelCommandChanged:(id)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *command = self.controlPanelCommandField.stringValue ?: @"";
  NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    [config removeValueForKeyPath:@"control_panel.command"];
    return;
  }
  [config setValue:trimmed forKeyPath:@"control_panel.command"];
}

- (void)controlPanelWindowModeChanged:(id)sender {
  (void)sender;
  NSString *mode = self.controlPanelWindowModeSelector.indexOfSelectedItem == 1 ? @"standard" : @"utility";
  [[BaristaPanelState sharedState] setWindowMode:mode];
  self.statusLabel.stringValue = @"✓ Window mode saved (reopen panel to apply)";
  self.statusLabel.textColor = [NSColor systemGreenColor];
}

- (void)openControlPanelNow:(id)sender {
  (void)sender;
  NSError *error = nil;
  if (![[BaristaCommandBus sharedBus] openControlPanelForTab:nil error:&error]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Control Panel Launch Failed";
    alert.informativeText = error.localizedDescription ?: @"Unable to launch control panel.";
    [alert runModal];
  } else {
    self.statusLabel.stringValue = @"✓ Control panel launch requested";
    self.statusLabel.textColor = [NSColor systemGreenColor];
  }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
  NSTextField *field = notification.object;
  if (field == self.controlPanelCommandField) {
    [self controlPanelCommandChanged:field];
  }
}

- (void)applyScriptsPath:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *value = [self.scriptsField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (value.length == 0) {
    [config removeValueForKeyPath:@"paths.scripts_dir"];
  } else {
    [config setValue:value forKeyPath:@"paths.scripts_dir"];
  }
  [config refreshPaths];
  self.scriptsResolvedLabel.stringValue = [NSString stringWithFormat:@"Resolved: %@", config.scriptsPath ?: @"(unknown)"];
  self.statusLabel.stringValue = @"✓ Scripts path saved (reload bar to apply)";
  self.statusLabel.textColor = [NSColor systemGreenColor];
}

- (void)resetScriptsPath:(id)sender {
  self.scriptsField.stringValue = @"";
  [self applyScriptsPath:sender];
}

- (void)openScriptsFolder:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (!config.scriptsPath) {
    return;
  }
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:config.scriptsPath]];
}

- (void)applyCodePath:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *value = [self.codeField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (value.length == 0) {
    [config removeValueForKeyPath:@"paths.code_dir"];
    [config removeValueForKeyPath:@"paths.code"];
  } else {
    [config setValue:value forKeyPath:@"paths.code_dir"];
  }
  [config refreshPaths];
  self.codeResolvedLabel.stringValue = [NSString stringWithFormat:@"Resolved: %@", config.codePath ?: @"(unknown)"];
  self.statusLabel.stringValue = @"✓ Code path saved (reload bar to apply)";
  self.statusLabel.textColor = [NSColor systemGreenColor];
}

- (void)resetCodePath:(id)sender {
  self.codeField.stringValue = @"";
  [self applyCodePath:sender];
}

- (void)openCodeFolder:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (!config.codePath) {
    return;
  }
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:config.codePath]];
}

- (void)reloadBar:(id)sender {
  (void)sender;
  [[BaristaCommandBus sharedBus] reloadSketchyBar];

  self.statusLabel.stringValue = @"✓ Sketchybar reloading...";
  self.statusLabel.textColor = [NSColor systemGreenColor];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.statusLabel.stringValue = @"";
  });
}

@end
