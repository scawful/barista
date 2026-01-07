#import "ConfigurationManager.h"
#import "MainWindowController.h"
#import "AppearanceTabViewController.h"
#import "WidgetsTabViewController.h"
#import "SpacesTabViewController.h"
#import "IconsTabViewController.h"
#import "MenuTabViewController.h"
#import "IntegrationsTabViewController.h"
#import "ThemesTabViewController.h"
#import "ShortcutsTabViewController.h"
#import "LaunchAgentsTabViewController.h"
#import "DebugTabViewController.h"
#import "PerformanceTabViewController.h"
#import "AdvancedTabViewController.h"
#import "BaristaStyle.h"
#import <Cocoa/Cocoa.h>

@interface MainWindowController ()
@property (assign) BOOL windowConfigured;
@end

@implementation MainWindowController

- (instancetype)init {
  NSRect frame = NSMakeRect(0, 0, 950, 750);
  NSScreen *screen = [NSScreen mainScreen];
  if (screen) {
    NSRect visible = screen.visibleFrame;
    CGFloat margin = 80.0;
    CGFloat maxWidth = MAX(700.0, visible.size.width - margin);
    CGFloat maxHeight = MAX(560.0, visible.size.height - margin);
    CGFloat width = MIN(980.0, maxWidth);
    CGFloat height = MIN(780.0, maxHeight);
    frame = NSMakeRect(0, 0, width, height);
  }
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

  self = [super initWithWindow:window];
  if (self) {
    NSLog(@"[barista] created window=%@", window);
    NSLog(@"[barista] before setupTabView");
    [self setupTabView];
    NSLog(@"[barista] init complete");
  }
  return self;
}

