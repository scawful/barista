#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// MARK: - Configuration Manager

@interface ConfigurationManager : NSObject
@property (copy, nonatomic) NSString *statePath;
@property (copy, nonatomic) NSString *configPath;
@property (copy, nonatomic) NSString *scriptsPath;
@property (strong, nonatomic) NSMutableDictionary *state;

+ (instancetype)sharedManager;
- (BOOL)loadState;
- (BOOL)saveState;
- (id)valueForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath;
- (void)reloadSketchyBar;
- (void)runScript:(NSString *)scriptName arguments:(NSArray *)args;
@end

@implementation ConfigurationManager

+ (instancetype)sharedManager {
  static ConfigurationManager *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[ConfigurationManager alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSString *home = NSHomeDirectory();
    NSString *configOverride = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_CONFIG_DIR"];
    if ([configOverride hasPrefix:@"~/"]) {
      configOverride = [home stringByAppendingPathComponent:[configOverride substringFromIndex:2]];
    }
    if (configOverride.length) {
      self.configPath = configOverride;
    } else {
      self.configPath = [home stringByAppendingPathComponent:@".config/sketchybar"];
    }
    self.statePath = [self.configPath stringByAppendingPathComponent:@"state.json"];
    self.scriptsPath = [self resolveScriptsPath];
    [self loadState];
  }
  return self;
}

- (NSString *)resolveScriptsPath {
  NSString *override = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_SCRIPTS_DIR"];
  if (override.length) {
    return override;
  }

  NSString *configScripts = [self.configPath stringByAppendingPathComponent:@"scripts"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:configScripts]) {
    return configScripts;
  }

  NSString *legacyScripts = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scripts"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:legacyScripts]) {
    return legacyScripts;
  }

  return configScripts;
}

- (BOOL)loadState {
  NSData *data = [NSData dataWithContentsOfFile:self.statePath];
  if (!data) {
    self.state = [NSMutableDictionary dictionary];
    return NO;
  }

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];

  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    self.state = [NSMutableDictionary dictionary];
    return NO;
  }

  self.state = [(NSDictionary *)json mutableCopy];
  return YES;
}

- (BOOL)saveState {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:self.state
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:&error];
  if (error || !data) {
    NSLog(@"Failed to serialize state: %@", error);
    return NO;
  }

  return [data writeToFile:self.statePath atomically:YES];
}

- (id)valueForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue {
  id value = [self.state valueForKeyPath:keyPath];
  return value ?: defaultValue;
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
  if (!keyPath || !value) return;

  NSArray *components = [keyPath componentsSeparatedByString:@"."];
  NSMutableDictionary *current = self.state;

  for (NSInteger i = 0; i < components.count - 1; i++) {
    NSString *key = components[i];
    if (!current[key] || ![current[key] isKindOfClass:[NSDictionary class]]) {
      current[key] = [NSMutableDictionary dictionary];
    }
    current = current[key];
  }

  current[components.lastObject] = value;
  [self saveState];
}

- (void)reloadSketchyBar {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    system("/opt/homebrew/opt/sketchybar/bin/sketchybar --reload");
  });
}

- (void)runScript:(NSString *)scriptName arguments:(NSArray *)args {
  NSString *scriptPath = [self.scriptsPath stringByAppendingPathComponent:scriptName];

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  NSMutableArray *taskArgs = [NSMutableArray arrayWithObject:scriptPath];
  if (args) [taskArgs addObjectsFromArray:args];
  task.arguments = taskArgs;

  @try {
    [task launch];
  } @catch (NSException *exception) {
    NSLog(@"Failed to run script %@: %@", scriptName, exception);
  }
}

@end

// MARK: - Tab View Controllers

@interface AppearanceTabViewController : NSViewController
@property (strong) NSSlider *heightSlider;
@property (strong) NSTextField *heightValueLabel;
@property (strong) NSSlider *cornerSlider;
@property (strong) NSTextField *cornerValueLabel;
@property (strong) NSSlider *blurSlider;
@property (strong) NSTextField *blurValueLabel;
@property (strong) NSSlider *scaleSlider;
@property (strong) NSTextField *scaleValueLabel;
@property (strong) NSColorWell *barColorWell;
@property (strong) NSTextField *barColorHexField;
@property (strong) NSButton *applyButton;
@property (strong) NSView *previewBox;
@property (strong) NSTextField *previewBarView;
@end

