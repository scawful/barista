#import "BaristaTabBaseViewController.h"
#import "BaristaStyle.h"
#import "ConfigurationManager.h"

@interface ThemesTabViewController : BaristaTabBaseViewController
@property (strong) NSPopUpButton *themeSelector;
@property (strong) NSView *swatchContainer;
@property (strong) NSArray *availableThemes;
@end

@implementation ThemesTabViewController

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

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(24, 24, 28, 24) spacing:20];

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
  [previewBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  [previewBox.heightAnchor constraintEqualToConstant:160].active = YES;
  [rootStack addView:previewBox inGravity:NSStackViewGravityTop];

  self.swatchContainer = previewBox;

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
  NSString *themeName = self.themeSelector.selectedItem.title;
  if (themeName) {
    [self buildSwatchesForTheme:themeName inContainer:self.swatchContainer];
  }
}

- (void)buildSwatchesForTheme:(NSString *)themeName inContainer:(NSView *)container {
  // Remove old swatches
  for (NSView *sub in [container.subviews copy]) {
    [sub removeFromSuperview];
  }

  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSString *barHex = nil;
  NSDictionary<NSString *, NSColor *> *palette = [style paletteForThemeName:themeName barHex:&barHex];

  if (!palette.count) {
    NSTextField *empty = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 200, 20)];
    empty.stringValue = @"No colors found in theme";
    empty.bordered = NO;
    empty.editable = NO;
    empty.backgroundColor = [NSColor clearColor];
    empty.textColor = [NSColor secondaryLabelColor];
    [container addSubview:empty];
    return;
  }

  // Build a flow layout of color swatches
  // Order: important keys first, then alphabetical
  NSArray *priorityKeys = @[@"BG_PRI_COLR", @"BG_SEC_COLR", @"WHITE", @"DARK_WHITE"];
  NSMutableArray *orderedKeys = [NSMutableArray arrayWithArray:priorityKeys];
  NSArray *remaining = [[palette.allKeys sortedArrayUsingSelector:@selector(compare:)]
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![priorityKeys containsObject:key];
      }]];
  [orderedKeys addObjectsFromArray:remaining];

  CGFloat x = 10, y = container.bounds.size.height - 54;
  CGFloat swatchSize = 28, spacing = 8, labelHeight = 14;

  // Bar background swatch (wider)
  if (barHex.length) {
    NSColor *barColor = [style colorFromHexString:barHex fallback:nil];
    if (barColor) {
      NSView *swatch = [[NSView alloc] initWithFrame:NSMakeRect(x, y, 60, swatchSize)];
      swatch.wantsLayer = YES;
      swatch.layer.backgroundColor = barColor.CGColor;
      swatch.layer.cornerRadius = 6;
      swatch.layer.borderWidth = 1;
      swatch.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
      [container addSubview:swatch];

      NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y - labelHeight - 2, 60, labelHeight)];
      label.stringValue = @"Bar BG";
      label.font = [NSFont systemFontOfSize:8];
      label.textColor = [NSColor secondaryLabelColor];
      label.bordered = NO;
      label.editable = NO;
      label.backgroundColor = [NSColor clearColor];
      label.alignment = NSTextAlignmentCenter;
      [container addSubview:label];
      x += 60 + spacing;
    }
  }

  // Palette swatches
  for (NSString *key in orderedKeys) {
    NSColor *color = palette[key];
    if (!color) continue;

    if (x + swatchSize > container.bounds.size.width - 10) {
      x = 10;
      y -= (swatchSize + labelHeight + spacing + 4);
    }

    NSView *swatch = [[NSView alloc] initWithFrame:NSMakeRect(x, y, swatchSize, swatchSize)];
    swatch.wantsLayer = YES;
    swatch.layer.backgroundColor = color.CGColor;
    swatch.layer.cornerRadius = 6;
    swatch.layer.borderWidth = 1;
    swatch.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    [container addSubview:swatch];

    // Abbreviated key name
    NSString *shortKey = key;
    if (shortKey.length > 8) {
      shortKey = [shortKey substringToIndex:8];
    }
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x - 2, y - labelHeight - 2, swatchSize + 4, labelHeight)];
    label.stringValue = shortKey;
    label.font = [NSFont systemFontOfSize:7];
    label.textColor = [NSColor secondaryLabelColor];
    label.bordered = NO;
    label.editable = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentCenter;
    [container addSubview:label];

    x += swatchSize + spacing;
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
  NSLog(@"[barista] applyTheme: name=%@ barHex=%@ configPath=%@",
        themeName, themeBarHex ?: @"(nil)", config.configPath);
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
