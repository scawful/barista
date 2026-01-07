#import "BaristaStyle.h"
#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static char kWorkflowDocKey;
static char kWorkflowActionKey;

@interface HelpCenterController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTabView *tabs;
@property (strong) NSSegmentedControl *tabControl;
@property (strong) NSDictionary *workflowData;
@property (copy) NSString *configPath;
@property (copy) NSString *scriptsPath;
@property (copy) NSString *codePath;
@property (strong) NSArray<NSDictionary *> *keymapRows;
@property (strong) NSTableView *keymapTable;
@property (strong) NSArray<NSDictionary *> *repoRows;
@property (strong) NSArray<NSDictionary *> *filteredRepoRows;
@property (strong) NSDictionary *repoSummary;
@property (strong) NSTableView *repoTable;
@property (strong) NSSearchField *repoSearchField;
@end

@implementation HelpCenterController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  self.configPath = config.configPath;
  self.scriptsPath = config.scriptsPath;
  self.codePath = config.codePath;
  self.workflowData = [self loadWorkflowData];
  self.keymapRows = [self buildKeymapRows];
  [self loadWorkspaceData];
  [self buildWindow];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

- (void)buildWindow {
  NSRect frame = [self preferredWindowFrame];
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  [self.window setTitle:@"Barista Help Center"];
  CGFloat minWidth = MIN(720.0, frame.size.width);
  CGFloat minHeight = MIN(480.0, frame.size.height);
  [self.window setMinSize:NSMakeSize(minWidth, minHeight)];
  [self.window center];
  NSView *content = [self.window contentView];
  BaristaStyle *style = [BaristaStyle sharedStyle];
  [style applyWindowStyle:self.window];
  content.wantsLayer = YES;
  content.layer.backgroundColor = style.backgroundColor.CGColor;

  NSTabView *tabs = [[NSTabView alloc] initWithFrame:content.bounds];
  tabs.tabViewType = NSNoTabsNoBorder;
  tabs.drawsBackground = YES;
  tabs.wantsLayer = YES;
  tabs.layer.backgroundColor = style.backgroundColor.CGColor;
  tabs.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabs = tabs;

  NSTabViewItem *shortcuts = [[NSTabViewItem alloc] initWithIdentifier:@"shortcuts"];
  [shortcuts setLabel:@"Shortcuts"];
  [shortcuts setView:[self buildKeymapTab]];
  [tabs addTabViewItem:shortcuts];

  NSTabViewItem *workflow = [[NSTabViewItem alloc] initWithIdentifier:@"workflow"];
  [workflow setLabel:@"Workflow"];
  [workflow setView:[self buildWorkflowTab]];
  [tabs addTabViewItem:workflow];

  NSTabViewItem *repos = [[NSTabViewItem alloc] initWithIdentifier:@"repos"];
  [repos setLabel:@"Repos"];
  [repos setView:[self buildRepoTab]];
  [tabs addTabViewItem:repos];
  [tabs selectTabViewItemAtIndex:0];

  NSArray *labels = @[ @"Shortcuts", @"Workflow", @"Repos" ];
  NSSegmentedControl *tabControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
  tabControl.segmentCount = labels.count;
  for (NSInteger idx = 0; idx < labels.count; idx++) {
    [tabControl setLabel:labels[idx] forSegment:idx];
  }
  tabControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
  tabControl.target = self;
  tabControl.action = @selector(changeTab:);
  tabControl.segmentStyle = NSSegmentStyleSeparated;
  tabControl.selectedSegment = 0;
  tabControl.font = style.sectionFont;
  tabControl.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabControl = tabControl;

  [content addSubview:tabControl];
  [content addSubview:tabs];

  CGFloat padding = 16.0;
  [NSLayoutConstraint activateConstraints:@[
    [tabControl.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:padding],
    [tabControl.topAnchor constraintEqualToAnchor:content.topAnchor constant:12.0],
    [tabControl.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-padding],
    [tabs.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [tabs.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [tabs.topAnchor constraintEqualToAnchor:tabControl.bottomAnchor constant:10.0],
    [tabs.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
  ]];
}

- (void)changeTab:(NSSegmentedControl *)sender {
  NSInteger index = sender.selectedSegment;
  if (index >= 0 && index < self.tabs.numberOfTabViewItems) {
    [self.tabs selectTabViewItemAtIndex:index];
  }
}

- (NSView *)buildKeymapTab {
  NSRect bounds = self.window.contentView.bounds;
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSView *container = [[NSView alloc] initWithFrame:bounds];
  container.wantsLayer = YES;
  container.layer.backgroundColor = style.backgroundColor.CGColor;

  NSTextField *header = [self headerLabelWithString:@"Keyboard Shortcuts" frame:NSZeroRect];
  header.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:header];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.borderType = NSNoBorder;
  scroll.hasVerticalScroller = YES;
  scroll.drawsBackground = YES;
  scroll.backgroundColor = style.panelColor;

  NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  tableView.dataSource = self;
  tableView.delegate = self;
  tableView.headerView = nil;
  tableView.usesAlternatingRowBackgroundColors = NO;
  tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
  tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  tableView.backgroundColor = style.panelColor;
  tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
  tableView.gridColor = style.dividerColor;
  tableView.rowHeight = 22.0;

  NSTableColumn *keysColumn = [[NSTableColumn alloc] initWithIdentifier:@"keys"];
  keysColumn.title = @"Shortcut";
  keysColumn.width = 180;
  [tableView addTableColumn:keysColumn];

  NSTableColumn *descColumn = [[NSTableColumn alloc] initWithIdentifier:@"description"];
  descColumn.title = @"Description";
  descColumn.width = bounds.size.width - 200;
  [tableView addTableColumn:descColumn];

  scroll.documentView = tableView;
  [container addSubview:scroll];
  self.keymapTable = tableView;

  CGFloat padding = 16.0;
  [NSLayoutConstraint activateConstraints:@[
    [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:padding],
    [header.topAnchor constraintEqualToAnchor:container.topAnchor constant:padding],
    [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-padding],
    [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:padding],
    [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-padding],
    [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8.0],
    [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-padding],
  ]];
  return container;
}

- (NSView *)buildWorkflowTab {
  NSRect bounds = self.window.contentView.bounds;
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
  scroll.borderType = NSNoBorder;
  scroll.hasVerticalScroller = YES;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scroll.drawsBackground = YES;
  scroll.backgroundColor = style.backgroundColor;
  CGFloat width = scroll.contentSize.width;
  NSFont *buttonFont = [self preferredTextFontWithSize:12 weight:NSFontWeightRegular];
  NSArray *docs = [self workflowArrayForKey:@"docs" fallback:nil];
  NSArray *actions = [self workflowArrayForKey:@"actions" fallback:nil];
  NSInteger rows = MAX(1, docs.count);
  NSInteger actionRows = MAX(1, (actions.count + 1) / 2);
  CGFloat height = MAX(420.0, 60.0 + rows * 34.0 + actionRows * 42.0 + 100.0);
  NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  container.autoresizingMask = NSViewWidthSizable;
  container.wantsLayer = YES;
  container.layer.backgroundColor = style.backgroundColor.CGColor;
  CGFloat y = height - 40;

  NSTextField *docsHeader = [self headerLabelWithString:@"Reference Docs" frame:NSMakeRect(20, y, width - 40, 20)];
  [container addSubview:docsHeader];
  y -= 30;

  if (docs.count == 0) {
    NSTextField *emptyDocs = [self detailLabelWithString:@"No reference docs configured." frame:NSMakeRect(20, y, width - 40, 18)];
    [container addSubview:emptyDocs];
    y -= 28;
  } else {
    for (NSDictionary *doc in docs) {
      NSString *title = doc[@"title"] ?: @"Document";
      NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, width - 40, 28)];
      [button setTitle:title];
      [button setButtonType:NSButtonTypeMomentaryPushIn];
      [button setBezelStyle:NSBezelStyleTexturedRounded];
      button.font = buttonFont;
      button.target = self;
      button.action = @selector(openDoc:);
      button.toolTip = doc[@"path"];
      objc_setAssociatedObject(button, &kWorkflowDocKey, doc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      [container addSubview:button];
      y -= 34;
    }
  }

  y -= 10;
  NSTextField *actionsHeader = [self headerLabelWithString:@"Quick Actions" frame:NSMakeRect(20, y, width - 40, 20)];
  [container addSubview:actionsHeader];
  y -= 34;

  CGFloat actionWidth = (width - 60) / 2.0;
  NSInteger idx = 0;
  for (NSDictionary *action in actions) {
    NSString *title = action[@"title"] ?: @"Action";
    NSString *selectorName = action[@"selector"];
    NSString *command = action[@"command"];
    NSString *path = action[@"path"];
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    BOOL hasSelector = (selector && [self respondsToSelector:selector]);
    BOOL hasCommand = [command isKindOfClass:[NSString class]] && command.length > 0;
    BOOL hasPath = [path isKindOfClass:[NSString class]] && path.length > 0;
    NSInteger col = idx % 2;
    NSInteger row = idx / 2;
    CGFloat buttonY = y - (row * 40);
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(20 + col * (actionWidth + 20), buttonY, actionWidth, 30)];
    [button setTitle:title];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleTexturedRounded];
    button.font = buttonFont;
    button.target = self;
    if (hasSelector) {
      button.action = selector;
    } else if (hasCommand || hasPath) {
      button.action = @selector(runWorkflowAction:);
      objc_setAssociatedObject(button, &kWorkflowActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
      button.enabled = NO;
    }
    if (hasCommand) {
      button.toolTip = command;
    } else if (hasPath) {
      button.toolTip = path;
    }
    [container addSubview:button];
    idx++;
  }

  [scroll setDocumentView:container];
  return scroll;
}

