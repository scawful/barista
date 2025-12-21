#import "ConfigurationManager.h"
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

@implementation LaunchAgentsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.launchAgents = [NSMutableArray array];
  self.filteredLaunchAgents = @[];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Launch Agents";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // Search
  self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  self.searchField.placeholderString = @"Filter by label or path";
  self.searchField.target = self;
  self.searchField.action = @selector(filterChanged:);
  [self.view addSubview:self.searchField];

  NSButton *refreshButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 320, y, 100, 24)];
  [refreshButton setButtonType:NSButtonTypeMomentaryPushIn];
  [refreshButton setBezelStyle:NSBezelStyleRounded];
  refreshButton.title = @"Refresh";
  refreshButton.target = self;
  refreshButton.action = @selector(loadLaunchAgents:);
  [self.view addSubview:refreshButton];
  y -= 50;

  // Table view
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 120, 700, y - 120)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 26.0;

  NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
  stateColumn.title = @"State";
  stateColumn.width = 140;
  [self.tableView addTableColumn:stateColumn];

  NSTableColumn *labelColumn = [[NSTableColumn alloc] initWithIdentifier:@"label"];
  labelColumn.title = @"Label";
  labelColumn.width = 320;
  [self.tableView addTableColumn:labelColumn];

  NSTableColumn *pidColumn = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
  pidColumn.title = @"PID";
  pidColumn.width = 80;
  [self.tableView addTableColumn:pidColumn];

  NSTableColumn *plistColumn = [[NSTableColumn alloc] initWithIdentifier:@"plist"];
  plistColumn.title = @"Plist";
  plistColumn.width = 180;
  [self.tableView addTableColumn:plistColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];

  // Control buttons
  self.startButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 720, y + 100, 160, 32)];
  [self.startButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.startButton setBezelStyle:NSBezelStyleRounded];
  self.startButton.title = @"Start";
  self.startButton.target = self;
  self.startButton.action = @selector(startSelected:);
  [self.view addSubview:self.startButton];

  self.stopButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 720, y + 50, 160, 32)];
  [self.stopButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.stopButton setBezelStyle:NSBezelStyleRounded];
  self.stopButton.title = @"Stop";
  self.stopButton.target = self;
  self.stopButton.action = @selector(stopSelected:);
  [self.view addSubview:self.stopButton];

  self.restartButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 720, y, 160, 32)];
  [self.restartButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.restartButton setBezelStyle:NSBezelStyleRounded];
  self.restartButton.title = @"Restart";
  self.restartButton.target = self;
  self.restartButton.action = @selector(restartSelected:);
  [self.view addSubview:self.restartButton];

  // Status
  self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, 80, 700, 24)];
  self.statusLabel.editable = NO;
  self.statusLabel.bezeled = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.stringValue = @"No agents loaded.";
  [self.view addSubview:self.statusLabel];

  [self loadLaunchAgents:nil];
}

- (NSString *)launchAgentHelperPath {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  return [[config.configPath stringByAppendingPathComponent:@"helpers"] stringByAppendingPathComponent:@"launch_agent_manager.sh"];
}

- (void)loadLaunchAgents:(id)sender {
  NSString *helper = [self launchAgentHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
    self.statusLabel.stringValue = @"helpers/launch_agent_manager.sh not found (build agent helper first).";
    self.launchAgents = [NSMutableArray array];
    self.filteredLaunchAgents = @[];
    [self.tableView reloadData];
    [self updateButtons];
    return;
  }

  self.statusLabel.stringValue = @"Loading launch agents…";

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = helper;
    task.arguments = @[@"list"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSInteger status = task.terminationStatus;

    NSError *error = nil;
    NSArray *agents = nil;
    if (status == 0) {
      agents = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (status != 0) {
        self.statusLabel.stringValue = output.length ? output : @"Failed to list launch agents.";
        return;
      }
      if (!agents || ![agents isKindOfClass:[NSArray class]]) {
        self.statusLabel.stringValue = @"Unable to parse launch agent JSON.";
        return;
      }

      self.launchAgents = [agents mutableCopy];
      [self applyFilter];
    });
  });
}

