#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface AdvancedTabViewController : NSViewController <NSTextViewDelegate, NSTextFieldDelegate>
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
@end

@implementation AdvancedTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Advanced Settings";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // JSON Editor Label
  NSTextField *editorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 20)];
  editorLabel.stringValue = @"Raw State JSON:";
  editorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  editorLabel.bordered = NO;
  editorLabel.editable = NO;
  editorLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:editorLabel];
  y -= 30;

  // JSON Editor
  CGFloat scrollBottom = 250;
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, scrollBottom, self.view.bounds.size.width - 80, y - scrollBottom)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.jsonEditor = [[NSTextView alloc] initWithFrame:scrollView.bounds];
  self.jsonEditor.font = [NSFont fontWithName:@"SF Mono" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
  self.jsonEditor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.jsonEditor.delegate = self;

  scrollView.documentView = self.jsonEditor;
  [self.view addSubview:scrollView];

  [self loadJSON];

  // Scripts Path
  CGFloat scriptsTop = scrollBottom - 10;
  NSTextField *scriptsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, scriptsTop, 400, 20)];
  scriptsLabel.stringValue = @"Scripts Directory (optional override):";
  scriptsLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  scriptsLabel.bordered = NO;
  scriptsLabel.editable = NO;
  scriptsLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:scriptsLabel];

  self.scriptsField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, scriptsTop - 28, 420, 24)];
  self.scriptsField.placeholderString = @"Auto (uses config/scripts)";
  [self.view addSubview:self.scriptsField];

  NSButton *scriptsApplyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 430, scriptsTop - 30, 70, 26)];
  [scriptsApplyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [scriptsApplyButton setBezelStyle:NSBezelStyleRounded];
  scriptsApplyButton.title = @"Apply";
  scriptsApplyButton.target = self;
  scriptsApplyButton.action = @selector(applyScriptsPath:);
  [self.view addSubview:scriptsApplyButton];

  NSButton *scriptsAutoButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 510, scriptsTop - 30, 80, 26)];
  [scriptsAutoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [scriptsAutoButton setBezelStyle:NSBezelStyleRounded];
  scriptsAutoButton.title = @"Auto";
  scriptsAutoButton.target = self;
  scriptsAutoButton.action = @selector(resetScriptsPath:);
  [self.view addSubview:scriptsAutoButton];

  NSButton *scriptsOpenButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 600, scriptsTop - 30, 120, 26)];
  [scriptsOpenButton setButtonType:NSButtonTypeMomentaryPushIn];
  [scriptsOpenButton setBezelStyle:NSBezelStyleRounded];
  scriptsOpenButton.title = @"Open Folder";
  scriptsOpenButton.target = self;
  scriptsOpenButton.action = @selector(openScriptsFolder:);
  [self.view addSubview:scriptsOpenButton];

  self.scriptsResolvedLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, scriptsTop - 52, 600, 18)];
  self.scriptsResolvedLabel.bordered = NO;
  self.scriptsResolvedLabel.editable = NO;
  self.scriptsResolvedLabel.backgroundColor = [NSColor clearColor];
  self.scriptsResolvedLabel.font = [NSFont systemFontOfSize:11];
  self.scriptsResolvedLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:self.scriptsResolvedLabel];

  [self loadScriptsPath];

  // Code Path
  CGFloat codeTop = scriptsTop - 70;
  NSTextField *codeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, codeTop, 400, 20)];
  codeLabel.stringValue = @"Code Directory (repos + workflows):";
  codeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  codeLabel.bordered = NO;
  codeLabel.editable = NO;
  codeLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:codeLabel];

  self.codeField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, codeTop - 28, 420, 24)];
  self.codeField.placeholderString = @"Auto (uses ~/src)";
  [self.view addSubview:self.codeField];

  NSButton *codeApplyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 430, codeTop - 30, 70, 26)];
  [codeApplyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [codeApplyButton setBezelStyle:NSBezelStyleRounded];
  codeApplyButton.title = @"Apply";
  codeApplyButton.target = self;
  codeApplyButton.action = @selector(applyCodePath:);
  [self.view addSubview:codeApplyButton];

  NSButton *codeAutoButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 510, codeTop - 30, 80, 26)];
  [codeAutoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [codeAutoButton setBezelStyle:NSBezelStyleRounded];
  codeAutoButton.title = @"Auto";
  codeAutoButton.target = self;
  codeAutoButton.action = @selector(resetCodePath:);
  [self.view addSubview:codeAutoButton];

  NSButton *codeOpenButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 600, codeTop - 30, 120, 26)];
  [codeOpenButton setButtonType:NSButtonTypeMomentaryPushIn];
  [codeOpenButton setBezelStyle:NSBezelStyleRounded];
  codeOpenButton.title = @"Open Folder";
  codeOpenButton.target = self;
  codeOpenButton.action = @selector(openCodeFolder:);
  [self.view addSubview:codeOpenButton];

  self.codeResolvedLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, codeTop - 52, 600, 18)];
  self.codeResolvedLabel.bordered = NO;
  self.codeResolvedLabel.editable = NO;
  self.codeResolvedLabel.backgroundColor = [NSColor clearColor];
  self.codeResolvedLabel.font = [NSFont systemFontOfSize:11];
  self.codeResolvedLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:self.codeResolvedLabel];

  [self loadCodePath];

  // Control Panel Routing
  CGFloat controlTop = codeTop - 40;
  NSTextField *controlLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, controlTop, 400, 20)];
  controlLabel.stringValue = @"Control Panel Routing:";
  controlLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  controlLabel.bordered = NO;
  controlLabel.editable = NO;
  controlLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:controlLabel];

  self.controlPanelModeSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin, controlTop - 28, 220, 26)];
  [self.controlPanelModeSelector addItemsWithTitles:@[
    @"Native (Cocoa)",
    @"ImGui (barista_config)",
    @"Custom Command"
  ]];
  self.controlPanelModeSelector.target = self;
  self.controlPanelModeSelector.action = @selector(controlPanelModeChanged:);
  [self.view addSubview:self.controlPanelModeSelector];

  NSButton *openPanelButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 240, controlTop - 30, 140, 28)];
  [openPanelButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openPanelButton setBezelStyle:NSBezelStyleRounded];
  openPanelButton.title = @"Open Panel";
  openPanelButton.target = self;
  openPanelButton.action = @selector(openControlPanelNow:);
  [self.view addSubview:openPanelButton];

  self.controlPanelCommandField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, controlTop - 56, 520, 24)];
  self.controlPanelCommandField.placeholderString = @"Custom command (used when mode = Custom)";
  self.controlPanelCommandField.delegate = self;
  self.controlPanelCommandField.target = self;
  self.controlPanelCommandField.action = @selector(controlPanelCommandChanged:);
  [self.view addSubview:self.controlPanelCommandField];

  [self loadControlPanelSettings];

  // Buttons
  self.saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, 50, 120, 32)];
  [self.saveButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.saveButton setBezelStyle:NSBezelStyleRounded];
  self.saveButton.title = @"Save JSON";
  self.saveButton.target = self;
  self.saveButton.action = @selector(saveJSON:);
  [self.view addSubview:self.saveButton];

  self.reloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 130, 50, 140, 32)];
  [self.reloadButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.reloadButton setBezelStyle:NSBezelStyleRounded];
  self.reloadButton.title = @"Reload from Disk";
  self.reloadButton.target = self;
  self.reloadButton.action = @selector(reloadJSON:);
  [self.view addSubview:self.reloadButton];

  NSButton *openConfigButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 280, 50, 160, 32)];
  [openConfigButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openConfigButton setBezelStyle:NSBezelStyleRounded];
  openConfigButton.title = @"Open Config Folder";
  openConfigButton.target = self;
  openConfigButton.action = @selector(openConfigFolder:);
  [self.view addSubview:openConfigButton];

  NSButton *openMenuDataButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 450, 50, 160, 32)];
  [openMenuDataButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openMenuDataButton setBezelStyle:NSBezelStyleRounded];
  openMenuDataButton.title = @"Open Menu Data";
  openMenuDataButton.target = self;
  openMenuDataButton.action = @selector(openMenuData:);
  [self.view addSubview:openMenuDataButton];

  NSButton *reloadBarButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 620, 50, 140, 32)];
  [reloadBarButton setButtonType:NSButtonTypeMomentaryPushIn];
  [reloadBarButton setBezelStyle:NSBezelStyleRounded];
  reloadBarButton.title = @"Reload Bar";
  reloadBarButton.target = self;
  reloadBarButton.action = @selector(reloadBar:);
  [self.view addSubview:reloadBarButton];

  // Status
  self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, 20, 500, 20)];
  self.statusLabel.stringValue = @"";
  self.statusLabel.bordered = NO;
  self.statusLabel.editable = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  [self.view addSubview:self.statusLabel];

  // System Info
  NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, 10, 600, 8)];
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  infoLabel.stringValue = [NSString stringWithFormat:@"Config: %@ | State: %@ | Code: %@",
                           config.configPath, config.statePath, config.codePath ?: @"(auto)"];
  infoLabel.bordered = NO;
  infoLabel.editable = NO;
  infoLabel.backgroundColor = [NSColor clearColor];
  infoLabel.font = [NSFont systemFontOfSize:9];
  infoLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:infoLabel];
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
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *command = self.controlPanelCommandField.stringValue ?: @"";
  NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    [config removeValueForKeyPath:@"control_panel.command"];
    return;
  }
  [config setValue:trimmed forKeyPath:@"control_panel.command"];
}

- (void)openControlPanelNow:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *script = [config.configPath stringByAppendingPathComponent:@"bin/open_control_panel.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Control Panel Script Missing";
    alert.informativeText = [NSString stringWithFormat:@"Expected executable at: %@", script];
    [alert runModal];
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[script];
  @try {
    [task launch];
  } @catch (NSException *exception) {
    NSLog(@"Failed to launch control panel: %@", exception);
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
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config reloadSketchyBar];

  self.statusLabel.stringValue = @"✓ Sketchybar reloading...";
  self.statusLabel.textColor = [NSColor systemGreenColor];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.statusLabel.stringValue = @"";
  });
}

@end