- (NSView *)buildRepoTab {
  NSRect bounds = self.window.contentView.bounds;
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSView *container = [[NSView alloc] initWithFrame:bounds];
  container.wantsLayer = YES;
  container.layer.backgroundColor = style.backgroundColor.CGColor;

  NSTextField *header = [self headerLabelWithString:@"Workspace Repos" frame:NSZeroRect];
  header.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:header];

  NSTextField *summaryLabel = [self detailLabelWithString:[self repoSummaryText] frame:NSZeroRect];
  summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:summaryLabel];

  NSSearchField *searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  searchField.translatesAutoresizingMaskIntoConstraints = NO;
  searchField.placeholderString = @"Filter repos";
  searchField.font = [self preferredTextFontWithSize:11 weight:NSFontWeightRegular];
  searchField.target = self;
  searchField.action = @selector(filterRepos:);
  if ([searchField respondsToSelector:@selector(setSendsSearchStringImmediately:)]) {
    searchField.sendsSearchStringImmediately = YES;
  }
  [container addSubview:searchField];
  self.repoSearchField = searchField;

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.borderType = NSNoBorder;
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = YES;
  scroll.drawsBackground = YES;
  scroll.backgroundColor = style.panelColor;

  NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  tableView.dataSource = self;
  tableView.delegate = self;
  tableView.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
  tableView.usesAlternatingRowBackgroundColors = NO;
  tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
  tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  tableView.backgroundColor = style.panelColor;
  tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
  tableView.gridColor = style.dividerColor;
  tableView.rowHeight = 22.0;
  tableView.target = self;
  tableView.doubleAction = @selector(openRepoFromTable:);

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Repo";
  nameColumn.width = 170;
  [tableView addTableColumn:nameColumn];

  NSTableColumn *bucketColumn = [[NSTableColumn alloc] initWithIdentifier:@"bucket"];
  bucketColumn.title = @"Bucket";
  bucketColumn.width = 80;
  [tableView addTableColumn:bucketColumn];

  NSTableColumn *branchColumn = [[NSTableColumn alloc] initWithIdentifier:@"branch"];
  branchColumn.title = @"Branch";
  branchColumn.width = 120;
  [tableView addTableColumn:branchColumn];

  NSTableColumn *syncColumn = [[NSTableColumn alloc] initWithIdentifier:@"sync"];
  syncColumn.title = @"Sync";
  syncColumn.width = 70;
  [tableView addTableColumn:syncColumn];

  NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
  stateColumn.title = @"State";
  stateColumn.width = 70;
  [tableView addTableColumn:stateColumn];

  NSTableColumn *publicColumn = [[NSTableColumn alloc] initWithIdentifier:@"public"];
  publicColumn.title = @"Public";
  publicColumn.width = 70;
  [tableView addTableColumn:publicColumn];

  NSTableColumn *descColumn = [[NSTableColumn alloc] initWithIdentifier:@"description"];
  descColumn.title = @"Description";
  descColumn.width = bounds.size.width - 600;
  [tableView addTableColumn:descColumn];

  scroll.documentView = tableView;
  [container addSubview:scroll];
  self.repoTable = tableView;

  CGFloat padding = 16.0;
  [NSLayoutConstraint activateConstraints:@[
    [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:padding],
    [header.topAnchor constraintEqualToAnchor:container.topAnchor constant:padding],
    [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-padding],
    [summaryLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:padding],
    [summaryLabel.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6.0],
    [summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:searchField.leadingAnchor constant:-12.0],
    [searchField.centerYAnchor constraintEqualToAnchor:summaryLabel.centerYAnchor],
    [searchField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-padding],
    [searchField.widthAnchor constraintEqualToConstant:220.0],
    [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:padding],
    [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-padding],
    [scroll.topAnchor constraintEqualToAnchor:summaryLabel.bottomAnchor constant:12.0],
    [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-padding],
  ]];
  return container;
}

