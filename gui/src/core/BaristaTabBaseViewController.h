#import <Cocoa/Cocoa.h>

@class ConfigurationManager;
@class BaristaCommandBus;

@interface BaristaTabBaseViewController : NSViewController

@property (readonly) ConfigurationManager *config;
@property (readonly) BaristaCommandBus *commandBus;

- (NSFont *)preferredIconFontWithSize:(CGFloat)size;

- (NSTextField *)titleLabel:(NSString *)text;
- (NSTextField *)titleLabel:(NSString *)text fontSize:(CGFloat)fontSize;

- (NSTextField *)helperLabel:(NSString *)text;

- (NSTextField *)fieldLabel:(NSString *)text;
- (NSTextField *)fieldLabel:(NSString *)text width:(CGFloat)width;

- (NSBox *)sectionBoxWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  contentStack:(NSStackView **)outStack;

- (NSBox *)sectionBoxWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  contentStack:(NSStackView **)outStack
                    edgeInsets:(NSEdgeInsets)insets
                       spacing:(CGFloat)spacing;

- (NSScrollView *)scrollViewWithRootStack:(NSStackView **)outRootStack
                               edgeInsets:(NSEdgeInsets)insets
                                  spacing:(CGFloat)spacing;

- (NSColor *)colorFromHexString:(NSString *)hexString;
- (NSString *)hexStringFromColor:(NSColor *)color;

- (NSPopUpButton *)fontFamilyPopupWithSelection:(NSString *)currentFamily
                                          width:(CGFloat)width
                                         target:(id)target
                                         action:(SEL)action;

- (NSPopUpButton *)fontStylePopupWithSelection:(NSString *)currentStyle
                                         width:(CGFloat)width
                                        target:(id)target
                                        action:(SEL)action;

@end
