#import <Cocoa/Cocoa.h>

@interface BaristaStyle : NSObject
@property (strong, nonatomic) NSColor *backgroundColor;
@property (strong, nonatomic) NSColor *panelColor;
@property (strong, nonatomic) NSColor *sidebarColor;
@property (strong, nonatomic) NSColor *dividerColor;
@property (strong, nonatomic) NSColor *accentColor;
@property (strong, nonatomic) NSColor *gridColor;
@property (strong, nonatomic) NSColor *textColor;
@property (strong, nonatomic) NSColor *mutedTextColor;
@property (strong, nonatomic) NSColor *selectionColor;
@property (strong, nonatomic) NSFont *titleFont;
@property (strong, nonatomic) NSFont *sectionFont;
@property (strong, nonatomic) NSFont *bodyFont;
@property (assign, nonatomic) CGFloat sidebarWidth;
@property (copy, nonatomic) NSString *themeName;
@property (copy, nonatomic) NSString *themeBarHex;

+ (instancetype)sharedStyle;
- (void)refreshFromConfig;
- (void)applyWindowStyle:(NSWindow *)window;
- (void)applyStyleToViewHierarchy:(NSView *)view;
- (NSFont *)monoFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (NSColor *)colorFromHexString:(NSString *)hex fallback:(NSColor *)fallback;
@end