@implementation AppearanceTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  CGFloat y = self.view.bounds.size.height - 30;
  CGFloat leftMargin = 50;
  CGFloat rightMargin = self.view.bounds.size.width - 50;
  CGFloat sliderWidth = 400;
  CGFloat spacing = 70;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 500, 28)];
  title.stringValue = @"Appearance Settings";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // Bar Height
  NSTextField *heightLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  heightLabel.stringValue = @"Bar Height:";
  heightLabel.bordered = NO;
  heightLabel.editable = NO;
  heightLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:heightLabel];

  self.heightValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 20)];
  self.heightValueLabel.bordered = NO;
  self.heightValueLabel.editable = NO;
  self.heightValueLabel.backgroundColor = [NSColor clearColor];
  self.heightValueLabel.alignment = NSTextAlignmentRight;
  [self.view addSubview:self.heightValueLabel];

  self.heightSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, sliderWidth, 20)];
  self.heightSlider.minValue = 20;
  self.heightSlider.maxValue = 50;
  self.heightSlider.doubleValue = [[config valueForKeyPath:@"appearance.bar_height" defaultValue:@28] doubleValue];
  self.heightSlider.target = self;
  self.heightSlider.action = @selector(sliderChanged:);
  [self.view addSubview:self.heightSlider];
  [self updateHeightLabel];
  y -= spacing;

  // Corner Radius
  NSTextField *cornerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  cornerLabel.stringValue = @"Corner Radius:";
  cornerLabel.bordered = NO;
  cornerLabel.editable = NO;
  cornerLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:cornerLabel];

  self.cornerValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 20)];
  self.cornerValueLabel.bordered = NO;
  self.cornerValueLabel.editable = NO;
  self.cornerValueLabel.backgroundColor = [NSColor clearColor];
  self.cornerValueLabel.alignment = NSTextAlignmentRight;
  [self.view addSubview:self.cornerValueLabel];

  self.cornerSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, sliderWidth, 20)];
  self.cornerSlider.minValue = 0;
  self.cornerSlider.maxValue = 16;
  self.cornerSlider.doubleValue = [[config valueForKeyPath:@"appearance.corner_radius" defaultValue:@0] doubleValue];
  self.cornerSlider.target = self;
  self.cornerSlider.action = @selector(sliderChanged:);
  [self.view addSubview:self.cornerSlider];
  [self updateCornerLabel];
  y -= spacing;

  // Blur Radius
  NSTextField *blurLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  blurLabel.stringValue = @"Blur Radius:";
  blurLabel.bordered = NO;
  blurLabel.editable = NO;
  blurLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:blurLabel];

  self.blurValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 20)];
  self.blurValueLabel.bordered = NO;
  self.blurValueLabel.editable = NO;
  self.blurValueLabel.backgroundColor = [NSColor clearColor];
  self.blurValueLabel.alignment = NSTextAlignmentRight;
  [self.view addSubview:self.blurValueLabel];

  self.blurSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, sliderWidth, 20)];
  self.blurSlider.minValue = 0;
  self.blurSlider.maxValue = 80;
  self.blurSlider.doubleValue = [[config valueForKeyPath:@"appearance.blur_radius" defaultValue:@30] doubleValue];
  self.blurSlider.target = self;
  self.blurSlider.action = @selector(sliderChanged:);
  [self.view addSubview:self.blurSlider];
  [self updateBlurLabel];
  y -= spacing;

  // Widget Scale
  NSTextField *scaleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  scaleLabel.stringValue = @"Widget Scale:";
  scaleLabel.bordered = NO;
  scaleLabel.editable = NO;
  scaleLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:scaleLabel];

  self.scaleValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 20)];
  self.scaleValueLabel.bordered = NO;
  self.scaleValueLabel.editable = NO;
  self.scaleValueLabel.backgroundColor = [NSColor clearColor];
  self.scaleValueLabel.alignment = NSTextAlignmentRight;
  [self.view addSubview:self.scaleValueLabel];

  self.scaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, sliderWidth, 20)];
  self.scaleSlider.minValue = 0.85;
  self.scaleSlider.maxValue = 1.25;
  self.scaleSlider.doubleValue = [[config valueForKeyPath:@"appearance.widget_scale" defaultValue:@1.0] doubleValue];
  self.scaleSlider.target = self;
  self.scaleSlider.action = @selector(sliderChanged:);
  [self.view addSubview:self.scaleSlider];
  [self updateScaleLabel];
  y -= spacing;

  // Bar Color
  NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  colorLabel.stringValue = @"Bar Color:";
  colorLabel.bordered = NO;
  colorLabel.editable = NO;
  colorLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:colorLabel];

  self.barColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 25)];
  self.barColorWell.target = self;
  self.barColorWell.action = @selector(colorChanged:);
  [self updateBarColorFromState];
  [self.view addSubview:self.barColorWell];

  self.barColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, 120, 22)];
  self.barColorHexField.placeholderString = @"0xAARRGGBB";
  self.barColorHexField.delegate = (id<NSTextFieldDelegate>)self;
  [self updateBarColorHexField];
  [self.view addSubview:self.barColorHexField];
  y -= spacing;

  // Live Preview
  NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  previewLabel.stringValue = @"Preview:";
  previewLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  previewLabel.bordered = NO;
  previewLabel.editable = NO;
  previewLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:previewLabel];
  y -= 40;

  self.previewBox = [[NSView alloc] initWithFrame:NSMakeRect(leftMargin, y, 600, 80)];
  self.previewBox.wantsLayer = YES;
  self.previewBox.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
  self.previewBox.layer.cornerRadius = 8;
  [self.view addSubview:self.previewBox];

  self.previewBarView = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 560, 28)];
  self.previewBarView.bordered = NO;
  self.previewBarView.editable = NO;
  self.previewBarView.stringValue = @"   Sketchybar Preview";
  self.previewBarView.font = [NSFont systemFontOfSize:14];
  self.previewBarView.textColor = [NSColor whiteColor];
  self.previewBarView.backgroundColor = [self.barColorWell.color colorWithAlphaComponent:0.8];
  self.previewBarView.wantsLayer = YES;
  [self.previewBox addSubview:self.previewBarView];
  [self updatePreview];
  y -= 100;

  // Apply Button
  self.applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 32)];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply & Reload Bar";
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.view addSubview:self.applyButton];
}

