#import "BaristaTabBaseViewController.h"
#import "ConfigurationManager.h"

@interface ShortcutRow : NSObject
@property (copy) NSString *action;
@property (copy) NSString *shortcutDescription;
@property (copy) NSString *symbol;
@property (copy) NSString *command;
@property (copy) NSString *mods;
@property (copy) NSString *key;
@end

@implementation ShortcutRow
@end

@interface ShortcutsTabViewController : BaristaTabBaseViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *shortcuts;
@property (strong) NSArray *filteredShortcuts;
@property (strong) NSSearchField *searchField;
@end

@implementation ShortcutsTabViewController

- (NSString *)humanizeAction:(NSString *)action {
  if (!action.length) {
    return @"";
  }
  NSString *label = [action stringByReplacingOccurrencesOfString:@"_" withString:@" "];
  NSArray *parts = [label componentsSeparatedByString:@" "];
  NSMutableArray *words = [NSMutableArray arrayWithCapacity:parts.count];

  for (NSString *part in parts) {
    if (!part.length) {
      continue;
    }
    if (part.length == 1) {
      [words addObject:[part uppercaseString]];
      continue;
    }
    NSString *head = [[part substringToIndex:1] uppercaseString];
    NSString *tail = [part substringFromIndex:1];
    [words addObject:[head stringByAppendingString:tail]];
  }

  return [words componentsJoinedByString:@" "];
}

