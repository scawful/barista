#import "BaristaStyle.h"
#import "ConfigurationManager.h"

@interface BaristaStyle ()
@property (strong, nonatomic) NSDictionary<NSString *, NSColor *> *themePalette;
@end

@implementation BaristaStyle

+ (instancetype)sharedStyle {
  static BaristaStyle *style = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    style = [[BaristaStyle alloc] init];
  });
  return style;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    self.sidebarWidth = 240.0;
    [self refreshFromConfig];
  }
  return self;
}

- (NSFont *)monoFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
  NSArray<NSString *> *candidates = @[
    @"Berkeley Mono",
    @"IBM Plex Mono",
    @"JetBrains Mono",
    @"Iosevka",
    @"SF Mono",
    @"Menlo",
    @"Monaco"
  ];
  for (NSString *name in candidates) {
    NSFont *font = [NSFont fontWithName:name size:size];
    if (font) {
      return font;
    }
  }
  return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

- (NSString *)normalizedHexStringFromValue:(NSString *)value {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed hasPrefix:@"\""] && [trimmed hasSuffix:@"\""] && trimmed.length > 2) {
    trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
  }
  if (![trimmed hasPrefix:@"0x"]) {
    return nil;
  }
  NSString *clean = [trimmed stringByReplacingOccurrencesOfString:@"0x" withString:@""];
  if (clean.length != 8) {
    return nil;
  }
  return [NSString stringWithFormat:@"0x%@", clean];
}

