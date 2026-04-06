#import "ConfigurationManager.h"
#import "BaristaTabBaseViewController.h"

@interface PerformanceTabViewController : BaristaTabBaseViewController
@property (strong) NSTextField *cpuUsageLabel;
@property (strong) NSTextField *memoryUsageLabel;
@property (strong) NSTextField *cacheHitsLabel;
@property (strong) NSTextField *updateRateLabel;
@property (strong) NSButton *daemonToggle;
@property (strong) NSPopUpButton *updateModeMenu;
@property (strong) NSTimer *updateTimer;
@end

@implementation PerformanceTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(28, 34, 34, 34) spacing:20];

  [rootStack addView:[self titleLabel:@"Performance"] inGravity:NSStackViewGravityTop];
  [rootStack addView:[self helperLabel:@"Use this page to inspect Barista runtime cost and the optional widget daemon state without dropping into the terminal."] inGravity:NSStackViewGravityTop];

  NSStackView *snapshotSection = nil;
  NSBox *snapshotBox = [self sectionBoxWithTitle:@"Runtime Snapshot"
                                        subtitle:@"A quick read on current resource use and update cadence."
                                     contentStack:&snapshotSection];
  [rootStack addView:snapshotBox inGravity:NSStackViewGravityTop];
  [snapshotBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.cpuUsageLabel = [self metricLabel:@"CPU Usage: 0%"];
  self.memoryUsageLabel = [self metricLabel:@"Memory Usage: 0 MB"];
  self.cacheHitsLabel = [self metricLabel:@"Cache Hits: 0/0"];
  self.updateRateLabel = [self metricLabel:@"Update Rate: 0 Hz"];
  [snapshotSection addView:self.cpuUsageLabel inGravity:NSStackViewGravityTop];
  [snapshotSection addView:self.memoryUsageLabel inGravity:NSStackViewGravityTop];
  [snapshotSection addView:self.cacheHitsLabel inGravity:NSStackViewGravityTop];
  [snapshotSection addView:self.updateRateLabel inGravity:NSStackViewGravityTop];

  NSStackView *daemonSection = nil;
  NSBox *daemonBox = [self sectionBoxWithTitle:@"Widget Daemon"
                                      subtitle:@"Toggle the helper process and choose how aggressively it should refresh."
                                   contentStack:&daemonSection];
  [rootStack addView:daemonBox inGravity:NSStackViewGravityTop];
  [daemonBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.daemonToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.daemonToggle.buttonType = NSButtonTypeSwitch;
  self.daemonToggle.title = @"Enable Widget Daemon";
  self.daemonToggle.target = self;
  self.daemonToggle.action = @selector(toggleDaemon:);
  [daemonSection addView:self.daemonToggle inGravity:NSStackViewGravityTop];

  NSStackView *modeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  modeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  modeRow.spacing = 12;
  [daemonSection addView:modeRow inGravity:NSStackViewGravityTop];

  NSTextField *modeLabel = [self fieldLabel:@"Update mode"];
  [modeRow addView:modeLabel inGravity:NSStackViewGravityLeading];

  self.updateModeMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
  [self.updateModeMenu addItemsWithTitles:@[@"Event-driven", @"Polling", @"Hybrid"]];
  [self.updateModeMenu.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
  [self.updateModeMenu setTarget:self];
  [self.updateModeMenu setAction:@selector(updateModeChanged:)];
  [modeRow addView:self.updateModeMenu inGravity:NSStackViewGravityLeading];

  [self updatePerformanceStats];
  
  // Start update timer
  self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                       target:self
                                                     selector:@selector(updatePerformanceStats)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (NSTextField *)metricLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:13];
  label.textColor = [NSColor labelColor];
  label.editable = NO;
  label.bezeled = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
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
        // Extract percentages from "CPU usage: X% user, Y% sys, Z% idle"
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9.]+)% user.*?([0-9.]+)% sys.*?([0-9.]+)% idle" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match && match.numberOfRanges >= 4) {
          NSString *user = [line substringWithRange:[match rangeAtIndex:1]];
          NSString *sys = [line substringWithRange:[match rangeAtIndex:2]];
          double used = [user doubleValue] + [sys doubleValue];
          cpuLine = [NSString stringWithFormat:@"CPU Usage: %.1f%% (user %.1f%%, sys %.1f%%)", used, [user doubleValue], [sys doubleValue]];
        }
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
    NSString *vmOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (vmOutput.length == 0) {
      memoryLine = @"Memory Usage: N/A";
    } else {
      // Parse vm_stat output
      NSArray *vmLines = [vmOutput componentsSeparatedByString:@"\n"];
      NSUInteger pagesActive = 0, pagesWired = 0, pagesCompressed = 0;
      for (NSString *vmLine in vmLines) {
        if ([vmLine containsString:@"Pages active"]) {
          pagesActive = [[vmLine componentsSeparatedByString:@":"].lastObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].integerValue;
        } else if ([vmLine containsString:@"Pages wired"]) {
          pagesWired = [[vmLine componentsSeparatedByString:@":"].lastObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].integerValue;
        } else if ([vmLine containsString:@"Pages occupied by compressor"]) {
          pagesCompressed = [[vmLine componentsSeparatedByString:@":"].lastObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].integerValue;
        }
      }
      // vm_stat reports values with trailing period, strip it
      NSUInteger totalPages = pagesActive + pagesWired + pagesCompressed;
      double memoryMB = (totalPages * 16384.0) / (1024.0 * 1024.0);
      if (memoryMB > 1024) {
        memoryLine = [NSString stringWithFormat:@"Memory Usage: %.1f GB (active + wired + compressed)", memoryMB / 1024.0];
      } else {
        memoryLine = [NSString stringWithFormat:@"Memory Usage: %.0f MB (active + wired + compressed)", memoryMB];
      }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      self.cpuUsageLabel.stringValue = cpuLine;
      self.memoryUsageLabel.stringValue = memoryLine;
      self.cacheHitsLabel.stringValue = @"Cache Hits: N/A";
      self.updateRateLabel.stringValue = @"Update Rate: N/A";
    });
  });
}

- (void)updateModeChanged:(id)sender {
  NSArray *modes = @[@"event", @"polling", @"hybrid"];
  NSInteger index = self.updateModeMenu.indexOfSelectedItem;
  if (index >= 0 && index < (NSInteger)modes.count) {
    [self.config setValue:modes[index] forKeyPath:@"modes.widget_daemon"];
    [self.config saveState];
  }
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
    NSTask *killTask = [[NSTask alloc] init];
    killTask.launchPath = @"/usr/bin/pkill";
    killTask.arguments = @[@"-f", @"widget_manager daemon"];
    [killTask launch];
  }
}

@end
