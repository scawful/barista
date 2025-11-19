#import <Cocoa/Cocoa.h>

@interface DebugTabViewController : NSViewController
@property (strong) NSButton *verboseToggle;
@property (strong) NSButton *hotloadToggle;
@property (strong) NSButton *menuHoverToggle;
@property (strong) NSSlider *refreshSlider;
@property (strong) NSTextField *refreshLabel;
@property (strong) NSTextField *statusLabel;
@end

