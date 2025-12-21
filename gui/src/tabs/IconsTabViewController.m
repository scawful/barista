#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface IconsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate>
@property (strong) NSSegmentedControl *modeControl;
@property (strong) NSScrollView *mappingScrollView;
@property (strong) NSView *libraryContainer;
@property (strong) NSView *mappingContainer;

@property (strong) NSSearchField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSTextField *previewField;
@property (strong) NSButton *glyphCopyButton;
@property (strong) NSButton *openBrowserButton;

@property (strong) NSMutableDictionary *widgetIconFields;
@property (strong) NSMutableDictionary *widgetIconPreviews;
@property (strong) NSButton *applyWidgetIconsButton;

@property (strong) NSSearchField *appSearchField;
@property (strong) NSButton *appOpenBrowserButton;
@property (strong) NSTableView *appTableView;
@property (strong) NSMutableDictionary *appIconMap;
@property (strong) NSArray *appIconKeys;
@property (strong) NSArray *filteredAppKeys;

@property (strong) NSArray *allIcons;
@property (strong) NSArray *filteredIcons;
@end

@implementation IconsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (NSArray *)widgetIconEntries {
  return @[
    @{@"key": @"apple", @"label": @"System Menu"},
    @{@"key": @"quest", @"label": @"Quest"},
    @{@"key": @"settings", @"label": @"Settings"},
    @{@"key": @"clock", @"label": @"Clock"},
    @{@"key": @"calendar", @"label": @"Calendar"},
    @{@"key": @"battery", @"label": @"Battery (Override)"},
    @{@"key": @"volume", @"label": @"Volume (Override)"},
    @{@"key": @"cpu", @"label": @"CPU (System Info)"},
    @{@"key": @"memory", @"label": @"Memory (System Info)"},
    @{@"key": @"disk", @"label": @"Disk (System Info)"},
    @{@"key": @"wifi", @"label": @"Wi-Fi (Connected)"},
    @{@"key": @"wifi_off", @"label": @"Wi-Fi (Disconnected)"},
  ];
}

- (NSFont *)preferredIconFontWithSize:(CGFloat)size {
  NSArray<NSString *> *candidates = @[
    @"Hack Nerd Font",
    @"JetBrainsMono Nerd Font",
    @"FiraCode Nerd Font",
    @"SFMono Nerd Font",
    @"Symbols Nerd Font",
    @"MesloLGS NF"
  ];
  for (NSString *name in candidates) {
    NSFont *font = [NSFont fontWithName:name size:size];
    if (font) {
      return font;
    }
  }
  return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self loadIcons];
  [self loadAppIconMap];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Icon Settings";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 40;

  // Mode toggle
  self.modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(leftMargin, y, 240, 26)];
  [self.modeControl setSegmentCount:2];
  [self.modeControl setLabel:@"Mappings" forSegment:0];
  [self.modeControl setLabel:@"Library" forSegment:1];
  self.modeControl.selectedSegment = 0;
  self.modeControl.target = self;
  self.modeControl.action = @selector(modeChanged:);
  [self.view addSubview:self.modeControl];
  y -= 30;

  CGFloat contentHeight = y - 10;
  CGFloat contentWidth = self.view.bounds.size.width;

  self.mappingContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, contentHeight)];
  self.libraryContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, contentHeight)];
  self.mappingContainer.autoresizingMask = NSViewWidthSizable;
  self.libraryContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  self.mappingScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, contentHeight)];
  self.mappingScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.mappingScrollView.hasVerticalScroller = YES;
  self.mappingScrollView.autohidesScrollers = YES;
  self.mappingScrollView.borderType = NSNoBorder;
  self.mappingScrollView.documentView = self.mappingContainer;

  [self.view addSubview:self.mappingScrollView];
  [self.view addSubview:self.libraryContainer];

  [self buildMappingUI];
  [self buildLibraryUI];
  [self modeChanged:self.modeControl];
}

