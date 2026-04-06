#import "ConfigurationManager.h"
#import "MainWindowController.h"
#import "BaristaPanelState.h"
#import "BaristaPanelWindow.h"
#import "BaristaTabRegistry.h"
#import "BaristaStyle.h"
#import "BaristaPanelView.h"
#import <Cocoa/Cocoa.h>

static NSString *const BaristaSelectTabNotification = @"BaristaSelectTabNotification";

@interface MainWindowController ()
@property (assign) BOOL windowConfigured;
@property (strong) BaristaPanelView *tabContainer;
@property (copy) NSString *requestedInitialTabIdentifier;
@property (strong) NSDictionary<NSString *, NSDictionary *> *tabDescriptorsByIdentifier;
@property (strong) NSMutableDictionary<NSString *, NSViewController *> *tabControllersByIdentifier;
@property (strong) NSArray<NSDictionary *> *sidebarItems;
@end

@interface BaristaSidebarRowView : NSTableRowView
@end

@implementation BaristaSidebarRowView

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
  BaristaStyle *style = [BaristaStyle sharedStyle];
  [style.sidebarColor setFill];
  NSRectFill(dirtyRect);
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
  if (!self.isSelected) {
    return;
  }
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSRect inset = NSInsetRect(self.bounds, 6.0, 2.0);
  NSBezierPath *highlight = [NSBezierPath bezierPathWithRoundedRect:inset xRadius:4.0 yRadius:4.0];
  [style.selectionColor setFill];
  [highlight fill];

  NSRect barRect = NSMakeRect(2.0, 3.0, 2.0, self.bounds.size.height - 6.0);
  [[style.accentColor colorWithAlphaComponent:0.85] setFill];
  NSRectFill(barRect);
}

@end

@implementation MainWindowController

- (NSFont *)preferredSidebarIconFontWithSize:(CGFloat)size {
  NSArray<NSString *> *candidates = @[
    @"Hack Nerd Font",
    @"JetBrainsMono Nerd Font",
    @"Symbols Nerd Font",
    @"MesloLGS NF"
  ];
  for (NSString *name in candidates) {
    NSFont *font = [NSFont fontWithName:name size:size];
    if (font) {
      return font;
    }
  }
  return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

- (instancetype)init {
  NSRect frame = NSMakeRect(0, 0, 720, 560);
  BaristaPanelState *panelState = [BaristaPanelState sharedState];
  NSScreen *screen = [NSScreen mainScreen];
  if (screen) {
    NSRect visible = screen.visibleFrame;
    CGFloat margin = 80.0;
    CGFloat maxWidth = MAX(560.0, visible.size.width - margin);
    CGFloat maxHeight = MAX(420.0, visible.size.height - margin);
    CGFloat width = MIN(760.0, maxWidth);
    CGFloat height = MIN(600.0, maxHeight);
    frame = NSMakeRect(0, 0, width, height);
  }
  NSWindow *window = [[BaristaPanelWindow alloc] initWithContentRect:frame];

  self = [super initWithWindow:window];
  if (self) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSelectTabNotification:)
                                                 name:BaristaSelectTabNotification
                                               object:nil];
    self.requestedInitialTabIdentifier = [self requestedInitialTabIdentifierFromProcess];
    if (!self.requestedInitialTabIdentifier.length) {
      self.requestedInitialTabIdentifier = [panelState lastSelectedTabIdentifier];
    }
    if (!self.requestedInitialTabIdentifier.length) {
      self.requestedInitialTabIdentifier = @"appearance";
    }
    NSLog(@"[barista] created window=%@", window);
    NSLog(@"[barista] before setupTabView");
    [self setupTabView];
    NSLog(@"[barista] init complete");
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:BaristaSelectTabNotification
                                                object:nil];
}

- (NSString *)requestedInitialTabIdentifierFromProcess {
  NSString *envTab = [[[NSProcessInfo processInfo] environment] objectForKey:@"BARISTA_CONTROL_TAB"];
  if ([envTab isKindOfClass:[NSString class]] && envTab.length > 0) {
    return [envTab lowercaseString];
  }

  NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
  for (NSUInteger idx = 0; idx + 1 < arguments.count; idx++) {
    if ([arguments[idx] isEqualToString:@"--tab"]) {
      return [arguments[idx + 1] lowercaseString];
    }
  }
  return nil;
}