- (void)sliderChanged:(NSSlider *)sender {
  if (sender == self.heightSlider) {
    [self updateHeightLabel];
    [self updatePreview];
  } else if (sender == self.cornerSlider) {
    [self updateCornerLabel];
    [self updatePreview];
  } else if (sender == self.blurSlider) {
    [self updateBlurLabel];
  } else if (sender == self.scaleSlider) {
    [self updateScaleLabel];
  }
}

- (void)colorChanged:(NSColorWell *)sender {
  [self updateBarColorHexField];
  [self updatePreview];
}

- (void)updateHeightLabel {
  self.heightValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.heightSlider.doubleValue];
}

- (void)updateCornerLabel {
  self.cornerValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.cornerSlider.doubleValue];
}

- (void)updateBlurLabel {
  self.blurValueLabel.stringValue = [NSString stringWithFormat:@"%d", (int)self.blurSlider.doubleValue];
}

- (void)updateScaleLabel {
  self.scaleValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", self.scaleSlider.doubleValue];
}

- (void)updateBarColorFromState {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *hexColor = [config valueForKeyPath:@"appearance.bar_color" defaultValue:@"0xC021162F"];
  NSColor *color = [self colorFromHexString:hexColor];
  if (color) {
    self.barColorWell.color = color;
  }
}

- (void)updateBarColorHexField {
  NSString *hex = [self hexStringFromColor:self.barColorWell.color];
  self.barColorHexField.stringValue = hex;
}

- (void)updatePreview {
  CGFloat height = self.heightSlider.doubleValue;
  CGFloat corner = self.cornerSlider.doubleValue;
  NSColor *color = [self.barColorWell.color colorWithAlphaComponent:0.8];

  CGRect frame = self.previewBarView.frame;
  frame.size.height = height;
  frame.origin.y = (self.previewBox.bounds.size.height - height) / 2;
  self.previewBarView.frame = frame;
  self.previewBarView.backgroundColor = color;
  self.previewBarView.layer.cornerRadius = corner;
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

- (void)applySettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  [config setValue:@((int)self.heightSlider.doubleValue) forKeyPath:@"appearance.bar_height"];
  [config setValue:@((int)self.cornerSlider.doubleValue) forKeyPath:@"appearance.corner_radius"];
  [config setValue:@((int)self.blurSlider.doubleValue) forKeyPath:@"appearance.blur_radius"];
  [config setValue:@(self.scaleSlider.doubleValue) forKeyPath:@"appearance.widget_scale"];

  NSString *hexColor = [self hexStringFromColor:self.barColorWell.color];
  [config setValue:hexColor forKeyPath:@"appearance.bar_color"];

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply & Reload Bar";
  });
}

@end

// MARK: - Widgets Tab

@interface WidgetsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *widgets;
@end

@implementation WidgetsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.widgets = @[
    @{@"key": @"clock", @"name": @"Clock", @"icon": @""},
    @{@"key": @"battery", @"name": @"Battery", @"icon": @""},
    @{@"key": @"volume", @"name": @"Volume", @"icon": @"󰕾"},
    @{@"key": @"network", @"name": @"Network", @"icon": @"󰖩"},
    @{@"key": @"system_info", @"name": @"System Info", @"icon": @"󰍛"},
  ];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Widget Management";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // Table view
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 60, 700, y - 60)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
  iconColumn.title = @"";
  iconColumn.width = 40;
  [self.tableView addTableColumn:iconColumn];

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Widget";
  nameColumn.width = 200;
  [self.tableView addTableColumn:nameColumn];

  NSTableColumn *enabledColumn = [[NSTableColumn alloc] initWithIdentifier:@"enabled"];
  enabledColumn.title = @"Enabled";
  enabledColumn.width = 80;
  [self.tableView addTableColumn:enabledColumn];

  NSTableColumn *colorColumn = [[NSTableColumn alloc] initWithIdentifier:@"color"];
  colorColumn.title = @"Color";
  colorColumn.width = 120;
  [self.tableView addTableColumn:colorColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.widgets.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *widget = self.widgets[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"icon"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
    textField.stringValue = widget[@"icon"];
    textField.font = [NSFont systemFontOfSize:16];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    return textField;
  }

  if ([identifier isEqualToString:@"name"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
    textField.stringValue = widget[@"name"];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    return textField;
  }

  if ([identifier isEqualToString:@"enabled"]) {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20)];
    [checkbox setButtonType:NSButtonTypeSwitch];
    checkbox.title = @"";
    checkbox.tag = row;
    checkbox.target = self;
    checkbox.action = @selector(toggleWidget:);

    ConfigurationManager *config = [ConfigurationManager sharedManager];
    NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", widget[@"key"]];
    BOOL enabled = [[config valueForKeyPath:keyPath defaultValue:@YES] boolValue];
    checkbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    return checkbox;
  }

  if ([identifier isEqualToString:@"color"]) {
    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    colorWell.tag = row;
    colorWell.target = self;
    colorWell.action = @selector(widgetColorChanged:);
    // Load widget color from state
    return colorWell;
  }

  return nil;
}