- (void)setupTabView {
  NSLog(@"[barista] setupTabView start");
  self.tabView = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
  self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.tabView.delegate = self;
  [self.tabView setTabViewType:NSNoTabsNoBorder];
  self.tabView.drawsBackground = NO;

  BaristaStyle *style = [BaristaStyle sharedStyle];
  self.tabView.wantsLayer = YES;
  self.tabView.layer.backgroundColor = style.panelColor.CGColor;
  self.tabView.layer.borderColor = style.dividerColor.CGColor;
  self.tabView.layer.borderWidth = 1.0;

  NSMutableArray<NSDictionary *> *tabItems = [NSMutableArray array];

  // Appearance Tab
  NSLog(@"[barista] setupTabView appearance");
  self.appearanceTab = [[AppearanceTabViewController alloc] init];
  [self addTabWithIdentifier:@"appearance"
                       label:@"Appearance"
                   controller:self.appearanceTab
                        store:tabItems];

  // Widgets Tab
  NSLog(@"[barista] setupTabView widgets");
  self.widgetsTab = [[WidgetsTabViewController alloc] init];
  [self addTabWithIdentifier:@"widgets"
                       label:@"Widgets"
                   controller:self.widgetsTab
                        store:tabItems];

  // Spaces Tab
  NSLog(@"[barista] setupTabView spaces");
  self.spacesTab = [[SpacesTabViewController alloc] init];
  [self addTabWithIdentifier:@"spaces"
                       label:@"Spaces"
                   controller:self.spacesTab
                        store:tabItems];

  // Icons Tab
  NSLog(@"[barista] setupTabView icons");
  self.iconsTab = [[IconsTabViewController alloc] init];
  [self addTabWithIdentifier:@"icons"
                       label:@"Icons"
                   controller:self.iconsTab
                        store:tabItems];

  // Menu Tab
  NSLog(@"[barista] setupTabView menu");
  self.menuTab = [[MenuTabViewController alloc] init];
  [self addTabWithIdentifier:@"menu"
                       label:@"Menu"
                   controller:self.menuTab
                        store:tabItems];

  // Themes Tab
  NSLog(@"[barista] setupTabView themes");
  self.themesTab = [[ThemesTabViewController alloc] init];
  [self addTabWithIdentifier:@"themes"
                       label:@"Themes"
                   controller:self.themesTab
                        store:tabItems];

  // Shortcuts Tab
  NSLog(@"[barista] setupTabView shortcuts");
  self.shortcutsTab = [[ShortcutsTabViewController alloc] init];
  [self addTabWithIdentifier:@"shortcuts"
                       label:@"Shortcuts"
                   controller:self.shortcutsTab
                        store:tabItems];

  // Integrations Tab
  NSLog(@"[barista] setupTabView integrations");
  self.integrationsTab = [[IntegrationsTabViewController alloc] init];
  [self addTabWithIdentifier:@"integrations"
                       label:@"Integrations"
                   controller:self.integrationsTab
                        store:tabItems];

  // Launch Agents Tab
  NSLog(@"[barista] setupTabView launchagents");
  self.launchAgentsTab = [[LaunchAgentsTabViewController alloc] init];
  [self addTabWithIdentifier:@"launchAgents"
                       label:@"Launch Agents"
                   controller:self.launchAgentsTab
                        store:tabItems];

  // Debug Tab
  NSLog(@"[barista] setupTabView debug");
  self.debugTab = [[DebugTabViewController alloc] init];
  [self addTabWithIdentifier:@"debug"
                       label:@"Debug"
                   controller:self.debugTab
                        store:tabItems];

  // Performance Tab
  NSLog(@"[barista] setupTabView performance");
  self.performanceTab = [[PerformanceTabViewController alloc] init];
  [self addTabWithIdentifier:@"performance"
                       label:@"Performance"
                   controller:self.performanceTab
                        store:tabItems];

  // Advanced Tab
  NSLog(@"[barista] setupTabView advanced");
  self.advancedTab = [[AdvancedTabViewController alloc] init];
  [self addTabWithIdentifier:@"advanced"
                       label:@"Advanced"
                   controller:self.advancedTab
                        store:tabItems];

  self.tabItems = [tabItems copy];
  [self setupSidebarWithStyle:style];
  NSRect bounds = self.window.contentView.bounds;
  self.tabView.frame = NSMakeRect(style.sidebarWidth, 0, bounds.size.width - style.sidebarWidth, bounds.size.height);

  self.splitView = [[NSSplitView alloc] initWithFrame:self.window.contentView.bounds];
  self.splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.splitView.vertical = YES;
  self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
  [self.splitView addSubview:self.sidebarView];
  [self.splitView addSubview:self.tabView];
  [self.window setContentView:self.splitView];

  [self.sidebarTable reloadData];
  if (self.tabItems.count > 0) {
    [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  }
  NSLog(@"[barista] setupTabView done");
}

- (void)addTabWithIdentifier:(NSString *)identifier
                       label:(NSString *)label
                   controller:(NSViewController *)controller
                        store:(NSMutableArray<NSDictionary *> *)store {
  if (!identifier || !label || !controller) {
    return;
  }
  NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:identifier];
  item.label = label;
  item.viewController = controller;
  [self.tabView addTabViewItem:item];
  [store addObject:@{@"id": identifier, @"label": label}];
}