- (NSInteger)indexOfTabIdentifier:(NSString *)identifier {
  if (!identifier.length) {
    return NSNotFound;
  }
  for (NSInteger idx = 0; idx < (NSInteger)self.sidebarItems.count; idx++) {
    NSDictionary *item = self.sidebarItems[idx];
    NSString *itemId = item[@"id"];
    if ([[itemId lowercaseString] isEqualToString:[identifier lowercaseString]]) {
      return idx;
    }
  }
  return NSNotFound;
}

- (void)rebuildSidebarItems {
  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  NSString *currentSection = nil;
  for (NSDictionary *descriptor in [BaristaTabRegistry defaultTabDescriptors]) {
    NSString *section = descriptor[@"section"] ?: @"";
    if (section.length > 0 && ![section isEqualToString:currentSection]) {
      [items addObject:@{ @"kind": @"section", @"label": section }];
      currentSection = section;
    }
    NSMutableDictionary *row = [descriptor mutableCopy];
    row[@"kind"] = @"tab";
    [items addObject:row];
  }
  self.sidebarItems = [items copy];
}

- (NSString *)tabIdentifierForSidebarRow:(NSInteger)row {
  if (row < 0 || row >= (NSInteger)self.sidebarItems.count) {
    return nil;
  }
  NSDictionary *item = self.sidebarItems[row];
  if (![item[@"kind"] isEqualToString:@"tab"]) {
    return nil;
  }
  return item[@"id"];
}

- (void)setupTabView {
  BaristaStyle *style = [BaristaStyle sharedStyle];

  // --- Tab view (borderless, no tabs — content only) ---
  self.tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
  self.tabView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabView.delegate = self;
  [self.tabView setTabViewType:NSNoTabsNoBorder];
  self.tabView.drawsBackground = NO;
  self.tabView.wantsLayer = YES;
  self.tabView.layer.backgroundColor = style.panelColor.CGColor;
  self.tabView.layer.borderColor = style.dividerColor.CGColor;
  self.tabView.layer.borderWidth = 1.0;

  // --- Register tab descriptors ---
  NSMutableArray<NSDictionary *> *tabItems = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSDictionary *> *descriptorMap = [NSMutableDictionary dictionary];
  self.tabControllersByIdentifier = [NSMutableDictionary dictionary];
  for (NSDictionary *descriptor in [BaristaTabRegistry defaultTabDescriptors]) {
    NSString *identifier = descriptor[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) {
      continue;
    }
    descriptorMap[identifier] = descriptor;
    [self addTabDescriptor:descriptor store:tabItems];
  }
  self.tabDescriptorsByIdentifier = [descriptorMap copy];
  self.tabItems = [tabItems copy];
  [self rebuildSidebarItems];

  // --- Sidebar ---
  [self setupSidebarWithStyle:style];

  // --- Tab container (holds the tab view with padding) ---
  self.tabContainer = [[BaristaPanelView alloc] initWithFrame:NSZeroRect];
  [self.tabContainer addSubview:self.tabView];

  CGFloat pad = 10.0;
  [NSLayoutConstraint activateConstraints:@[
    [self.tabView.leadingAnchor constraintEqualToAnchor:self.tabContainer.leadingAnchor constant:pad],
    [self.tabView.trailingAnchor constraintEqualToAnchor:self.tabContainer.trailingAnchor constant:-pad],
    [self.tabView.topAnchor constraintEqualToAnchor:self.tabContainer.topAnchor constant:pad],
    [self.tabView.bottomAnchor constraintEqualToAnchor:self.tabContainer.bottomAnchor constant:-pad],
  ]];

  // --- Split view (sidebar | content) ---
  self.splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
  self.splitView.vertical = YES;
  self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
  self.splitView.delegate = self;
  [self.splitView addSubview:self.sidebarView];
  [self.splitView addSubview:self.tabContainer];

  [self.window setContentView:self.splitView];

  // --- Apply styles ---
  for (NSTabViewItem *item in self.tabView.tabViewItems) {
    NSViewController *controller = item.viewController;
    if (controller) {
      @try {
        [style applyStyleToViewHierarchy:controller.view];
      } @catch (NSException *exception) {
        NSLog(@"[barista] style exception on tab %@: %@", item.identifier, exception.reason);
      }
    }
  }

  // --- Select initial tab ---
  [self.sidebarTable reloadData];
  NSInteger initialRow = [self indexOfTabIdentifier:self.requestedInitialTabIdentifier];
  if (initialRow == NSNotFound) {
    initialRow = [self indexOfTabIdentifier:@"appearance"];
  }
  if (self.sidebarItems.count > 0 && initialRow >= 0 && initialRow < (NSInteger)self.sidebarItems.count) {
    [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:initialRow] byExtendingSelection:NO];
    NSString *initialIdentifier = [self tabIdentifierForSidebarRow:initialRow];
    NSInteger tabIndex = [self.tabItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
      return [[item[@"id"] lowercaseString] isEqualToString:[initialIdentifier lowercaseString]];
    }];
    if (tabIndex != NSNotFound) {
      [self selectTabAtIndex:tabIndex];
    }
  }
}

