#import <Cocoa/Cocoa.h>

@interface PerformanceTabViewController : NSViewController
@property (strong) NSTextField *cpuUsageLabel;
@property (strong) NSTextField *memoryUsageLabel;
@property (strong) NSTextField *cacheHitsLabel;
@property (strong) NSTextField *updateRateLabel;
@property (strong) NSButton *daemonToggle;
@property (strong) NSPopUpButton *updateModeMenu;
@property (strong) NSTimer *updateTimer;
@end

