#import "ConfigurationManager.h"
#import "BaristaTabBaseViewController.h"

@interface IconsTabViewController : BaristaTabBaseViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate>
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

- (NSString *)configDir {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (config.configPath.length) {
    return config.configPath;
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
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

- (void)viewDidLoad {
  [super viewDidLoad];

  [self loadIcons];
  [self loadAppIconMap];

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(20, 24, 20, 24) spacing:20];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Icon Settings";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // Mode toggle
  self.modeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
  [self.modeControl setSegmentCount:2];
  [self.modeControl setLabel:@"Mappings" forSegment:0];
  [self.modeControl setLabel:@"Library" forSegment:1];
  self.modeControl.selectedSegment = 0;
  self.modeControl.target = self;
  self.modeControl.action = @selector(modeChanged:);
  [self.modeControl.widthAnchor constraintEqualToConstant:300].active = YES;
  [rootStack addView:self.modeControl inGravity:NSStackViewGravityTop];

  // Container for content
  NSView *contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  contentContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [rootStack addView:contentContainer inGravity:NSStackViewGravityTop];
  [contentContainer.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  [contentContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20].active = YES;

  self.mappingContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  self.libraryContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  
  for (NSView *v in @[self.mappingContainer, self.libraryContainer]) {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [contentContainer addSubview:v];
    [v.topAnchor constraintEqualToAnchor:contentContainer.topAnchor].active = YES;
    [v.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor].active = YES;
    [v.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor].active = YES;
    [v.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor].active = YES;
  }

  [self buildMappingUI];
  [self buildLibraryUI];
  [self modeChanged:self.modeControl];
}

- (void)buildMappingUI {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.mappingContainer.bounds];
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSNoBorder;
  scrollView.drawsBackground = NO;
  [self.mappingContainer addSubview:scrollView];
  self.mappingScrollView = scrollView;

  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 16;
  stack.edgeInsets = NSEdgeInsetsMake(10, 0, 20, 20);
  scrollView.documentView = stack;
  [stack.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor constant:-20].active = YES;

  NSTextField *widgetHeader = [[NSTextField alloc] initWithFrame:NSZeroRect];
  widgetHeader.stringValue = @"Widget Icons";
  widgetHeader.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  widgetHeader.bordered = NO;
  widgetHeader.editable = NO;
  widgetHeader.backgroundColor = [NSColor clearColor];
  [stack addView:widgetHeader inGravity:NSStackViewGravityTop];

  self.widgetIconFields = [NSMutableDictionary dictionary];
  self.widgetIconPreviews = [NSMutableDictionary dictionary];
  NSArray *entries = [self widgetIconEntries];

  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.rowSpacing = 10;
  grid.columnSpacing = 12;
  [stack addView:grid inGravity:NSStackViewGravityTop];

  for (NSDictionary *entry in entries) {
    NSString *key = entry[@"key"];
    NSString *labelText = entry[@"label"];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.stringValue = labelText;
    label.bordered = NO;
    label.editable = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.placeholderString = @"Glyph";
    field.delegate = self;
    [field.widthAnchor constraintEqualToConstant:80].active = YES;
    NSString *currentValue = [config valueForKeyPath:[NSString stringWithFormat:@"icons.%@", key] defaultValue:@""];
    if ([currentValue isKindOfClass:[NSString class]]) {
      field.stringValue = currentValue;
    }

    NSTextField *preview = [[NSTextField alloc] initWithFrame:NSZeroRect];
    preview.bordered = NO;
    preview.editable = NO;
    preview.backgroundColor = [NSColor clearColor];
    preview.alignment = NSTextAlignmentCenter;
    preview.font = [self preferredIconFontWithSize:20];
    preview.stringValue = field.stringValue;
    [preview.widthAnchor constraintEqualToConstant:40].active = YES;

    [grid addRowWithViews:@[label, field, preview]];
    self.widgetIconFields[key] = field;
    self.widgetIconPreviews[key] = preview;
  }

  self.applyWidgetIconsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.applyWidgetIconsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyWidgetIconsButton setBezelStyle:NSBezelStyleRounded];
  self.applyWidgetIconsButton.title = @"Apply Widget Icons";
  self.applyWidgetIconsButton.target = self;
  self.applyWidgetIconsButton.action = @selector(applyWidgetIcons:);
  [self.applyWidgetIconsButton.widthAnchor constraintEqualToConstant:200].active = YES;
  [stack addView:self.applyWidgetIconsButton inGravity:NSStackViewGravityTop];

  [stack setCustomSpacing:40 afterView:self.applyWidgetIconsButton];

  NSTextField *appHeader = [[NSTextField alloc] initWithFrame:NSZeroRect];
  appHeader.stringValue = @"App Icon Map";
  appHeader.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  appHeader.bordered = NO;
  appHeader.editable = NO;
  appHeader.backgroundColor = [NSColor clearColor];
  [stack addView:appHeader inGravity:NSStackViewGravityTop];

  NSStackView *appControls = [[NSStackView alloc] initWithFrame:NSZeroRect];
  appControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  appControls.spacing = 12;
  [stack addView:appControls inGravity:NSStackViewGravityTop];

  self.appSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  self.appSearchField.placeholderString = @"Search apps...";
  self.appSearchField.target = self;
  self.appSearchField.action = @selector(appSearchChanged:);
  self.appSearchField.delegate = self;
  [self.appSearchField.widthAnchor constraintEqualToConstant:250].active = YES;
  [appControls addView:self.appSearchField inGravity:NSStackViewGravityLeading];

  self.appOpenBrowserButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.appOpenBrowserButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.appOpenBrowserButton setBezelStyle:NSBezelStyleRounded];
  self.appOpenBrowserButton.title = @"Open Icon Browser";
  self.appOpenBrowserButton.target = self;
  self.appOpenBrowserButton.action = @selector(openIconBrowser:);
  [appControls addView:self.appOpenBrowserButton inGravity:NSStackViewGravityLeading];

  NSScrollView *appTableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  appTableScroll.hasVerticalScroller = YES;
  appTableScroll.autohidesScrollers = YES;
  appTableScroll.borderType = NSBezelBorder;
  [appTableScroll.heightAnchor constraintEqualToConstant:300].active = YES;
  [appTableScroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

  self.appTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.appTableView.dataSource = self;
  self.appTableView.delegate = self;
  self.appTableView.rowHeight = 30;

  NSTableColumn *appColumn = [[NSTableColumn alloc] initWithIdentifier:@"app"];
  appColumn.title = @"Application";
  appColumn.width = 300;
  [self.appTableView addTableColumn:appColumn];

  NSTableColumn *glyphColumn = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphColumn.title = @"Glyph";
  glyphColumn.width = 100;
  [self.appTableView addTableColumn:glyphColumn];

  appTableScroll.documentView = self.appTableView;
  [stack addView:appTableScroll inGravity:NSStackViewGravityTop];
}