- (NSRect)preferredWindowFrame {
  NSScreen *screen = [NSScreen mainScreen];
  if (!screen) {
    screen = [NSScreen screens].firstObject;
  }
  if (!screen) {
    return NSMakeRect(0, 0, 720, 520);
  }

  NSRect visible = screen.visibleFrame;
  CGFloat margin = 80.0;
  CGFloat maxWidth = MAX(520.0, visible.size.width - margin);
  CGFloat maxHeight = MAX(420.0, visible.size.height - margin);
  CGFloat width = MIN(980.0, maxWidth);
  CGFloat height = MIN(700.0, maxHeight);

  CGFloat originX = NSMidX(visible) - width / 2.0;
  CGFloat originY = NSMidY(visible) - height / 2.0;
  return NSMakeRect(originX, originY, width, height);
}

- (NSTextField *)headerLabelWithString:(NSString *)value frame:(NSRect)frame {
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setBezeled:NO];
  [label setEditable:NO];
  [label setDrawsBackground:NO];
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSFont *font = style.sectionFont ?: [self preferredTextFontWithSize:13 weight:NSFontWeightSemibold];
  [label setFont:font];
  [label setTextColor:style.textColor ?: [NSColor labelColor]];
  [label setStringValue:value];
  return label;
}

- (NSTextField *)detailLabelWithString:(NSString *)value frame:(NSRect)frame {
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setBezeled:NO];
  [label setEditable:NO];
  [label setDrawsBackground:NO];
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSFont *font = [self preferredTextFontWithSize:11 weight:NSFontWeightRegular];
  [label setFont:font];
  [label setTextColor:style.mutedTextColor ?: [NSColor secondaryLabelColor]];
  [label setStringValue:value ?: @""];
  return label;
}