- (void)filterChanged:(id)sender {
  [self applyFilter];
}

- (void)applyFilter {
  NSString *query = [[self.searchField.stringValue lowercaseString] lowercaseString];
  if (!query) query = @"";

  if (query.length == 0) {
    self.filteredLaunchAgents = [self.launchAgents copy];
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *agent in self.launchAgents) {
      NSString *label = [[agent[@"label"] description] lowercaseString];
      NSString *plist = [[agent[@"plist"] description] lowercaseString];
      if ((label && [label containsString:query]) || (plist && [plist containsString:query])) {
        [filtered addObject:agent];
      }
    }
    self.filteredLaunchAgents = filtered;
  }
  [self.tableView reloadData];
  [self updateButtons];
  self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu agents", (unsigned long)self.filteredLaunchAgents.count];
}

- (NSDictionary *)selectedAgent {
  NSInteger row = self.tableView.selectedRow;
  if (row < 0 || row >= (NSInteger)self.filteredLaunchAgents.count) {
    return nil;
  }
  return self.filteredLaunchAgents[row];
}

- (void)updateButtons {
  NSDictionary *agent = [self selectedAgent];
  if (!agent) {
    self.startButton.enabled = NO;
    self.stopButton.enabled = NO;
    self.restartButton.enabled = NO;
    return;
  }
  BOOL running = [agent[@"running"] boolValue];
  self.startButton.enabled = !running;
  self.stopButton.enabled = running;
  self.restartButton.enabled = YES;
}

- (void)startSelected:(id)sender {
  NSDictionary *agent = [self selectedAgent];
  if (!agent) return;
  [self runLaunchAgentCommand:@[@"start", agent[@"label"] ?: @""] successMessage:@"Agent started."];
}

- (void)stopSelected:(id)sender {
  NSDictionary *agent = [self selectedAgent];
  if (!agent) return;
  [self runLaunchAgentCommand:@[@"stop", agent[@"label"] ?: @""] successMessage:@"Agent stopped."];
}

- (void)restartSelected:(id)sender {
  NSDictionary *agent = [self selectedAgent];
  if (!agent) return;
  [self runLaunchAgentCommand:@[@"restart", agent[@"label"] ?: @""] successMessage:@"Agent restarted."];
}

- (void)runLaunchAgentCommand:(NSArray<NSString *> *)arguments successMessage:(NSString *)message {
  NSString *helper = [self launchAgentHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
    self.statusLabel.stringValue = @"launch_agent_manager.sh not found.";
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = helper;
  task.arguments = arguments;
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  [task launch];
  [task waitUntilExit];

  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  if (task.terminationStatus == 0) {
    self.statusLabel.stringValue = output.length ? [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : message;
    [self loadLaunchAgents:nil];
  } else {
    self.statusLabel.stringValue = output.length ? output : @"Command failed.";
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredLaunchAgents.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *agent = self.filteredLaunchAgents[row];
  NSString *identifier = tableColumn.identifier;

  NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 24)];
    NSTextField *textField = [[NSTextField alloc] initWithFrame:cell.bounds];
    textField.autoresizingMask = NSViewWidthSizable;
    textField.editable = NO;
    textField.bezeled = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.font = [NSFont systemFontOfSize:12];
    cell.textField = textField;
    cell.identifier = identifier;
    [cell addSubview:textField];
  }

  NSString *value = @"";
  if ([identifier isEqualToString:@"state"]) {
    BOOL running = [agent[@"running"] boolValue];
    value = running ? @"● Running" : @"○ Stopped";
  } else if ([identifier isEqualToString:@"label"]) {
    value = [agent[@"label"] description] ?: @"";
  } else if ([identifier isEqualToString:@"pid"]) {
    id pid = agent[@"pid"];
    value = (pid && pid != [NSNull null]) ? [pid stringValue] : @"—";
  } else if ([identifier isEqualToString:@"plist"]) {
    value = [[agent[@"plist"] description] stringByAbbreviatingWithTildeInPath] ?: @"";
  }
  cell.textField.stringValue = value ?: @"";
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  [self updateButtons];
}

@end
