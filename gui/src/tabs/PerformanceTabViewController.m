#import "ConfigurationManager.h"
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

@implementation PerformanceTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  CGFloat y = 650;
  CGFloat x = 100;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y + 50, 400, 30)];
  title.stringValue = @"Performance Statistics";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];

  NSTextField *statsTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  statsTitle.stringValue = @"Performance Statistics";
  statsTitle.font = [NSFont boldSystemFontOfSize:16];
  statsTitle.editable = NO;
  statsTitle.bezeled = NO;
  statsTitle.backgroundColor = [NSColor clearColor];
  [self.view addSubview:statsTitle];

  y -= 40;

  self.cpuUsageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  self.cpuUsageLabel.stringValue = @"CPU Usage: 0%";
  self.cpuUsageLabel.editable = NO;
  self.cpuUsageLabel.bezeled = NO;
  self.cpuUsageLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:self.cpuUsageLabel];
  y -= 30;

  self.memoryUsageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  self.memoryUsageLabel.stringValue = @"Memory Usage: 0 MB";
  self.memoryUsageLabel.editable = NO;
  self.memoryUsageLabel.bezeled = NO;
  self.memoryUsageLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:self.memoryUsageLabel];
  y -= 30;

  self.cacheHitsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  self.cacheHitsLabel.stringValue = @"Cache Hits: 0/0";
  self.cacheHitsLabel.editable = NO;
  self.cacheHitsLabel.bezeled = NO;
  self.cacheHitsLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:self.cacheHitsLabel];
  y -= 30;

  self.updateRateLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  self.updateRateLabel.stringValue = @"Update Rate: 0 Hz";
  self.updateRateLabel.editable = NO;
  self.updateRateLabel.bezeled = NO;
  self.updateRateLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:self.updateRateLabel];

  y -= 60;

  NSTextField *daemonTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
  daemonTitle.stringValue = @"Widget Daemon";
  daemonTitle.font = [NSFont boldSystemFontOfSize:16];
  daemonTitle.editable = NO;
  daemonTitle.bezeled = NO;
  daemonTitle.backgroundColor = [NSColor clearColor];
  [self.view addSubview:daemonTitle];

  y -= 40;

  self.daemonToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 200, 24)];
  self.daemonToggle.buttonType = NSButtonTypeSwitch;
  self.daemonToggle.title = @"Enable Widget Daemon";
  self.daemonToggle.target = self;
  self.daemonToggle.action = @selector(toggleDaemon:);
  [self.view addSubview:self.daemonToggle];

  y -= 40;

  NSTextField *modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 120, 24)];
  modeLabel.stringValue = @"Update Mode:";
  modeLabel.editable = NO;
  modeLabel.bezeled = NO;
  modeLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:modeLabel];

  self.updateModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 120, y, 200, 24)];
  [self.updateModeMenu addItemsWithTitles:@[@"Event-driven", @"Polling", @"Hybrid"]];
  [self.view addSubview:self.updateModeMenu];

  [self updatePerformanceStats];
  
  // Start update timer
  self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                       target:self
                                                     selector:@selector(updatePerformanceStats)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)dealloc {
  [self.updateTimer invalidate];
}

- (void)updatePerformanceStats {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *cpuLine = @"CPU Usage: N/A";
    NSString *memoryLine = @"Memory Usage: Calculating...";

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/top";
    task.arguments = @[@"-l", @"1", @"-n", @"0"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line containsString:@"CPU usage"]) {
        cpuLine = [NSString stringWithFormat:@"CPU Usage: %@", line];
        break;
      }
    }

    task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/vm_stat";
    pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];

    data = [[pipe fileHandleForReading] readDataToEndOfFile];
    output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (output.length == 0) {
      memoryLine = @"Memory Usage: N/A";
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      self.cpuUsageLabel.stringValue = cpuLine;
      self.memoryUsageLabel.stringValue = memoryLine;
      self.cacheHitsLabel.stringValue = @"Cache Hits: N/A";
      self.updateRateLabel.stringValue = @"Update Rate: N/A";
    });
  });
}

- (void)toggleDaemon:(id)sender {
  if (self.daemonToggle.state == NSControlStateValueOn) {
    // Start daemon
    ConfigurationManager *config = [ConfigurationManager sharedManager];
    NSString *widgetManager = [[config.configPath stringByAppendingPathComponent:@"bin"] stringByAppendingPathComponent:@"widget_manager"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:widgetManager]) {
      NSTask *task = [[NSTask alloc] init];
      task.launchPath = widgetManager;
      task.arguments = @[@"daemon"];
      [task launch];
    }
  } else {
    // Stop daemon
    system("pkill -f 'widget_manager daemon'");
  }
}

@end