- (NSArray<NSDictionary *> *)buildKeymapRows {
  NSMutableArray *rows = [NSMutableArray array];
  NSArray *sections = [self workflowArrayForKey:@"keymap" fallback:nil];
  for (NSDictionary *section in sections) {
    NSString *title = section[@"section"] ?: @"Shortcuts";
    [rows addObject:@{ @"type": @"section", @"title": title }];
    NSArray *items = section[@"items"];
    if (![items isKindOfClass:[NSArray class]]) continue;
    for (NSDictionary *item in items) {
      NSString *keys = item[@"keys"] ?: @"";
      NSString *desc = item[@"description"] ?: @"";
      [rows addObject:@{
        @"type": @"item",
        @"keys": keys,
        @"description": desc
      }];
    }
  }
  if (rows.count == 0) {
    [rows addObject:@{ @"type": @"section", @"title": @"Shortcuts" }];
    [rows addObject:@{ @"type": @"item", @"keys": @"—", @"description": @"No shortcuts defined in workflow data." }];
  }
  return rows;
}

- (void)loadWorkspaceData {
  NSDictionary *list = [self runWsJSON:@[ @"list", @"--format", @"json" ]];
  NSDictionary *status = [self runWsJSON:@[ @"status", @"--format", @"json", @"--fast" ]];
  NSDictionary *summary = status[@"summary"];
  if ([summary isKindOfClass:[NSDictionary class]]) {
    self.repoSummary = summary;
  } else {
    self.repoSummary = @{};
  }
  self.repoRows = [self buildRepoRowsFromList:list status:status];
  self.filteredRepoRows = self.repoRows;
}

- (NSDictionary *)runWsJSON:(NSArray<NSString *> *)arguments {
  NSMutableArray *args = [NSMutableArray arrayWithObject:@"ws"];
  if ([arguments isKindOfClass:[NSArray class]]) {
    [args addObjectsFromArray:arguments];
  }
  NSString *output = [self runCommandAndCapture:@"/usr/bin/env" arguments:args];
  if (![output isKindOfClass:[NSString class]] || output.length == 0) {
    return @{};
  }
  NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) {
    return @{};
  }
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return json;
}

