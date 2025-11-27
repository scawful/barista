#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface SpacesTabViewController : NSViewController
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconField;
@property (strong) NSTextField *iconPreview;
@property (strong) NSSegmentedControl *modeSelector;
@property (strong) NSButton *applyButton;
@property (strong) NSTextView *unmanagedAppsTextView;
@property (strong) NSSegmentedControl *shortcutToggle;
@property (assign) NSInteger currentSpace;
@end

@implementation SpacesTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.currentSpace = 1;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Space Customization";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // Space Selector
  NSTextField *spaceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 100, 20)];
  spaceLabel.stringValue = @"Space:";
  spaceLabel.bordered = NO;
  spaceLabel.editable = NO;
  spaceLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:spaceLabel];

  self.spaceSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 110, y - 3, 150, 26)];
  for (int i = 1; i <= 10; i++) {
    [self.spaceSelector addItemWithTitle:[NSString stringWithFormat:@"Space %d", i]];
  }
  self.spaceSelector.target = self;
  self.spaceSelector.action = @selector(spaceChanged:);
  [self.view addSubview:self.spaceSelector];
  y -= 60;

  // Icon Section
  NSTextField *iconSectionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 24)];
  iconSectionLabel.stringValue = @"Space Icon";
  iconSectionLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  iconSectionLabel.bordered = NO;
  iconSectionLabel.editable = NO;
  iconSectionLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:iconSectionLabel];
  y -= 40;

  // Icon Preview
  self.iconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 100, 80)];
  self.iconPreview.stringValue = @"󰝚";
  self.iconPreview.font = [NSFont systemFontOfSize:64];
  self.iconPreview.bordered = NO;
  self.iconPreview.editable = NO;
  self.iconPreview.backgroundColor = [NSColor clearColor];
  self.iconPreview.alignment = NSTextAlignmentCenter;
  [self.view addSubview:self.iconPreview];

  // Icon Input
  NSTextField *iconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 120, y + 30, 100, 20)];
  iconLabel.stringValue = @"Glyph:";
  iconLabel.bordered = NO;
  iconLabel.editable = NO;
  iconLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:iconLabel];

  self.iconField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 180, y + 28, 200, 24)];
  self.iconField.placeholderString = @"Enter Nerd Font glyph...";
  self.iconField.target = self;
  self.iconField.action = @selector(iconChanged:);
  [self.view addSubview:self.iconField];

  NSButton *browseIconsButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 390, y + 26, 120, 28)];
  [browseIconsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [browseIconsButton setBezelStyle:NSBezelStyleRounded];
  browseIconsButton.title = @"Browse Icons";
  browseIconsButton.target = self;
  browseIconsButton.action = @selector(browseIcons:);
  [self.view addSubview:browseIconsButton];

  NSButton *clearIconButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 520, y + 26, 80, 28)];
  [clearIconButton setButtonType:NSButtonTypeMomentaryPushIn];
  [clearIconButton setBezelStyle:NSBezelStyleRounded];
  clearIconButton.title = @"Clear";
  clearIconButton.target = self;
  clearIconButton.action = @selector(clearIcon:);
  [self.view addSubview:clearIconButton];
  y -= 100;

  // Layout Mode Section
  NSTextField *modeSectionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 24)];
  modeSectionLabel.stringValue = @"Layout Mode";
  modeSectionLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  modeSectionLabel.bordered = NO;
  modeSectionLabel.editable = NO;
  modeSectionLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:modeSectionLabel];
  y -= 40;

  // Mode Selector
  self.modeSelector = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(leftMargin, y, 450, 28)];
  self.modeSelector.segmentCount = 3;
  [self.modeSelector setLabel:@"Float (Default)" forSegment:0];
  [self.modeSelector setLabel:@"BSP Tiling" forSegment:1];
  [self.modeSelector setLabel:@"Stack Tiling" forSegment:2];
  [self.modeSelector setWidth:150 forSegment:0];
  [self.modeSelector.cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
  self.modeSelector.target = self;
  self.modeSelector.action = @selector(modeChanged:);
  [self.view addSubview:self.modeSelector];
  y -= 60;

  // Description
  NSTextField *descLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 500, 60)];
  descLabel.stringValue = @"• Float: Windows can be moved and resized freely\n• BSP: Binary space partitioning (tiling)\n• Stack: Windows stacked on top of each other";
  descLabel.font = [NSFont systemFontOfSize:12];
  descLabel.bordered = NO;
  descLabel.editable = NO;
  descLabel.backgroundColor = [NSColor clearColor];
  descLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:descLabel];
  y -= 60;

  // Apply Button
  self.applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 32)];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply to Current Space";
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.view addSubview:self.applyButton];
  y -= 60;

  // Space Switching Section
  NSTextField *switchingSectionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 24)];
  switchingSectionLabel.stringValue = @"Space Switching";
  switchingSectionLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  switchingSectionLabel.bordered = NO;
  switchingSectionLabel.editable = NO;
  switchingSectionLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:switchingSectionLabel];
  y -= 40;

  self.shortcutToggle = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 30)];
  [self.shortcutToggle setSegmentCount:2];
  [self.shortcutToggle setLabel:@"Yabai (Fast)" forSegment:0];
  [self.shortcutToggle setLabel:@"Native (Animation)" forSegment:1];
  [self.shortcutToggle setWidth:148 forSegment:0];
  [self.shortcutToggle setWidth:148 forSegment:1];
  
  BOOL shortcutsOn = [[config valueForKeyPath:@"toggles.yabai_shortcuts" defaultValue:@YES] boolValue];
  [self.shortcutToggle setSelected:shortcutsOn forSegment:0];
  [self.shortcutToggle setSelected:!shortcutsOn forSegment:1];
  self.shortcutToggle.target = self;
  self.shortcutToggle.action = @selector(shortcutModeChanged:);
  [self.view addSubview:self.shortcutToggle];
  y -= 60;

  // Unmanaged Apps Section
  NSTextField *unmanagedSectionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  unmanagedSectionLabel.stringValue = @"Unmanaged Apps (Yabai)";
  unmanagedSectionLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  unmanagedSectionLabel.bordered = NO;
  unmanagedSectionLabel.editable = NO;
  unmanagedSectionLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:unmanagedSectionLabel];
  y -= 30;

  NSTextField *unmanagedHelp = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 600, 20)];
  [unmanagedHelp setBezeled:NO];
  [unmanagedHelp setEditable:NO];
  [unmanagedHelp setDrawsBackground:NO];
  [unmanagedHelp setLineBreakMode:NSLineBreakByWordWrapping];
  [unmanagedHelp setStringValue:@"One app name per line. These apps will not be tiled by yabai."];
  [self.view addSubview:unmanagedHelp];
  y -= 130;

  NSScrollView *unmanagedScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, y, 600, 120)];
  unmanagedScroll.hasVerticalScroller = YES;
  unmanagedScroll.autohidesScrollers = YES;
  unmanagedScroll.borderType = NSBezelBorder;

  self.unmanagedAppsTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, unmanagedScroll.contentSize.width, unmanagedScroll.contentSize.height)];
  [self.unmanagedAppsTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
  [self.unmanagedAppsTextView setAutomaticQuoteSubstitutionEnabled:NO];
  [self.unmanagedAppsTextView setAutomaticDashSubstitutionEnabled:NO];
  
  NSArray<NSString *> *unmanagedApps = [self currentUnmanagedApps];
  NSString *unmanagedText = [unmanagedApps componentsJoinedByString:@"\n"];
  [self.unmanagedAppsTextView setString:unmanagedText ?: @""];
  unmanagedScroll.documentView = self.unmanagedAppsTextView;
  [self.view addSubview:unmanagedScroll];
  
  y -= 40;

  NSButton *saveUnmanaged = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 120, 28)];
  [saveUnmanaged setTitle:@"Save Apps"];
  [saveUnmanaged setButtonType:NSButtonTypeMomentaryPushIn];
  [saveUnmanaged setBezelStyle:NSBezelStyleRounded];
  saveUnmanaged.target = self;
  saveUnmanaged.action = @selector(saveUnmanagedApps:);
  [self.view addSubview:saveUnmanaged];

  [self loadSpaceSettings];
}

