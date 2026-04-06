#import "ConfigurationManager.h"
#import "BaristaTabBaseViewController.h"

@interface LaunchAgentsTabViewController : BaristaTabBaseViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSSearchField *searchField;
@property (strong) NSTextField *statusLabel;
@property (strong) NSButton *startButton;
@property (strong) NSButton *stopButton;
@property (strong) NSButton *restartButton;
@property (strong) NSMutableArray *launchAgents;
@property (strong) NSArray *filteredLaunchAgents;
@property (strong) NSTextView *plistPreview;
@property (strong) NSScrollView *plistScrollView;
@end

@implementation LaunchAgentsTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.launchAgents = [NSMutableArray array];
  self.filteredLaunchAgents = @[];

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(28, 34, 34, 34) spacing:20];

  [rootStack addView:[self titleLabel:@"Launch Agents"] inGravity:NSStackViewGravityTop];
  [rootStack addView:[self helperLabel:@"Manage Barista-related launch agents without leaving the panel. Search, inspect state, and restart services from one place."] inGravity:NSStackViewGravityTop];

  NSStackView *browserSection = nil;
  NSBox *browserBox = [self sectionBoxWithTitle:@"Agent Browser"
                                       subtitle:@"Filter by label or plist path, then inspect live state in the table below."
                                    contentStack:&browserSection];
  [rootStack addView:browserBox inGravity:NSStackViewGravityTop];
  [browserBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *headerStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  headerStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  headerStack.spacing = 12;
  [browserSection addView:headerStack inGravity:NSStackViewGravityTop];

  self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  self.searchField.placeholderString = @"Filter by label or path";
  self.searchField.target = self;
  self.searchField.action = @selector(filterChanged:);
  [self.searchField.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
  [self.searchField.widthAnchor constraintLessThanOrEqualToConstant:360].active = YES;
  [headerStack addView:self.searchField inGravity:NSStackViewGravityLeading];

  NSButton *refreshButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [refreshButton setButtonType:NSButtonTypeMomentaryPushIn];
  [refreshButton setBezelStyle:NSBezelStyleRounded];
  refreshButton.title = @"Refresh Status";
  refreshButton.target = self;
  refreshButton.action = @selector(loadLaunchAgents:);
  [headerStack addView:refreshButton inGravity:NSStackViewGravityLeading];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;
  [scrollView.heightAnchor constraintEqualToConstant:360].active = YES;
  [browserSection addView:scrollView inGravity:NSStackViewGravityTop];

  self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 30.0;

  NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
  stateColumn.title = @"State";
  stateColumn.width = 120;
  [self.tableView addTableColumn:stateColumn];

  NSTableColumn *labelColumn = [[NSTableColumn alloc] initWithIdentifier:@"label"];
  labelColumn.title = @"Agent Label";
  labelColumn.width = 300;
  [self.tableView addTableColumn:labelColumn];

  NSTableColumn *pidColumn = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
  pidColumn.title = @"PID";
  pidColumn.width = 80;
  [self.tableView addTableColumn:pidColumn];

  NSTableColumn *plistColumn = [[NSTableColumn alloc] initWithIdentifier:@"plist"];
  plistColumn.title = @"Plist Path";
  plistColumn.width = 250;
  [self.tableView addTableColumn:plistColumn];

  scrollView.documentView = self.tableView;

  NSStackView *actionSection = nil;
  NSBox *actionBox = [self sectionBoxWithTitle:@"Selected Agent"
                                      subtitle:@"Start, stop, or restart the currently selected launch agent."
                                   contentStack:&actionSection];
  [rootStack addView:actionBox inGravity:NSStackViewGravityTop];
  [actionBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttonRow.spacing = 12;
  [actionSection addView:buttonRow inGravity:NSStackViewGravityTop];

  for (NSString *title in @[@"Start", @"Stop", @"Restart"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    [btn.widthAnchor constraintEqualToConstant:120].active = YES;
    if ([title isEqualToString:@"Start"]) { btn.action = @selector(startSelected:); self.startButton = btn; }
    else if ([title isEqualToString:@"Stop"]) { btn.action = @selector(stopSelected:); self.stopButton = btn; }
    else { btn.action = @selector(restartSelected:); self.restartButton = btn; }
    [buttonRow addView:btn inGravity:NSStackViewGravityLeading];
  }

  self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.statusLabel.editable = NO;
  self.statusLabel.bordered = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.stringValue = @"No agents loaded.";
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  self.statusLabel.textColor = [NSColor secondaryLabelColor];
  [actionSection addView:self.statusLabel inGravity:NSStackViewGravityTop];

  // Plist Contents Preview Section
  NSStackView *plistStack = nil;
  NSBox *plistBox = [self sectionBoxWithTitle:@"Plist Contents"
                                     subtitle:@"Select an agent above to view its plist."
                                 contentStack:&plistStack];
  [rootStack addView:plistBox inGravity:NSStackViewGravityTop];
  [plistBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.plistScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  self.plistScrollView.hasVerticalScroller = YES;
  self.plistScrollView.autohidesScrollers = YES;
  self.plistScrollView.borderType = NSBezelBorder;
  [self.plistScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

  self.plistPreview = [[NSTextView alloc] initWithFrame:NSZeroRect];
  self.plistPreview.editable = NO;
  self.plistPreview.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
  self.plistPreview.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1.0];
  self.plistPreview.textColor = [NSColor colorWithWhite:0.85 alpha:1.0];
  self.plistPreview.minSize = NSMakeSize(0.0, 150);
  self.plistPreview.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
  self.plistPreview.verticallyResizable = YES;
  self.plistPreview.horizontallyResizable = NO;
  self.plistPreview.autoresizingMask = NSViewWidthSizable;
  self.plistPreview.string = @"No agent selected.";
  self.plistScrollView.documentView = self.plistPreview;
  [plistStack addView:self.plistScrollView inGravity:NSStackViewGravityTop];
  [self.plistScrollView.widthAnchor constraintEqualToAnchor:plistStack.widthAnchor].active = YES;

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
  self.plistPreview.string = @"No agent selected.";
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
  [self updatePlistPreview];
}

- (void)updatePlistPreview {
  NSDictionary *agent = [self selectedAgent];
  if (!agent) {
    self.plistPreview.string = @"No agent selected.";
    return;
  }

  NSString *path = [agent[@"plist"] description];
  if (!path || path.length == 0) {
    self.plistPreview.string = @"Unable to load plist: no path available.";
    return;
  }

  // Expand tilde if present
  path = [path stringByExpandingTildeInPath];

  NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:path];
  if (!plistDict) {
    self.plistPreview.string = [NSString stringWithFormat:@"Unable to load plist at:\n%@", path];
    return;
  }

  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:plistDict
                                                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                       error:&error];
  if (error || !jsonData) {
    self.plistPreview.string = [NSString stringWithFormat:@"Unable to serialize plist: %@", error.localizedDescription ?: @"unknown error"];
    return;
  }

  self.plistPreview.string = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"Unable to load plist";
}

@end