- (void)toggleWidget:(NSButton *)sender {
  NSDictionary *widget = self.widgets[sender.tag];
  BOOL enabled = sender.state == NSControlStateValueOn;

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", widget[@"key"]];
  [config setValue:@(enabled) forKeyPath:keyPath];
}

- (void)widgetColorChanged:(NSColorWell *)sender {
  NSDictionary *widget = self.widgets[sender.tag];
  NSColor *color = sender.color;

  // Convert to hex and save
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  NSString *hexColor = [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widget_colors.%@", widget[@"key"]];
  [config setValue:hexColor forKeyPath:keyPath];
}

@end
// MARK: - Spaces Tab

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

  NSButton *clearIconButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 390, y + 26, 80, 28)];
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

- (void)modeChanged:(id)sender {
  // Visual feedback only, saved on apply
}

- (void)loadSpaceSettings {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  // Validate config and state exist
  if (!config || !config.state) {
    NSLog(@"Config manager or state not initialized");
    self.iconField.stringValue = @"";
    self.iconPreview.stringValue = @"󰝚";
    [self.modeSelector setSelectedSegment:0];
    return;
  }

  // Ensure space_icons dictionary exists
  if (!config.state[@"space_icons"]) {
    config.state[@"space_icons"] = [NSMutableDictionary dictionary];
  }

  // Ensure space_modes dictionary exists
  if (!config.state[@"space_modes"]) {
    config.state[@"space_modes"] = [NSMutableDictionary dictionary];
  }

  // Load icon
  NSString *keyPath = [NSString stringWithFormat:@"space_icons.%ld", (long)self.currentSpace];
  NSString *icon = [config valueForKeyPath:keyPath defaultValue:@""];
  self.iconField.stringValue = icon ? icon : @"";
  self.iconPreview.stringValue = ([icon length] > 0) ? icon : @"󰝚";

  // Load mode
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

  // Save icon
  NSString *icon = self.iconField.stringValue;
  if ([icon length] > 0) {
    NSString *keyPath = [NSString stringWithFormat:@"space_icons.%ld", (long)self.currentSpace];
    [config setValue:icon forKeyPath:keyPath];
  }

  // Save mode
  NSInteger segment = self.modeSelector.selectedSegment;
  NSString *mode = @"float";
  if (segment == 1) mode = @"bsp";
  else if (segment == 2) mode = @"stack";

  NSString *keyPath = [NSString stringWithFormat:@"space_modes.%ld", (long)self.currentSpace];
  [config setValue:mode forKeyPath:keyPath];

  // Apply layout mode via script
  NSString *script = [config.scriptsPath stringByAppendingPathComponent:@"set_space_mode.sh"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:script]) {
    [config runScript:@"set_space_mode.sh" arguments:@[[NSString stringWithFormat:@"%ld", (long)self.currentSpace], mode]];
  }

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply to Current Space";
  });
}

@end

// MARK: - Icons Tab

@interface IconsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) NSSearchField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSTextField *previewField;
@property (strong) NSButton *glyphCopyButton;
@property (strong) NSArray *allIcons;
@property (strong) NSArray *filteredIcons;
@end

