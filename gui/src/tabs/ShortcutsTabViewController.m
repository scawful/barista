#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface ShortcutRow : NSObject
@property (copy) NSString *action;
@property (copy) NSString *shortcutDescription;
@property (copy) NSString *symbol;
@property (copy) NSString *command;
@end

@implementation ShortcutRow
@end

@interface ShortcutsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *shortcuts;
@property (strong) NSSearchField *searchField;
@end

@implementation ShortcutsTabViewController

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
  NSButton *exportButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 720, y, 150, 32)];
  [exportButton setButtonType:NSButtonTypeMomentaryPushIn];
  [exportButton setBezelStyle:NSBezelStyleRounded];
  exportButton.title = @"Export to skhd";
  exportButton.target = self;
  exportButton.action = @selector(exportToSkhd:);
  [self.view addSubview:exportButton];
}

- (void)loadShortcuts {
  // Parse shortcuts.lua to extract shortcut definitions
  NSString *shortcutsPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"modules/shortcuts.lua"];
  NSString *content = [NSString stringWithContentsOfFile:shortcutsPath encoding:NSUTF8StringEncoding error:nil];
  
  if (!content) {
    self.shortcuts = @[];
    return;
  }

  NSMutableArray *shortcuts = [NSMutableArray array];
  
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
  
  self.shortcuts = shortcuts;
  [self.tableView reloadData];
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
        // This is a simplified version - full implementation would parse mods properly
        [output appendFormat:@"# %@ - %@\n", shortcut.shortcutDescription, shortcut.symbol];
        [output appendFormat:@"# %@\n\n", shortcut.command];
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

@end

