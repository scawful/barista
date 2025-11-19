#import <Cocoa/Cocoa.h>

@interface AdvancedTabViewController : NSViewController <NSTextViewDelegate>
@property (strong) NSTextView *jsonEditor;
@property (strong) NSButton *saveButton;
@property (strong) NSButton *reloadButton;
@property (strong) NSTextField *statusLabel;
@end

