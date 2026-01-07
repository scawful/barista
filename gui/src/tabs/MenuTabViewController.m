#import "ConfigurationManager.h"
#import "MenuTabViewController.h"

@interface MenuTabViewController ()
@property (strong) NSArray<NSDictionary *> *tools;
@property (strong) NSScrollView *scrollView;
@property (strong) NSView *contentView;
@property (strong) NSButton *showMissingToggle;
@property (strong) NSButton *allowTerminalToggle;
@end

@implementation MenuTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.tools = @[
    @{@"key": @"afs_browser", @"label": @"AFS Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"afs_studio", @"label": @"AFS Studio", @"icon": @"󰆍", @"default_enabled": @YES},
    @{@"key": @"afs_labeler", @"label": @"AFS Labeler", @"icon": @"󰓹", @"default_enabled": @YES},
    @{@"key": @"stemforge", @"label": @"StemForge", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"stem_sampler", @"label": @"StemSampler", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"yaze", @"label": @"Yaze", @"icon": @"󰯙", @"default_enabled": @YES},
    @{@"key": @"cortex_toggle", @"label": @"Cortex Dashboard", @"icon": @"󰕮", @"default_enabled": @YES},
    @{@"key": @"cortex_hub", @"label": @"Cortex Hub", @"icon": @"󰣖", @"default_enabled": @YES},
    @{@"key": @"help_center", @"label": @"Help Center", @"icon": @"󰘥", @"default_enabled": @YES},
    @{@"key": @"sys_manual", @"label": @"Sys Manual", @"icon": @"󰋜", @"default_enabled": @YES},
    @{@"key": @"icon_browser", @"label": @"Icon Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"barista_config", @"label": @"Barista Config", @"icon": @"󰒓", @"default_enabled": @YES},
    @{@"key": @"reload_bar", @"label": @"Reload SketchyBar", @"icon": @"󰑐", @"default_enabled": @YES}
  ];

  CGFloat contentHeight = MAX(560.0, 240.0 + self.tools.count * 40.0);
  self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.autohidesScrollers = YES;

  self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.view.bounds.size.width, contentHeight)];
  self.contentView.autoresizingMask = NSViewWidthSizable;
  self.scrollView.documentView = self.contentView;
  [self.view addSubview:self.scrollView];

  CGFloat y = self.contentView.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Apple Menu Tools";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:title];
  y -= 36;

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 740, 20)];
  hint.stringValue = @"Toggle items, edit labels/icons, and set order (lower numbers appear first).";
  hint.font = [NSFont systemFontOfSize:12];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.bordered = NO;
  hint.editable = NO;
  hint.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:hint];
  y -= 34;

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL showMissing = [[config valueForKeyPath:@"menus.apple.show_missing" defaultValue:@NO] boolValue];
  self.showMissingToggle = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 260, 20)];
  [self.showMissingToggle setButtonType:NSButtonTypeSwitch];
  self.showMissingToggle.title = @"Show missing tools";
  self.showMissingToggle.target = self;
  self.showMissingToggle.action = @selector(toggleShowMissing:);
  self.showMissingToggle.state = showMissing ? NSControlStateValueOn : NSControlStateValueOff;
  [self.contentView addSubview:self.showMissingToggle];
  y -= 26;

  BOOL allowTerminal = [[config valueForKeyPath:@"menus.apple.terminal" defaultValue:@NO] boolValue];
  self.allowTerminalToggle = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 320, 20)];
  [self.allowTerminalToggle setButtonType:NSButtonTypeSwitch];
  self.allowTerminalToggle.title = @"Allow terminal-only tools";
  self.allowTerminalToggle.target = self;
  self.allowTerminalToggle.action = @selector(toggleAllowTerminal:);
  self.allowTerminalToggle.state = allowTerminal ? NSControlStateValueOn : NSControlStateValueOff;
  [self.contentView addSubview:self.allowTerminalToggle];
  y -= 36;

  CGFloat iconX = leftMargin;
  CGFloat labelX = leftMargin + 40;
  CGFloat enabledX = leftMargin + 310;
  CGFloat colorX = leftMargin + 400;
  CGFloat orderX = leftMargin + 490;
  CGFloat rowHeight = 36;

  NSTextField *labelHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
  labelHeader.stringValue = @"Label";
  labelHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  labelHeader.textColor = [NSColor secondaryLabelColor];
  labelHeader.bordered = NO;
  labelHeader.editable = NO;
  labelHeader.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:labelHeader];

  NSTextField *enabledHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(enabledX, y, 80, 18)];
  enabledHeader.stringValue = @"Enabled";
  enabledHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  enabledHeader.textColor = [NSColor secondaryLabelColor];
  enabledHeader.bordered = NO;
  enabledHeader.editable = NO;
  enabledHeader.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:enabledHeader];

  NSTextField *colorHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(colorX, y, 80, 18)];
  colorHeader.stringValue = @"Color";
  colorHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  colorHeader.textColor = [NSColor secondaryLabelColor];
  colorHeader.bordered = NO;
  colorHeader.editable = NO;
  colorHeader.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:colorHeader];

  NSTextField *orderHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(orderX, y, 100, 18)];
  orderHeader.stringValue = @"Order";
  orderHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  orderHeader.textColor = [NSColor secondaryLabelColor];
  orderHeader.bordered = NO;
  orderHeader.editable = NO;
  orderHeader.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:orderHeader];
  y -= 26;

  for (NSInteger index = 0; index < self.tools.count; index++) {
    NSDictionary *tool = self.tools[index];
    NSString *key = tool[@"key"];
    NSString *baseLabel = tool[@"label"] ?: @"";
    NSString *baseIcon = tool[@"icon"] ?: @"";

    NSString *labelKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.label", key];
    NSString *iconKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon", key];
    NSString *colorKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon_color", key];
    NSString *orderKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.order", key];
    NSString *enabledKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.enabled", key];

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSMakeRect(iconX, y - 2, 28, 24)];
    iconField.stringValue = [config valueForKeyPath:iconKeyPath defaultValue:baseIcon] ?: baseIcon;
    iconField.font = [self preferredIconFontWithSize:16];
    iconField.bordered = YES;
    iconField.editable = YES;
    iconField.backgroundColor = [NSColor clearColor];
    iconField.alignment = NSTextAlignmentCenter;
    iconField.tag = index;
    iconField.identifier = @"icon";
    iconField.delegate = self;
    [self.contentView addSubview:iconField];

    NSTextField *labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y - 2, 200, 24)];
    labelField.stringValue = [config valueForKeyPath:labelKeyPath defaultValue:baseLabel] ?: baseLabel;
    labelField.bordered = YES;
    labelField.editable = YES;
    labelField.tag = index;
    labelField.identifier = @"label";
    labelField.delegate = self;
    [self.contentView addSubview:labelField];

    NSButton *toggle = [[NSButton alloc] initWithFrame:NSMakeRect(enabledX, y - 2, 60, 24)];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.title = @"";
    toggle.tag = index;
    toggle.target = self;
    toggle.action = @selector(toggleItemEnabled:);
    id enabledValue = [config valueForKeyPath:enabledKeyPath defaultValue:nil];
    BOOL enabled = enabledValue ? [enabledValue boolValue] : [tool[@"default_enabled"] boolValue];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.contentView addSubview:toggle];

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(colorX, y - 4, 60, 24)];
    colorWell.tag = index;
    colorWell.target = self;
    colorWell.action = @selector(iconColorChanged:);
    NSString *hexColor = [config valueForKeyPath:colorKeyPath defaultValue:nil];
    if ([hexColor isKindOfClass:[NSString class]] && [hexColor length] > 0) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) {
        colorWell.color = color;
      }
    }
    [self.contentView addSubview:colorWell];

    NSTextField *orderField = [[NSTextField alloc] initWithFrame:NSMakeRect(orderX, y - 2, 60, 24)];
    id orderValue = [config valueForKeyPath:orderKeyPath defaultValue:nil];
    if ([orderValue isKindOfClass:[NSNumber class]]) {
      orderField.stringValue = [(NSNumber *)orderValue stringValue];
    } else if ([orderValue isKindOfClass:[NSString class]]) {
      orderField.stringValue = (NSString *)orderValue;
    } else {
      orderField.placeholderString = @"Auto";
    }
    orderField.bordered = YES;
    orderField.editable = YES;
    orderField.tag = index;
    orderField.identifier = @"order";
    orderField.delegate = self;
    [self.contentView addSubview:orderField];

    y -= rowHeight;
  }
}

