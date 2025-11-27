#import "ConfigurationManager.h"
#import "MainWindowController.h"
#import "AppearanceTabViewController.h"
#import "WidgetsTabViewController.h"
#import "SpacesTabViewController.h"
#import "IconsTabViewController.h"
#import "IntegrationsTabViewController.h"
#import "ThemesTabViewController.h"
#import "ShortcutsTabViewController.h"
#import "WorkflowTabViewController.h"
#import "LaunchAgentsTabViewController.h"
#import "DebugTabViewController.h"
#import "PerformanceTabViewController.h"
#import "AdvancedTabViewController.h"
#import <Cocoa/Cocoa.h>

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
    window.title = @"Barista Configuration";
    window.delegate = self;
    [window setMinSize:NSMakeSize(850, 650)];
    [window center];

    // Make window stay on top but not intrusive
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];

    [self setupTabView];
  }
  return self;
}

- (void)setupTabView {
  self.tabView = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
  self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.tabView.delegate = self;
  [self.tabView setTabViewType:NSTopTabsBezelBorder];

  // Appearance Tab
  self.appearanceTab = [[AppearanceTabViewController alloc] init];
  NSTabViewItem *appearanceItem = [[NSTabViewItem alloc] initWithIdentifier:@"appearance"];
  appearanceItem.label = @"Appearance";
  appearanceItem.viewController = self.appearanceTab;
  [self.tabView addTabViewItem:appearanceItem];

  // Widgets Tab
  self.widgetsTab = [[WidgetsTabViewController alloc] init];
  NSTabViewItem *widgetsItem = [[NSTabViewItem alloc] initWithIdentifier:@"widgets"];
  widgetsItem.label = @"Widgets";
  widgetsItem.viewController = self.widgetsTab;
  [self.tabView addTabViewItem:widgetsItem];

  // Spaces Tab
  self.spacesTab = [[SpacesTabViewController alloc] init];
  NSTabViewItem *spacesItem = [[NSTabViewItem alloc] initWithIdentifier:@"spaces"];
  spacesItem.label = @"Spaces";
  spacesItem.viewController = self.spacesTab;
  [self.tabView addTabViewItem:spacesItem];

  // Icons Tab
  self.iconsTab = [[IconsTabViewController alloc] init];
  NSTabViewItem *iconsItem = [[NSTabViewItem alloc] initWithIdentifier:@"icons"];
  iconsItem.label = @"Icons";
  iconsItem.viewController = self.iconsTab;
  [self.tabView addTabViewItem:iconsItem];

  // Themes Tab
  self.themesTab = [[ThemesTabViewController alloc] init];
  NSTabViewItem *themesItem = [[NSTabViewItem alloc] initWithIdentifier:@"themes"];
  themesItem.label = @"Themes";
  themesItem.viewController = self.themesTab;
  [self.tabView addTabViewItem:themesItem];

  // Shortcuts Tab
  self.shortcutsTab = [[ShortcutsTabViewController alloc] init];
  NSTabViewItem *shortcutsItem = [[NSTabViewItem alloc] initWithIdentifier:@"shortcuts"];
  shortcutsItem.label = @"Shortcuts";
  shortcutsItem.viewController = self.shortcutsTab;
  [self.tabView addTabViewItem:shortcutsItem];

  // Workflow Tab
  self.workflowTab = [[WorkflowTabViewController alloc] init];
  NSTabViewItem *workflowItem = [[NSTabViewItem alloc] initWithIdentifier:@"workflow"];
  workflowItem.label = @"Workflow";
  workflowItem.viewController = self.workflowTab;
  [self.tabView addTabViewItem:workflowItem];

  // Integrations Tab
  self.integrationsTab = [[IntegrationsTabViewController alloc] init];
  NSTabViewItem *integrationsItem = [[NSTabViewItem alloc] initWithIdentifier:@"integrations"];
  integrationsItem.label = @"Integrations";
  integrationsItem.viewController = self.integrationsTab;
  [self.tabView addTabViewItem:integrationsItem];

  // Launch Agents Tab
  self.launchAgentsTab = [[LaunchAgentsTabViewController alloc] init];
  NSTabViewItem *launchAgentsItem = [[NSTabViewItem alloc] initWithIdentifier:@"launchAgents"];
  launchAgentsItem.label = @"Launch Agents";
  launchAgentsItem.viewController = self.launchAgentsTab;
  [self.tabView addTabViewItem:launchAgentsItem];

  // Debug Tab
  self.debugTab = [[DebugTabViewController alloc] init];
  NSTabViewItem *debugItem = [[NSTabViewItem alloc] initWithIdentifier:@"debug"];
  debugItem.label = @"Debug";
  debugItem.viewController = self.debugTab;
  [self.tabView addTabViewItem:debugItem];

  // Performance Tab
  self.performanceTab = [[PerformanceTabViewController alloc] init];
  NSTabViewItem *performanceItem = [[NSTabViewItem alloc] initWithIdentifier:@"performance"];
  performanceItem.label = @"Performance";
  performanceItem.viewController = self.performanceTab;
  [self.tabView addTabViewItem:performanceItem];

  // Advanced Tab
  self.advancedTab = [[AdvancedTabViewController alloc] init];
  NSTabViewItem *advancedItem = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
  advancedItem.label = @"Advanced";
  advancedItem.viewController = self.advancedTab;
  [self.tabView addTabViewItem:advancedItem];

  [self.window.contentView addSubview:self.tabView];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  // Quit app when window is closed
  [NSApp terminate:nil];
  return YES;
}

- (void)showWindow:(id)sender {
  [super showWindow:sender];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

@end
