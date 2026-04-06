#import "BaristaTabBaseViewController.h"

@interface ShortcutsTabViewController : BaristaTabBaseViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *shortcuts;
@property (strong) NSSearchField *searchField;
@end

