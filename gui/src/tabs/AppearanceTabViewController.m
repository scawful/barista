#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

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
// Font Settings
@property (strong) NSPopUpButton *clockFontMenu;
@property (strong) NSTextField *clockFontFamilyField;
// Menu Icons
@property (strong) NSPopUpButton *appleIconMenu;
@property (strong) NSPopUpButton *questIconMenu;
@property (strong) NSTextField *appleIconPreviewField;
@property (strong) NSTextField *questIconPreviewField;
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
  CGFloat spacing = 60;

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
  y -= spacing + 10;

  // Font Settings
  NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  fontLabel.stringValue = @"Clock Font:";
  fontLabel.bordered = NO;
  fontLabel.editable = NO;
  fontLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:fontLabel];

  self.clockFontMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 3, 120, 26)];
  NSArray *fontOptions = @[ @"Regular", @"Medium", @"Semibold", @"Bold", @"Heavy" ];
  for (NSString *option in fontOptions) {
    [self.clockFontMenu addItemWithTitle:option];
  }
  NSString *currentFont = [config valueForKeyPath:@"appearance.clock_font_style" defaultValue:@"Bold"];
  [self.clockFontMenu selectItemWithTitle:currentFont];
  self.clockFontMenu.target = self;
  self.clockFontMenu.action = @selector(clockFontChanged:);
  [self.view addSubview:self.clockFontMenu];

  self.clockFontFamilyField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 300, y, 200, 22)];
  self.clockFontFamilyField.placeholderString = @"Font Family (e.g. SF Mono)";
  NSString *currentFamily = [config valueForKeyPath:@"appearance.clock_font_family" defaultValue:@"SF Pro"];
  self.clockFontFamilyField.stringValue = currentFamily;
  [self.view addSubview:self.clockFontFamilyField];
  y -= spacing + 10;

  // Menu Icons
  NSTextField *menuIconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  menuIconLabel.stringValue = @"Menu Icons:";
  menuIconLabel.bordered = NO;
  menuIconLabel.editable = NO;
  menuIconLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:menuIconLabel];

  NSArray *iconChoices = @[
    @{ @"title": @"Apple", @"glyph": @"" },
    @{ @"title": @"Alt Apple", @"glyph": @"" },
    @{ @"title": @"Gear", @"glyph": @"" },
    @{ @"title": @"Triforce", @"glyph": @"󰊠" },
    @{ @"title": @"Quest", @"glyph": @"" },
    @{ @"title": @"Gamepad", @"glyph": @"󰍳" }
  ];

  // Apple Icon
  self.appleIconMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 3, 120, 26)];
  for (NSDictionary *option in iconChoices) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"glyph"];
    [self.appleIconMenu.menu addItem:item];
  }
  NSString *appleCurrent = [config valueForKeyPath:@"icons.apple" defaultValue:@""];
  [self selectMenu:self.appleIconMenu matchingValue:appleCurrent];
  self.appleIconMenu.tag = 0;
  self.appleIconMenu.target = self;
  self.appleIconMenu.action = @selector(menuIconChanged:);
  [self.view addSubview:self.appleIconMenu];

  self.appleIconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 290, y, 30, 22)];
  self.appleIconPreviewField.bordered = NO;
  self.appleIconPreviewField.editable = NO;
  self.appleIconPreviewField.backgroundColor = [NSColor clearColor];
  self.appleIconPreviewField.font = [NSFont systemFontOfSize:16];
  [self.view addSubview:self.appleIconPreviewField];

  // Quest Icon
  self.questIconMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 340, y - 3, 120, 26)];
  for (NSDictionary *option in iconChoices) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"glyph"];
    [self.questIconMenu.menu addItem:item];
  }
  NSString *questCurrent = [config valueForKeyPath:@"icons.quest" defaultValue:@""];
  [self selectMenu:self.questIconMenu matchingValue:questCurrent];
  self.questIconMenu.tag = 1;
  self.questIconMenu.target = self;
  self.questIconMenu.action = @selector(menuIconChanged:);
  [self.view addSubview:self.questIconMenu];

  self.questIconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 470, y, 30, 22)];
  self.questIconPreviewField.bordered = NO;
  self.questIconPreviewField.editable = NO;
  self.questIconPreviewField.backgroundColor = [NSColor clearColor];
  self.questIconPreviewField.font = [NSFont systemFontOfSize:16];
  [self.view addSubview:self.questIconPreviewField];
  
  [self updateMenuIconPreview];
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
  y -= 80;

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

- (void)clockFontChanged:(id)sender {
  // Will be saved on Apply
}

- (void)menuIconChanged:(id)sender {
  [self updateMenuIconPreview];
}

- (void)updateMenuIconPreview {
  NSString *appleGlyph = self.appleIconMenu.selectedItem.representedObject;
  NSString *questGlyph = self.questIconMenu.selectedItem.representedObject;
  self.appleIconPreviewField.stringValue = appleGlyph ?: @"";
  self.questIconPreviewField.stringValue = questGlyph ?: @"";
}

- (void)selectMenu:(NSPopUpButton *)menu matchingValue:(NSString *)value {
  if (!menu || !value) return;
  for (NSMenuItem *item in menu.itemArray) {
    if ([item.representedObject isEqual:value]) {
      [menu selectItem:item];
      return;
    }
  }
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

  // Save Fonts
  [config setValue:self.clockFontMenu.selectedItem.title forKeyPath:@"appearance.clock_font_style"];
  [config setValue:self.clockFontFamilyField.stringValue forKeyPath:@"appearance.clock_font_family"];

  // Save Icons
  [config setValue:self.appleIconMenu.selectedItem.representedObject forKeyPath:@"icons.apple"];
  [config setValue:self.questIconMenu.selectedItem.representedObject forKeyPath:@"icons.quest"];

  // Run scripts to apply individual settings if needed, or just reload
  // Ideally we would have specific scripts, but reloading sketchybar often picks up state changes if the bar config reads from state.json
  // The original config_menu.m ran specific scripts. Let's replicate that for font/icons if critical.
  // For now, reloading sketchybar is the main mechanism.
  
  [config runScript:@"set_menu_icon.sh" arguments:@[@"apple", self.appleIconMenu.selectedItem.representedObject]];
  [config runScript:@"set_menu_icon.sh" arguments:@[@"quest", self.questIconMenu.selectedItem.representedObject]];
  [config runScript:@"set_clock_font.sh" arguments:@[self.clockFontMenu.selectedItem.title]];

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply & Reload Bar";
  });
}

@end