- (void)buildMappingUI {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  CGFloat leftMargin = 40;
  CGFloat labelWidth = 130;
  CGFloat fieldWidth = 80;
  CGFloat rowHeight = 26;

  self.widgetIconFields = [NSMutableDictionary dictionary];
  self.widgetIconPreviews = [NSMutableDictionary dictionary];
  NSArray *entries = [self widgetIconEntries];

  CGFloat requiredHeight = 20 + 30 + (entries.count * rowHeight) + 40 + 28 + 34 + 220;
  if (requiredHeight > self.mappingContainer.bounds.size.height) {
    NSRect frame = self.mappingContainer.frame;
    frame.size.height = requiredHeight;
    self.mappingContainer.frame = frame;
  }

  CGFloat y = self.mappingContainer.bounds.size.height - 20;

  NSTextField *widgetHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 22)];
  widgetHeader.stringValue = @"Widget Icons";
  widgetHeader.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
  widgetHeader.bordered = NO;
  widgetHeader.editable = NO;
  widgetHeader.backgroundColor = [NSColor clearColor];
  [self.mappingContainer addSubview:widgetHeader];
  y -= 30;

  for (NSDictionary *entry in entries) {
    NSString *key = entry[@"key"];
    NSString *labelText = entry[@"label"];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, labelWidth, 20)];
    label.stringValue = labelText;
    label.bordered = NO;
    label.editable = NO;
    label.backgroundColor = [NSColor clearColor];
    [self.mappingContainer addSubview:label];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + labelWidth + 8, y - 2, fieldWidth, 24)];
    field.placeholderString = @"Glyph";
    field.delegate = self;
    NSString *currentValue = [config valueForKeyPath:[NSString stringWithFormat:@"icons.%@", key] defaultValue:@""];
    if ([currentValue isKindOfClass:[NSString class]]) {
      field.stringValue = currentValue;
    }
    [self.mappingContainer addSubview:field];

    NSTextField *preview = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + labelWidth + 8 + fieldWidth + 8, y - 6, 36, 28)];
    preview.bordered = NO;
    preview.editable = NO;
    preview.backgroundColor = [NSColor clearColor];
    preview.alignment = NSTextAlignmentCenter;
    preview.font = [self preferredIconFontWithSize:18];
    preview.stringValue = field.stringValue;
    [self.mappingContainer addSubview:preview];

    self.widgetIconFields[key] = field;
    self.widgetIconPreviews[key] = preview;

    y -= rowHeight;
  }

  self.applyWidgetIconsButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y - 4, 180, 28)];
  [self.applyWidgetIconsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyWidgetIconsButton setBezelStyle:NSBezelStyleRounded];
  self.applyWidgetIconsButton.title = @"Apply Widget Icons";
  self.applyWidgetIconsButton.target = self;
  self.applyWidgetIconsButton.action = @selector(applyWidgetIcons:);
  [self.mappingContainer addSubview:self.applyWidgetIconsButton];
  y -= 40;

  NSTextField *appHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 22)];
  appHeader.stringValue = @"App Icon Map";
  appHeader.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
  appHeader.bordered = NO;
  appHeader.editable = NO;
  appHeader.backgroundColor = [NSColor clearColor];
  [self.mappingContainer addSubview:appHeader];
  y -= 28;

  self.appSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 220, 24)];
  self.appSearchField.placeholderString = @"Search apps...";
  self.appSearchField.target = self;
  self.appSearchField.action = @selector(appSearchChanged:);
  self.appSearchField.delegate = self;
  [self.mappingContainer addSubview:self.appSearchField];

  self.appOpenBrowserButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 240, y, 150, 24)];
  [self.appOpenBrowserButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.appOpenBrowserButton setBezelStyle:NSBezelStyleRounded];
  self.appOpenBrowserButton.title = @"Icon Browser";
  self.appOpenBrowserButton.target = self;
  self.appOpenBrowserButton.action = @selector(openIconBrowser:);
  [self.mappingContainer addSubview:self.appOpenBrowserButton];
  y -= 34;

  CGFloat tableHeight = 220;
  CGFloat tableWidth = self.mappingContainer.bounds.size.width - (leftMargin * 2);
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, y - tableHeight + 6, tableWidth, tableHeight)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.appTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.appTableView.dataSource = self;
  self.appTableView.delegate = self;

  NSTableColumn *appColumn = [[NSTableColumn alloc] initWithIdentifier:@"app"];
  appColumn.title = @"App";
  appColumn.width = tableWidth - 110;
  [self.appTableView addTableColumn:appColumn];

  NSTableColumn *glyphColumn = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphColumn.title = @"Glyph";
  glyphColumn.width = 90;
  glyphColumn.editable = YES;
  [self.appTableView addTableColumn:glyphColumn];

  scrollView.documentView = self.appTableView;
  [self.mappingContainer addSubview:scrollView];
}

