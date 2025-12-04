#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface SpacesTabViewController : NSViewController
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconField;
@property (strong) NSTextField *iconPreview;
@property (strong) NSSegmentedControl *modeSelector;
@property (strong) NSButton *applyButton;
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
  y -= 80;

  // Apply Button
  self.applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 32)];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply to Current Space";
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.view addSubview:self.applyButton];

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

@end