// MARK: - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
  return 120.0;  // sidebar min width
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
  return splitView.bounds.size.width * 0.35;  // sidebar never > 35% of window
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
  return NO;
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
  // Keep sidebar at its current width, give all extra space to content
  NSView *sidebar = splitView.subviews.firstObject;
  NSView *content = splitView.subviews.lastObject;
  CGFloat divider = splitView.dividerThickness;
  CGFloat totalWidth = splitView.bounds.size.width;
  CGFloat totalHeight = splitView.bounds.size.height;
  CGFloat sidebarWidth = sidebar.frame.size.width;
  if (sidebarWidth < 1.0) {
    sidebarWidth = [BaristaStyle sharedStyle].sidebarWidth;
  }

  // Clamp sidebar
  CGFloat maxSidebar = totalWidth * 0.35;
  if (sidebarWidth > maxSidebar) sidebarWidth = maxSidebar;
  if (sidebarWidth < 120.0) sidebarWidth = 120.0;

  CGFloat contentWidth = totalWidth - sidebarWidth - divider;
  sidebar.frame = NSMakeRect(0, 0, sidebarWidth, totalHeight);
  content.frame = NSMakeRect(sidebarWidth + divider, 0, contentWidth, totalHeight);
}

- (void)addTabDescriptor:(NSDictionary *)descriptor
                    store:(NSMutableArray<NSDictionary *> *)store {
  NSString *identifier = descriptor[@"id"];
  NSString *label = descriptor[@"label"];
  if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0
      || ![label isKindOfClass:[NSString class]] || label.length == 0) {
    return;
  }

  NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:identifier];
  item.label = label;
  NSView *placeholder = [[NSView alloc] initWithFrame:self.tabView.bounds];
  placeholder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  item.view = placeholder;
  [self.tabView addTabViewItem:item];
  [store addObject:@{
    @"id": identifier,
    @"label": label,
    @"icon": descriptor[@"icon"] ?: @""
  }];
}

- (NSTabViewItem *)tabViewItemForIdentifier:(NSString *)identifier {
  if (!identifier.length) {
    return nil;
  }

  for (NSTabViewItem *item in self.tabView.tabViewItems) {
    if ([[item.identifier description] isEqualToString:identifier]) {
      return item;
    }
  }
  return nil;
}

- (NSViewController *)ensureControllerLoadedForIdentifier:(NSString *)identifier {
  if (!identifier.length) {
    return nil;
  }

  NSViewController *controller = self.tabControllersByIdentifier[identifier];
  NSTabViewItem *item = [self tabViewItemForIdentifier:identifier];
  if (controller) {
    if (item && item.view != controller.view) {
      item.view = controller.view;
    }
    return controller;
  }

  NSDictionary *descriptor = self.tabDescriptorsByIdentifier[identifier];
  Class controllerClass = descriptor[@"controllerClass"];
  if (!controllerClass || ![controllerClass isSubclassOfClass:[NSViewController class]]) {
    return nil;
  }

  controller = [[controllerClass alloc] init];
  self.tabControllersByIdentifier[identifier] = controller;
  if (item) {
    item.view = controller.view;
  }

  @try {
    [[BaristaStyle sharedStyle] applyStyleToViewHierarchy:controller.view];
  } @catch (NSException *exception) {
    NSLog(@"[barista] style exception on tab %@: %@", identifier, exception.reason);
  }
  return controller;
}

