#import "BaristaStyle.h"
#import "ConfigurationManager.h"

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
    self.sidebarWidth = 220.0;
    [self refreshFromConfig];
  }
  return self;
}

- (NSFont *)monoFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
  NSArray<NSString *> *candidates = @[
    @"Berkeley Mono",
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
  NSString *barHex = [config valueForKeyPath:@"appearance.bar_color" defaultValue:@"0xC021162F"];
  NSColor *baseColor = [self colorFromHexString:barHex fallback:fallback];
  baseColor = [baseColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] ?: fallback;

  NSColor *black = [NSColor colorWithCalibratedWhite:0 alpha:1.0];
  self.backgroundColor = [baseColor blendedColorWithFraction:0.18 ofColor:black] ?: fallback;
  self.panelColor = [baseColor blendedColorWithFraction:0.08 ofColor:black] ?: fallback;
  self.sidebarColor = [baseColor blendedColorWithFraction:0.28 ofColor:black] ?: fallback;
  self.dividerColor = [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
  self.accentColor = [self colorFromHexString:@"0xFF89DCEB"
                                     fallback:[NSColor colorWithCalibratedRed:0.31 green:0.71 blue:1.0 alpha:1.0]];
  self.textColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
  self.mutedTextColor = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
  self.selectionColor = [self.accentColor colorWithAlphaComponent:0.25];

  self.titleFont = [self monoFontOfSize:16.0 weight:NSFontWeightSemibold];
  self.sectionFont = [self monoFontOfSize:13.0 weight:NSFontWeightSemibold];
  self.bodyFont = [self monoFontOfSize:12.0 weight:NSFontWeightRegular];
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

@end