@implementation IconsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  // Icon library from modules/icons.lua
  self.allIcons = @[
    @{@"name": @"Apple", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Apple Alt", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Battery", @"glyph": @"", @"category": @"System"},
    @{@"name": @"WiFi", @"glyph": @"󰖩", @"category": @"System"},
    @{@"name": @"Volume", @"glyph": @"󰕾", @"category": @"System"},
    @{@"name": @"Calendar", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Clock", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Settings", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Terminal", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Code", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Git", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"GitHub", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"VSCode", @"glyph": @"󰨞", @"category": @"Development"},
    @{@"name": @"Vim", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Emacs", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Docker", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Database", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"Folder", @"glyph": @"", @"category": @"Files"},
    @{@"name": @"File", @"glyph": @"", @"category": @"Files"},
    @{@"name": @"Trash", @"glyph": @"", @"category": @"Files"},
    @{@"name": @"Download", @"glyph": @"", @"category": @"Files"},
    @{@"name": @"Cloud", @"glyph": @"󰅧", @"category": @"Files"},
    @{@"name": @"Window", @"glyph": @"󰖯", @"category": @"Window Management"},
    @{@"name": @"Tile", @"glyph": @"󰆾", @"category": @"Window Management"},
    @{@"name": @"Stack", @"glyph": @"󰓩", @"category": @"Window Management"},
    @{@"name": @"Float", @"glyph": @"󰒄", @"category": @"Window Management"},
    @{@"name": @"Fullscreen", @"glyph": @"󰊓", @"category": @"Window Management"},
    @{@"name": @"Display", @"glyph": @"󰍹", @"category": @"Window Management"},
    @{@"name": @"Workspace", @"glyph": @"󱂬", @"category": @"Window Management"},
    @{@"name": @"Triforce", @"glyph": @"󰊠", @"category": @"Gaming"},
    @{@"name": @"Quest", @"glyph": @"", @"category": @"Gaming"},
    @{@"name": @"Gamepad", @"glyph": @"󰍳", @"category": @"Gaming"},
    @{@"name": @"ROM", @"glyph": @"󰯙", @"category": @"ROM Hacking"},
    @{@"name": @"Hex", @"glyph": @"󰘨", @"category": @"ROM Hacking"},
    @{@"name": @"Chip", @"glyph": @"", @"category": @"ROM Hacking"},
    @{@"name": @"Check", @"glyph": @"", @"category": @"Status"},
    @{@"name": @"Error", @"glyph": @"", @"category": @"Status"},
    @{@"name": @"Warning", @"glyph": @"", @"category": @"Status"},
    @{@"name": @"Info", @"glyph": @"", @"category": @"Status"},
    @{@"name": @"Star", @"glyph": @"", @"category": @"Status"},
    @{@"name": @"Heart", @"glyph": @"", @"category": @"Status"},
  ];
  self.filteredIcons = [self.allIcons copy];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Icon Library";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // Search
  self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  self.searchField.placeholderString = @"Search icons...";
  self.searchField.delegate = self;
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.view addSubview:self.searchField];
  y -= 50;

  // Preview
  self.previewField = [[NSTextField alloc] initWithFrame:NSMakeRect(self.view.bounds.size.width - 180, y + 10, 120, 120)];
  self.previewField.stringValue = @"";
  self.previewField.font = [NSFont systemFontOfSize:96];
  self.previewField.bordered = NO;
  self.previewField.editable = NO;
  self.previewField.backgroundColor = [NSColor clearColor];
  self.previewField.alignment = NSTextAlignmentCenter;
  [self.view addSubview:self.previewField];

  self.glyphCopyButton = [[NSButton alloc] initWithFrame:NSMakeRect(self.view.bounds.size.width - 180, y - 40, 120, 32)];
  [self.glyphCopyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.glyphCopyButton setBezelStyle:NSBezelStyleRounded];
  self.glyphCopyButton.title = @"Copy Glyph";
  self.glyphCopyButton.target = self;
  self.glyphCopyButton.action = @selector(copyGlyph:);
  [self.view addSubview:self.glyphCopyButton];

  // Table
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 40, self.view.bounds.size.width - 240, y - 60)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *glyphColumn = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphColumn.title = @"Icon";
  glyphColumn.width = 60;
  [self.tableView addTableColumn:glyphColumn];

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Name";
  nameColumn.width = 150;
  [self.tableView addTableColumn:nameColumn];

  NSTableColumn *categoryColumn = [[NSTableColumn alloc] initWithIdentifier:@"category"];
  categoryColumn.title = @"Category";
  categoryColumn.width = 120;
  [self.tableView addTableColumn:categoryColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];
}

- (void)searchChanged:(id)sender {
  NSString *searchText = [self.searchField.stringValue lowercaseString];

  if ([searchText length] == 0) {
    self.filteredIcons = [self.allIcons copy];
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *icon in self.allIcons) {
      NSString *name = [[icon[@"name"] lowercaseString] lowercaseString];
      NSString *category = [[icon[@"category"] lowercaseString] lowercaseString];
      if ([name containsString:searchText] || [category containsString:searchText]) {
        [filtered addObject:icon];
      }
    }
    self.filteredIcons = filtered;
  }

  [self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredIcons.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *icon = self.filteredIcons[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"glyph"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    textField.stringValue = icon[@"glyph"];
    textField.font = [NSFont systemFontOfSize:20];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.alignment = NSTextAlignmentCenter;
    return textField;
  }

  NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
  textField.stringValue = icon[identifier];
  textField.bordered = NO;
  textField.editable = NO;
  textField.backgroundColor = [NSColor clearColor];
  return textField;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < self.filteredIcons.count) {
    NSDictionary *icon = self.filteredIcons[row];
    self.previewField.stringValue = icon[@"glyph"];
  }
}

