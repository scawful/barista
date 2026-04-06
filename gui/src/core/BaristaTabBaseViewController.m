#import "BaristaTabBaseViewController.h"
#import "ConfigurationManager.h"
#import "BaristaCommandBus.h"
#import "BaristaStyle.h"

@interface BaristaFlippedClipView : NSClipView
@end

@implementation BaristaFlippedClipView
- (BOOL)isFlipped {
  return YES;
}
@end

@implementation BaristaTabBaseViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 500)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (NSScrollView *)scrollViewWithRootStack:(NSStackView **)outRootStack
                               edgeInsets:(NSEdgeInsets)insets
                                  spacing:(CGFloat)spacing {
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSNoBorder;
  scrollView.drawsBackground = NO;

  BaristaFlippedClipView *flippedClip = [[BaristaFlippedClipView alloc] initWithFrame:scrollView.contentView.frame];
  flippedClip.drawsBackground = NO;
  scrollView.contentView = flippedClip;

  [self.view addSubview:scrollView];

  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  rootStack.translatesAutoresizingMaskIntoConstraints = NO;
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = spacing;
  rootStack.edgeInsets = insets;
  scrollView.documentView = rootStack;
  [rootStack.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor].active = YES;

  if (outRootStack) {
    *outRootStack = rootStack;
  }
  return scrollView;
}

- (ConfigurationManager *)config {
  return [ConfigurationManager sharedManager];
}

- (BaristaCommandBus *)commandBus {
  return [BaristaCommandBus sharedBus];
}

#pragma mark - Icon Font

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

#pragma mark - Label Factories

- (NSTextField *)titleLabel:(NSString *)text {
  return [self titleLabel:text fontSize:24];
}

- (NSTextField *)titleLabel:(NSString *)text fontSize:(CGFloat)fontSize {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightBold];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (NSTextField *)helperLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:12.5];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  label.usesSingleLineMode = NO;
  label.lineBreakMode = NSLineBreakByWordWrapping;
  return label;
}

- (NSTextField *)fieldLabel:(NSString *)text {
  return [self fieldLabel:text width:120];
}

- (NSTextField *)fieldLabel:(NSString *)text width:(CGFloat)width {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  [label.widthAnchor constraintEqualToConstant:width].active = YES;
  return label;
}

#pragma mark - Section Box

- (NSBox *)sectionBoxWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  contentStack:(NSStackView **)outStack {
  return [self sectionBoxWithTitle:title
                          subtitle:subtitle
                      contentStack:outStack
                        edgeInsets:NSEdgeInsetsMake(18, 18, 18, 18)
                           spacing:12];
}

- (NSBox *)sectionBoxWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  contentStack:(NSStackView **)outStack
                    edgeInsets:(NSEdgeInsets)insets
                       spacing:(CGFloat)spacing {
  BaristaStyle *style = [BaristaStyle sharedStyle];

  NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
  box.boxType = NSBoxCustom;
  box.titlePosition = NSNoTitle;
  box.cornerRadius = 12.0;
  box.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08];
  box.fillColor = [style.panelColor blendedColorWithFraction:0.3
                                                     ofColor:[NSColor blackColor]]
                  ?: [NSColor colorWithCalibratedRed:0.11 green:0.12 blue:0.15 alpha:0.95];
  box.transparent = NO;

  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = spacing;
  stack.edgeInsets = insets;
  box.contentView = stack;

  NSTextField *sectionTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  sectionTitle.stringValue = title ?: @"";
  sectionTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  sectionTitle.bordered = NO;
  sectionTitle.editable = NO;
  sectionTitle.backgroundColor = [NSColor clearColor];
  [stack addView:sectionTitle inGravity:NSStackViewGravityTop];

  if (subtitle.length > 0) {
    [stack addView:[self helperLabel:subtitle] inGravity:NSStackViewGravityTop];
  }

  if (outStack) {
    *outStack = stack;
  }
  return box;
}

#pragma mark - Color Conversion

- (NSColor *)colorFromHexString:(NSString *)hexString {
  if (!hexString) {
    return nil;
  }
  // Handle NSNumber values from config (hex integers stored as numbers)
  if ([hexString isKindOfClass:[NSNumber class]]) {
    unsigned int num = [(NSNumber *)(id)hexString unsignedIntValue];
    hexString = [NSString stringWithFormat:@"0x%08X", num];
  }
  if (![hexString isKindOfClass:[NSString class]] || !hexString.length) {
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

#pragma mark - Font Popup Factories

- (NSPopUpButton *)fontFamilyPopupWithSelection:(NSString *)currentFamily
                                          width:(CGFloat)width
                                         target:(id)target
                                         action:(SEL)action {
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [popup.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
  popup.font = [NSFont systemFontOfSize:12];

  NSArray<NSString *> *families = [[[NSFontManager sharedFontManager] availableFontFamilies]
      sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  [popup addItemWithTitle:@"(System Default)"];
  [popup addItemsWithTitles:families];

  if (currentFamily.length > 0) {
    NSInteger index = [popup indexOfItemWithTitle:currentFamily];
    if (index != -1) {
      [popup selectItemAtIndex:index];
    }
  }

  popup.target = target;
  popup.action = action;
  return popup;
}

- (NSPopUpButton *)fontStylePopupWithSelection:(NSString *)currentStyle
                                         width:(CGFloat)width
                                        target:(id)target
                                        action:(SEL)action {
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [popup.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
  popup.font = [NSFont systemFontOfSize:12];

  NSArray<NSString *> *styles = @[@"Regular", @"Medium", @"Semibold", @"Bold", @"Heavy"];
  [popup addItemsWithTitles:styles];

  if (currentStyle.length > 0) {
    NSInteger index = [popup indexOfItemWithTitle:currentStyle];
    if (index != -1) {
      [popup selectItemAtIndex:index];
    } else {
      [popup selectItemAtIndex:3]; // Bold default
    }
  }

  popup.target = target;
  popup.action = action;
  return popup;
}

@end
