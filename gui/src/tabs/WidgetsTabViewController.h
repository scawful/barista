#import <Cocoa/Cocoa.h>

@interface WidgetsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *widgets;
@end

