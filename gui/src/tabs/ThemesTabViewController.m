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

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 50;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Theme Selection";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // Theme Selector
  NSTextField *selectorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  selectorLabel.stringValue = @"Current Theme:";
  selectorLabel.bordered = NO;
  selectorLabel.editable = NO;
  selectorLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:selectorLabel];

  self.themeSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 3, 300, 26)];
  for (NSString *theme in self.availableThemes) {
    [self.themeSelector addItemWithTitle:theme];
  }
  self.themeSelector.target = self;
  self.themeSelector.action = @selector(themeChanged:);
  
  // Load current theme from state
  NSString *currentTheme = [config valueForKeyPath:@"appearance.theme" defaultValue:@"default"];
  [self.themeSelector selectItemWithTitle:currentTheme];
  if (![self.themeSelector selectedItem]) {
    [self.themeSelector selectItemAtIndex:0];
  }
  
  [self.view addSubview:self.themeSelector];
  y -= 60;

  // Preview
  NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  previewLabel.stringValue = @"Theme Preview:";
  previewLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  previewLabel.bordered = NO;
  previewLabel.editable = NO;
  previewLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:previewLabel];
  y -= 40;

  NSView *previewBox = [[NSView alloc] initWithFrame:NSMakeRect(leftMargin, y - 200, 600, 200)];
  previewBox.wantsLayer = YES;
  previewBox.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
  previewBox.layer.cornerRadius = 8;
  [self.view addSubview:previewBox];

  self.themePreview = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 560, 40)];
  self.themePreview.stringValue = @"Theme colors will be applied to the bar";
  self.themePreview.font = [NSFont systemFontOfSize:14];
  self.themePreview.bordered = NO;
  self.themePreview.editable = NO;
  self.themePreview.alignment = NSTextAlignmentCenter;
  [previewBox addSubview:self.themePreview];
  y -= 250;

  // Apply Button
  NSButton *applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 32)];
  [applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [applyButton setBezelStyle:NSBezelStyleRounded];
  applyButton.title = @"Apply Theme";
  applyButton.target = self;
  applyButton.action = @selector(applyTheme:);
  [self.view addSubview:applyButton];

  NSButton *openThemesButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 220, y, 180, 32)];
  [openThemesButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openThemesButton setBezelStyle:NSBezelStyleRounded];
  openThemesButton.title = @"Open Themes Folder";
  openThemesButton.target = self;
  openThemesButton.action = @selector(openThemesFolder:);
  [self.view addSubview:openThemesButton];

  NSButton *openOverrideButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 420, y, 200, 32)];
  [openOverrideButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openOverrideButton setBezelStyle:NSBezelStyleRounded];
  openOverrideButton.title = @"Edit theme.local.lua";
  openOverrideButton.target = self;
  openOverrideButton.action = @selector(openThemeOverride:);
  [self.view addSubview:openOverrideButton];

  [self updatePreview];
}

- (void)themeChanged:(id)sender {
  [self updatePreview];
}

- (void)updatePreview {
  NSString *themeName = self.themeSelector.selectedItem.title;
  if (themeName) {
    self.themePreview.stringValue = [NSString stringWithFormat:@"Selected: %@ theme", themeName];
  }
}

- (void)applyTheme:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *configDir = config.configPath ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *themeName = self.themeSelector.selectedItem.title;
  
  if (!themeName) {
    NSBeep();
    return;
  }

  // Save theme to state
  [config setValue:themeName forKeyPath:@"appearance.theme"];

  // Update theme.lua file
  NSString *themeLuaPath = [configDir stringByAppendingPathComponent:@"theme.lua"];
  NSString *themeContent = [NSString stringWithFormat:@"local current_theme = \"%@\"\nlocal theme = require(\"themes.\" .. current_theme)\n\nreturn theme\n", themeName];
  
  NSError *error = nil;
  if (![themeContent writeToFile:themeLuaPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    NSLog(@"Failed to write theme.lua: %@", error);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Failed to Apply Theme";
    alert.informativeText = [NSString stringWithFormat:@"Could not write theme.lua: %@", error.localizedDescription];
    [alert runModal];
    return;
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
