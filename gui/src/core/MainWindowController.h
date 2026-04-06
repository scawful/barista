#import <Cocoa/Cocoa.h>

@interface MainWindowController : NSWindowController <NSWindowDelegate, NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate>
@property (strong) NSTabView *tabView;
@property (strong) NSSplitView *splitView;
@property (strong) NSTableView *sidebarTable;
@property (strong) NSView *sidebarView;
@property (strong) NSArray<NSDictionary *> *tabItems;
@end
