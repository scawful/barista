#import "ConfigurationManager.h"
#import "MainWindowController.h"
#import "AppearanceTabViewController.h"
#import "WidgetsTabViewController.h"
#import "SpacesTabViewController.h"
#import "IconsTabViewController.h"
#import "IntegrationsTabViewController.h"
#import "ThemesTabViewController.h"
#import "ShortcutsTabViewController.h"
#import "LaunchAgentsTabViewController.h"
#import "DebugTabViewController.h"
#import "PerformanceTabViewController.h"
#import "AdvancedTabViewController.h"
#import <Cocoa/Cocoa.h>

@interface MainWindowController ()
@property (assign) BOOL windowConfigured;
@end

@implementation MainWindowController

- (instancetype)init {
  NSRect frame = NSMakeRect(0, 0, 950, 750);
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
  [self.tabView setTabViewType:NSTopTabsBezelBorder];

  // Appearance Tab
  NSLog(@"[barista] setupTabView appearance");
  self.appearanceTab = [[AppearanceTabViewController alloc] init];
  NSTabViewItem *appearanceItem = [[NSTabViewItem alloc] initWithIdentifier:@"appearance"];
  appearanceItem.label = @"Appearance";
  appearanceItem.viewController = self.appearanceTab;
  [self.tabView addTabViewItem:appearanceItem];

  // Widgets Tab
  NSLog(@"[barista] setupTabView widgets");
  self.widgetsTab = [[WidgetsTabViewController alloc] init];
  NSTabViewItem *widgetsItem = [[NSTabViewItem alloc] initWithIdentifier:@"widgets"];
  widgetsItem.label = @"Widgets";
  widgetsItem.viewController = self.widgetsTab;
  [self.tabView addTabViewItem:widgetsItem];

  // Spaces Tab
  NSLog(@"[barista] setupTabView spaces");
  self.spacesTab = [[SpacesTabViewController alloc] init];
  NSTabViewItem *spacesItem = [[NSTabViewItem alloc] initWithIdentifier:@"spaces"];
  spacesItem.label = @"Spaces";
  spacesItem.viewController = self.spacesTab;
  [self.tabView addTabViewItem:spacesItem];

  // Icons Tab
  NSLog(@"[barista] setupTabView icons");
  self.iconsTab = [[IconsTabViewController alloc] init];
  NSTabViewItem *iconsItem = [[NSTabViewItem alloc] initWithIdentifier:@"icons"];
  iconsItem.label = @"Icons";
  iconsItem.viewController = self.iconsTab;
  [self.tabView addTabViewItem:iconsItem];

  // Themes Tab
  NSLog(@"[barista] setupTabView themes");
  self.themesTab = [[ThemesTabViewController alloc] init];
  NSTabViewItem *themesItem = [[NSTabViewItem alloc] initWithIdentifier:@"themes"];
  themesItem.label = @"Themes";
  themesItem.viewController = self.themesTab;
  [self.tabView addTabViewItem:themesItem];

  // Shortcuts Tab
  NSLog(@"[barista] setupTabView shortcuts");
  self.shortcutsTab = [[ShortcutsTabViewController alloc] init];
  NSTabViewItem *shortcutsItem = [[NSTabViewItem alloc] initWithIdentifier:@"shortcuts"];
  shortcutsItem.label = @"Shortcuts";
  shortcutsItem.viewController = self.shortcutsTab;
  [self.tabView addTabViewItem:shortcutsItem];

  // Integrations Tab
  NSLog(@"[barista] setupTabView integrations");
  self.integrationsTab = [[IntegrationsTabViewController alloc] init];
  NSTabViewItem *integrationsItem = [[NSTabViewItem alloc] initWithIdentifier:@"integrations"];
  integrationsItem.label = @"Integrations";
  integrationsItem.viewController = self.integrationsTab;
  [self.tabView addTabViewItem:integrationsItem];

  // Launch Agents Tab
  NSLog(@"[barista] setupTabView launchagents");
  self.launchAgentsTab = [[LaunchAgentsTabViewController alloc] init];
  NSTabViewItem *launchAgentsItem = [[NSTabViewItem alloc] initWithIdentifier:@"launchAgents"];
  launchAgentsItem.label = @"Launch Agents";
  launchAgentsItem.viewController = self.launchAgentsTab;
  [self.tabView addTabViewItem:launchAgentsItem];

  // Debug Tab
  NSLog(@"[barista] setupTabView debug");
  self.debugTab = [[DebugTabViewController alloc] init];
  NSTabViewItem *debugItem = [[NSTabViewItem alloc] initWithIdentifier:@"debug"];
  debugItem.label = @"Debug";
  debugItem.viewController = self.debugTab;
  [self.tabView addTabViewItem:debugItem];

  // Performance Tab
  NSLog(@"[barista] setupTabView performance");
  self.performanceTab = [[PerformanceTabViewController alloc] init];
  NSTabViewItem *performanceItem = [[NSTabViewItem alloc] initWithIdentifier:@"performance"];
  performanceItem.label = @"Performance";
  performanceItem.viewController = self.performanceTab;
  [self.tabView addTabViewItem:performanceItem];

  // Advanced Tab
  NSLog(@"[barista] setupTabView advanced");
  self.advancedTab = [[AdvancedTabViewController alloc] init];
  NSTabViewItem *advancedItem = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
  advancedItem.label = @"Advanced";
  advancedItem.viewController = self.advancedTab;
  [self.tabView addTabViewItem:advancedItem];

  [self.window.contentView addSubview:self.tabView];
  NSLog(@"[barista] setupTabView done");
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
  [self.window setMinSize:NSMakeSize(850, 650)];
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

  if (!NSIntersectsRect(frame, visible)) {
    NSLog(@"[barista] window offscreen frame=%@ visible=%@", NSStringFromRect(frame), NSStringFromRect(visible));
    CGFloat width = MIN(frame.size.width, visible.size.width - 40.0);
    CGFloat height = MIN(frame.size.height, visible.size.height - 40.0);
    CGFloat originX = NSMidX(visible) - width / 2.0;
    CGFloat originY = NSMidY(visible) - height / 2.0;
    NSRect corrected = NSMakeRect(originX, originY, width, height);
    [window setFrame:corrected display:YES];
    NSLog(@"[barista] window corrected frame=%@", NSStringFromRect(corrected));
  }
}

@end
