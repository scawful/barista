#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface HelpCenterController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSDictionary *workflowData;
@property (copy) NSString *configPath;
@property (copy) NSString *scriptsPath;
@property (copy) NSString *codePath;
@end

@implementation HelpCenterController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  self.configPath = config.configPath;
  self.scriptsPath = config.scriptsPath;
  self.codePath = config.codePath;
  self.workflowData = [self loadWorkflowData];
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
  [self.window setTitle:@"Sketchybar Help Center"];
  CGFloat minWidth = MIN(600.0, frame.size.width);
  CGFloat minHeight = MIN(420.0, frame.size.height);
  [self.window setMinSize:NSMakeSize(minWidth, minHeight)];
  [self.window center];
  NSView *content = [self.window contentView];

  NSTabView *tabs = [[NSTabView alloc] initWithFrame:content.bounds];
  [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

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

  [content addSubview:tabs];
}

- (NSView *)buildKeymapTab {
  NSRect bounds = self.window.contentView.bounds;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
  [scroll setBorderType:NSNoBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSSize contentSize = scroll.contentSize;
  NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
  textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  textView.horizontallyResizable = YES;
  textView.verticallyResizable = YES;
  textView.textContainer.widthTracksTextView = YES;
  textView.textContainer.containerSize = NSMakeSize(contentSize.width, CGFLOAT_MAX);
  [textView setEditable:NO];
  [textView setDrawsBackground:NO];
  [textView setFont:[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular]];
  NSMutableString *buffer = [NSMutableString string];
  NSArray *sections = [self workflowArrayForKey:@"keymap" fallback:nil];
  for (NSDictionary *section in sections) {
    NSString *title = section[@"section"] ?: @"Untitled";
    [buffer appendFormat:@"%@\n", title];
    NSArray *items = section[@"items"];
    if (![items isKindOfClass:[NSArray class]]) continue;
    for (NSDictionary *item in items) {
      NSString *keys = item[@"keys"] ?: @"";
      NSString *desc = item[@"description"] ?: @"";
      [buffer appendFormat:@"  %-15s %@\n", [keys UTF8String], desc];
    }
    [buffer appendString:@"\n"];
  }
  if (buffer.length == 0) {
    [buffer appendString:@"No shortcuts defined in workflow data."];
  }
  [textView setString:buffer];
  [scroll setDocumentView:textView];
  return scroll;
}

- (NSView *)buildWorkflowTab {
  NSRect bounds = self.window.contentView.bounds;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
  [scroll setBorderType:NSNoBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  CGFloat width = scroll.contentSize.width;
  NSArray *docs = [self workflowArrayForKey:@"docs" fallback:nil];
  NSArray *actions = [self workflowArrayForKey:@"actions" fallback:nil];
  NSInteger rows = MAX(1, docs.count);
  NSInteger actionRows = MAX(1, (actions.count + 1) / 2);
  CGFloat height = MAX(420.0, 60.0 + rows * 34.0 + actionRows * 42.0 + 80.0);
  NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  container.autoresizingMask = NSViewWidthSizable;
  CGFloat y = height - 40;

  NSTextField *docsHeader = [self headerLabelWithString:@"Reference Docs" frame:NSMakeRect(20, y, width - 40, 20)];
  [container addSubview:docsHeader];
  y -= 30;

  for (NSDictionary *doc in docs) {
    NSString *title = doc[@"title"] ?: @"Document";
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, width - 40, 28)];
    [button setTitle:title];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    button.action = @selector(openDoc:);
    button.toolTip = doc[@"path"];
    [container addSubview:button];
    y -= 34;
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
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    if (!selector || ![self respondsToSelector:selector]) {
      idx++;
      continue;
    }
    NSInteger col = idx % 2;
    NSInteger row = idx / 2;
    CGFloat buttonY = y - (row * 40);
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(20 + col * (actionWidth + 20), buttonY, actionWidth, 30)];
    [button setTitle:title];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    button.action = selector;
    [container addSubview:button];
    idx++;
  }

  [scroll setDocumentView:container];
  return scroll;
}

