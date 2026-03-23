#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface SpacesTabViewController : NSViewController
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconField;
@property (strong) NSTextField *iconPreview;
@property (strong) NSSegmentedControl *modeSelector;
@property (strong) NSPopUpButton *creatorModePopup;
@property (strong) NSPopUpButton *rightClickPopup;
@property (strong) NSPopUpButton *reorderModePopup;
@property (strong) NSButton *contextMenuToggle;
@property (strong) NSButton *swapIndicatorToggle;
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
  title.stringValue = @"Spaces Widget";
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
  descLabel.stringValue = @"Each space chip can have its own icon and layout mode.\n• Float: Windows can be moved and resized freely\n• BSP: Binary space partitioning (tiling)\n• Stack: Windows stacked on top of each other";
  descLabel.font = [NSFont systemFontOfSize:13];
  descLabel.bordered = NO;
  descLabel.editable = NO;
  descLabel.backgroundColor = [NSColor clearColor];
  descLabel.textColor = [NSColor secondaryLabelColor];
  [rootStack addView:descLabel inGravity:NSStackViewGravityTop];

  [rootStack setCustomSpacing:40 afterView:descLabel];

  // Widget behavior section
  NSTextField *behaviorSectionLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  behaviorSectionLabel.stringValue = @"WIDGET BEHAVIOR";
  behaviorSectionLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  behaviorSectionLabel.textColor = [NSColor secondaryLabelColor];
  behaviorSectionLabel.bordered = NO;
  behaviorSectionLabel.editable = NO;
  behaviorSectionLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:behaviorSectionLabel inGravity:NSStackViewGravityTop];

  NSStackView *creatorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  creatorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  creatorRow.spacing = 12;
  [rootStack addView:creatorRow inGravity:NSStackViewGravityTop];

  NSTextField *creatorLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  creatorLabel.stringValue = @"Create Button:";
  creatorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  creatorLabel.bordered = NO;
  creatorLabel.editable = NO;
  creatorLabel.backgroundColor = [NSColor clearColor];
  [creatorLabel.widthAnchor constraintEqualToConstant:140].active = YES;
  [creatorRow addView:creatorLabel inGravity:NSStackViewGravityLeading];

  self.creatorModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [self.creatorModePopup addItemsWithTitles:@[@"Every Display", @"Active Display", @"Primary Display"]];
  [self.creatorModePopup.widthAnchor constraintEqualToConstant:180].active = YES;
  [creatorRow addView:self.creatorModePopup inGravity:NSStackViewGravityLeading];

  NSStackView *rightClickRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  rightClickRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  rightClickRow.spacing = 12;
  [rootStack addView:rightClickRow inGravity:NSStackViewGravityTop];

  NSTextField *rightClickLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  rightClickLabel.stringValue = @"Close Action:";
  rightClickLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  rightClickLabel.bordered = NO;
  rightClickLabel.editable = NO;
  rightClickLabel.backgroundColor = [NSColor clearColor];
  [rightClickLabel.widthAnchor constraintEqualToConstant:140].active = YES;
  [rightClickRow addView:rightClickLabel inGravity:NSStackViewGravityLeading];

  self.rightClickPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [self.rightClickPopup addItemsWithTitles:@[@"Confirm Before Close", @"Close Immediately", @"Never Close"]];
  [self.rightClickPopup.widthAnchor constraintEqualToConstant:200].active = YES;
  [rightClickRow addView:self.rightClickPopup inGravity:NSStackViewGravityLeading];

  NSStackView *reorderRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  reorderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  reorderRow.spacing = 12;
  [rootStack addView:reorderRow inGravity:NSStackViewGravityTop];

  NSTextField *reorderLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  reorderLabel.stringValue = @"Reorder Controls:";
  reorderLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  reorderLabel.bordered = NO;
  reorderLabel.editable = NO;
  reorderLabel.backgroundColor = [NSColor clearColor];
  [reorderLabel.widthAnchor constraintEqualToConstant:140].active = YES;
  [reorderRow addView:reorderLabel inGravity:NSStackViewGravityLeading];

  self.reorderModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [self.reorderModePopup addItemsWithTitles:@[@"Popup Menu", @"Shift-click", @"Off"]];
  [self.reorderModePopup.widthAnchor constraintEqualToConstant:180].active = YES;
  [reorderRow addView:self.reorderModePopup inGravity:NSStackViewGravityLeading];

  NSStackView *toggleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  toggleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  toggleRow.spacing = 20;
  [rootStack addView:toggleRow inGravity:NSStackViewGravityTop];

  self.contextMenuToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.contextMenuToggle setButtonType:NSButtonTypeSwitch];
  self.contextMenuToggle.title = @"Open popup menu on right click";
  [toggleRow addView:self.contextMenuToggle inGravity:NSStackViewGravityLeading];

  self.swapIndicatorToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.swapIndicatorToggle setButtonType:NSButtonTypeSwitch];
  self.swapIndicatorToggle.title = @"Show swap indicator";
  [toggleRow addView:self.swapIndicatorToggle inGravity:NSStackViewGravityLeading];

  [rootStack setCustomSpacing:40 afterView:toggleRow];

  // Action Buttons
  NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttonRow.spacing = 12;
  [rootStack addView:buttonRow inGravity:NSStackViewGravityTop];

  self.applyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply Space + Widget Settings";
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
  [self loadBehaviorSettings];
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

