#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface AppearanceTabViewController : NSViewController <NSTextFieldDelegate>
@property (strong) NSSlider *heightSlider;
@property (strong) NSTextField *heightValueLabel;
@property (strong) NSSlider *cornerSlider;
@property (strong) NSTextField *cornerValueLabel;
@property (strong) NSSlider *blurSlider;
@property (strong) NSTextField *blurValueLabel;
@property (strong) NSSlider *scaleSlider;
@property (strong) NSTextField *scaleValueLabel;
@property (strong) NSSlider *widgetCornerSlider;
@property (strong) NSTextField *widgetCornerValueLabel;
@property (strong) NSColorWell *barColorWell;
@property (strong) NSTextField *barColorHexField;
@property (strong) NSTextField *menuIconField;
@property (strong) NSTextField *menuIconPreview;
@property (strong) NSButton *menuIconBrowseButton;
@property (strong) NSTextField *fontIconField;
@property (strong) NSTextField *fontTextField;
@property (strong) NSTextField *fontNumbersField;
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
  CGFloat spacing = 56;

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

  // Widget Corner Radius
  NSTextField *widgetCornerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  widgetCornerLabel.stringValue = @"Widget Radius:";
  widgetCornerLabel.bordered = NO;
  widgetCornerLabel.editable = NO;
  widgetCornerLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:widgetCornerLabel];

  self.widgetCornerValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y, 60, 20)];
  self.widgetCornerValueLabel.bordered = NO;
  self.widgetCornerValueLabel.editable = NO;
  self.widgetCornerValueLabel.backgroundColor = [NSColor clearColor];
  self.widgetCornerValueLabel.alignment = NSTextAlignmentRight;
  [self.view addSubview:self.widgetCornerValueLabel];

  self.widgetCornerSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(leftMargin + 230, y, sliderWidth, 20)];
  self.widgetCornerSlider.minValue = 0;
  self.widgetCornerSlider.maxValue = 16;
  self.widgetCornerSlider.doubleValue = [[config valueForKeyPath:@"appearance.widget_corner_radius" defaultValue:@6] doubleValue];
  self.widgetCornerSlider.target = self;
  self.widgetCornerSlider.action = @selector(sliderChanged:);
  [self.view addSubview:self.widgetCornerSlider];
  [self updateWidgetCornerLabel];
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
  self.barColorHexField.delegate = self;
  [self updateBarColorHexField];
  [self.view addSubview:self.barColorHexField];
  y -= spacing;

  // System Menu Icon
  NSTextField *menuIconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  menuIconLabel.stringValue = @"System Menu Icon:";
  menuIconLabel.bordered = NO;
  menuIconLabel.editable = NO;
  menuIconLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:menuIconLabel];

  self.menuIconField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 2, 60, 24)];
  self.menuIconField.placeholderString = @"Glyph";
  self.menuIconField.delegate = self;
  NSString *currentMenuIcon = [config valueForKeyPath:@"icons.apple" defaultValue:@"󰒓"];
  self.menuIconField.stringValue = [currentMenuIcon isKindOfClass:[NSString class]] ? currentMenuIcon : @"";
  [self.view addSubview:self.menuIconField];

  self.menuIconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 230, y - 6, 40, 32)];
  self.menuIconPreview.bordered = NO;
  self.menuIconPreview.editable = NO;
  self.menuIconPreview.backgroundColor = [NSColor clearColor];
  self.menuIconPreview.alignment = NSTextAlignmentCenter;
  self.menuIconPreview.font = [NSFont fontWithName:@"Symbols Nerd Font" size:20] ?: [NSFont systemFontOfSize:20];
  [self.view addSubview:self.menuIconPreview];

  self.menuIconBrowseButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 290, y - 2, 140, 24)];
  [self.menuIconBrowseButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.menuIconBrowseButton setBezelStyle:NSBezelStyleRounded];
  self.menuIconBrowseButton.title = @"Icon Browser";
  self.menuIconBrowseButton.target = self;
  self.menuIconBrowseButton.action = @selector(openIconBrowser:);
  [self.view addSubview:self.menuIconBrowseButton];

  [self updateMenuIconPreview];
  y -= spacing;

  // Fonts
  NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 150, 20)];
  fontLabel.stringValue = @"Fonts:";
  fontLabel.bordered = NO;
  fontLabel.editable = NO;
  fontLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:fontLabel];

  self.fontIconField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 2, 220, 24)];
  self.fontIconField.placeholderString = @"Icon font (e.g. Hack Nerd Font)";
  self.fontIconField.delegate = self;
  self.fontIconField.stringValue = [config valueForKeyPath:@"appearance.font_icon" defaultValue:@""] ?: @"";
  [self.view addSubview:self.fontIconField];

  self.fontTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 390, y - 2, 220, 24)];
  self.fontTextField.placeholderString = @"Text font (e.g. Source Code Pro)";
  self.fontTextField.delegate = self;
  self.fontTextField.stringValue = [config valueForKeyPath:@"appearance.font_text" defaultValue:@""] ?: @"";
  [self.view addSubview:self.fontTextField];
  y -= 34;

  self.fontNumbersField = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 160, y - 2, 220, 24)];
  self.fontNumbersField.placeholderString = @"Numbers font (e.g. SF Mono)";
  self.fontNumbersField.delegate = self;
  self.fontNumbersField.stringValue = [config valueForKeyPath:@"appearance.font_numbers" defaultValue:@""] ?: @"";
  [self.view addSubview:self.fontNumbersField];
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
  } else if (sender == self.widgetCornerSlider) {
    [self updateWidgetCornerLabel];
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

- (void)updateMenuIconPreview {
  NSString *icon = self.menuIconField.stringValue ?: @"";
  self.menuIconPreview.stringValue = icon;
}

- (void)openIconBrowser:(id)sender {
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

- (void)controlTextDidChange:(NSNotification *)notification {
  id field = notification.object;
  if (field == self.barColorHexField) {
    NSColor *color = [self colorFromHexString:self.barColorHexField.stringValue];
    if (color) {
      self.barColorWell.color = color;
      [self updatePreview];
    }
  } else if (field == self.menuIconField) {
    [self updateMenuIconPreview];
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
  [config setValue:@((int)self.widgetCornerSlider.doubleValue) forKeyPath:@"appearance.widget_corner_radius"];

  NSString *hexColor = [self hexStringFromColor:self.barColorWell.color];
  [config setValue:hexColor forKeyPath:@"appearance.bar_color"];

  NSString *menuIcon = self.menuIconField.stringValue ?: @"";
  [config setValue:menuIcon forKeyPath:@"icons.apple"];

  if (self.fontIconField.stringValue.length > 0) {
    [config setValue:self.fontIconField.stringValue forKeyPath:@"appearance.font_icon"];
  }
  if (self.fontTextField.stringValue.length > 0) {
    [config setValue:self.fontTextField.stringValue forKeyPath:@"appearance.font_text"];
  }
  if (self.fontNumbersField.stringValue.length > 0) {
    [config setValue:self.fontNumbersField.stringValue forKeyPath:@"appearance.font_numbers"];
  }

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply & Reload Bar";
  });
}

- (void)updateWidgetCornerLabel {
  if (!self.widgetCornerValueLabel) return;
  [self.widgetCornerValueLabel setStringValue:[NSString stringWithFormat:@"%0.0f", self.widgetCornerSlider.doubleValue]];
}

@end