- (void)spaceChanged:(id)sender {
  self.currentSpace = self.spaceSelector.indexOfSelectedItem + 1;
  [self loadSpaceSettings];
}

- (void)iconChanged:(id)sender {
  self.iconPreview.stringValue = self.iconField.stringValue;
}

- (void)clearIcon:(id)sender {
  self.iconField.stringValue = @"";
  self.iconPreview.stringValue = @"󰝚";
}

- (void)browseIcons:(id)sender {
  // Launch icon browser
  NSString *iconBrowserPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:iconBrowserPath]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = iconBrowserPath;
    [task launch];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = @"Build icon_browser first: cd ~/.config/sketchybar/gui && make icon_browser";
    [alert runModal];
  }
}

- (void)modeChanged:(id)sender {
  // Visual feedback only, saved on apply
}

- (void)loadSpaceSettings {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  if (!config || !config.state) {
    self.iconField.stringValue = @"";
    self.iconPreview.stringValue = @"󰝚";
    [self.modeSelector setSelectedSegment:0];
    return;
  }

  if (!config.state[@"space_icons"]) {
    config.state[@"space_icons"] = [NSMutableDictionary dictionary];
  }
  if (!config.state[@"space_modes"]) {
    config.state[@"space_modes"] = [NSMutableDictionary dictionary];
  }

  NSString *keyPath = [NSString stringWithFormat:@"space_icons.%ld", (long)self.currentSpace];
  NSString *icon = [config valueForKeyPath:keyPath defaultValue:@""];
  self.iconField.stringValue = icon ? icon : @"";
  self.iconPreview.stringValue = ([icon length] > 0) ? icon : @"󰝚";

  keyPath = [NSString stringWithFormat:@"space_modes.%ld", (long)self.currentSpace];
  NSString *mode = [config valueForKeyPath:keyPath defaultValue:@"float"];

  if ([mode isEqualToString:@"bsp"]) {
    [self.modeSelector setSelectedSegment:1];
  } else if ([mode isEqualToString:@"stack"]) {
    [self.modeSelector setSelectedSegment:2];
  } else {
    [self.modeSelector setSelectedSegment:0];
  }
}

