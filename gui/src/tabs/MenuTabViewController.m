#import "ConfigurationManager.h"
#import "MenuTabViewController.h"

@interface MenuTabViewController ()
@property (strong) NSArray<NSDictionary *> *tools;
@property (strong) NSScrollView *scrollView;
@property (strong) NSView *contentView;
@property (strong) NSButton *showMissingToggle;
@property (strong) NSButton *allowTerminalToggle;
@property (strong) NSTextField *workDomainField;
@property (strong) NSTextField *workAppsFileField;
@property (strong) NSButton *applyWorkAppsButton;
@property (strong) NSButton *openWorkAppsFileButton;
@end

@implementation MenuTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL yazeDefaultEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@NO] boolValue];

  self.tools = @[
    @{@"key": @"afs_browser", @"label": @"AFS Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"afs_studio", @"label": @"AFS Studio", @"icon": @"󰆍", @"default_enabled": @YES},
    @{@"key": @"afs_labeler", @"label": @"AFS Labeler", @"icon": @"󰓹", @"default_enabled": @YES},
    @{@"key": @"stemforge", @"label": @"StemForge", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"stem_sampler", @"label": @"StemSampler", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"yaze", @"label": @"Yaze", @"icon": @"󰯙", @"default_enabled": @(yazeDefaultEnabled)},
    @{@"key": @"cortex_toggle", @"label": @"Cortex Dashboard", @"icon": @"󰕮", @"default_enabled": @YES},
    @{@"key": @"cortex_hub", @"label": @"Cortex Hub", @"icon": @"󰣖", @"default_enabled": @YES},
    @{@"key": @"help_center", @"label": @"Help Center", @"icon": @"󰘥", @"default_enabled": @YES},
    @{@"key": @"sys_manual", @"label": @"Sys Manual", @"icon": @"󰋜", @"default_enabled": @YES},
    @{@"key": @"icon_browser", @"label": @"Icon Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"keyboard_overlay", @"label": @"Keyboard Overlay", @"icon": @"󰌌", @"default_enabled": @YES},
    @{@"key": @"barista_config", @"label": @"Barista Config", @"icon": @"󰒓", @"default_enabled": @YES},
    @{@"key": @"reload_bar", @"label": @"Reload SketchyBar", @"icon": @"󰑐", @"default_enabled": @YES}
  ];

  self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.autohidesScrollers = YES;
  self.scrollView.borderType = NSNoBorder;
  self.scrollView.drawsBackground = NO;
  [self.view addSubview:self.scrollView];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 24;
  rootStack.edgeInsets = NSEdgeInsetsMake(30, 40, 40, 40);
  self.scrollView.documentView = rootStack;
  [rootStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor].active = YES;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Apple Menu Tools";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hint.stringValue = @"Toggle items, edit labels/icons, and set order (lower numbers appear first).";
  hint.font = [NSFont systemFontOfSize:13];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.bordered = NO;
  hint.editable = NO;
  hint.backgroundColor = [NSColor clearColor];
  [rootStack addView:hint inGravity:NSStackViewGravityTop];

  // Options row
  NSStackView *optionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  optionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  optionsRow.spacing = 20;
  [rootStack addView:optionsRow inGravity:NSStackViewGravityTop];

  BOOL showMissing = [[config valueForKeyPath:@"menus.apple.show_missing" defaultValue:@NO] boolValue];
  self.showMissingToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.showMissingToggle setButtonType:NSButtonTypeSwitch];
  self.showMissingToggle.title = @"Show missing tools";
  self.showMissingToggle.target = self;
  self.showMissingToggle.action = @selector(toggleShowMissing:);
  self.showMissingToggle.state = showMissing ? NSControlStateValueOn : NSControlStateValueOff;
  [optionsRow addView:self.showMissingToggle inGravity:NSStackViewGravityLeading];

  BOOL allowTerminal = [[config valueForKeyPath:@"menus.apple.terminal" defaultValue:@NO] boolValue];
  self.allowTerminalToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.allowTerminalToggle setButtonType:NSButtonTypeSwitch];
  self.allowTerminalToggle.title = @"Allow terminal-only tools";
  self.allowTerminalToggle.target = self;
  self.allowTerminalToggle.action = @selector(toggleAllowTerminal:);
  self.allowTerminalToggle.state = allowTerminal ? NSControlStateValueOn : NSControlStateValueOff;
  [optionsRow addView:self.allowTerminalToggle inGravity:NSStackViewGravityLeading];

  [rootStack setCustomSpacing:30 afterView:optionsRow];

  // Work apps controls
  NSStackView *workAppsSection = [[NSStackView alloc] initWithFrame:NSZeroRect];
  workAppsSection.orientation = NSUserInterfaceLayoutOrientationVertical;
  workAppsSection.spacing = 10;
  [rootStack addView:workAppsSection inGravity:NSStackViewGravityTop];

  NSTextField *workAppsTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  workAppsTitle.stringValue = @"Work Google Apps";
  workAppsTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  workAppsTitle.bordered = NO;
  workAppsTitle.editable = NO;
  workAppsTitle.backgroundColor = [NSColor clearColor];
  [workAppsSection addView:workAppsTitle inGravity:NSStackViewGravityTop];

  NSTextField *workAppsHint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  workAppsHint.stringValue = @"Set workspace domain + data file path, then apply and open the JSON file to customize links.";
  workAppsHint.font = [NSFont systemFontOfSize:12];
  workAppsHint.textColor = [NSColor secondaryLabelColor];
  workAppsHint.bordered = NO;
  workAppsHint.editable = NO;
  workAppsHint.backgroundColor = [NSColor clearColor];
  [workAppsSection addView:workAppsHint inGravity:NSStackViewGravityTop];

  NSStackView *domainRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  domainRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  domainRow.spacing = 10;
  [workAppsSection addView:domainRow inGravity:NSStackViewGravityTop];

  NSTextField *domainLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  domainLabel.stringValue = @"Workspace Domain";
  domainLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  domainLabel.bordered = NO;
  domainLabel.editable = NO;
  domainLabel.backgroundColor = [NSColor clearColor];
  [domainLabel.widthAnchor constraintEqualToConstant:130].active = YES;
  [domainRow addView:domainLabel inGravity:NSStackViewGravityLeading];

  self.workDomainField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.workDomainField.placeholderString = @"company.com";
  self.workDomainField.stringValue = [config valueForKeyPath:@"menus.work.workspace_domain" defaultValue:@""] ?: @"";
  [self.workDomainField.widthAnchor constraintEqualToConstant:220].active = YES;
  [domainRow addView:self.workDomainField inGravity:NSStackViewGravityLeading];

  NSStackView *appsFileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  appsFileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  appsFileRow.spacing = 10;
  [workAppsSection addView:appsFileRow inGravity:NSStackViewGravityTop];

  NSTextField *appsFileLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  appsFileLabel.stringValue = @"Apps Data File";
  appsFileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  appsFileLabel.bordered = NO;
  appsFileLabel.editable = NO;
  appsFileLabel.backgroundColor = [NSColor clearColor];
  [appsFileLabel.widthAnchor constraintEqualToConstant:130].active = YES;
  [appsFileRow addView:appsFileLabel inGravity:NSStackViewGravityLeading];

  self.workAppsFileField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.workAppsFileField.placeholderString = @"data/work_apps.local.json";
  self.workAppsFileField.stringValue = [config valueForKeyPath:@"menus.work.apps_file" defaultValue:@"data/work_apps.local.json"] ?: @"data/work_apps.local.json";
  [self.workAppsFileField.widthAnchor constraintEqualToConstant:320].active = YES;
  [appsFileRow addView:self.workAppsFileField inGravity:NSStackViewGravityLeading];

  NSStackView *workActionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  workActionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  workActionsRow.spacing = 10;
  [workAppsSection addView:workActionsRow inGravity:NSStackViewGravityTop];

  self.applyWorkAppsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.applyWorkAppsButton.title = @"Apply Work Apps";
  self.applyWorkAppsButton.target = self;
  self.applyWorkAppsButton.action = @selector(applyWorkApps:);
  [workActionsRow addView:self.applyWorkAppsButton inGravity:NSStackViewGravityLeading];

  self.openWorkAppsFileButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.openWorkAppsFileButton.title = @"Open JSON";
  self.openWorkAppsFileButton.target = self;
  self.openWorkAppsFileButton.action = @selector(openWorkAppsFile:);
  [workActionsRow addView:self.openWorkAppsFileButton inGravity:NSStackViewGravityLeading];

  [rootStack setCustomSpacing:24 afterView:workAppsSection];

  // Tools Grid
  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.rowSpacing = 12;
  grid.columnSpacing = 16;
  grid.xPlacement = NSGridCellPlacementLeading;
  grid.yPlacement = NSGridCellPlacementCenter;
  [rootStack addView:grid inGravity:NSStackViewGravityTop];

  // Header
  [grid addRowWithViews:@[
    [self headerLabel:@"ICON"],
    [self headerLabel:@"LABEL"],
    [self headerLabel:@"ENABLED"],
    [self headerLabel:@"COLOR"],
    [self headerLabel:@"ORDER"]
  ]];

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

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [iconField.widthAnchor constraintEqualToConstant:40].active = YES;
    iconField.stringValue = [config valueForKeyPath:iconKeyPath defaultValue:baseIcon] ?: baseIcon;
    iconField.font = [self preferredIconFontWithSize:18];
    iconField.alignment = NSTextAlignmentCenter;
    iconField.tag = index;
    iconField.identifier = @"icon";
    iconField.delegate = self;

    NSTextField *labelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [labelField.widthAnchor constraintEqualToConstant:220].active = YES;
    labelField.stringValue = [config valueForKeyPath:labelKeyPath defaultValue:baseLabel] ?: baseLabel;
    labelField.font = [NSFont systemFontOfSize:14];
    labelField.tag = index;
    labelField.identifier = @"label";
    labelField.delegate = self;

    NSButton *toggle = [[NSButton alloc] initWithFrame:NSZeroRect];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.title = @"";
    toggle.tag = index;
    toggle.target = self;
    toggle.action = @selector(toggleItemEnabled:);
    id enabledValue = [config valueForKeyPath:enabledKeyPath defaultValue:nil];
    BOOL enabled = enabledValue ? [enabledValue boolValue] : [tool[@"default_enabled"] boolValue];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 50, 28)];
    colorWell.tag = index;
    colorWell.target = self;
    colorWell.action = @selector(iconColorChanged:);
    NSString *hexColor = [config valueForKeyPath:colorKeyPath defaultValue:nil];
    if ([hexColor isKindOfClass:[NSString class]] && [hexColor length] > 0) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) colorWell.color = color;
    }

    NSTextField *orderField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [orderField.widthAnchor constraintEqualToConstant:60].active = YES;
    id orderValue = [config valueForKeyPath:orderKeyPath defaultValue:nil];
    if ([orderValue isKindOfClass:[NSNumber class]]) orderField.stringValue = [(NSNumber *)orderValue stringValue];
    else if ([orderValue isKindOfClass:[NSString class]]) orderField.stringValue = (NSString *)orderValue;
    else orderField.placeholderString = @"Auto";
    orderField.tag = index;
    orderField.identifier = @"order";
    orderField.delegate = self;

    [grid addRowWithViews:@[iconField, labelField, toggle, colorWell, orderField]];
  }
}

