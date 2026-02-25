#import "BaristaStyle.h"
#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface ThemesTabViewController : NSViewController
@property (strong) NSPopUpButton *themeSelector;
@property (strong) NSTextField *themePreview;
@property (strong) NSArray *availableThemes;
@end

@implementation ThemesTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  // Scan themes directory
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSString *configDir = config.configPath ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *themesPath = [configDir stringByAppendingPathComponent:@"themes"];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *themeFiles = [fm contentsOfDirectoryAtPath:themesPath error:nil];
  
  NSMutableArray *themes = [NSMutableArray array];
  for (NSString *file in themeFiles) {
    if ([file hasSuffix:@".lua"]) {
      NSString *themeName = [file stringByDeletingPathExtension];
      [themes addObject:themeName];
    }
  }
  self.availableThemes = [themes sortedArrayUsingSelector:@selector(compare:)];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSInsetRect(self.view.bounds, 40, 20)];
  rootStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 24;
  rootStack.edgeInsets = NSEdgeInsetsMake(20, 0, 20, 0);
  [self.view addSubview:rootStack];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Theme Selection";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // Theme Selector Row
  NSStackView *selectorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  selectorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  selectorRow.spacing = 12;
  [rootStack addView:selectorRow inGravity:NSStackViewGravityTop];

  NSTextField *selectorLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  selectorLabel.stringValue = @"Active Theme:";
  selectorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  selectorLabel.bordered = NO;
  selectorLabel.editable = NO;
  selectorLabel.backgroundColor = [NSColor clearColor];
  [selectorRow addView:selectorLabel inGravity:NSStackViewGravityLeading];

  self.themeSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  for (NSString *theme in self.availableThemes) {
    [self.themeSelector addItemWithTitle:theme];
  }
  self.themeSelector.target = self;
  self.themeSelector.action = @selector(themeChanged:);
  [self.themeSelector.widthAnchor constraintEqualToConstant:250].active = YES;
  [selectorRow addView:self.themeSelector inGravity:NSStackViewGravityLeading];

  // Load current theme from state
  NSString *currentTheme = [config valueForKeyPath:@"appearance.theme" defaultValue:@"default"];
  [self.themeSelector selectItemWithTitle:currentTheme];
  if (![self.themeSelector selectedItem]) {
    [self.themeSelector selectItemAtIndex:0];
  }

  // Preview Section
  NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  previewLabel.stringValue = @"PREVIEW";
  previewLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  previewLabel.textColor = [NSColor secondaryLabelColor];
  previewLabel.bordered = NO;
  previewLabel.editable = NO;
  previewLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:previewLabel inGravity:NSStackViewGravityTop];

  NSView *previewBox = [[NSView alloc] initWithFrame:NSZeroRect];
  previewBox.wantsLayer = YES;
  previewBox.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.2].CGColor;
  previewBox.layer.cornerRadius = 12;
  [previewBox.widthAnchor constraintEqualToConstant:600].active = YES;
  [previewBox.heightAnchor constraintEqualToConstant:120].active = YES;
  [rootStack addView:previewBox inGravity:NSStackViewGravityTop];

  self.themePreview = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.themePreview.stringValue = @"Theme colors will be applied to the bar";
  self.themePreview.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
  self.themePreview.bordered = NO;
  self.themePreview.editable = NO;
  self.themePreview.alignment = NSTextAlignmentCenter;
  self.themePreview.backgroundColor = [NSColor clearColor];
  self.themePreview.tag = 9901;
  self.themePreview.translatesAutoresizingMaskIntoConstraints = NO;
  [previewBox addSubview:self.themePreview];
  [self.themePreview.centerXAnchor constraintEqualToAnchor:previewBox.centerXAnchor].active = YES;
  [self.themePreview.centerYAnchor constraintEqualToAnchor:previewBox.centerYAnchor].active = YES;

  [rootStack setCustomSpacing:40 afterView:previewBox];

  // Action Buttons
  NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttonRow.spacing = 12;
  [rootStack addView:buttonRow inGravity:NSStackViewGravityTop];

  NSButton *applyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [applyButton setBezelStyle:NSBezelStyleRounded];
  applyButton.title = @"Apply Theme";
  applyButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  applyButton.target = self;
  applyButton.action = @selector(applyTheme:);
  [applyButton.widthAnchor constraintEqualToConstant:160].active = YES;
  [buttonRow addView:applyButton inGravity:NSStackViewGravityLeading];

  NSButton *openThemesButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [openThemesButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openThemesButton setBezelStyle:NSBezelStyleRounded];
  openThemesButton.title = @"Themes Folder";
  openThemesButton.target = self;
  openThemesButton.action = @selector(openThemesFolder:);
  [buttonRow addView:openThemesButton inGravity:NSStackViewGravityLeading];

  NSButton *openOverrideButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [openOverrideButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openOverrideButton setBezelStyle:NSBezelStyleRounded];
  openOverrideButton.title = @"Edit Local Overrides";
  openOverrideButton.target = self;
  openOverrideButton.action = @selector(openThemeOverride:);
  [buttonRow addView:openOverrideButton inGravity:NSStackViewGravityLeading];

  [self updatePreview];
}

- (void)themeChanged:(id)sender {
  [self updatePreview];
}

- (void)updatePreview {
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSString *themeName = self.themeSelector.selectedItem.title;
  if (themeName) {
    self.themePreview.stringValue = [NSString stringWithFormat:@"Selected: %@ theme", themeName];
    self.themePreview.textColor = style.accentColor;
  }
}

- (void)applyTheme:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *themeName = self.themeSelector.selectedItem.title;
  
  if (!themeName) {
    NSBeep();
    return;
  }

  // Save theme to state
  [config setValue:themeName forKeyPath:@"appearance.theme"];
  [[BaristaStyle sharedStyle] refreshFromConfig];
  NSString *themeBarHex = [BaristaStyle sharedStyle].themeBarHex;
  if (themeBarHex.length) {
    [config setValue:themeBarHex forKeyPath:@"appearance.bar_color"];
  }

  [config reloadSketchyBar];

  // Visual feedback
  NSButton *button = (NSButton *)sender;
  button.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    button.title = @"Apply Theme";
  });
}

- (void)openThemesFolder:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *basePath = config.configPath.length
    ? config.configPath
    : [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *themesPath = [basePath stringByAppendingPathComponent:@"themes"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:themesPath]];
}

- (void)openThemeOverride:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *basePath = config.configPath.length
    ? config.configPath
    : [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *overridePath = [basePath stringByAppendingPathComponent:@"themes/theme.local.lua"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:overridePath]) {
    [@"" writeToFile:overridePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:overridePath]];
}

@end
