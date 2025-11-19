#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface IconsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) NSSearchField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSTextField *previewField;
@property (strong) NSButton *glyphCopyButton;
@property (strong) NSButton *openBrowserButton;
@property (strong) NSArray *allIcons;
@property (strong) NSArray *filteredIcons;
@end

@implementation IconsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  // Load icons from icon_map.json or modules/icons.lua
  [self loadIcons];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Icon Library";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // Search
  self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  self.searchField.placeholderString = @"Search icons...";
  self.searchField.delegate = self;
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.view addSubview:self.searchField];

  // Open Icon Browser button
  self.openBrowserButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 320, y, 150, 24)];
  [self.openBrowserButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.openBrowserButton setBezelStyle:NSBezelStyleRounded];
  self.openBrowserButton.title = @"Open Icon Browser";
  self.openBrowserButton.target = self;
  self.openBrowserButton.action = @selector(openIconBrowser:);
  [self.view addSubview:self.openBrowserButton];
  y -= 50;

  // Preview
  self.previewField = [[NSTextField alloc] initWithFrame:NSMakeRect(self.view.bounds.size.width - 180, y + 10, 120, 120)];
  self.previewField.stringValue = @"";
  self.previewField.font = [NSFont systemFontOfSize:96];
  self.previewField.bordered = NO;
  self.previewField.editable = NO;
  self.previewField.backgroundColor = [NSColor clearColor];
  self.previewField.alignment = NSTextAlignmentCenter;
  [self.view addSubview:self.previewField];

  self.glyphCopyButton = [[NSButton alloc] initWithFrame:NSMakeRect(self.view.bounds.size.width - 180, y - 40, 120, 32)];
  [self.glyphCopyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.glyphCopyButton setBezelStyle:NSBezelStyleRounded];
  self.glyphCopyButton.title = @"Copy Glyph";
  self.glyphCopyButton.target = self;
  self.glyphCopyButton.action = @selector(copyGlyph:);
  [self.view addSubview:self.glyphCopyButton];

  // Table
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 40, self.view.bounds.size.width - 240, y - 60)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *glyphColumn = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphColumn.title = @"Icon";
  glyphColumn.width = 60;
  [self.tableView addTableColumn:glyphColumn];

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Name";
  nameColumn.width = 150;
  [self.tableView addTableColumn:nameColumn];

  NSTableColumn *categoryColumn = [[NSTableColumn alloc] initWithIdentifier:@"category"];
  categoryColumn.title = @"Category";
  categoryColumn.width = 120;
  [self.tableView addTableColumn:categoryColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];
}

- (void)loadIcons {
  // Try to load from icon_map.json first
  NSString *iconMapPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"icon_map.json"];
  NSData *data = [NSData dataWithContentsOfFile:iconMapPath];
  
  if (data) {
    NSError *error = nil;
    NSDictionary *iconMap = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (iconMap && [iconMap isKindOfClass:[NSDictionary class]]) {
      NSMutableArray *icons = [NSMutableArray array];
      for (NSString *name in iconMap) {
        NSString *glyph = iconMap[name];
        [icons addObject:@{@"name": name, @"glyph": glyph ?: @"", @"category": @"Custom"}];
      }
      self.allIcons = icons;
      self.filteredIcons = [self.allIcons copy];
      [self.tableView reloadData];
      return;
    }
  }

  // Fallback to hardcoded list
  self.allIcons = @[
    @{@"name": @"Apple", @"glyph": @"", @"category": @"System"},
    @{@"name": @"Battery", @"glyph": @"", @"category": @"System"},
    @{@"name": @"WiFi", @"glyph": @"󰖩", @"category": @"System"},
    @{@"name": @"Volume", @"glyph": @"󰕾", @"category": @"System"},
    @{@"name": @"Terminal", @"glyph": @"", @"category": @"Development"},
    @{@"name": @"VSCode", @"glyph": @"󰨞", @"category": @"Development"},
    @{@"name": @"Window", @"glyph": @"󰖯", @"category": @"Window Management"},
    @{@"name": @"Tile", @"glyph": @"󰆾", @"category": @"Window Management"},
    @{@"name": @"Stack", @"glyph": @"󰓩", @"category": @"Window Management"},
    @{@"name": @"Float", @"glyph": @"󰒄", @"category": @"Window Management"},
  ];
  self.filteredIcons = [self.allIcons copy];
}

- (void)searchChanged:(id)sender {
  NSString *searchText = [self.searchField.stringValue lowercaseString];

  if ([searchText length] == 0) {
    self.filteredIcons = [self.allIcons copy];
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *icon in self.allIcons) {
      NSString *name = [[icon[@"name"] lowercaseString] lowercaseString];
      NSString *category = [[icon[@"category"] lowercaseString] lowercaseString];
      if ([name containsString:searchText] || [category containsString:searchText]) {
        [filtered addObject:icon];
      }
    }
    self.filteredIcons = filtered;
  }

  [self.tableView reloadData];
}

- (void)openIconBrowser:(id)sender {
  NSString *iconBrowserPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:iconBrowserPath]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = iconBrowserPath;
    [task launch];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = @"Build icon_browser first: cd ~/.config/sketchybar/gui && make icon_browser";
    [alert runModal];
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredIcons.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *icon = self.filteredIcons[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"glyph"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    textField.stringValue = icon[@"glyph"];
    textField.font = [NSFont systemFontOfSize:20];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.alignment = NSTextAlignmentCenter;
    return textField;
  }

  NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
  textField.stringValue = icon[identifier];
  textField.bordered = NO;
  textField.editable = NO;
  textField.backgroundColor = [NSColor clearColor];
  return textField;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < self.filteredIcons.count) {
    NSDictionary *icon = self.filteredIcons[row];
    self.previewField.stringValue = icon[@"glyph"];
  }
}

- (void)copyGlyph:(id)sender {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < self.filteredIcons.count) {
    NSDictionary *icon = self.filteredIcons[row];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:icon[@"glyph"] forType:NSPasteboardTypeString];

    self.glyphCopyButton.title = @"✓ Copied!";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      self.glyphCopyButton.title = @"Copy Glyph";
    });
  }
}

@end