- (void)buildLibraryUI {
  CGFloat y = self.libraryContainer.bounds.size.height - 20;
  CGFloat leftMargin = 40;

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 24)];
  title.stringValue = @"Icon Library";
  title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.libraryContainer addSubview:title];
  y -= 36;

  self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(leftMargin, y, 300, 24)];
  self.searchField.placeholderString = @"Search icons...";
  self.searchField.delegate = self;
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.libraryContainer addSubview:self.searchField];

  self.openBrowserButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 320, y, 150, 24)];
  [self.openBrowserButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.openBrowserButton setBezelStyle:NSBezelStyleRounded];
  self.openBrowserButton.title = @"Open Icon Browser";
  self.openBrowserButton.target = self;
  self.openBrowserButton.action = @selector(openIconBrowser:);
  [self.libraryContainer addSubview:self.openBrowserButton];
  y -= 50;

  self.previewField = [[NSTextField alloc] initWithFrame:NSMakeRect(self.libraryContainer.bounds.size.width - 180, y + 10, 120, 120)];
  self.previewField.stringValue = @"";
  self.previewField.font = [NSFont systemFontOfSize:96];
  self.previewField.bordered = NO;
  self.previewField.editable = NO;
  self.previewField.backgroundColor = [NSColor clearColor];
  self.previewField.alignment = NSTextAlignmentCenter;
  [self.libraryContainer addSubview:self.previewField];

  self.glyphCopyButton = [[NSButton alloc] initWithFrame:NSMakeRect(self.libraryContainer.bounds.size.width - 180, y - 40, 120, 32)];
  [self.glyphCopyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.glyphCopyButton setBezelStyle:NSBezelStyleRounded];
  self.glyphCopyButton.title = @"Copy Glyph";
  self.glyphCopyButton.target = self;
  self.glyphCopyButton.action = @selector(copyGlyph:);
  [self.libraryContainer addSubview:self.glyphCopyButton];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 40, self.libraryContainer.bounds.size.width - 240, y - 60)];
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
  [self.libraryContainer addSubview:scrollView];
}

- (void)modeChanged:(NSSegmentedControl *)sender {
  BOOL showMappings = sender.selectedSegment == 0;
  self.mappingScrollView.hidden = !showMappings;
  self.libraryContainer.hidden = showMappings;
}

- (void)loadIcons {
  NSString *iconMapPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"icon_map.json"];
  NSData *data = [NSData dataWithContentsOfFile:iconMapPath];

  if (data) {
    NSError *error = nil;
    NSDictionary *iconMap = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (iconMap && [iconMap isKindOfClass:[NSDictionary class]]) {
      NSMutableArray *icons = [NSMutableArray array];
      for (NSString *name in iconMap) {
        NSString *glyph = iconMap[name];
        [icons addObject:@{ @"name": name, @"glyph": glyph ?: @"", @"category": @"Custom" }];
      }
      self.allIcons = icons;
      self.filteredIcons = [self.allIcons copy];
      return;
    }
  }

  self.allIcons = @[
    @{ @"name": @"Apple", @"glyph": @"", @"category": @"System" },
    @{ @"name": @"Battery", @"glyph": @"", @"category": @"System" },
    @{ @"name": @"WiFi", @"glyph": @"󰖩", @"category": @"System" },
    @{ @"name": @"Volume", @"glyph": @"󰕾", @"category": @"System" },
    @{ @"name": @"Terminal", @"glyph": @"", @"category": @"Development" },
    @{ @"name": @"VSCode", @"glyph": @"󰨞", @"category": @"Development" },
    @{ @"name": @"Window", @"glyph": @"󰖯", @"category": @"Window Management" },
    @{ @"name": @"Tile", @"glyph": @"󰆾", @"category": @"Window Management" },
    @{ @"name": @"Stack", @"glyph": @"󰓩", @"category": @"Window Management" },
    @{ @"name": @"Float", @"glyph": @"󰒄", @"category": @"Window Management" },
  ];
  self.filteredIcons = [self.allIcons copy];
}