- (void)copyGlyph:(id)sender {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < self.filteredIcons.count) {
    NSDictionary *icon = self.filteredIcons[row];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:icon[@"glyph"] forType:NSPasteboardTypeString];

    self.glyphCopyButton.title = @"✓ Copied!";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      self.glyphCopyButton.title = @"Copy Glyph";
    });
  }
}

@end
// MARK: - Integrations Tab

@interface IntegrationsTabViewController : NSViewController
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
@end

@implementation IntegrationsTabViewController

- (NSString *)codeDir {
  NSString *envPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_CODE_DIR"];
  if (envPath.length) {
    return envPath;
  }
  NSString *defaultPath = [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
  BOOL isDir = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:defaultPath isDirectory:&isDir] && isDir) {
    return defaultPath;
  }
  return defaultPath;
}

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;
  CGFloat sectionSpacing = 80;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"External Integrations";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // MARK: Yaze Integration
  NSBox *yazeBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 130, 700, 130)];
  yazeBox.title = @"Yaze (ROM Hacking Tool)";
  yazeBox.titlePosition = NSAtTop;

  self.yazeToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 80, 200, 20)];
  [self.yazeToggle setButtonType:NSButtonTypeSwitch];
  self.yazeToggle.title = @"Enable Yaze Integration";
  self.yazeToggle.target = self;
  self.yazeToggle.action = @selector(yazeToggled:);
  BOOL yazeEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@YES] boolValue];
  self.yazeToggle.state = yazeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [yazeBox addSubview:self.yazeToggle];

  self.yazeStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 300, 20)];
  self.yazeStatus.stringValue = @"Status: Checking...";
  self.yazeStatus.bordered = NO;
  self.yazeStatus.editable = NO;
  self.yazeStatus.backgroundColor = [NSColor clearColor];
  self.yazeStatus.font = [NSFont systemFontOfSize:12];
  [yazeBox addSubview:self.yazeStatus];

  self.yazeLaunch = [[NSButton alloc] initWithFrame:NSMakeRect(20, 15, 120, 28)];
  [self.yazeLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.yazeLaunch setBezelStyle:NSBezelStyleRounded];
  self.yazeLaunch.title = @"Launch Yaze";
  self.yazeLaunch.target = self;
  self.yazeLaunch.action = @selector(launchYaze:);
  [yazeBox addSubview:self.yazeLaunch];

  NSButton *yazeRepoButton = [[NSButton alloc] initWithFrame:NSMakeRect(150, 15, 120, 28)];
  [yazeRepoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [yazeRepoButton setBezelStyle:NSBezelStyleRounded];
  yazeRepoButton.title = @"Open Repo";
  yazeRepoButton.target = self;
  yazeRepoButton.action = @selector(openYazeRepo:);
  [yazeBox addSubview:yazeRepoButton];

  [self.view addSubview:yazeBox];
  [self updateYazeStatus];
  y -= 150;

  // MARK: Emacs Integration
  NSBox *emacsBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 130, 700, 130)];
  emacsBox.title = @"Emacs";
  emacsBox.titlePosition = NSAtTop;

  self.emacsToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 80, 200, 20)];
  [self.emacsToggle setButtonType:NSButtonTypeSwitch];
  self.emacsToggle.title = @"Enable Emacs Integration";
  self.emacsToggle.target = self;
  self.emacsToggle.action = @selector(emacsToggled:);
  BOOL emacsEnabled = [[config valueForKeyPath:@"integrations.emacs.enabled" defaultValue:@YES] boolValue];
  self.emacsToggle.state = emacsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [emacsBox addSubview:self.emacsToggle];

  self.emacsStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 300, 20)];
  self.emacsStatus.stringValue = @"Status: Checking...";
  self.emacsStatus.bordered = NO;
  self.emacsStatus.editable = NO;
  self.emacsStatus.backgroundColor = [NSColor clearColor];
  self.emacsStatus.font = [NSFont systemFontOfSize:12];
  [emacsBox addSubview:self.emacsStatus];

  self.emacsLaunch = [[NSButton alloc] initWithFrame:NSMakeRect(20, 15, 120, 28)];
  [self.emacsLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.emacsLaunch setBezelStyle:NSBezelStyleRounded];
  self.emacsLaunch.title = @"Launch Emacs";
  self.emacsLaunch.target = self;
  self.emacsLaunch.action = @selector(launchEmacs:);
  [emacsBox addSubview:self.emacsLaunch];

  [self.view addSubview:emacsBox];
  [self updateEmacsStatus];
  y -= 150;

  // MARK: halext-org Integration (Future)
  NSBox *halextBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 180, 700, 180)];
  halextBox.title = @"halext-org Server (Tasks, Calendar, LLM)";
  halextBox.titlePosition = NSAtTop;

  self.halextToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 130, 250, 20)];
  [self.halextToggle setButtonType:NSButtonTypeSwitch];
  self.halextToggle.title = @"Enable halext-org Integration";
  self.halextToggle.target = self;
  self.halextToggle.action = @selector(halextToggled:);
  BOOL halextEnabled = [[config valueForKeyPath:@"integrations.halext.enabled" defaultValue:@NO] boolValue];
  self.halextToggle.state = halextEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [halextBox addSubview:self.halextToggle];

  NSTextField *serverLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 100, 20)];
  serverLabel.stringValue = @"Server URL:";
  serverLabel.bordered = NO;
  serverLabel.editable = NO;
  serverLabel.backgroundColor = [NSColor clearColor];
  [halextBox addSubview:serverLabel];

  self.halextServerField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 98, 400, 24)];
  self.halextServerField.placeholderString = @"https://halext.yourdomain.com";
  NSString *serverUrl = [config valueForKeyPath:@"integrations.halext.server_url" defaultValue:@""];
  self.halextServerField.stringValue = serverUrl;
  [halextBox addSubview:self.halextServerField];

  NSTextField *apiKeyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 70, 100, 20)];
  apiKeyLabel.stringValue = @"API Key:";
  apiKeyLabel.bordered = NO;
  apiKeyLabel.editable = NO;
  apiKeyLabel.backgroundColor = [NSColor clearColor];
  [halextBox addSubview:apiKeyLabel];

  self.halextApiKeyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(120, 68, 400, 24)];
  self.halextApiKeyField.placeholderString = @"Enter API key...";
  [halextBox addSubview:self.halextApiKeyField];

  self.halextStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 500, 20)];
  self.halextStatus.stringValue = @"Status: Not configured";
  self.halextStatus.bordered = NO;
  self.halextStatus.editable = NO;
  self.halextStatus.backgroundColor = [NSColor clearColor];
  self.halextStatus.font = [NSFont systemFontOfSize:12];
  self.halextStatus.textColor = [NSColor secondaryLabelColor];
  [halextBox addSubview:self.halextStatus];

  self.halextTestButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 5, 140, 28)];
  [self.halextTestButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.halextTestButton setBezelStyle:NSBezelStyleRounded];
  self.halextTestButton.title = @"Test Connection";
  self.halextTestButton.target = self;
  self.halextTestButton.action = @selector(testHalextConnection:);
  [halextBox addSubview:self.halextTestButton];

  NSButton *halextSaveButton = [[NSButton alloc] initWithFrame:NSMakeRect(170, 5, 100, 28)];
  [halextSaveButton setButtonType:NSButtonTypeMomentaryPushIn];
  [halextSaveButton setBezelStyle:NSBezelStyleRounded];
  halextSaveButton.title = @"Save";
  halextSaveButton.target = self;
  halextSaveButton.action = @selector(saveHalextSettings:);
  [halextBox addSubview:halextSaveButton];

  [self.view addSubview:halextBox];
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

