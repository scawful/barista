#import "BaristaTabBaseViewController.h"

@interface WidgetsTabViewController : BaristaTabBaseViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *widgets;
@end

