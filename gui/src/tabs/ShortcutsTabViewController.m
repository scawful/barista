#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

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

@interface ShortcutsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *shortcuts;
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

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  // Load shortcuts from modules/shortcuts.lua
  [self loadShortcuts];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Keyboard Shortcuts";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // Search
  self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  self.searchField.placeholderString = @"Search shortcuts...";
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.view addSubview:self.searchField];
  y -= 50;

  CGFloat buttonY = y;
  NSButton *openButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 380, buttonY, 160, 32)];
  [openButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openButton setBezelStyle:NSBezelStyleRounded];
  openButton.title = @"Open shortcuts.lua";
  openButton.target = self;
  openButton.action = @selector(openShortcutsSource:);
  [self.view addSubview:openButton];

  NSButton *generateButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 550, buttonY, 160, 32)];
  [generateButton setButtonType:NSButtonTypeMomentaryPushIn];
  [generateButton setBezelStyle:NSBezelStyleRounded];
  generateButton.title = @"Generate + Reload";
  generateButton.target = self;
  generateButton.action = @selector(generateShortcuts:);
  [self.view addSubview:generateButton];

  // Table view
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 60, 700, y - 60)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *descColumn = [[NSTableColumn alloc] initWithIdentifier:@"description"];
  descColumn.title = @"Description";
  descColumn.width = 250;
  [self.tableView addTableColumn:descColumn];

  NSTableColumn *symbolColumn = [[NSTableColumn alloc] initWithIdentifier:@"symbol"];
  symbolColumn.title = @"Shortcut";
  symbolColumn.width = 150;
  [self.tableView addTableColumn:symbolColumn];

  NSTableColumn *commandColumn = [[NSTableColumn alloc] initWithIdentifier:@"command"];
  commandColumn.title = @"Command";
  commandColumn.width = 300;
  [self.tableView addTableColumn:commandColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];

  // Export button
  NSButton *exportButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 720, buttonY, 150, 32)];
  [exportButton setButtonType:NSButtonTypeMomentaryPushIn];
  [exportButton setBezelStyle:NSBezelStyleRounded];
  exportButton.title = @"Export to skhd";
  exportButton.target = self;
  exportButton.action = @selector(exportToSkhd:);
  [self.view addSubview:exportButton];
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
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\s*mods\\s*=\\s*\\{([^}]+)\\},\\s*key\\s*=\\s*\"([^\"]+)\",\\s*action\\s*=\\s*\"([^\"]+)\",\\s*desc\\s*=\\s*\"([^\"]+)\",\\s*symbol\\s*=\\s*\"([^\"]+)\"\\s*\\}" options:0 error:nil];
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
      NSRegularExpression *cmdRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@\\s*=\\s*\"([^\"]+)\"", action] options:0 error:nil];
      NSTextCheckingResult *cmdMatch = [cmdRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
      if (cmdMatch && cmdMatch.numberOfRanges >= 2) {
        row.command = [content substringWithRange:[cmdMatch rangeAtIndex:1]];
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

      NSRegularExpression *cmdRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@\\s*=\\s*\"([^\"]+)\"", action] options:0 error:nil];
      NSTextCheckingResult *cmdMatch = [cmdRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
      if (cmdMatch && cmdMatch.numberOfRanges >= 2) {
        row.command = [content substringWithRange:[cmdMatch rangeAtIndex:1]];
      } else {
        row.command = @"";
      }

      [shortcuts addObject:row];
    }
  }
  
  self.shortcuts = shortcuts;
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
  // Filtering would be implemented here
  [self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.shortcuts.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  ShortcutRow *shortcut = self.shortcuts[row];
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