- (NSDictionary<NSString *, NSColor *> *)themePaletteForName:(NSString *)themeName
                                                  configPath:(NSString *)configPath
                                                      barHex:(NSString **)barHex {
  if (!themeName.length || !configPath.length) {
    return nil;
  }
  NSString *themePath = [[configPath stringByAppendingPathComponent:@"themes"]
                           stringByAppendingPathComponent:[themeName stringByAppendingString:@".lua"]];
  NSString *contents = [NSString stringWithContentsOfFile:themePath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
  if (!contents.length) {
    return nil;
  }

  NSRegularExpression *paletteRegex = [NSRegularExpression regularExpressionWithPattern:@"^([A-Z0-9_]+)\\s*=\\s*\"?(0x[0-9A-Fa-f]{8})\"?"
                                                                               options:0
                                                                                 error:nil];
  NSRegularExpression *barRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bbg\\s*=\\s*\"?(0x[0-9A-Fa-f]{8})\"?"
                                                                           options:0
                                                                             error:nil];
  NSMutableDictionary<NSString *, NSColor *> *palette = [NSMutableDictionary dictionary];
  BOOL inBar = NO;
  __block NSString *barHexValue = nil;

  NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *rawLine in lines) {
    NSString *line = rawLine;
    NSRange commentRange = [line rangeOfString:@"--"];
    if (commentRange.location != NSNotFound) {
      line = [line substringToIndex:commentRange.location];
    }
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (line.length == 0) {
      continue;
    }

    if ([line containsString:@"bar"] && [line containsString:@"{"]) {
      inBar = YES;
    }

    if (inBar) {
      NSTextCheckingResult *barMatch = [barRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
      if (barMatch.numberOfRanges >= 2) {
        NSString *hexCandidate = [line substringWithRange:[barMatch rangeAtIndex:1]];
        barHexValue = [self normalizedHexStringFromValue:hexCandidate];
      }
      if ([line containsString:@"}"]) {
        inBar = NO;
      }
      continue;
    }

    NSTextCheckingResult *paletteMatch = [paletteRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (paletteMatch.numberOfRanges >= 3) {
      NSString *key = [line substringWithRange:[paletteMatch rangeAtIndex:1]];
      NSString *hexCandidate = [line substringWithRange:[paletteMatch rangeAtIndex:2]];
      NSString *hex = [self normalizedHexStringFromValue:hexCandidate];
      if (hex.length) {
        NSColor *color = [self colorFromHexString:hex fallback:nil];
        if (color) {
          palette[key] = color;
        }
      }
    }
  }

  if (barHex) {
    *barHex = barHexValue;
  }
  return palette.count ? palette : nil;
}

- (NSColor *)colorFromHexString:(NSString *)hex fallback:(NSColor *)fallback {
  if (![hex isKindOfClass:[NSString class]] || hex.length == 0) {
    return fallback;
  }
  NSString *clean = [hex stringByReplacingOccurrencesOfString:@"0x" withString:@""];
  if (clean.length != 8) {
    return fallback;
  }
  unsigned int value = 0;
  NSScanner *scanner = [NSScanner scannerWithString:clean];
  if (![scanner scanHexInt:&value]) {
    return fallback;
  }
  CGFloat alpha = ((value >> 24) & 0xFF) / 255.0;
  CGFloat red = ((value >> 16) & 0xFF) / 255.0;
  CGFloat green = ((value >> 8) & 0xFF) / 255.0;
  CGFloat blue = (value & 0xFF) / 255.0;
  return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

- (void)refreshFromConfig {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSColor *fallback = [NSColor colorWithCalibratedRed:0.07 green:0.08 blue:0.11 alpha:1.0];
  NSString *defaultBarHex = [config valueForKeyPath:@"appearance.bar_color" defaultValue:@"0xC021162F"];
  NSString *themeOverride = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_THEME"];
  NSString *themeName = themeOverride.length
    ? themeOverride
    : [config valueForKeyPath:@"appearance.theme" defaultValue:@"default"];
  self.themeName = themeName;

  NSString *themeBarHex = nil;
  NSDictionary<NSString *, NSColor *> *palette = [self themePaletteForName:themeName
                                                                configPath:config.configPath
                                                                    barHex:&themeBarHex];
  self.themePalette = palette ?: @{};
  self.themeBarHex = themeBarHex;

  NSString *barHex = themeBarHex ?: defaultBarHex;
  NSColor *baseColor = [self colorFromHexString:barHex fallback:fallback];
  baseColor = [baseColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] ?: fallback;

  NSColor *bgPrimary = self.themePalette[@"BG_PRI_COLR"];
  NSColor *bgSecondary = self.themePalette[@"BG_SEC_COLR"];
  NSColor *text = self.themePalette[@"WHITE"];
  NSColor *muted = self.themePalette[@"DARK_WHITE"];
  NSColor *accent = self.themePalette[@"GREEN"] ?: self.themePalette[@"BLUE"];

  NSColor *black = [NSColor colorWithCalibratedWhite:0 alpha:1.0];
  self.backgroundColor = bgPrimary ?: ([baseColor blendedColorWithFraction:0.28 ofColor:black] ?: fallback);
  self.panelColor = bgSecondary ?: ([self.backgroundColor blendedColorWithFraction:0.12 ofColor:black] ?: fallback);
  self.sidebarColor = [self.backgroundColor blendedColorWithFraction:0.18 ofColor:black] ?: fallback;
  self.textColor = text ?: [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
  self.mutedTextColor = muted ?: [self.textColor colorWithAlphaComponent:0.62];
  self.accentColor = accent ?: [self colorFromHexString:@"0xFF89DCEB"
                                               fallback:[NSColor colorWithCalibratedRed:0.31 green:0.71 blue:1.0 alpha:1.0]];
  self.dividerColor = [self.textColor colorWithAlphaComponent:0.14];
  self.gridColor = [self.textColor colorWithAlphaComponent:0.06];
  self.selectionColor = [self.accentColor colorWithAlphaComponent:0.18];

  self.titleFont = [self monoFontOfSize:15.0 weight:NSFontWeightSemibold];
  self.sectionFont = [self monoFontOfSize:12.0 weight:NSFontWeightSemibold];
  self.bodyFont = [self monoFontOfSize:11.0 weight:NSFontWeightRegular];
}

- (void)applyWindowStyle:(NSWindow *)window {
  if (!window) {
    return;
  }
  [self refreshFromConfig];
  window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  window.backgroundColor = self.backgroundColor;
  window.titleVisibility = NSWindowTitleHidden;
  window.titlebarAppearsTransparent = YES;
}

- (void)applyStyleToViewHierarchy:(NSView *)view {
  if (!view) {
    return;
  }

  if ([view isKindOfClass:[NSTextField class]]) {
    NSTextField *field = (NSTextField *)view;
    CGFloat size = field.font.pointSize;
    if (size >= 18.0) {
      field.font = self.titleFont;
    } else if (size >= 13.0) {
      field.font = self.sectionFont;
    } else {
      field.font = self.bodyFont;
    }
    if (field.tag != 9901) {
      NSColor *labelColor = (size <= 11.0) ? self.mutedTextColor : self.textColor;
      field.textColor = field.isEditable ? self.textColor : labelColor;
    }
    if (field.isEditable) {
      field.drawsBackground = YES;
      field.backgroundColor = [self.panelColor blendedColorWithFraction:0.2 ofColor:[NSColor blackColor]];
      field.bordered = YES;
      field.bezeled = YES;
    }
  } else if ([view isKindOfClass:[NSButton class]]) {
    NSButton *button = (NSButton *)view;
    button.font = self.bodyFont;
  } else if ([view isKindOfClass:[NSTableView class]]) {
    NSTableView *table = (NSTableView *)view;
    table.backgroundColor = self.panelColor;
    table.gridColor = self.dividerColor;
  } else if ([view isKindOfClass:[NSScrollView class]]) {
    NSScrollView *scroll = (NSScrollView *)view;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = self.panelColor;
  } else if ([view isKindOfClass:[NSSegmentedControl class]]) {
    NSSegmentedControl *segmented = (NSSegmentedControl *)view;
    segmented.font = self.sectionFont;
  }

  for (NSView *subview in view.subviews) {
    [self applyStyleToViewHierarchy:subview];
  }
}

@end