- (void)selectTabAtIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)self.tabItems.count) {
    return;
  }

  NSString *identifier = self.tabItems[index][@"id"];
  [self ensureControllerLoadedForIdentifier:identifier];
  [self.tabView selectTabViewItemAtIndex:index];
  [[BaristaPanelState sharedState] setLastSelectedTabIdentifier:identifier];
}

- (void)saveWindowFrame {
  if (self.window) {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:@"BaristaControlPanelWindowFrame"];
  }
}

- (void)handleSelectTabNotification:(NSNotification *)notification {
  NSString *identifier = notification.userInfo[@"tab"];
  NSInteger index = [self indexOfTabIdentifier:identifier];
  if (index == NSNotFound) {
    return;
  }
  [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
  NSString *tabIdentifier = [self tabIdentifierForSidebarRow:index];
  NSInteger tabIndex = [self.tabItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
    return [[item[@"id"] lowercaseString] isEqualToString:[tabIdentifier lowercaseString]];
  }];
  if (tabIndex != NSNotFound) {
    [self selectTabAtIndex:tabIndex];
  }
  [self.sidebarTable reloadData];
}

- (void)setupSidebarWithStyle:(BaristaStyle *)style {
  // Sidebar is a vertical stack: header on top, table scroll below
  self.sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, style.sidebarWidth, 100)];
  self.sidebarView.wantsLayer = YES;
  self.sidebarView.layer.backgroundColor = style.sidebarColor.CGColor;

  // --- Header ---
  NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
  header.translatesAutoresizingMaskIntoConstraints = NO;
  header.wantsLayer = YES;
  header.layer.backgroundColor = style.backgroundColor.CGColor;
  [self.sidebarView addSubview:header];

  NSStackView *headerStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  headerStack.translatesAutoresizingMaskIntoConstraints = NO;
  headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  headerStack.alignment = NSLayoutAttributeLeading;
  headerStack.spacing = 3;
  headerStack.edgeInsets = NSEdgeInsetsMake(10, 12, 8, 12);
  [header addSubview:headerStack];

  [NSLayoutConstraint activateConstraints:@[
    [headerStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [headerStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
    [headerStack.topAnchor constraintEqualToAnchor:header.topAnchor],
    [headerStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
  ]];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *themeName = style.themeName.length ? style.themeName : @"default";
  NSString *profileName = [config valueForKeyPath:@"profile" defaultValue:@"default"] ?: @"default";

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Barista";
  title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightBold];
  title.textColor = style.textColor;
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [headerStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *subtitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  subtitle.stringValue = [NSString stringWithFormat:@"%@ · %@", themeName, profileName];
  subtitle.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
  subtitle.textColor = style.mutedTextColor;
  subtitle.bordered = NO;
  subtitle.editable = NO;
  subtitle.backgroundColor = [NSColor clearColor];
  [headerStack addView:subtitle inGravity:NSStackViewGravityTop];

  // --- Divider ---
  NSView *headerDivider = [[NSView alloc] initWithFrame:NSZeroRect];
  headerDivider.translatesAutoresizingMaskIntoConstraints = NO;
  headerDivider.wantsLayer = YES;
  headerDivider.layer.backgroundColor = style.dividerColor.CGColor;
  [self.sidebarView addSubview:headerDivider];
  [headerDivider.heightAnchor constraintEqualToConstant:1.0].active = YES;

  // --- Table scroll ---
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSNoBorder;
  scrollView.drawsBackground = NO;

  self.sidebarTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.sidebarTable.dataSource = self;
  self.sidebarTable.delegate = self;
  self.sidebarTable.headerView = nil;
  self.sidebarTable.rowHeight = 30.0;
  self.sidebarTable.backgroundColor = style.sidebarColor;
  self.sidebarTable.focusRingType = NSFocusRingTypeNone;
  self.sidebarTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;

  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"label"];
  column.resizingMask = NSTableColumnAutoresizingMask;
  [self.sidebarTable addTableColumn:column];
  scrollView.documentView = self.sidebarTable;
  [self.sidebarView addSubview:scrollView];

  // --- Layout: header | divider | scroll fill remaining ---
  [NSLayoutConstraint activateConstraints:@[
    [header.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor],
    [header.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
    [header.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],

    [headerDivider.topAnchor constraintEqualToAnchor:header.bottomAnchor],
    [headerDivider.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
    [headerDivider.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],

    [scrollView.topAnchor constraintEqualToAnchor:headerDivider.bottomAnchor],
    [scrollView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
    [scrollView.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor],
  ]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.sidebarItems.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  NSDictionary *item = (row >= 0 && row < (NSInteger)self.sidebarItems.count) ? self.sidebarItems[row] : nil;
  if ([item[@"kind"] isEqualToString:@"section"]) {
    return 22.0;
  }
  return 30.0;
}

- (NSIndexSet *)tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes {
  NSMutableIndexSet *allowed = [NSMutableIndexSet indexSet];
  [proposedSelectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    NSString *identifier = [self tabIdentifierForSidebarRow:idx];
    if (identifier.length > 0) {
      [allowed addIndex:idx];
    }
  }];
  if (allowed.count == 0) {
    return tableView.selectedRowIndexes ?: [NSIndexSet indexSet];
  }
  return allowed;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
  return [[BaristaSidebarRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *item = (row >= 0 && row < (NSInteger)self.sidebarItems.count) ? self.sidebarItems[row] : nil;
  if (!item) {
    return nil;
  }

  BaristaStyle *style = [BaristaStyle sharedStyle];
  if ([item[@"kind"] isEqualToString:@"section"]) {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"BaristaSectionCell" owner:self];
    if (!cell) {
      cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 22)];
      NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 4, tableColumn.width - 14, 14)];
      textField.bordered = NO;
      textField.editable = NO;
      textField.backgroundColor = [NSColor clearColor];
      textField.autoresizingMask = NSViewWidthSizable;
      textField.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
      textField.textColor = style.mutedTextColor;
      textField.tag = 2001;
      [cell addSubview:textField];
      cell.identifier = @"BaristaSectionCell";
    }
    NSTextField *textField = [cell viewWithTag:2001];
    textField.stringValue = [item[@"label"] uppercaseString];
    return cell;
  }

  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"BaristaTabCell" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 28)];
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 5, tableColumn.width - 12, 18)];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.autoresizingMask = NSViewWidthSizable;
    textField.tag = 1001;
    [cell addSubview:textField];
    cell.textField = textField;
    cell.identifier = @"BaristaTabCell";
  }
  NSTextField *textField = [cell viewWithTag:1001];
  if (![textField isKindOfClass:[NSTextField class]]) {
    textField = [cell.subviews firstObject];
  }
  NSString *label = item[@"label"] ?: @"";
  NSString *icon = item[@"icon"] ?: @"";
  textField.stringValue = icon.length ? [NSString stringWithFormat:@"%@  %@", icon, label] : label;
  BOOL isSelected = (row == self.sidebarTable.selectedRow);
  textField.font = [self preferredSidebarIconFontWithSize:(isSelected ? 12.0 : 11.5)];
  textField.textColor = isSelected ? style.accentColor : style.textColor;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  NSInteger row = self.sidebarTable.selectedRow;
  NSString *identifier = [self tabIdentifierForSidebarRow:row];
  if (identifier.length > 0) {
    NSInteger tabIndex = [self.tabItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
      return [[item[@"id"] lowercaseString] isEqualToString:[identifier lowercaseString]];
    }];
    if (tabIndex != NSNotFound) {
      [self selectTabAtIndex:tabIndex];
    }
  }
  [self.sidebarTable reloadData];
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
  (void)tabView;
  NSString *identifier = [[tabViewItem identifier] description];
  [self ensureControllerLoadedForIdentifier:identifier];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;
  // Quit app when window is closed
  [NSApp terminate:nil];
  return YES;
}