- (void)buildLibraryUI {
  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 16;
  [self.libraryContainer addSubview:stack];
  
  [stack.topAnchor constraintEqualToAnchor:self.libraryContainer.topAnchor].active = YES;
  [stack.leadingAnchor constraintEqualToAnchor:self.libraryContainer.leadingAnchor].active = YES;
  [stack.trailingAnchor constraintEqualToAnchor:self.libraryContainer.trailingAnchor].active = YES;
  [stack.bottomAnchor constraintEqualToAnchor:self.libraryContainer.bottomAnchor].active = YES;

  NSStackView *controls = [[NSStackView alloc] initWithFrame:NSZeroRect];
  controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  controls.spacing = 12;
  [stack addView:controls inGravity:NSStackViewGravityTop];

  self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  self.searchField.placeholderString = @"Search icon library...";
  self.searchField.delegate = self;
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  [self.searchField.widthAnchor constraintEqualToConstant:300].active = YES;
  [controls addView:self.searchField inGravity:NSStackViewGravityLeading];

  self.openBrowserButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.openBrowserButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.openBrowserButton setBezelStyle:NSBezelStyleRounded];
  self.openBrowserButton.title = @"Full Icon Browser";
  self.openBrowserButton.target = self;
  self.openBrowserButton.action = @selector(openIconBrowser:);
  [controls addView:self.openBrowserButton inGravity:NSStackViewGravityLeading];

  NSStackView *mainContent = [[NSStackView alloc] initWithFrame:NSZeroRect];
  mainContent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  mainContent.spacing = 20;
  mainContent.alignment = NSLayoutAttributeTop;
  [stack addView:mainContent inGravity:NSStackViewGravityTop];
  [mainContent.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  [mainContent.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor].active = YES;

  NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  tableScroll.hasVerticalScroller = YES;
  tableScroll.autohidesScrollers = YES;
  tableScroll.borderType = NSBezelBorder;
  [mainContent addView:tableScroll inGravity:NSStackViewGravityLeading];
  [tableScroll.bottomAnchor constraintEqualToAnchor:mainContent.bottomAnchor].active = YES;

  self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 30;

  NSTableColumn *glyphCol = [[NSTableColumn alloc] initWithIdentifier:@"glyph"];
  glyphCol.title = @"Icon";
  glyphCol.width = 60;
  [self.tableView addTableColumn:glyphCol];

  NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameCol.title = @"Name";
  nameCol.width = 200;
  [self.tableView addTableColumn:nameCol];

  tableScroll.documentView = self.tableView;

  NSStackView *previewStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  previewStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  previewStack.spacing = 20;
  previewStack.alignment = NSLayoutAttributeCenterX;
  [previewStack.widthAnchor constraintEqualToConstant:200].active = YES;
  [mainContent addView:previewStack inGravity:NSStackViewGravityTrailing];

  self.previewField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.previewField.stringValue = @"";
  self.previewField.font = [self preferredIconFontWithSize:120];
  self.previewField.bordered = NO;
  self.previewField.editable = NO;
  self.previewField.backgroundColor = [NSColor clearColor];
  self.previewField.alignment = NSTextAlignmentCenter;
  [previewStack addView:self.previewField inGravity:NSStackViewGravityTop];

  self.glyphCopyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.glyphCopyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.glyphCopyButton setBezelStyle:NSBezelStyleRounded];
  self.glyphCopyButton.title = @"Copy Glyph";
  self.glyphCopyButton.target = self;
  self.glyphCopyButton.action = @selector(copyGlyph:);
  [self.glyphCopyButton.widthAnchor constraintEqualToConstant:140].active = YES;
  [previewStack addView:self.glyphCopyButton inGravity:NSStackViewGravityTop];

  // Fallback notice when icon_map.json is missing
  if (self.allIcons.count <= 10) {
    NSTextField *fallbackLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    fallbackLabel.stringValue = @"Using built-in icons. Place icon_map.json in your SketchyBar config directory for a full library.";
    fallbackLabel.font = [NSFont systemFontOfSize:11];
    fallbackLabel.textColor = [NSColor secondaryLabelColor];
    fallbackLabel.bordered = NO;
    fallbackLabel.editable = NO;
    fallbackLabel.backgroundColor = [NSColor clearColor];
    fallbackLabel.lineBreakMode = NSLineBreakByWordWrapping;
    fallbackLabel.preferredMaxLayoutWidth = 500;
    [stack addView:fallbackLabel inGravity:NSStackViewGravityTop];
  }
}

- (void)modeChanged:(NSSegmentedControl *)sender {
  BOOL showMappings = sender.selectedSegment == 0;
  self.mappingContainer.hidden = !showMappings;
  self.libraryContainer.hidden = showMappings;
}

- (void)loadIcons {
  NSString *iconMapPath = [[self configDir] stringByAppendingPathComponent:@"icon_map.json"];
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
  NSString *iconMapPath = [[self configDir] stringByAppendingPathComponent:@"icon_map.json"];
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
  NSString *iconMapPath = [[self configDir] stringByAppendingPathComponent:@"icon_map.json"];
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
  NSString *iconBrowserPath = [[self configDir] stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:iconBrowserPath]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = iconBrowserPath;
    [task launch];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = [NSString stringWithFormat:@"Build icon_browser first: cd %@/gui && make icon_browser", [self configDir]];
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
    textField.font = [self preferredIconFontWithSize:20];
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