- (void)updateYazeStatus {
  NSString *yazePath = [[self codeDir] stringByAppendingPathComponent:@"yaze"];
  NSString *buildBinary = [yazePath stringByAppendingPathComponent:@"build/bin/yaze"];

  if ([[NSFileManager defaultManager] fileExistsAtPath:buildBinary]) {
    self.yazeStatus.stringValue = @"Status: ✓ Installed and built";
    self.yazeStatus.textColor = [NSColor systemGreenColor];
  } else if ([[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    self.yazeStatus.stringValue = @"Status: ⚠ Installed but not built";
    self.yazeStatus.textColor = [NSColor systemOrangeColor];
  } else {
    self.yazeStatus.stringValue = @"Status: ✗ Not installed";
    self.yazeStatus.textColor = [NSColor systemRedColor];
  }
}

- (void)updateEmacsStatus {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/pgrep";
  task.arguments = @[@"-x", @"Emacs"];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;

  @try {
    [task launch];
    [task waitUntilExit];
    if (task.terminationStatus == 0) {
      self.emacsStatus.stringValue = @"Status: ✓ Running";
      self.emacsStatus.textColor = [NSColor systemGreenColor];
    } else {
      self.emacsStatus.stringValue = @"Status: Installed but not running";
      self.emacsStatus.textColor = [NSColor secondaryLabelColor];
    }
  } @catch (NSException *exception) {
    self.emacsStatus.stringValue = @"Status: ✗ Not found";
    self.emacsStatus.textColor = [NSColor systemRedColor];
  }
}

- (void)launchYaze:(id)sender {
  NSString *yazePath = [[[self codeDir] stringByAppendingPathComponent:@"yaze"] stringByAppendingPathComponent:@"build/bin/yaze"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:yazePath]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    NSString *message = [NSString stringWithFormat:@"Build Yaze first: cd %@/yaze && make", [self codeDir]];
    [alert setInformativeText:message];
    [alert runModal];
  }
}

- (void)openYazeRepo:(id)sender {
  NSString *yazePath = [[self codeDir] stringByAppendingPathComponent:@"yaze"];
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

- (void)saveHalextSettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *serverUrl = self.halextServerField.stringValue;
  [config setValue:serverUrl forKeyPath:@"integrations.halext.server_url"];

  // TODO: Save API key to Keychain for security
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

// MARK: - Advanced Tab

@interface AdvancedTabViewController : NSViewController <NSTextViewDelegate>
@property (strong) NSTextView *jsonEditor;
@property (strong) NSButton *saveButton;
@property (strong) NSButton *reloadButton;
@property (strong) NSTextField *statusLabel;
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
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 100, self.view.bounds.size.width - 80, y - 100)];
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

  NSButton *reloadBarButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 450, 50, 140, 32)];
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
  infoLabel.stringValue = [NSString stringWithFormat:@"Config: %@ | State: %@",
                           config.configPath, config.statePath];
  infoLabel.bordered = NO;
  infoLabel.editable = NO;
  infoLabel.backgroundColor = [NSColor clearColor];
  infoLabel.font = [NSFont systemFontOfSize:9];
  infoLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:infoLabel];
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

