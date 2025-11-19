#import <Cocoa/Cocoa.h>

@interface IconsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) NSSearchField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSTextField *previewField;
@property (strong) NSButton *glyphCopyButton;
@property (strong) NSButton *openBrowserButton;
@property (strong) NSArray *allIcons;
@property (strong) NSArray *filteredIcons;
@end

