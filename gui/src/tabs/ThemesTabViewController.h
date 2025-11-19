#import <Cocoa/Cocoa.h>

@interface ThemesTabViewController : NSViewController
@property (strong) NSPopUpButton *themeSelector;
@property (strong) NSTextField *themePreview;
@property (strong) NSArray *availableThemes;
@end