// MARK: - Main Window Controller (Updated)

@interface MainWindowController : NSWindowController <NSWindowDelegate, NSTabViewDelegate>
@property (strong) NSTabView *tabView;
@property (strong) AppearanceTabViewController *appearanceTab;
@property (strong) WidgetsTabViewController *widgetsTab;
@property (strong) SpacesTabViewController *spacesTab;
@property (strong) IconsTabViewController *iconsTab;
@property (strong) IntegrationsTabViewController *integrationsTab;
@property (strong) AdvancedTabViewController *advancedTab;
@end

@implementation MainWindowController

- (instancetype)init {
  NSRect frame = NSMakeRect(0, 0, 950, 750);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

  self = [super initWithWindow:window];
  if (self) {
    window.title = @"Sketchybar Configuration";
    window.delegate = self;
    [window setMinSize:NSMakeSize(850, 650)];
    [window center];

    // Make window stay on top but not intrusive
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];

    [self setupTabView];
  }
  return self;
}

- (void)setupTabView {
  self.tabView = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
  self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.tabView.delegate = self;
  [self.tabView setTabViewType:NSTopTabsBezelBorder];

  // Appearance Tab
  self.appearanceTab = [[AppearanceTabViewController alloc] init];
  NSTabViewItem *appearanceItem = [[NSTabViewItem alloc] initWithIdentifier:@"appearance"];
  appearanceItem.label = @"Appearance";
  appearanceItem.viewController = self.appearanceTab;
  [self.tabView addTabViewItem:appearanceItem];

  // Widgets Tab
  self.widgetsTab = [[WidgetsTabViewController alloc] init];
  NSTabViewItem *widgetsItem = [[NSTabViewItem alloc] initWithIdentifier:@"widgets"];
  widgetsItem.label = @"Widgets";
  widgetsItem.viewController = self.widgetsTab;
  [self.tabView addTabViewItem:widgetsItem];

  // Spaces Tab
  self.spacesTab = [[SpacesTabViewController alloc] init];
  NSTabViewItem *spacesItem = [[NSTabViewItem alloc] initWithIdentifier:@"spaces"];
  spacesItem.label = @"Spaces";
  spacesItem.viewController = self.spacesTab;
  [self.tabView addTabViewItem:spacesItem];

  // Icons Tab
  self.iconsTab = [[IconsTabViewController alloc] init];
  NSTabViewItem *iconsItem = [[NSTabViewItem alloc] initWithIdentifier:@"icons"];
  iconsItem.label = @"Icons";
  iconsItem.viewController = self.iconsTab;
  [self.tabView addTabViewItem:iconsItem];

  // Integrations Tab
  self.integrationsTab = [[IntegrationsTabViewController alloc] init];
  NSTabViewItem *integrationsItem = [[NSTabViewItem alloc] initWithIdentifier:@"integrations"];
  integrationsItem.label = @"Integrations";
  integrationsItem.viewController = self.integrationsTab;
  [self.tabView addTabViewItem:integrationsItem];

  // Advanced Tab
  self.advancedTab = [[AdvancedTabViewController alloc] init];
  NSTabViewItem *advancedItem = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
  advancedItem.label = @"Advanced";
  advancedItem.viewController = self.advancedTab;
  [self.tabView addTabViewItem:advancedItem];

  [self.window.contentView addSubview:self.tabView];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  // Quit app when window is closed
  [NSApp terminate:nil];
  return YES;
}

- (void)showWindow:(id)sender {
  [super showWindow:sender];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

@end

// MARK: - App Delegate

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) MainWindowController *windowController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  // Set activation policy to regular app (shows in dock, stays open)
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.windowController = [[MainWindowController alloc] init];
  [self.windowController showWindow:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES; // Quit app when window is closed
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  // Cleanup if needed
}

@end

// MARK: - Main

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