- (void)toggleShowMissing:(NSButton *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL enabled = sender.state == NSControlStateValueOn;
  [config setValue:@(enabled) forKeyPath:@"menus.apple.show_missing"];
  [config reloadSketchyBar];
}

- (void)toggleItemEnabled:(NSButton *)sender {
  if (sender.tag < 0 || sender.tag >= self.tools.count) {
    return;
  }
  NSString *key = self.tools[sender.tag][@"key"];
  BOOL enabled = sender.state == NSControlStateValueOn;
  NSString *keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.enabled", key];
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)toggleAllowTerminal:(NSButton *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL enabled = sender.state == NSControlStateValueOn;
  [config setValue:@(enabled) forKeyPath:@"menus.apple.terminal"];
  [config reloadSketchyBar];
}

- (void)iconColorChanged:(NSColorWell *)sender {
  if (sender.tag < 0 || sender.tag >= self.tools.count) {
    return;
  }
  NSString *key = self.tools[sender.tag][@"key"];
  NSString *keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon_color", key];
  NSString *hexColor = [self hexStringFromColor:sender.color];
  if (!hexColor.length) {
    return;
  }
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:hexColor forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
  NSTextField *field = notification.object;
  if (![field isKindOfClass:[NSTextField class]]) {
    return;
  }
  if (field.tag < 0 || field.tag >= self.tools.count) {
    return;
  }
  NSString *key = self.tools[field.tag][@"key"];
  NSString *value = field.stringValue ?: @"";
  NSString *identifier = field.identifier ?: @"";

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = nil;

  if ([identifier isEqualToString:@"label"]) {
    keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.label", key];
  } else if ([identifier isEqualToString:@"icon"]) {
    keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon", key];
  } else if ([identifier isEqualToString:@"order"]) {
    keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.order", key];
  } else {
    return;
  }

  NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    [config removeValueForKeyPath:keyPath];
    [config reloadSketchyBar];
    return;
  }

  if ([identifier isEqualToString:@"order"]) {
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger number = 0;
    if ([scanner scanInteger:&number] && scanner.isAtEnd) {
      [config setValue:@(number) forKeyPath:keyPath];
      [config reloadSketchyBar];
    }
    return;
  }

  [config setValue:trimmed forKeyPath:keyPath];
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
  if (!hexString.length) {
    return nil;
  }
  NSString *cleaned = [hexString stringByReplacingOccurrencesOfString:@"0x" withString:@""];
  if (cleaned.length != 8) {
    return nil;
  }
  unsigned int hexValue = 0;
  NSScanner *scanner = [NSScanner scannerWithString:cleaned];
  if (![scanner scanHexInt:&hexValue]) {
    return nil;
  }
  CGFloat alpha = ((hexValue >> 24) & 0xFF) / 255.0;
  CGFloat red = ((hexValue >> 16) & 0xFF) / 255.0;
  CGFloat green = ((hexValue >> 8) & 0xFF) / 255.0;
  CGFloat blue = (hexValue & 0xFF) / 255.0;
  return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

- (NSString *)hexStringFromColor:(NSColor *)color {
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  return [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];
}

@end
