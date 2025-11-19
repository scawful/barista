#import <Cocoa/Cocoa.h>

@interface ShortcutsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *shortcuts;
@property (strong) NSSearchField *searchField;
@end