- (NSArray<NSDictionary *> *)buildRepoRowsFromList:(NSDictionary *)list status:(NSDictionary *)status {
  NSArray *projects = [list[@"projects"] isKindOfClass:[NSArray class]] ? list[@"projects"] : @[];
  NSArray *statusRows = [status[@"rows"] isKindOfClass:[NSArray class]] ? status[@"rows"] : @[];
  NSMutableDictionary *statusByName = [NSMutableDictionary dictionary];
  NSMutableDictionary *statusByRel = [NSMutableDictionary dictionary];

  for (NSDictionary *row in statusRows) {
    if (![row isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = row[@"name"];
    NSString *rel = row[@"rel_path"];
    if (name.length > 0) {
      statusByName[name] = row;
    }
    if (rel.length > 0) {
      statusByRel[rel] = row;
    }
  }

  NSMutableArray *rows = [NSMutableArray array];
  for (NSDictionary *project in projects) {
    if (![project isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = project[@"name"] ?: @"";
    NSString *rel = project[@"rel_path"] ?: @"";
    NSString *path = project[@"path"] ?: @"";
    NSString *desc = project[@"description"] ?: @"";
    NSString *bucket = [self bucketForRelPath:rel];
    id publicValue = project[@"public"];
    NSString *publicFlag = @"—";
    if ([publicValue isKindOfClass:[NSNumber class]]) {
      publicFlag = [publicValue boolValue] ? @"yes" : @"no";
    }
    BOOL hasGit = [project[@"has_git"] boolValue];

    NSDictionary *statusRow = statusByName[name] ?: statusByRel[rel];
    NSString *branch = statusRow[@"branch"] ?: (hasGit ? @"—" : @"");
    BOOL dirty = [statusRow[@"dirty"] boolValue];
    NSInteger ahead = [statusRow[@"ahead"] integerValue];
    NSInteger behind = [statusRow[@"behind"] integerValue];
    NSString *sync = (ahead != 0 || behind != 0) ? [NSString stringWithFormat:@"A%ld B%ld", (long)ahead, (long)behind] : @"-";
    NSString *state = hasGit ? (dirty ? @"dirty" : @"clean") : @"no git";

    [rows addObject:@{
      @"name": name,
      @"bucket": bucket ?: @"",
      @"rel_path": rel ?: @"",
      @"path": path ?: @"",
      @"description": desc ?: @"",
      @"public": publicFlag ?: @"—",
      @"branch": branch ?: @"—",
      @"sync": sync ?: @"—",
      @"state": state ?: @"—",
      @"dirty": @(dirty)
    }];
  }

  [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    NSString *bucketA = a[@"bucket"] ?: @"";
    NSString *bucketB = b[@"bucket"] ?: @"";
    NSComparisonResult bucketCompare = [bucketA compare:bucketB options:NSCaseInsensitiveSearch];
    if (bucketCompare != NSOrderedSame) {
      return bucketCompare;
    }
    NSString *nameA = a[@"name"] ?: @"";
    NSString *nameB = b[@"name"] ?: @"";
    return [nameA compare:nameB options:NSCaseInsensitiveSearch];
  }];

  return rows;
}

- (NSString *)bucketForRelPath:(NSString *)relPath {
  if (![relPath isKindOfClass:[NSString class]] || relPath.length == 0) {
    return @"";
  }
  NSArray *parts = [relPath componentsSeparatedByString:@"/"];
  return parts.count > 0 ? parts.firstObject : @"";
}

- (NSString *)repoSummaryText {
  NSDictionary *summary = self.repoSummary;
  if (![summary isKindOfClass:[NSDictionary class]] || summary.count == 0) {
    return @"Workspace status unavailable. Run ws status to populate.";
  }
  NSInteger total = [summary[@"total"] integerValue];
  NSInteger dirty = [summary[@"dirty"] integerValue];
  NSInteger clean = [summary[@"clean"] integerValue];
  NSInteger ahead = [summary[@"ahead"] integerValue];
  NSInteger behind = [summary[@"behind"] integerValue];
  return [NSString stringWithFormat:@"Total %ld | Dirty %ld | Clean %ld | Ahead %ld | Behind %ld",
                                    (long)total, (long)dirty, (long)clean, (long)ahead, (long)behind];
}

- (void)filterRepos:(id)sender {
  NSString *query = self.repoSearchField.stringValue ?: @"";
  if (query.length == 0) {
    self.filteredRepoRows = self.repoRows;
  } else {
    NSString *needle = [query lowercaseString];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *row in self.repoRows) {
      NSString *name = [row[@"name"] lowercaseString] ?: @"";
      NSString *rel = [row[@"rel_path"] lowercaseString] ?: @"";
      NSString *desc = [row[@"description"] lowercaseString] ?: @"";
      NSString *bucket = [row[@"bucket"] lowercaseString] ?: @"";
      if ([name containsString:needle] || [rel containsString:needle] || [desc containsString:needle] || [bucket containsString:needle]) {
        [filtered addObject:row];
      }
    }
    self.filteredRepoRows = filtered;
  }
  [self.repoTable reloadData];
}

- (void)openRepoFromTable:(id)sender {
  NSInteger row = self.repoTable.clickedRow;
  if (row < 0) {
    row = self.repoTable.selectedRow;
  }
  if (row < 0 || row >= self.filteredRepoRows.count) {
    return;
  }
  NSString *path = self.filteredRepoRows[row][@"path"];
  if (![path isKindOfClass:[NSString class]] || path.length == 0) {
    return;
  }
  NSURL *url = [NSURL fileURLWithPath:path];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)runWorkflowAction:(NSButton *)sender {
  NSDictionary *action = objc_getAssociatedObject(sender, &kWorkflowActionKey);
  if (![action isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSString *command = action[@"command"];
  NSString *path = action[@"path"];
  if ([command isKindOfClass:[NSString class]] && command.length > 0) {
    [self runShellCommand:command];
    return;
  }
  if ([path isKindOfClass:[NSString class]] && path.length > 0) {
    NSString *resolved = [self expandedWorkflowPath:path];
    if (resolved) {
      NSURL *url = [NSURL fileURLWithPath:resolved];
      [[NSWorkspace sharedWorkspace] openURL:url];
    }
  }
}

- (NSFont *)preferredTextFontWithSize:(CGFloat)size weight:(NSFontWeight)weight {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *fontName = [config valueForKeyPath:@"appearance.font_text" defaultValue:nil];
  if ([fontName isKindOfClass:[NSString class]] && fontName.length > 0) {
    NSFont *font = [NSFont fontWithName:fontName size:size];
    if (font) {
      return font;
    }
  }
  BaristaStyle *style = [BaristaStyle sharedStyle];
  if (style.bodyFont) {
    NSFont *font = [NSFont fontWithName:style.bodyFont.fontName size:size];
    if (font) {
      return font;
    }
  }
  return [NSFont systemFontOfSize:size weight:weight];
}

- (NSFont *)preferredMonoFontWithSize:(CGFloat)size weight:(NSFontWeight)weight {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *fontName = [config valueForKeyPath:@"appearance.font_numbers" defaultValue:nil];
  if ([fontName isKindOfClass:[NSString class]] && fontName.length > 0) {
    NSFont *font = [NSFont fontWithName:fontName size:size];
    if (font) {
      return font;
    }
  }
  BaristaStyle *style = [BaristaStyle sharedStyle];
  return [style monoFontOfSize:size weight:weight];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  if (tableView == self.repoTable) {
    return self.filteredRepoRows.count;
  }
  return self.keymapRows.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
  if (tableView != self.keymapTable) {
    return NO;
  }
  if (row < 0 || row >= self.keymapRows.count) {
    return NO;
  }
  return [self.keymapRows[row][@"type"] isEqualToString:@"section"];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  if (tableView == self.repoTable) {
    return 22.0;
  }
  return [self tableView:tableView isGroupRow:row] ? 26.0 : 22.0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSString *identifier = tableColumn.identifier ?: @"cell";
  NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
    cell.identifier = identifier;
    NSTextField *textField = [[NSTextField alloc] initWithFrame:cell.bounds];
    textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.textField = textField;
    [cell addSubview:textField];
  }

  NSTextField *textField = cell.textField;
  if (tableView == self.repoTable) {
    BaristaStyle *style = [BaristaStyle sharedStyle];
    NSDictionary *entry = (row >= 0 && row < self.filteredRepoRows.count) ? self.filteredRepoRows[row] : @{};
    NSString *name = entry[@"name"] ?: @"";
    NSString *bucket = entry[@"bucket"] ?: @"";
    NSString *branch = entry[@"branch"] ?: @"—";
    NSString *sync = entry[@"sync"] ?: @"—";
    NSString *state = entry[@"state"] ?: @"—";
    NSString *publicFlag = entry[@"public"] ?: @"—";
    NSString *desc = entry[@"description"] ?: @"";
    if ([identifier isEqualToString:@"name"]) {
      textField.stringValue = name;
      textField.font = style.sectionFont ?: [self preferredTextFontWithSize:12 weight:NSFontWeightSemibold];
      textField.textColor = style.textColor ?: [NSColor labelColor];
    } else if ([identifier isEqualToString:@"bucket"]) {
      textField.stringValue = bucket;
      textField.font = [self preferredMonoFontWithSize:11 weight:NSFontWeightRegular];
      textField.textColor = style.mutedTextColor ?: [NSColor secondaryLabelColor];
    } else if ([identifier isEqualToString:@"branch"]) {
      textField.stringValue = branch;
      textField.font = [self preferredMonoFontWithSize:11 weight:NSFontWeightRegular];
      textField.textColor = style.textColor ?: [NSColor labelColor];
    } else if ([identifier isEqualToString:@"sync"]) {
      textField.stringValue = sync;
      textField.font = [self preferredMonoFontWithSize:11 weight:NSFontWeightRegular];
      textField.textColor = style.mutedTextColor ?: [NSColor secondaryLabelColor];
    } else if ([identifier isEqualToString:@"state"]) {
      textField.stringValue = state;
      textField.font = [self preferredMonoFontWithSize:11 weight:NSFontWeightRegular];
      if ([state isEqualToString:@"dirty"]) {
        textField.textColor = [NSColor systemOrangeColor];
      } else {
        textField.textColor = style.mutedTextColor ?: [NSColor secondaryLabelColor];
      }
    } else if ([identifier isEqualToString:@"public"]) {
      textField.stringValue = publicFlag;
      textField.font = [self preferredMonoFontWithSize:11 weight:NSFontWeightRegular];
      textField.textColor = style.mutedTextColor ?: [NSColor secondaryLabelColor];
    } else {
      textField.stringValue = desc;
      textField.font = [self preferredTextFontWithSize:11 weight:NSFontWeightRegular];
      textField.textColor = style.textColor ?: [NSColor labelColor];
    }
    return cell;
  }

  NSDictionary *entry = self.keymapRows[row];
  NSString *type = entry[@"type"];
  if ([type isEqualToString:@"section"]) {
    if ([identifier isEqualToString:@"keys"]) {
      textField.stringValue = entry[@"title"] ?: @"Shortcuts";
      textField.font = [self preferredTextFontWithSize:12.5 weight:NSFontWeightSemibold];
      textField.textColor = [NSColor secondaryLabelColor];
    } else {
      textField.stringValue = @"";
    }
  } else {
    if ([identifier isEqualToString:@"keys"]) {
      textField.stringValue = entry[@"keys"] ?: @"";
      textField.font = [self preferredMonoFontWithSize:12 weight:NSFontWeightRegular];
      textField.textColor = [NSColor labelColor];
    } else {
      textField.stringValue = entry[@"description"] ?: @"";
      textField.font = [self preferredTextFontWithSize:12 weight:NSFontWeightRegular];
      textField.textColor = [NSColor labelColor];
    }
  }
  return cell;
}


- (NSArray *)workflowArrayForKey:(NSString *)key fallback:(NSArray *)fallback {
  id value = self.workflowData[key];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return fallback ?: @[];
}

- (NSDictionary *)loadWorkflowData {
  if (![self.configPath isKindOfClass:[NSString class]] || self.configPath.length == 0) {
    return @{};
  }
  NSString *path = [self.configPath stringByAppendingPathComponent:@"data/workflow_shortcuts.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data) return @{};
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return json;
}

- (NSString *)expandedWorkflowPath:(NSString *)relativePath {
  if (![relativePath isKindOfClass:[NSString class]]) return nil;
  if ([relativePath containsString:@"%CONFIG%"] && self.configPath.length) {
    relativePath = [relativePath stringByReplacingOccurrencesOfString:@"%CONFIG%" withString:self.configPath];
  }
  if ([relativePath containsString:@"%CODE%"] && self.codePath.length) {
    relativePath = [relativePath stringByReplacingOccurrencesOfString:@"%CODE%" withString:self.codePath];
  }
  if ([relativePath hasPrefix:@"~/"]) {
    return [relativePath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:NSHomeDirectory()];
  }
  if ([relativePath hasPrefix:@"/"]) {
    return relativePath;
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:relativePath];
}

- (void)openDoc:(NSButton *)sender {
  NSDictionary *entry = objc_getAssociatedObject(sender, &kWorkflowDocKey);
  NSString *urlString = [entry isKindOfClass:[NSDictionary class]] ? entry[@"url"] : nil;
  NSString *path = [entry isKindOfClass:[NSDictionary class]] ? entry[@"path"] : sender.toolTip;
  if ([urlString isKindOfClass:[NSString class]] && urlString.length > 0) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
      [[NSWorkspace sharedWorkspace] openURL:url];
      return;
    }
  }
  NSString *resolved = [self expandedWorkflowPath:path];
  if (!resolved) return;
  NSURL *url = [NSURL fileURLWithPath:resolved];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openPathFromButton:(NSButton *)sender {
  NSString *path = sender.toolTip;
  if (!path) return;
  NSURL *url = [NSURL fileURLWithPath:path];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)reloadBar:(id)sender {
  [self runCommand:@"/opt/homebrew/opt/sketchybar/bin/sketchybar" arguments:@[@"--reload"]];
}

- (void)openLogs:(id)sender {
  NSURL *url = [NSURL fileURLWithPath:@"/opt/homebrew/var/log/sketchybar"];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)runAccessibilityFix:(id)sender {
  NSString *script = [self.configPath stringByAppendingPathComponent:@"helpers/setup_permissions.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    script = [self.scriptsPath stringByAppendingPathComponent:@"yabai_accessibility_fix.sh"];
  }
  [self runScript:script arguments:@[]];
}

- (void)focusEmacsSpace:(id)sender {
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"yabai_control.sh"];
  [self runScript:script arguments:@[@"space-focus-app", @"Emacs"]];
}

- (void)launchYaze:(id)sender {
  NSString *path = [[self.codePath stringByAppendingPathComponent:@"yaze"] stringByAppendingPathComponent:@"build/bin/yaze"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
    [self runCommand:path arguments:@[]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    NSString *message = [NSString stringWithFormat:@"Build Yaze first: cd %@/yaze && make", self.codePath ?: @"~/src"];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  }
}

- (void)openControlPanel:(id)sender {
  [self openControlPanelWithMode:nil];
}

- (void)openControlPanelNative:(id)sender {
  [self openControlPanelWithMode:@"--native"];
}

- (void)openControlPanelImGui:(id)sender {
  [self openControlPanelWithMode:@"--imgui"];
}

- (void)openIconBrowser:(id)sender {
  NSString *path = [self.configPath stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    [self runCommand:path arguments:@[]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = [NSString stringWithFormat:@"Build icon_browser first: cd %@/gui && make icon_browser", self.configPath];
    [alert runModal];
  }
}

- (NSString *)resolveSysManualBinary {
  NSString *codeDir = self.codePath ?: [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
  NSArray *candidates = @[
    [codeDir stringByAppendingPathComponent:@"lab/sys_manual/build/sys_manual"],
    [codeDir stringByAppendingPathComponent:@"sys_manual/build/sys_manual"],
    @"/Applications/sys_manual.app/Contents/MacOS/sys_manual"
  ];
  for (NSString *candidate in candidates) {
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
  return nil;
}

- (void)openSysManual:(id)sender {
  NSString *binary = [self resolveSysManualBinary];
  if (binary) {
    [self runCommand:binary arguments:@[]];
    return;
  }
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Sys Manual Not Found";
  alert.informativeText = @"Build sys_manual first (~/src/lab/sys_manual/build/sys_manual) or install it in /Applications.";
  [alert runModal];
}

- (void)openControlPanelWithMode:(NSString *)mode {
  NSString *script = [self.configPath stringByAppendingPathComponent:@"bin/open_control_panel.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Control Panel Script Missing";
    alert.informativeText = [NSString stringWithFormat:@"Missing script: %@", script];
    [alert runModal];
    return;
  }
  if (mode && mode.length > 0) {
    [self runScript:script arguments:@[mode]];
  } else {
    [self runScript:script arguments:@[]];
  }
}

- (void)runScript:(NSString *)script arguments:(NSArray<NSString *> *)arguments {
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) return;
  [self runCommand:script arguments:arguments];
}

- (void)runShellCommand:(NSString *)command {
  if (![command isKindOfClass:[NSString class]] || command.length == 0) {
    return;
  }
  [self runCommand:@"/bin/sh" arguments:@[ @"-lc", command ]];
}

- (NSMutableDictionary *)commandEnvironment {
  NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  NSString *path = env[@"PATH"] ?: @"";
  env[@"PATH"] = [NSString stringWithFormat:@"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:%@", path];
  return env;
}

- (NSString *)runCommandAndCapture:(NSString *)command arguments:(NSArray<NSString *> *)arguments {
  if (![command isKindOfClass:[NSString class]] || command.length == 0) {
    return @"";
  }
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = command;
  task.arguments = arguments ?: @[];
  task.environment = [self commandEnvironment];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    return @"";
  }
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (void)runCommand:(NSString *)command arguments:(NSArray<NSString *> *)arguments {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = command;
  task.arguments = arguments ?: @[];
  task.environment = [self commandEnvironment];
  @try {
    [task launch];
  } @catch (NSException *exception) {
    (void)exception;
  }
}

@end

int main(int argc, const char **argv) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    HelpCenterController *delegate = [HelpCenterController new];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [app run];
  }
  return 0;
}