- (void)loadAppIconMap {
  NSString *iconMapPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"icon_map.json"];
  NSData *data = [NSData dataWithContentsOfFile:iconMapPath];
  if (!data) {
    self.appIconMap = [NSMutableDictionary dictionary];
    self.appIconKeys = @[];
    self.filteredAppKeys = @[];
    return;
  }

  NSError *error = nil;
  NSDictionary *iconMap = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
  if (error || ![iconMap isKindOfClass:[NSDictionary class]]) {
    self.appIconMap = [NSMutableDictionary dictionary];
    self.appIconKeys = @[];
    self.filteredAppKeys = @[];
    return;
  }

  self.appIconMap = [iconMap mutableCopy];
  NSArray *keys = [[self.appIconMap allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  self.appIconKeys = keys;
  self.filteredAppKeys = keys;
}

- (void)saveAppIconMap {
  NSString *iconMapPath = [[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"] stringByAppendingPathComponent:@"icon_map.json"];
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:self.appIconMap options:NSJSONWritingPrettyPrinted error:&error];
  if (!data || error) {
    return;
  }
  [data writeToFile:iconMapPath atomically:YES];
}

- (void)searchChanged:(id)sender {
  NSString *searchText = [self.searchField.stringValue lowercaseString];

  if ([searchText length] == 0) {
    self.filteredIcons = [self.allIcons copy];
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *icon in self.allIcons) {
      NSString *name = [icon[@"name"] lowercaseString];
      NSString *category = [icon[@"category"] lowercaseString];
      if ([name containsString:searchText] || [category containsString:searchText]) {
        [filtered addObject:icon];
      }
    }
    self.filteredIcons = filtered;
  }

  [self.tableView reloadData];
}

- (void)appSearchChanged:(id)sender {
  NSString *searchText = [self.appSearchField.stringValue lowercaseString];
  if (searchText.length == 0) {
    self.filteredAppKeys = self.appIconKeys;
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *key in self.appIconKeys) {
      if ([[key lowercaseString] containsString:searchText]) {
        [filtered addObject:key];
      }
    }
    self.filteredAppKeys = filtered;
  }
  [self.appTableView reloadData];
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
  if (tableView == self.appTableView) {
    return self.filteredAppKeys.count;
  }
  return self.filteredIcons.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if (tableView == self.appTableView) {
    NSString *key = self.filteredAppKeys[row];
    NSString *identifier = tableColumn.identifier;

    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
    textField.bordered = NO;
    textField.backgroundColor = [NSColor clearColor];
    textField.editable = [identifier isEqualToString:@"glyph"];

    if ([identifier isEqualToString:@"glyph"]) {
      NSString *glyph = self.appIconMap[key] ?: @"";
      textField.stringValue = glyph;
      textField.alignment = NSTextAlignmentCenter;
      textField.font = [self preferredIconFontWithSize:18];
    } else {
      textField.stringValue = key;
      textField.editable = NO;
    }
    return textField;
  }

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

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if (tableView == self.appTableView) {
    return [tableColumn.identifier isEqualToString:@"glyph"];
  }
  return NO;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if (tableView != self.appTableView || ![tableColumn.identifier isEqualToString:@"glyph"]) {
    return;
  }

  NSString *key = self.filteredAppKeys[row];
  NSString *glyph = @"";
  if ([object isKindOfClass:[NSString class]]) {
    glyph = (NSString *)object;
  }
  self.appIconMap[key] = glyph;
  [self saveAppIconMap];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (notification.object != self.tableView) {
    return;
  }

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

- (void)applyWidgetIcons:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  for (NSString *key in self.widgetIconFields) {
    NSTextField *field = self.widgetIconFields[key];
    NSString *value = field.stringValue ?: @"";
    [config setValue:value forKeyPath:[NSString stringWithFormat:@"icons.%@", key]];
  }
  [config reloadSketchyBar];

  self.applyWidgetIconsButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyWidgetIconsButton.title = @"Apply Widget Icons";
  });
}

- (void)controlTextDidChange:(NSNotification *)notification {
  id field = notification.object;

  if (field == self.searchField) {
    [self searchChanged:field];
    return;
  }

  if (field == self.appSearchField) {
    [self appSearchChanged:field];
    return;
  }

  for (NSString *key in self.widgetIconFields) {
    if (self.widgetIconFields[key] == field) {
      NSTextField *preview = self.widgetIconPreviews[key];
      preview.stringValue = ((NSTextField *)field).stringValue ?: @"";
      break;
    }
  }
}

@end