- (void)setupSidebarWithStyle:(BaristaStyle *)style {
  CGFloat sidebarWidth = style.sidebarWidth;
  NSRect bounds = self.window.contentView.bounds;
  self.sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, sidebarWidth, bounds.size.height)];
  self.sidebarView.autoresizingMask = NSViewHeightSizable;
  self.sidebarView.wantsLayer = YES;
  self.sidebarView.layer.backgroundColor = style.sidebarColor.CGColor;

  CGFloat headerHeight = 64.0;
  NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, bounds.size.height - headerHeight, sidebarWidth, headerHeight)];
  header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  header.wantsLayer = YES;
  header.layer.backgroundColor = style.backgroundColor.CGColor;
  [self.sidebarView addSubview:header];

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(14, headerHeight - 28, sidebarWidth - 24, 18)];
  title.stringValue = @"BARISTA CONFIG";
  title.font = style.sectionFont;
  title.textColor = style.textColor;
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [header addSubview:title];

  NSTextField *subtitle = [[NSTextField alloc] initWithFrame:NSMakeRect(14, headerHeight - 46, sidebarWidth - 24, 16)];
  subtitle.stringValue = @"system control + layout";
  subtitle.font = style.bodyFont;
  subtitle.textColor = style.mutedTextColor;
  subtitle.bordered = NO;
  subtitle.editable = NO;
  subtitle.backgroundColor = [NSColor clearColor];
  [header addSubview:subtitle];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, sidebarWidth, bounds.size.height - headerHeight)];
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSNoBorder;
  scrollView.drawsBackground = NO;

  self.sidebarTable = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.sidebarTable.dataSource = self;
  self.sidebarTable.delegate = self;
  self.sidebarTable.headerView = nil;
  self.sidebarTable.rowHeight = 28.0;
  self.sidebarTable.backgroundColor = style.sidebarColor;
  self.sidebarTable.focusRingType = NSFocusRingTypeNone;
  self.sidebarTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;

  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"label"];
  column.width = sidebarWidth - 20.0;
  [self.sidebarTable addTableColumn:column];
  scrollView.documentView = self.sidebarTable;
  [self.sidebarView addSubview:scrollView];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.tabItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *item = (row >= 0 && row < (NSInteger)self.tabItems.count) ? self.tabItems[row] : nil;
  if (!item) {
    return nil;
  }

  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"BaristaTabCell" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 24)];
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 2, tableColumn.width - 12, 20)];
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
  textField.stringValue = item[@"label"] ?: @"";
  textField.font = style.bodyFont;
  textField.textColor = style.textColor;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSInteger row = self.sidebarTable.selectedRow;
  if (row >= 0 && row < (NSInteger)self.tabItems.count) {
    [self.tabView selectTabViewItemAtIndex:row];
  }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  // Quit app when window is closed
  [NSApp terminate:nil];
  return YES;
}

- (NSScreen *)activeScreenForPoint:(NSPoint)point {
  for (NSScreen *screen in [NSScreen screens]) {
    if (NSPointInRect(point, screen.frame)) {
      return screen;
    }
  }
  return [NSScreen mainScreen];
}

- (NSSize)preferredWindowSizeForScreen:(NSScreen *)screen {
  if (!screen) {
    return NSMakeSize(950, 750);
  }
  NSRect visible = screen.visibleFrame;
  CGFloat margin = 80.0;
  CGFloat maxWidth = MAX(700.0, visible.size.width - margin);
  CGFloat maxHeight = MAX(560.0, visible.size.height - margin);
  CGFloat width = MIN(980.0, maxWidth);
  CGFloat height = MIN(780.0, maxHeight);
  return NSMakeSize(width, height);
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
  [self centerWindowOnActiveScreen];
  [self.window displayIfNeeded];
  if (self.window.isMiniaturized) {
    [self.window deminiaturize:nil];
  }
  [self.window setIsVisible:YES];
  [self.window makeKeyAndOrderFront:nil];
  [self.window orderFrontRegardless];
  [self ensureWindowIsOnScreen];
  [NSApp arrangeInFront:nil];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [self ensureWindowIsOnScreen];
                   [self.window makeKeyAndOrderFront:nil];
                   [self.window orderFrontRegardless];
                 });
}

- (void)configureWindowIfNeeded {
  if (self.windowConfigured || !self.window) { return; }

  self.window.title = @"Barista Configuration";
  self.window.delegate = self;
  [[BaristaStyle sharedStyle] applyWindowStyle:self.window];
  NSScreen *screen = [self activeScreenForPoint:[NSEvent mouseLocation]];
  NSSize preferred = [self preferredWindowSizeForScreen:screen];
  [self.window setContentSize:preferred];
  CGFloat minWidth = MIN(850.0, preferred.width);
  CGFloat minHeight = MIN(650.0, preferred.height);
  [self.window setMinSize:NSMakeSize(minWidth, minHeight)];
  [self.window center];
  self.window.alphaValue = 1.0;
  self.window.opaque = YES;
  self.window.hasShadow = YES;

  // Use a normal window level to avoid Stage Manager hiding it.
  [self.window setLevel:NSNormalWindowLevel];
  [self.window setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorFullScreenAuxiliary |
                                      NSWindowCollectionBehaviorMoveToActiveSpace)];
  self.windowConfigured = YES;
  NSLog(@"[barista] window configured");
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
  CGFloat width = MIN(frame.size.width, visible.size.width - margin);
  CGFloat height = MIN(frame.size.height, visible.size.height - margin);
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