- (NSView *)buildRepoTab {
  NSRect bounds = self.window.contentView.bounds;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
  [scroll setBorderType:NSNoBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  CGFloat width = scroll.contentSize.width;
  NSArray *repos = [self workflowArrayForKey:@"repos" fallback:nil];
  NSInteger rows = MAX(1, repos.count);
  CGFloat height = MAX(360.0, 40.0 + rows * 70.0);
  NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  container.autoresizingMask = NSViewWidthSizable;
  CGFloat y = height - 50;

  for (NSDictionary *repo in repos) {
    NSString *name = repo[@"name"] ?: @"Repository";
    NSDictionary *status = [self statusForRepo:repo];
    NSString *branch = status[@"branch"] ?: @"—";
    BOOL dirty = [status[@"dirty"] boolValue];
    NSString *path = [self expandedWorkflowPath:repo[@"path"]];

    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(20, y - 40, width - 40, 60)];
    [box setTitle:name];
    box.autoresizingMask = NSViewWidthSizable;
    [container addSubview:box];
    NSView *content = [box contentView];

    NSTextField *branchLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, content.bounds.size.height - 30, content.bounds.size.width - 140, 20)];
    [branchLabel setBezeled:NO];
    [branchLabel setEditable:NO];
    [branchLabel setDrawsBackground:NO];
    [branchLabel setStringValue:[NSString stringWithFormat:@"Branch: %@%@", branch, dirty ? @" *" : @""]];
    [branchLabel setTextColor:dirty ? [NSColor systemOrangeColor] : [NSColor labelColor]];
    branchLabel.autoresizingMask = NSViewWidthSizable;
    [content addSubview:branchLabel];

    NSButton *openButton = [[NSButton alloc] initWithFrame:NSMakeRect(content.bounds.size.width - 110, content.bounds.size.height - 32, 100, 24)];
    [openButton setTitle:@"Open Repo"];
    [openButton setButtonType:NSButtonTypeMomentaryPushIn];
    [openButton setBezelStyle:NSBezelStyleRounded];
    openButton.target = self;
    openButton.action = @selector(openPathFromButton:);
    openButton.toolTip = path;
    openButton.autoresizingMask = NSViewMinXMargin;
    [content addSubview:openButton];

    y -= 80;
  }

  [scroll setDocumentView:container];
  return scroll;
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
  CGFloat width = MIN(860.0, maxWidth);
  CGFloat height = MIN(620.0, maxHeight);

  CGFloat originX = NSMidX(visible) - width / 2.0;
  CGFloat originY = NSMidY(visible) - height / 2.0;
  return NSMakeRect(originX, originY, width, height);
}

- (NSTextField *)headerLabelWithString:(NSString *)value frame:(NSRect)frame {
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setBezeled:NO];
  [label setEditable:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont boldSystemFontOfSize:13]];
  [label setStringValue:value];
  return label;
}

- (NSDictionary *)statusForRepo:(NSDictionary *)entry {
  NSString *path = [self expandedWorkflowPath:entry[@"path"]];
  if (!path) return @{ @"branch": @"—", @"dirty": @NO };
  NSString *branch = [self runGitArguments:@[ @"rev-parse", @"--abbrev-ref", @"HEAD" ] atPath:path];
  NSString *dirtyOutput = [self runGitArguments:@[ @"status", @"--short" ] atPath:path];
  BOOL dirty = dirtyOutput.length > 0;
  if (branch.length == 0) {
    branch = @"(detached)";
  }
  return @{ @"branch": branch, @"dirty": @(dirty) };
}

- (NSString *)runGitArguments:(NSArray<NSString *> *)arguments atPath:(NSString *)path {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/env";
  NSMutableArray *args = [NSMutableArray arrayWithObject:@"git"];
  [args addObjectsFromArray:arguments];
  task.arguments = args;
  task.currentDirectoryPath = path;
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
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  return [output stringByTrimmingCharactersInSet:ws] ?: @"";
}

- (NSArray *)workflowArrayForKey:(NSString *)key fallback:(NSArray *)fallback {
  id value = self.workflowData[key];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return fallback ?: @[];
}

- (NSDictionary *)loadWorkflowData {
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
  NSString *path = sender.toolTip;
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
  NSString *script = [self.configPath stringByAppendingPathComponent:@"bin/open_control_panel.sh"];
  [self runScript:script arguments:@[]];
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

- (void)runScript:(NSString *)script arguments:(NSArray<NSString *> *)arguments {
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) return;
  [self runCommand:script arguments:arguments];
}

- (void)runCommand:(NSString *)command arguments:(NSArray<NSString *> *)arguments {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = command;
  task.arguments = arguments;
  NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  NSString *path = env[@"PATH"] ?: @"";
  env[@"PATH"] = [NSString stringWithFormat:@"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:%@", path];
  task.environment = env;
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
