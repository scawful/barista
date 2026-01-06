#import <Cocoa/Cocoa.h>

// Icon Browser - Search and preview Nerd Font icons
@interface IconBrowserController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *tableView;
@property (strong) NSTextField *searchField;
@property (strong) NSTextField *previewField;
@property (strong) NSPopUpButton *categoryFilter;
@property (strong) NSButton *clipboardButton;
@property (strong) NSMutableArray<NSDictionary *> *allIcons;
@property (strong) NSMutableArray<NSDictionary *> *filteredIcons;
@property (strong) NSString *selectedGlyph;
@end

@implementation IconBrowserController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [self loadIconLibrary];
  [self buildWindow];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

- (void)loadIconLibrary {
  // Load icon library from icons.lua module
  self.allIcons = [NSMutableArray array];

  NSString *luaScript = @"local config = os.getenv('BARISTA_CONFIG_DIR') or (os.getenv('HOME') .. '/.config/sketchybar'); "
                        @"package.path = package.path .. ';' .. config .. '/modules/?.lua'; "
                        @"local icons = require('icons'); "
                        @"local json = require('json'); "
                        @"print(json.encode(icons.get_all()))";

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/lua";
  task.arguments = @[@"-e", luaScript];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  [task launch];
  [task waitUntilExit];

  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

  if (task.terminationStatus == 0 && output.length > 0) {
    NSError *error = nil;
    id jsonArray = [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding]
                                                   options:0
                                                     error:&error];
    if ([jsonArray isKindOfClass:[NSArray class]]) {
      [self.allIcons addObjectsFromArray:jsonArray];
    }
  }

  // Fallback icons if Lua fails
  if (self.allIcons.count == 0) {
    [self loadFallbackIcons];
  }

  self.filteredIcons = [self.allIcons mutableCopy];
}

- (void)loadFallbackIcons {
  NSArray *fallbackIcons = @[
    @{@"name": @"apple", @"glyph": @"", @"category": @"system"},
    @{@"name": @"terminal", @"glyph": @"", @"category": @"development"},
    @{@"name": @"code", @"glyph": @"", @"category": @"development"},
    @{@"name": @"folder", @"glyph": @"", @"category": @"files"},
    @{@"name": @"music", @"glyph": @"", @"category": @"misc"},
    @{@"name": @"triforce", @"glyph": @"󰊠", @"category": @"gaming"},
    @{@"name": @"emacs", @"glyph": @"", @"category": @"emacs"},
    @{@"name": @"vim", @"glyph": @"", @"category": @"development"},
  ];
  [self.allIcons addObjectsFromArray:fallbackIcons];
}

- (void)buildWindow {
  NSRect frame = NSMakeRect(0, 0, 800, 600);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  [self.window setTitle:@"Icon Browser"];
  [self.window setLevel:NSFloatingWindowLevel];
  [self.window setMinSize:NSMakeSize(600, 400)];
  self.window.delegate = self;
  [self.window center];

  NSView *content = [self.window contentView];

  // Search field
  self.searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, frame.size.height - 60, 400, 24)];
  self.searchField.placeholderString = @"Search icons...";
  self.searchField.delegate = self;
  [content addSubview:self.searchField];

  // Category filter
  self.categoryFilter = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(430, frame.size.height - 60, 200, 24)];
  [self.categoryFilter addItemWithTitle:@"All Categories"];

  NSSet *categories = [NSSet setWithArray:[self.allIcons valueForKey:@"category"]];
  for (NSString *category in [categories.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
    if (category && ![category isEqual:[NSNull null]]) {
      [self.categoryFilter addItemWithTitle:[category capitalizedString]];
    }
  }

  self.categoryFilter.target = self;
  self.categoryFilter.action = @selector(filterChanged:);
  [content addSubview:self.categoryFilter];

  // Table view
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 140, frame.size.width - 40, frame.size.height - 220)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *glyphColumn = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphColumn.title = @"Icon";
  glyphColumn.width = 60;
  [self.tableView addTableColumn:glyphColumn];

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Name";
  nameColumn.width = 200;
  [self.tableView addTableColumn:nameColumn];

  NSTableColumn *categoryColumn = [[NSTableColumn alloc] initWithIdentifier:@"category"];
  categoryColumn.title = @"Category";
  categoryColumn.width = 150;
  [self.tableView addTableColumn:categoryColumn];

  scrollView.documentView = self.tableView;
  [content addSubview:scrollView];

  // Preview area
  NSBox *previewBox = [[NSBox alloc] initWithFrame:NSMakeRect(20, 20, frame.size.width - 40, 100)];
  previewBox.title = @"Preview";
  previewBox.autoresizingMask = NSViewWidthSizable;
  [content addSubview:previewBox];

  NSView *previewContent = [previewBox contentView];

  self.previewField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 100, 60)];
  [self.previewField setBezeled:NO];
  [self.previewField setEditable:NO];
  [self.previewField setDrawsBackground:NO];
  [self.previewField setAlignment:NSTextAlignmentCenter];
  NSFont *previewFont = [NSFont fontWithName:@"Hack Nerd Font" size:48.0];
  if (!previewFont) {
    previewFont = [NSFont systemFontOfSize:48.0];
  }
  [self.previewField setFont:previewFont];
  [self.previewField setStringValue:@""];
  [previewContent addSubview:self.previewField];

  self.clipboardButton = [[NSButton alloc] initWithFrame:NSMakeRect(previewContent.bounds.size.width - 130, 25, 120, 28)];
  self.clipboardButton.autoresizingMask = NSViewMinXMargin;
  [self.clipboardButton setTitle:@"Copy to Clipboard"];
  [self.clipboardButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.clipboardButton setBezelStyle:NSBezelStyleRounded];
  self.clipboardButton.target = self;
  self.clipboardButton.action = @selector(copyGlyph:);
  [previewContent addSubview:self.clipboardButton];
}