- (void)applySettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *icon = self.iconField.stringValue;
  if ([icon length] > 0) {
    NSString *keyPath = [NSString stringWithFormat:@"space_icons.%ld", (long)self.currentSpace];
    [config setValue:icon forKeyPath:keyPath];
  }

  NSInteger segment = self.modeSelector.selectedSegment;
  NSString *mode = @"float";
  if (segment == 1) mode = @"bsp";
  else if (segment == 2) mode = @"stack";

  NSString *keyPath = [NSString stringWithFormat:@"space_modes.%ld", (long)self.currentSpace];
  [config setValue:mode forKeyPath:keyPath];

  NSString *script = [[config.configPath stringByAppendingPathComponent:@"plugins"] stringByAppendingPathComponent:@"set_space_mode.sh"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
    [config runScript:@"set_space_mode.sh" arguments:@[[NSString stringWithFormat:@"%ld", (long)self.currentSpace], mode]];
  }

  [config reloadSketchyBar];

  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply to Current Space";
  });
}

- (void)shortcutModeChanged:(id)sender {
  BOOL shortcutsOn = self.shortcutToggle.selectedSegment == 0;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(shortcutsOn) forKeyPath:@"toggles.yabai_shortcuts"];
  
  NSString *mode = shortcutsOn ? @"on" : @"off";
  [config runScript:@"toggle_yabai_shortcuts.sh" arguments:@[mode]];
}

// MARK: - Unmanaged Apps

- (NSString *)unmanagedAppsFilePath {
  return [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar/unmanaged_apps.conf"];
}

- (NSArray<NSString *> *)parseUnmanagedAppsFromString:(NSString *)string {
  if (![string isKindOfClass:[NSString class]]) return @[];
  NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSArray<NSString *> *lines = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:ws];
    if (trimmed.length == 0) continue;
    if ([trimmed hasPrefix:@"#"]) continue;
    [set addObject:trimmed];
  }
  return set.array;
}

- (NSArray<NSString *> *)currentUnmanagedApps {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSMutableOrderedSet<NSString *> *apps = [NSMutableOrderedSet orderedSet];
  id stored = [config valueForKeyPath:@"yabai_unmanaged_apps" defaultValue:@[]];
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  if ([stored isKindOfClass:[NSArray class]]) {
    for (id entry in (NSArray *)stored) {
      if (![entry isKindOfClass:[NSString class]]) continue;
      NSString *trimmed = [((NSString *)entry) stringByTrimmingCharactersInSet:ws];
      if (trimmed.length > 0) {
        [apps addObject:trimmed];
      }
    }
  }

  if (apps.count == 0) {
    NSString *path = [self unmanagedAppsFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
      for (NSString *entry in [self parseUnmanagedAppsFromString:contents]) {
        [apps addObject:entry];
      }
    }
  }

  return apps.array;
}

- (void)saveUnmanagedApps:(id)sender {
  NSString *text = self.unmanagedAppsTextView.string ?: @"";
  NSArray<NSString *> *apps = [self parseUnmanagedAppsFromString:text];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:apps forKeyPath:@"yabai_unmanaged_apps"];

  NSString *path = [self unmanagedAppsFilePath];
  if (path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *body = apps.count ? [[apps componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] : @"";
    [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }

  NSString *scriptName = @"update_unmanaged_apps.sh";
  [config runScript:scriptName arguments:@[]];
  
  NSButton *button = (NSButton *)sender;
  NSString *originalTitle = button.title;
  button.title = @"✓ Saved!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    button.title = originalTitle;
  });
}

@end
