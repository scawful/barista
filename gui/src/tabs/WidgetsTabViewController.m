#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface WidgetsTabViewController : NSViewController
@property (strong) NSArray *widgets;
@property (strong) NSMutableDictionary *toggleButtons;
@property (strong) NSMutableDictionary *colorWells;
@end

@implementation WidgetsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.widgets = @[
    @{@"key": @"clock", @"name": @"Clock", @"icon": @"󰥔"},
    @{@"key": @"battery", @"name": @"Battery", @"icon": @"󰁹"},
    @{@"key": @"volume", @"name": @"Volume", @"icon": @"󰕾"},
    @{@"key": @"network", @"name": @"Network", @"icon": @"󰖩"},
    @{@"key": @"system_info", @"name": @"System Info", @"icon": @"󰍛"},
  ];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSInsetRect(self.view.bounds, 40, 20)];
  rootStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 20;
  rootStack.edgeInsets = NSEdgeInsetsMake(20, 0, 20, 0);
  [self.view addSubview:rootStack];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Widget Management";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hint.stringValue = @"Toggle widgets and pick accent colors. Specific icon glyphs can be customized in the Icons tab.";
  hint.font = [NSFont systemFontOfSize:13];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.bordered = NO;
  hint.editable = NO;
  hint.backgroundColor = [NSColor clearColor];
  [rootStack addView:hint inGravity:NSStackViewGravityTop];

  [rootStack setCustomSpacing:30 afterView:hint];

  self.toggleButtons = [NSMutableDictionary dictionary];
  self.colorWells = [NSMutableDictionary dictionary];

  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.rowSpacing = 16;
  grid.columnSpacing = 24;
  grid.xPlacement = NSGridCellPlacementLeading;
  grid.yPlacement = NSGridCellPlacementCenter;
  [rootStack addView:grid inGravity:NSStackViewGravityTop];

  // Header Row
  NSTextField *hIcon = [self headerLabel:@" "];
  NSTextField *hName = [self headerLabel:@"WIDGET"];
  NSTextField *hToggle = [self headerLabel:@"STATUS"];
  NSTextField *hColor = [self headerLabel:@"ACCENT COLOR"];
  [grid addRowWithViews:@[hIcon, hName, hToggle, hColor]];

  ConfigurationManager *config = [ConfigurationManager sharedManager];

  for (NSInteger index = 0; index < self.widgets.count; index++) {
    NSDictionary *widget = self.widgets[index];
    NSString *key = widget[@"key"];

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    iconField.stringValue = widget[@"icon"] ?: @"";
    iconField.font = [self preferredIconFontWithSize:18];
    iconField.bordered = NO;
    iconField.editable = NO;
    iconField.backgroundColor = [NSColor clearColor];
    iconField.alignment = NSTextAlignmentCenter;
    [iconField.widthAnchor constraintEqualToConstant:30].active = YES;

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    nameField.stringValue = widget[@"name"] ?: @"";
    nameField.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    nameField.bordered = NO;
    nameField.editable = NO;
    nameField.backgroundColor = [NSColor clearColor];
    [nameField.widthAnchor constraintEqualToConstant:180].active = YES;

    NSButton *toggle = [[NSButton alloc] initWithFrame:NSZeroRect];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.title = @"Enabled";
    toggle.font = [NSFont systemFontOfSize:13];
    toggle.target = self;
    toggle.action = @selector(toggleWidget:);
    toggle.tag = index;
    NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", key];
    BOOL enabled = [[config valueForKeyPath:keyPath defaultValue:@YES] boolValue];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.toggleButtons[key] = toggle;

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 30)];
    colorWell.target = self;
    colorWell.action = @selector(widgetColorChanged:);
    colorWell.tag = index;
    NSString *colorKeyPath = [NSString stringWithFormat:@"widget_colors.%@", key];
    id colorValue = [config valueForKeyPath:colorKeyPath defaultValue:nil];
    NSString *hexColor = [self hexStringFromValue:colorValue];
    if (hexColor) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) {
        colorWell.color = color;
      }
    }
    [colorWell.widthAnchor constraintEqualToConstant:80].active = YES;
    [colorWell.heightAnchor constraintEqualToConstant:32].active = YES;
    self.colorWells[key] = colorWell;

    [grid addRowWithViews:@[iconField, nameField, toggle, colorWell]];
  }
}

- (NSTextField *)headerLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text;
  label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (void)toggleWidget:(NSButton *)sender {
  if (sender.tag < 0 || sender.tag >= self.widgets.count) {
    return;
  }
  NSString *key = self.widgets[sender.tag][@"key"];
  BOOL enabled = sender.state == NSControlStateValueOn;

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", key];
  [config setValue:@(enabled) forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)widgetColorChanged:(NSColorWell *)sender {
  if (sender.tag < 0 || sender.tag >= self.widgets.count) {
    return;
  }
  NSString *key = self.widgets[sender.tag][@"key"];
  NSColor *color = sender.color;

  // Convert to hex and save
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  NSString *hexColor = [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widget_colors.%@", key];
  [config setValue:hexColor forKeyPath:keyPath];
  [config reloadSketchyBar];
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
  return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

- (NSString *)hexStringFromValue:(id)value {
  if ([value isKindOfClass:[NSString class]]) {
    return (NSString *)value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    unsigned int num = [(NSNumber *)value unsignedIntValue];
    return [NSString stringWithFormat:@"0x%08X", num];
  }
  return nil;
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

@end