- (void)filterChanged:(id)sender {
  [self applyFilter];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == self.searchField) {
    [self applyFilter];
  }
}

- (void)applyFilter {
  NSString *searchText = [[self.searchField stringValue] lowercaseString];
  NSString *category = [self.categoryFilter.selectedItem.title lowercaseString];

  [self.filteredIcons removeAllObjects];

  for (NSDictionary *icon in self.allIcons) {
    NSString *name = [icon[@"name"] lowercaseString];
    NSString *iconCategory = [icon[@"category"] lowercaseString];

    BOOL matchesSearch = searchText.length == 0 || [name containsString:searchText];
    BOOL matchesCategory = [category isEqualToString:@"all categories"] || [iconCategory isEqualToString:category];

    if (matchesSearch && matchesCategory) {
      [self.filteredIcons addObject:icon];
    }
  }

  [self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredIcons.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSString *identifier = tableColumn.identifier;
  NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];

  if (!cell) {
    cell = [[NSTableCellView alloc] init];
    NSTextField *textField = [[NSTextField alloc] initWithFrame:cell.bounds];
    textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [textField setBezeled:NO];
    [textField setEditable:NO];
    [textField setDrawsBackground:NO];
    cell.textField = textField;
    [cell addSubview:textField];
    cell.identifier = identifier;
  }

  NSDictionary *icon = self.filteredIcons[row];

  if ([identifier isEqualToString:@"glyph"]) {
    cell.textField.stringValue = icon[@"glyph"] ?: @"";
    NSFont *iconFont = [NSFont fontWithName:@"Hack Nerd Font" size:18.0];
    if (iconFont) {
      cell.textField.font = iconFont;
    }
    cell.textField.alignment = NSTextAlignmentCenter;
  } else if ([identifier isEqualToString:@"name"]) {
    cell.textField.stringValue = icon[@"name"] ?: @"";
    cell.textField.font = [NSFont systemFontOfSize:13.0];
  } else if ([identifier isEqualToString:@"category"]) {
    NSString *category = icon[@"category"] ?: @"";
    cell.textField.stringValue = [category capitalizedString];
    cell.textField.font = [NSFont systemFontOfSize:12.0];
    cell.textField.textColor = [NSColor secondaryLabelColor];
  }

  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < self.filteredIcons.count) {
    NSDictionary *icon = self.filteredIcons[row];
    self.selectedGlyph = icon[@"glyph"];
    [self.previewField setStringValue:self.selectedGlyph ?: @""];
  } else {
    self.selectedGlyph = nil;
    [self.previewField setStringValue:@""];
  }
}

- (void)copyGlyph:(id)sender {
  if (self.selectedGlyph) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.selectedGlyph forType:NSPasteboardTypeString];

    // Visual feedback
    NSString *originalTitle = self.clipboardButton.title;
    [self.clipboardButton setTitle:@"✓ Copied!"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self.clipboardButton setTitle:originalTitle];
    });
  }
}

- (void)windowWillClose:(NSNotification *)notification {
  [NSApp terminate:nil];
}

@end

int main(int argc, const char **argv) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    IconBrowserController *delegate = [IconBrowserController new];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [app run];
  }
  return 0;
}
