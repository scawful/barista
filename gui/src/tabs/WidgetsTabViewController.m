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

  self.toggleButtons = [NSMutableDictionary dictionary];
  self.colorWells = [NSMutableDictionary dictionary];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 700, 20)];
  hint.stringValue = @"Toggle widgets and pick accent colors (icon overrides live in the Icons tab).";
  hint.font = [NSFont systemFontOfSize:12];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.bordered = NO;
  hint.editable = NO;
  hint.backgroundColor = [NSColor clearColor];
  [self.view addSubview:hint];
  y -= 40;

  CGFloat iconX = leftMargin;
  CGFloat nameX = leftMargin + 36;
  CGFloat toggleX = leftMargin + 260;
  CGFloat colorX = leftMargin + 420;
  CGFloat rowHeight = 36;

  NSTextField *nameHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(nameX, y, 160, 18)];
  nameHeader.stringValue = @"Widget";
  nameHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  nameHeader.textColor = [NSColor secondaryLabelColor];
  nameHeader.bordered = NO;
  nameHeader.editable = NO;
  nameHeader.backgroundColor = [NSColor clearColor];
  [self.view addSubview:nameHeader];

  NSTextField *toggleHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(toggleX, y, 120, 18)];
  toggleHeader.stringValue = @"Enabled";
  toggleHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  toggleHeader.textColor = [NSColor secondaryLabelColor];
  toggleHeader.bordered = NO;
  toggleHeader.editable = NO;
  toggleHeader.backgroundColor = [NSColor clearColor];
  [self.view addSubview:toggleHeader];

  NSTextField *colorHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(colorX, y, 120, 18)];
  colorHeader.stringValue = @"Color";
  colorHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  colorHeader.textColor = [NSColor secondaryLabelColor];
  colorHeader.bordered = NO;
  colorHeader.editable = NO;
  colorHeader.backgroundColor = [NSColor clearColor];
  [self.view addSubview:colorHeader];
  y -= 26;

  ConfigurationManager *config = [ConfigurationManager sharedManager];

  for (NSInteger index = 0; index < self.widgets.count; index++) {
    NSDictionary *widget = self.widgets[index];
    NSString *key = widget[@"key"];

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSMakeRect(iconX, y - 2, 24, 24)];
    iconField.stringValue = widget[@"icon"] ?: @"";
    iconField.font = [self preferredIconFontWithSize:16];
    iconField.bordered = NO;
    iconField.editable = NO;
    iconField.backgroundColor = [NSColor clearColor];
    iconField.alignment = NSTextAlignmentCenter;
    [self.view addSubview:iconField];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(nameX, y, 200, 20)];
    nameField.stringValue = widget[@"name"] ?: @"";
    nameField.bordered = NO;
    nameField.editable = NO;
    nameField.backgroundColor = [NSColor clearColor];
    [self.view addSubview:nameField];

    NSButton *toggle = [[NSButton alloc] initWithFrame:NSMakeRect(toggleX, y - 2, 120, 20)];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.title = @"";
    toggle.target = self;
    toggle.action = @selector(toggleWidget:);
    toggle.tag = index;
    NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", key];
    BOOL enabled = [[config valueForKeyPath:keyPath defaultValue:@YES] boolValue];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.view addSubview:toggle];
    self.toggleButtons[key] = toggle;

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(colorX, y - 4, 60, 24)];
    colorWell.target = self;
    colorWell.action = @selector(widgetColorChanged:);
    colorWell.tag = index;
    NSString *colorKeyPath = [NSString stringWithFormat:@"widget_colors.%@", key];
    NSString *hexColor = [config valueForKeyPath:colorKeyPath defaultValue:nil];
    if (hexColor) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) {
        colorWell.color = color;
      }
    }
    [self.view addSubview:colorWell];
    self.colorWells[key] = colorWell;

    y -= rowHeight;
  }
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
