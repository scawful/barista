#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface HelpCenterController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSDictionary *workflowData;
@property (copy) NSString *configPath;
@property (copy) NSString *scriptsPath;
@property (copy) NSString *codePath;
@property (strong) NSArray<NSDictionary *> *keymapRows;
@end

@implementation HelpCenterController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  self.configPath = config.configPath;
  self.scriptsPath = config.scriptsPath;
  self.codePath = config.codePath;
  self.workflowData = [self loadWorkflowData];
  self.keymapRows = [self buildKeymapRows];
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

  NSTableView *tableView = [[NSTableView alloc] initWithFrame:bounds];
  tableView.dataSource = self;
  tableView.delegate = self;
  tableView.headerView = nil;
  tableView.usesAlternatingRowBackgroundColors = YES;
  tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
  tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  NSTableColumn *keysColumn = [[NSTableColumn alloc] initWithIdentifier:@"keys"];
  keysColumn.title = @"Shortcut";
  keysColumn.width = 180;
  [tableView addTableColumn:keysColumn];

  NSTableColumn *descColumn = [[NSTableColumn alloc] initWithIdentifier:@"description"];
  descColumn.title = @"Description";
  descColumn.width = bounds.size.width - 200;
  [tableView addTableColumn:descColumn];

  scroll.documentView = tableView;
  return scroll;
}

- (NSView *)buildWorkflowTab {
  NSRect bounds = self.window.contentView.bounds;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
  [scroll setBorderType:NSNoBorder];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  CGFloat width = scroll.contentSize.width;
  NSFont *buttonFont = [self preferredTextFontWithSize:12 weight:NSFontWeightRegular];
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
    button.font = buttonFont;
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
    button.font = buttonFont;
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
  [label setFont:[self preferredTextFontWithSize:13 weight:NSFontWeightSemibold]];
  [label setStringValue:value];
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

- (NSFont *)preferredTextFontWithSize:(CGFloat)size weight:(NSFontWeight)weight {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *fontName = [config valueForKeyPath:@"appearance.font_text" defaultValue:nil];
  if ([fontName isKindOfClass:[NSString class]] && fontName.length > 0) {
    NSFont *font = [NSFont fontWithName:fontName size:size];
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
  return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.keymapRows.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
  if (row < 0 || row >= self.keymapRows.count) {
    return NO;
  }
  return [self.keymapRows[row][@"type"] isEqualToString:@"section"];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  return [self tableView:tableView isGroupRow:row] ? 26.0 : 22.0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *entry = self.keymapRows[row];
  NSString *type = entry[@"type"];
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
    cell.textField = textField;
    [cell addSubview:textField];
  }

  NSTextField *textField = cell.textField;
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
  NSString *fallbackPath = [self expandedWorkflowPath:@"%CODE%/lab/sys_manual/README.md"];
  if (fallbackPath && [[NSFileManager defaultManager] fileExistsAtPath:fallbackPath]) {
    NSURL *url = [NSURL fileURLWithPath:fallbackPath];
    [[NSWorkspace sharedWorkspace] openURL:url];
    return;
  }
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Sys Manual Not Found";
  alert.informativeText = @"Build sys_manual first (~/src/lab/sys_manual/build/sys_manual) or install it in /Applications.";
  [alert runModal];
}

- (void)openControlPanelWithMode:(NSString *)mode {
  NSString *script = [self.configPath stringByAppendingPathComponent:@"bin/open_control_panel.sh"];
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