- (void)loadBehaviorSettings {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *creatorMode = [config valueForKeyPath:@"spaces.creator_mode" defaultValue:@"per_display"] ?: @"per_display";
  if ([creatorMode isEqualToString:@"active"]) {
    [self.creatorModePopup selectItemAtIndex:1];
  } else if ([creatorMode isEqualToString:@"primary"]) {
    [self.creatorModePopup selectItemAtIndex:2];
  } else {
    [self.creatorModePopup selectItemAtIndex:0];
  }

  NSString *closeMode = [config valueForKeyPath:@"spaces.right_click_close" defaultValue:@"confirm"] ?: @"confirm";
  if ([closeMode isEqualToString:@"direct"]) {
    [self.rightClickPopup selectItemAtIndex:1];
  } else if ([closeMode isEqualToString:@"off"]) {
    [self.rightClickPopup selectItemAtIndex:2];
  } else {
    [self.rightClickPopup selectItemAtIndex:0];
  }

  NSString *reorderMode = [config valueForKeyPath:@"spaces.reorder_mode" defaultValue:@"menu"] ?: @"menu";
  if ([reorderMode isEqualToString:@"modifiers"]) {
    [self.reorderModePopup selectItemAtIndex:1];
  } else if ([reorderMode isEqualToString:@"off"]) {
    [self.reorderModePopup selectItemAtIndex:2];
  } else {
    [self.reorderModePopup selectItemAtIndex:0];
  }

  BOOL contextMenuEnabled = [[config valueForKeyPath:@"spaces.context_menu_on_right_click" defaultValue:@YES] boolValue];
  self.contextMenuToggle.state = contextMenuEnabled ? NSControlStateValueOn : NSControlStateValueOff;

  BOOL swapIndicatorEnabled = [[config valueForKeyPath:@"spaces.swap_indicator" defaultValue:@YES] boolValue];
  self.swapIndicatorToggle.state = swapIndicatorEnabled ? NSControlStateValueOn : NSControlStateValueOff;
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

  NSString *creatorMode = @"per_display";
  if (self.creatorModePopup.indexOfSelectedItem == 1) {
    creatorMode = @"active";
  } else if (self.creatorModePopup.indexOfSelectedItem == 2) {
    creatorMode = @"primary";
  }
  [config setValue:creatorMode forKeyPath:@"spaces.creator_mode"];

  NSString *closeMode = @"confirm";
  if (self.rightClickPopup.indexOfSelectedItem == 1) {
    closeMode = @"direct";
  } else if (self.rightClickPopup.indexOfSelectedItem == 2) {
    closeMode = @"off";
  }
  [config setValue:closeMode forKeyPath:@"spaces.right_click_close"];

  NSString *reorderMode = @"menu";
  NSNumber *modifierReorderEnabled = @NO;
  if (self.reorderModePopup.indexOfSelectedItem == 1) {
    reorderMode = @"modifiers";
    modifierReorderEnabled = @YES;
  } else if (self.reorderModePopup.indexOfSelectedItem == 2) {
    reorderMode = @"off";
  }
  [config setValue:reorderMode forKeyPath:@"spaces.reorder_mode"];
  [config setValue:modifierReorderEnabled forKeyPath:@"spaces.modifier_reorder_enabled"];
  [config setValue:@(self.contextMenuToggle.state == NSControlStateValueOn) forKeyPath:@"spaces.context_menu_on_right_click"];
  [config setValue:@(self.swapIndicatorToggle.state == NSControlStateValueOn) forKeyPath:@"spaces.swap_indicator"];

  NSString *script = [[config.configPath stringByAppendingPathComponent:@"plugins"] stringByAppendingPathComponent:@"set_space_mode.sh"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
    [config runScript:@"set_space_mode.sh" arguments:@[[NSString stringWithFormat:@"%ld", (long)self.currentSpace], mode]];
  }

  [config reloadSketchyBar];

  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply Space + Widget Settings";
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