- (void)windowDidMove:(NSNotification *)notification {
  (void)notification;
  [self saveWindowFrame];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
  (void)notification;
  [self saveWindowFrame];
}

- (void)windowDidResize:(NSNotification *)notification {
  (void)notification;
  [self saveWindowFrame];
}

- (NSScreen *)activeScreenForPoint:(NSPoint)point {
  for (NSScreen *screen in [NSScreen screens]) {
    if (NSPointInRect(point, screen.frame)) {
      return screen;
    }
  }
  return [NSScreen mainScreen];
}

- (void)centerWindowOnActiveScreen {
  NSScreen *screen = [self activeScreenForPoint:[NSEvent mouseLocation]];
  if (!screen) { return; }

  NSRect screenFrame = screen.visibleFrame;
  NSRect windowFrame = self.window.frame;
  NSPoint origin = NSMakePoint(NSMidX(screenFrame) - windowFrame.size.width / 2.0,
                               NSMidY(screenFrame) - windowFrame.size.height / 2.0);
  [self.window setFrameOrigin:origin];
}

- (void)showWindow:(id)sender {
  [super showWindow:sender];
  [self configureWindowIfNeeded];
  [NSApp activateIgnoringOtherApps:YES];
  [NSApp unhide:nil];

  NSString *savedFrame = [[NSUserDefaults standardUserDefaults] stringForKey:@"BaristaControlPanelWindowFrame"];
  if (savedFrame.length) {
    NSRect frame = NSRectFromString(savedFrame);
    if (frame.size.width > 0 && frame.size.height > 0) {
      [self.window setFrame:frame display:YES];
    }
  } else {
    [self centerWindowOnActiveScreen];
  }

  [self.window displayIfNeeded];
  if (self.window.isMiniaturized) {
    [self.window deminiaturize:nil];
  }
  [self.window setIsVisible:YES];
  [self.window makeKeyAndOrderFront:nil];
  [self ensureWindowIsOnScreen];
}

