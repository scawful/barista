#import "WorkflowTabViewController.h"
#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@implementation WorkflowTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self loadWorkflowData];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;
  CGFloat contentWidth = self.view.bounds.size.width - 80;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Workflow Shortcuts";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // Documentation Section
  NSTextField *docsHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, contentWidth, 18)];
  [docsHeader setBezeled:NO];
  [docsHeader setEditable:NO];
  [docsHeader setDrawsBackground:NO];
  [docsHeader setStringValue:@"Reference Files"];
  [docsHeader setFont:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]];
  [self.view addSubview:docsHeader];
  y -= 35;

  NSArray *docs = [self workflowArrayForKey:@"docs" fallback:nil];
  for (NSDictionary *doc in docs) {
    NSString *title = doc[@"title"] ?: @"Document";
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, contentWidth, 32)];
    [button setTitle:title];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    button.action = @selector(openDoc:);
    button.toolTip = doc[@"path"];
    [self.view addSubview:button];
    y -= 40;
  }

  y -= 20;
  
  // Quick Actions Section
  NSTextField *actionsHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, contentWidth, 18)];
  [actionsHeader setBezeled:NO];
  [actionsHeader setEditable:NO];
  [actionsHeader setDrawsBackground:NO];
  [actionsHeader setStringValue:@"Quick Actions"];
  [actionsHeader setFont:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]];
  [self.view addSubview:actionsHeader];
  y -= 35;

  NSArray *rawActions = [self workflowArrayForKey:@"actions" fallback:nil];
  NSMutableArray<NSDictionary *> *quickActions = [NSMutableArray array];
  for (NSDictionary *entry in rawActions) {
    NSString *selectorName = entry[@"selector"];
    if (selectorName.length == 0) continue;
    // We only support a few known selectors for now to be safe, or we map them to methods
    NSString *title = entry[@"title"] ?: selectorName;
    [quickActions addObject:@{ @"title": title, @"selector": selectorName }];
  }

  CGFloat quickButtonWidth = (contentWidth - 10) / 2.0;
  for (NSInteger idx = 0; idx < quickActions.count; idx++) {
    NSInteger row = idx / 2;
    NSInteger col = idx % 2;
    CGFloat quickY = y - (row * 40);
    NSDictionary *action = quickActions[idx];
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + col * (quickButtonWidth + 10), quickY, quickButtonWidth, 32)];
    [button setTitle:action[@"title"]];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    
    NSString *selName = action[@"selector"];
    if ([selName isEqualToString:@"reloadBar:"]) {
        button.action = @selector(reloadBar:);
    } else if ([selName isEqualToString:@"openLogs:"]) {
        button.action = @selector(openLogs:);
    } else if ([selName isEqualToString:@"runAccessibilityFix:"]) {
        button.action = @selector(runAccessibilityFix:);
    }
    
    [self.view addSubview:button];
  }
}

- (void)loadWorkflowData {
  NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar/data/workflow_shortcuts.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data) {
      self.workflowData = @{};
      return;
  }
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    self.workflowData = @{};
    return;
  }
  self.workflowData = json;
}

- (NSArray *)workflowArrayForKey:(NSString *)key fallback:(NSArray *)fallback {
  id value = self.workflowData[key];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return fallback ?: @[];
}

- (NSString *)expandedWorkflowPath:(NSString *)relativePath {
  if (![relativePath isKindOfClass:[NSString class]]) return nil;
  if ([relativePath hasPrefix:@"~/"]) {
    return [relativePath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:NSHomeDirectory()];
  }
  if ([relativePath hasPrefix:@"/"]) {
    return relativePath;
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:relativePath];
}

- (void)openDoc:(NSButton *)sender {
  NSString *path = sender.toolTip;
  if (!path) return;
  NSString *fullPath = [self expandedWorkflowPath:path];
  if (!fullPath) return;
  NSURL *url = [NSURL fileURLWithPath:fullPath];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)reloadBar:(id)sender {
    ConfigurationManager *config = [ConfigurationManager sharedManager];
    [config reloadSketchyBar];
}

- (void)openLogs:(id)sender {
  NSURL *url = [NSURL fileURLWithPath:@"/opt/homebrew/var/log/sketchybar"];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)runAccessibilityFix:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config runScript:@"yabai_accessibility_fix.sh" arguments:@[]];
}

@end

