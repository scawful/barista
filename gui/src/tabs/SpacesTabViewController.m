#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface SpacesTabViewController : NSViewController
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconField;
@property (strong) NSTextField *iconPreview;
@property (strong) NSSegmentedControl *modeSelector;
@property (strong) NSButton *applyButton;
@property (strong) NSButton *clearModeButton;
@property (strong) NSButton *resetModesButton;
@property (assign) NSInteger currentSpace;
@end

@implementation SpacesTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.currentSpace = 1;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSInsetRect(self.view.bounds, 40, 20)];
  rootStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 24;
  rootStack.edgeInsets = NSEdgeInsetsMake(20, 0, 20, 0);
  [self.view addSubview:rootStack];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Space Customization";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // Space Selector Row
  NSStackView *selectorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  selectorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  selectorRow.spacing = 12;
  [rootStack addView:selectorRow inGravity:NSStackViewGravityTop];

  NSTextField *spaceLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  spaceLabel.stringValue = @"Space:";
  spaceLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  spaceLabel.bordered = NO;
  spaceLabel.editable = NO;
  spaceLabel.backgroundColor = [NSColor clearColor];
  [selectorRow addView:spaceLabel inGravity:NSStackViewGravityLeading];

  self.spaceSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  for (int i = 1; i <= 10; i++) {
    [self.spaceSelector addItemWithTitle:[NSString stringWithFormat:@"Space %d", i]];
  }
  self.spaceSelector.target = self;
  self.spaceSelector.action = @selector(spaceChanged:);
  [self.spaceSelector.widthAnchor constraintEqualToConstant:150].active = YES;
  [selectorRow addView:self.spaceSelector inGravity:NSStackViewGravityLeading];

  [rootStack setCustomSpacing:40 afterView:selectorRow];

  // Icon Section
  NSTextField *iconSectionLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  iconSectionLabel.stringValue = @"SPACE ICON";
  iconSectionLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  iconSectionLabel.textColor = [NSColor secondaryLabelColor];
  iconSectionLabel.bordered = NO;
  iconSectionLabel.editable = NO;
  iconSectionLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:iconSectionLabel inGravity:NSStackViewGravityTop];

  NSStackView *iconContent = [[NSStackView alloc] initWithFrame:NSZeroRect];
  iconContent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  iconContent.spacing = 20;
  iconContent.alignment = NSLayoutAttributeCenterY;
  [rootStack addView:iconContent inGravity:NSStackViewGravityTop];

  // Icon Preview Box
  NSView *previewBox = [[NSView alloc] initWithFrame:NSZeroRect];
  previewBox.wantsLayer = YES;
  previewBox.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.2].CGColor;
  previewBox.layer.cornerRadius = 8;
  [previewBox.widthAnchor constraintEqualToConstant:100].active = YES;
  [previewBox.heightAnchor constraintEqualToConstant:100].active = YES;
  [iconContent addView:previewBox inGravity:NSStackViewGravityLeading];

  self.iconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
  self.iconPreview.stringValue = @"󰝚";
  self.iconPreview.font = [self preferredIconFontWithSize:60];
  self.iconPreview.bordered = NO;
  self.iconPreview.editable = NO;
  self.iconPreview.backgroundColor = [NSColor clearColor];
  self.iconPreview.alignment = NSTextAlignmentCenter;
  self.iconPreview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [previewBox addSubview:self.iconPreview];

  NSStackView *iconControls = [[NSStackView alloc] initWithFrame:NSZeroRect];
  iconControls.orientation = NSUserInterfaceLayoutOrientationVertical;
  iconControls.spacing = 12;
  iconControls.alignment = NSLayoutAttributeLeading;
  [iconContent addView:iconControls inGravity:NSStackViewGravityLeading];

  NSStackView *inputRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  inputRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  inputRow.spacing = 8;
  [iconControls addView:inputRow inGravity:NSStackViewGravityTop];

  self.iconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.iconField.placeholderString = @"Glyph";
  self.iconField.font = [self preferredIconFontWithSize:16];
  self.iconField.target = self;
  self.iconField.action = @selector(iconChanged:);
  [self.iconField.widthAnchor constraintEqualToConstant:120].active = YES;
  [inputRow addView:self.iconField inGravity:NSStackViewGravityLeading];

  NSButton *browseIconsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [browseIconsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [browseIconsButton setBezelStyle:NSBezelStyleRounded];
  browseIconsButton.title = @"Icon Library";
  browseIconsButton.target = self;
  browseIconsButton.action = @selector(browseIcons:);
  [inputRow addView:browseIconsButton inGravity:NSStackViewGravityLeading];

  NSButton *clearIconButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [clearIconButton setButtonType:NSButtonTypeMomentaryPushIn];
  [clearIconButton setBezelStyle:NSBezelStyleRounded];
  clearIconButton.title = @"Clear";
  clearIconButton.target = self;
  clearIconButton.action = @selector(clearIcon:);
  [inputRow addView:clearIconButton inGravity:NSStackViewGravityLeading];

  [rootStack setCustomSpacing:40 afterView:iconContent];

  // Layout Mode Section
  NSTextField *modeSectionLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  modeSectionLabel.stringValue = @"LAYOUT MODE";
  modeSectionLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  modeSectionLabel.textColor = [NSColor secondaryLabelColor];
  modeSectionLabel.bordered = NO;
  modeSectionLabel.editable = NO;
  modeSectionLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:modeSectionLabel inGravity:NSStackViewGravityTop];

  self.modeSelector = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
  self.modeSelector.segmentCount = 3;
  [self.modeSelector setLabel:@"Float (Default)" forSegment:0];
  [self.modeSelector setLabel:@"BSP Tiling" forSegment:1];
  [self.modeSelector setLabel:@"Stack Tiling" forSegment:2];
  [self.modeSelector.cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
  self.modeSelector.target = self;
  self.modeSelector.action = @selector(modeChanged:);
  [self.modeSelector.widthAnchor constraintEqualToConstant:450].active = YES;
  [rootStack addView:self.modeSelector inGravity:NSStackViewGravityTop];

  NSTextField *descLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  descLabel.stringValue = @"• Float: Windows can be moved and resized freely\n• BSP: Binary space partitioning (tiling)\n• Stack: Windows stacked on top of each other";
  descLabel.font = [NSFont systemFontOfSize:13];
  descLabel.bordered = NO;
  descLabel.editable = NO;
  descLabel.backgroundColor = [NSColor clearColor];
  descLabel.textColor = [NSColor secondaryLabelColor];
  [rootStack addView:descLabel inGravity:NSStackViewGravityTop];

  [rootStack setCustomSpacing:40 afterView:descLabel];

  // Action Buttons
  NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttonRow.spacing = 12;
  [rootStack addView:buttonRow inGravity:NSStackViewGravityTop];

  self.applyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply to Space";
  self.applyButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.applyButton.widthAnchor constraintEqualToConstant:160].active = YES;
  [buttonRow addView:self.applyButton inGravity:NSStackViewGravityLeading];

  self.clearModeButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.clearModeButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.clearModeButton setBezelStyle:NSBezelStyleRounded];
  self.clearModeButton.title = @"Clear Mode";
  self.clearModeButton.target = self;
  self.clearModeButton.action = @selector(clearMode:);
  [buttonRow addView:self.clearModeButton inGravity:NSStackViewGravityLeading];

  self.resetModesButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.resetModesButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.resetModesButton setBezelStyle:NSBezelStyleRounded];
  self.resetModesButton.title = @"Reset All";
  self.resetModesButton.target = self;
  self.resetModesButton.action = @selector(resetAllModes:);
  [buttonRow addView:self.resetModesButton inGravity:NSStackViewGravityLeading];

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
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *configDir = config.configPath ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *iconBrowserPath = [configDir stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:iconBrowserPath]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = iconBrowserPath;
    [task launch];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = [NSString stringWithFormat:@"Build icon_browser first: cd %@/gui && make icon_browser", configDir];
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

- (void)clearMode:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"space_modes.%ld", (long)self.currentSpace];
  [config removeValueForKeyPath:keyPath];

  NSString *script = [[config.configPath stringByAppendingPathComponent:@"plugins"] stringByAppendingPathComponent:@"set_space_mode.sh"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
    [config runScript:@"set_space_mode.sh" arguments:@[[NSString stringWithFormat:@"%ld", (long)self.currentSpace], @"float"]];
  }

  [config reloadSketchyBar];
  [self loadSpaceSettings];
}

- (void)resetAllModes:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:[NSMutableDictionary dictionary] forKeyPath:@"space_modes"];

  NSString *script = [[config.configPath stringByAppendingPathComponent:@"plugins"] stringByAppendingPathComponent:@"set_space_mode.sh"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
    [config runScript:@"set_space_mode.sh" arguments:@[[NSString stringWithFormat:@"%ld", (long)self.currentSpace], @"float"]];
  }

  [config reloadSketchyBar];
  [self loadSpaceSettings];
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
  return [NSFont systemFontOfSize:size];
}

@end