- (void)configureWindowIfNeeded {
  if (self.windowConfigured || !self.window) { return; }

  self.window.title = @"Barista Control Panel";
  self.window.delegate = self;
  [[BaristaStyle sharedStyle] applyWindowStyle:self.window];
  NSSize currentSize = self.window.frame.size;
  CGFloat minWidth = MIN(520.0, currentSize.width);
  CGFloat minHeight = MIN(400.0, currentSize.height);
  [self.window setMinSize:NSMakeSize(minWidth, minHeight)];
  self.window.alphaValue = 1.0;
  self.window.opaque = YES;
  self.window.hasShadow = YES;

  BaristaPanelWindow *panelWindow = (BaristaPanelWindow *)self.window;
  if ([[BaristaPanelState sharedState] prefersUtilityWindowMode]) {
    [self.window setLevel:NSFloatingWindowLevel];
    panelWindow.floatingPanel = YES;
    self.window.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
  } else {
    [self.window setLevel:NSNormalWindowLevel];
    panelWindow.floatingPanel = NO;
    self.window.animationBehavior = NSWindowAnimationBehaviorDocumentWindow;
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
  }
  self.windowConfigured = YES;
  [self saveWindowFrame];
  NSLog(@"[barista] window configured");
}

- (NSString *)shortPath:(NSString *)path {
  if (!path.length) {
    return @"";
  }
  NSString *home = NSHomeDirectory();
  if ([path hasPrefix:home]) {
    return [@"~" stringByAppendingString:[path substringFromIndex:home.length]];
  }
  return path;
}

- (void)ensureWindowIsOnScreen {
  NSWindow *window = self.window;
  if (!window) { return; }

  NSScreen *screen = [NSScreen mainScreen];
  if (!screen) {
    screen = [NSScreen screens].firstObject;
  }
  if (!screen) { return; }

  NSRect visible = screen.visibleFrame;
  NSRect frame = window.frame;

  CGFloat margin = 40.0;
  CGFloat maxWidth = visible.size.width - margin;
  CGFloat maxHeight = visible.size.height - margin;
  if (![[BaristaPanelState sharedState] prefersUtilityWindowMode]) {
    maxWidth = MIN(maxWidth, 860.0);
    maxHeight = MIN(maxHeight, 680.0);
  }
  CGFloat width = MIN(frame.size.width, maxWidth);
  CGFloat height = MIN(frame.size.height, maxHeight);
  CGFloat minX = visible.origin.x + (margin / 2.0);
  CGFloat minY = visible.origin.y + (margin / 2.0);
  CGFloat maxX = visible.origin.x + visible.size.width - width - (margin / 2.0);
  CGFloat maxY = visible.origin.y + visible.size.height - height - (margin / 2.0);
  CGFloat originX = MIN(MAX(frame.origin.x, minX), maxX);
  CGFloat originY = MIN(MAX(frame.origin.y, minY), maxY);
  NSRect corrected = NSMakeRect(originX, originY, width, height);
  if (!NSEqualRects(frame, corrected)) {
    NSLog(@"[barista] window corrected frame=%@ visible=%@", NSStringFromRect(frame), NSStringFromRect(visible));
    [window setFrame:corrected display:YES];
  }
}

@end
