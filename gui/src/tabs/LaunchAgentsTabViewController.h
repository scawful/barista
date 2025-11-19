#import <Cocoa/Cocoa.h>

@interface LaunchAgentsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSSearchField *searchField;
@property (strong) NSTextField *statusLabel;
@property (strong) NSButton *startButton;
@property (strong) NSButton *stopButton;
@property (strong) NSButton *restartButton;
@property (strong) NSMutableArray *launchAgents;
@property (strong) NSArray *filteredLaunchAgents;
@end