- (NSTextField *)headerLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text;
  label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (NSString *)trimmedString:(NSString *)value {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)resolveWorkAppsPath:(NSString *)rawPath config:(ConfigurationManager *)config {
  NSString *trimmed = [self trimmedString:rawPath ?: @""];
  if (trimmed.length == 0) {
    return nil;
  }
  if ([trimmed hasPrefix:@"~/"]) {
    return [NSHomeDirectory() stringByAppendingPathComponent:[trimmed substringFromIndex:2]];
  }
  if ([trimmed hasPrefix:@"/"]) {
    return trimmed;
  }
  return [config.configPath stringByAppendingPathComponent:trimmed];
}

- (void)applyWorkApps:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *domain = [self trimmedString:self.workDomainField.stringValue ?: @""];
  NSString *appsFile = [self trimmedString:self.workAppsFileField.stringValue ?: @""];
  if (appsFile.length == 0) {
    appsFile = @"data/work_apps.local.json";
    self.workAppsFileField.stringValue = appsFile;
  }

  [config setValue:appsFile forKeyPath:@"menus.work.apps_file"];
  [config setValue:domain forKeyPath:@"menus.work.workspace_domain"];

  NSMutableArray *args = [NSMutableArray arrayWithArray:@[
    @"--apps-only",
    @"--replace",
    @"--state", config.statePath,
    @"--work-apps-out-file", appsFile,
    @"--yes",
    @"--no-reload"
  ]];
  if (domain.length > 0) {
    [args addObjectsFromArray:@[@"--domain", domain]];
  }

  [config runScript:@"setup_machine.sh" arguments:args];
  [config reloadSketchyBar];
}

- (void)openWorkAppsFile:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *appsFile = [self trimmedString:self.workAppsFileField.stringValue ?: @""];
  if (appsFile.length == 0) {
    appsFile = @"data/work_apps.local.json";
  }
  NSString *resolvedPath = [self resolveWorkAppsPath:appsFile config:config];
  if (!resolvedPath.length) {
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [resolvedPath stringByDeletingLastPathComponent];
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  if (![fm fileExistsAtPath:resolvedPath]) {
    NSString *templatePath = [config.configPath stringByAppendingPathComponent:@"data/work_apps.work.json"];
    if ([fm fileExistsAtPath:templatePath]) {
      [fm copyItemAtPath:templatePath toPath:resolvedPath error:nil];
    } else {
      [@"[]\n" writeToFile:resolvedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
  }

  NSURL *fileURL = [NSURL fileURLWithPath:resolvedPath];
  [[NSWorkspace sharedWorkspace] openURL:fileURL];
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