- (NSString *)symbolForKey:(NSString *)key {
  if (!key.length) {
    return @"";
  }
  static NSDictionary<NSString *, NSString *> *symbols = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    symbols = @{
      @"left": @"←",
      @"right": @"→",
      @"up": @"↑",
      @"down": @"↓",
      @"space": @"␣",
      @"return": @"↩",
      @"tab": @"⇥",
      @"delete": @"⌫",
      @"escape": @"⎋",
    };
  });
  NSString *symbol = symbols[key];
  if (symbol) {
    return symbol;
  }
  if (key.length == 1) {
    return [key uppercaseString];
  }
  return key;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self loadShortcuts];

  if (self.shortcuts.count == 0) {
    NSTextField *placeholder = [[NSTextField alloc] initWithFrame:NSZeroRect];
    placeholder.stringValue = @"No shortcuts found. Ensure modules/shortcuts.lua exists in your SketchyBar config directory.";
    placeholder.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    placeholder.textColor = [NSColor secondaryLabelColor];
    placeholder.bordered = NO;
    placeholder.editable = NO;
    placeholder.backgroundColor = [NSColor clearColor];
    placeholder.alignment = NSTextAlignmentCenter;
    placeholder.tag = 999;
    placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:placeholder];
    [NSLayoutConstraint activateConstraints:@[
      [placeholder.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
      [placeholder.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
  }

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(20, 24, 20, 24) spacing:20];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Keyboard Shortcuts";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // Search and Header Actions
  NSStackView *headerStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  headerStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  headerStack.spacing = 12;
  [rootStack addView:headerStack inGravity:NSStackViewGravityTop];

  self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  self.searchField.placeholderString = @"Filter shortcuts...";
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.searchField.widthAnchor constraintEqualToConstant:300].active = YES;
  [headerStack addView:self.searchField inGravity:NSStackViewGravityLeading];

  for (NSString *title in @[@"Open shortcuts.lua", @"Generate + Reload"]) {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    [btn setBezelStyle:NSBezelStyleRounded];
    btn.title = title;
    btn.target = self;
    if ([title containsString:@"Open"]) btn.action = @selector(openShortcutsSource:);
    else btn.action = @selector(generateShortcuts:);
    [headerStack addView:btn inGravity:NSStackViewGravityLeading];
  }

  // Table View
  NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  tableScroll.hasVerticalScroller = YES;
  tableScroll.autohidesScrollers = YES;
  tableScroll.borderType = NSBezelBorder;
  [rootStack addView:tableScroll inGravity:NSStackViewGravityTop];
  [tableScroll.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  [tableScroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-80].active = YES;

  self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 28;

  NSTableColumn *descColumn = [[NSTableColumn alloc] initWithIdentifier:@"description"];
  descColumn.title = @"Description";
  descColumn.width = 300;
  [self.tableView addTableColumn:descColumn];

  NSTableColumn *symbolColumn = [[NSTableColumn alloc] initWithIdentifier:@"symbol"];
  symbolColumn.title = @"Shortcut";
  symbolColumn.width = 150;
  [self.tableView addTableColumn:symbolColumn];

  NSTableColumn *commandColumn = [[NSTableColumn alloc] initWithIdentifier:@"command"];
  commandColumn.title = @"Action / Command";
  commandColumn.width = 400;
  [self.tableView addTableColumn:commandColumn];

  tableScroll.documentView = self.tableView;

  // Footer Actions
  NSStackView *footerStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  footerStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  footerStack.spacing = 12;
  [rootStack addView:footerStack inGravity:NSStackViewGravityTop];

  NSButton *exportButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [exportButton setButtonType:NSButtonTypeMomentaryPushIn];
  [exportButton setBezelStyle:NSBezelStyleRounded];
  exportButton.title = @"Export to skhd.conf";
  exportButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  exportButton.target = self;
  exportButton.action = @selector(exportToSkhd:);
  [exportButton.widthAnchor constraintEqualToConstant:180].active = YES;
  [footerStack addView:exportButton inGravity:NSStackViewGravityLeading];
}

- (void)loadShortcuts {
  // Parse shortcuts.lua to extract shortcut definitions
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *shortcutsPath = [config.configPath stringByAppendingPathComponent:@"modules/shortcuts.lua"];
  NSString *content = [NSString stringWithContentsOfFile:shortcutsPath encoding:NSUTF8StringEncoding error:nil];
  
  if (!content) {
    self.shortcuts = @[];
    return;
  }

  NSMutableArray *shortcuts = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSString *> *actionDescriptions = [NSMutableDictionary dictionary];
  
  // Parse shortcuts.global array
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\s*mods\\s*=\\s*\\{([^}]+)\\},\\s*key\\s*=\\s*\"([^\"]+)\",\\s*action\\s*=\\s*\"([^\"]+)\",\\s*desc\\s*=\\s*\"([^\"]+)\",\\s*symbol\\s*=\\s*\"([^\"]+)\"(?:,\\s*\\w+\\s*=\\s*\"[^\"]*\")*\\s*\\}" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
  NSArray *matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
  
  for (NSTextCheckingResult *match in matches) {
    if (match.numberOfRanges >= 6) {
      NSString *modsStr = [content substringWithRange:[match rangeAtIndex:1]];
      NSString *key = [content substringWithRange:[match rangeAtIndex:2]];
      NSString *action = [content substringWithRange:[match rangeAtIndex:3]];
      NSString *desc = [content substringWithRange:[match rangeAtIndex:4]];
      NSString *symbol = [content substringWithRange:[match rangeAtIndex:5]];
      
      ShortcutRow *row = [[ShortcutRow alloc] init];
      row.action = action;
      row.shortcutDescription = desc;
      row.symbol = symbol;
      row.mods = modsStr;
      row.key = key;
      if (action.length && desc.length) {
        actionDescriptions[action] = desc;
      }
      
      // Get command from actions table
      NSRegularExpression *cmdRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@\\s*=\\s*([^\\n,}]+)", action] options:0 error:nil];
      NSTextCheckingResult *cmdMatch = [cmdRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
      if (cmdMatch && cmdMatch.numberOfRanges >= 2) {
        row.command = [[content substringWithRange:[cmdMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      } else {
        row.command = @"";
      }

      [shortcuts addObject:row];
    }
  }

  // Parse fn mappings
  NSRegularExpression *fnRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[\"fn-([^\"]+)\"\\]\\s*=\\s*\"([^\"]+)\"" options:0 error:nil];
  NSArray *fnMatches = [fnRegex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
  for (NSTextCheckingResult *match in fnMatches) {
    if (match.numberOfRanges >= 3) {
      NSString *key = [content substringWithRange:[match rangeAtIndex:1]];
      NSString *action = [content substringWithRange:[match rangeAtIndex:2]];
      NSString *desc = actionDescriptions[action] ?: [self humanizeAction:action];

      ShortcutRow *row = [[ShortcutRow alloc] init];
      row.action = action;
      row.shortcutDescription = desc;
      row.symbol = [NSString stringWithFormat:@"🌐%@", [self symbolForKey:key]];
      row.mods = @"\"fn\"";
      row.key = key;

      NSRegularExpression *cmdRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@\\s*=\\s*([^\\n,}]+)", action] options:0 error:nil];
      NSTextCheckingResult *cmdMatch = [cmdRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
      if (cmdMatch && cmdMatch.numberOfRanges >= 2) {
        row.command = [[content substringWithRange:[cmdMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      } else {
        row.command = @"";
      }

      [shortcuts addObject:row];
    }
  }

  // JSON fallback: if Lua parsing yielded nothing, try workflow_shortcuts.json
  if (shortcuts.count == 0) {
    NSString *jsonPath = [config.configPath stringByAppendingPathComponent:@"data/workflow_shortcuts.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    if (jsonData) {
      NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
      NSArray *keymap = json[@"keymap"];
      if ([keymap isKindOfClass:[NSArray class]]) {
        for (NSDictionary *section in keymap) {
          NSString *sectionName = section[@"section"] ?: @"";
          NSArray *items = section[@"items"];
          if (![items isKindOfClass:[NSArray class]]) continue;
          for (NSDictionary *item in items) {
            ShortcutRow *row = [[ShortcutRow alloc] init];
            row.symbol = item[@"keys"] ?: @"";
            row.shortcutDescription = item[@"description"] ?: @"";
            row.command = sectionName;
            row.action = @"";
            row.mods = @"";
            row.key = @"";
            [shortcuts addObject:row];
          }
        }
      }
    }
  }

  self.shortcuts = shortcuts;
  self.filteredShortcuts = self.shortcuts;
  [self.tableView reloadData];
}

- (NSString *)skhdModsFromString:(NSString *)modsStr {
  if (!modsStr.length) {
    return @"";
  }

  NSArray *parts = [modsStr componentsSeparatedByString:@","];
  NSMutableArray *mods = [NSMutableArray arrayWithCapacity:parts.count];
  NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSCharacterSet *quoteSet = [NSCharacterSet characterSetWithCharactersInString:@"\""];

  for (NSString *part in parts) {
    NSString *mod = [[part stringByTrimmingCharactersInSet:trimSet] stringByTrimmingCharactersInSet:quoteSet];
    if (mod.length) {
      [mods addObject:mod];
    }
  }

  return [mods componentsJoinedByString:@" + "];
}

- (void)searchChanged:(id)sender {
  NSString *searchText = [self.searchField.stringValue lowercaseString];
  if (searchText.length == 0) {
    self.filteredShortcuts = self.shortcuts;
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (ShortcutRow *row in self.shortcuts) {
      if ([[row.shortcutDescription lowercaseString] containsString:searchText] ||
          [[row.key lowercaseString] containsString:searchText] ||
          [[row.command lowercaseString] containsString:searchText]) {
        [filtered addObject:row];
      }
    }
    self.filteredShortcuts = filtered;
  }
  [self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredShortcuts.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  ShortcutRow *shortcut = self.filteredShortcuts[row];
  NSString *identifier = tableColumn.identifier;

  NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
  textField.bordered = NO;
  textField.editable = NO;
  textField.backgroundColor = [NSColor clearColor];

  if ([identifier isEqualToString:@"description"]) {
    textField.stringValue = shortcut.shortcutDescription;
  } else if ([identifier isEqualToString:@"symbol"]) {
    textField.stringValue = shortcut.symbol;
    textField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
  } else if ([identifier isEqualToString:@"command"]) {
    textField.stringValue = shortcut.command;
    textField.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    textField.textColor = [NSColor secondaryLabelColor];
  }

  return textField;
}

- (void)exportToSkhd:(id)sender {
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.allowedFileTypes = @[@"conf", @"txt"];
  panel.nameFieldStringValue = @"barista_shortcuts.conf";
  panel.message = @"Export shortcuts to skhd configuration file";

  [panel beginWithCompletionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK) {
      NSMutableString *output = [NSMutableString string];
      [output appendString:@"# SketchyBar Global Shortcuts\n"];
      [output appendString:@"# Generated by Barista Control Panel\n\n"];

      for (ShortcutRow *shortcut in self.shortcuts) {
        // Format: mods - key : command
        [output appendFormat:@"# %@ - %@\n", shortcut.shortcutDescription, shortcut.symbol];
        if (shortcut.command.length) {
          NSString *mods = [self skhdModsFromString:shortcut.mods];
          if (mods.length && shortcut.key.length) {
            [output appendFormat:@"%@ - %@ : %@\n\n", mods, shortcut.key, shortcut.command];
          } else {
            [output appendFormat:@"# %@\n\n", shortcut.command];
          }
        } else {
          [output appendString:@"# (missing command)\n\n"];
        }
      }

      NSError *error = nil;
      if (![output writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Failed";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
      } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Successful";
        alert.informativeText = [NSString stringWithFormat:@"Shortcuts exported to %@", panel.URL.path];
        [alert runModal];
      }
    }
  }];
}

- (void)openShortcutsSource:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *shortcutsPath = [config.configPath stringByAppendingPathComponent:@"modules/shortcuts.lua"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:shortcutsPath]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Shortcuts file not found";
    alert.informativeText = shortcutsPath;
    [alert runModal];
    return;
  }
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:shortcutsPath]];
}

- (BOOL)runTask:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(NSString *__autoreleasing *)output {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = launchPath;
  task.arguments = arguments;
  NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  if (environment) {
    [env addEntriesFromDictionary:environment];
  }
  NSString *path = env[@"PATH"] ?: @"";
  env[@"PATH"] = [NSString stringWithFormat:@"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:%@", path];
  task.environment = env;
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    if (output) {
      *output = exception.reason ?: @"Failed to launch task";
    }
    return NO;
  }
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  if (output && data) {
    *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }
  return task.terminationStatus == 0;
}

- (void)generateShortcuts:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *scriptPath = [config.configPath stringByAppendingPathComponent:@"helpers/generate_shortcuts.lua"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Generator not found";
    alert.informativeText = scriptPath;
    [alert runModal];
    return;
  }

  NSString *output = nil;
  NSDictionary *env = @{@"BARISTA_CONFIG_DIR": config.configPath ?: @""};
  BOOL ok = [self runTask:@"/usr/bin/env" arguments:@[@"lua", scriptPath] environment:env output:&output];
  if (!ok) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Shortcut generation failed";
    alert.informativeText = output ?: @"Check the generator output for details.";
    [alert runModal];
    return;
  }

  NSString *reloadOutput = nil;
  [self runTask:@"/usr/bin/env" arguments:@[@"skhd", @"--reload"] environment:nil output:&reloadOutput];

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Shortcuts updated";
  alert.informativeText = @"Generated barista_shortcuts.conf and reloaded skhd.";
  [alert runModal];
}

@end
