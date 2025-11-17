#import <Cocoa/Cocoa.h>

// Enhanced Control Panel with comprehensive customization options

@interface IconPickerViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDataSource>
@property (strong) NSCollectionView *collectionView;
@property (strong) NSArray *icons;
@property (copy) void (^selectionHandler)(NSDictionary *icon);
@end

@interface WidgetConfigViewController : NSViewController
@property (strong) NSTextField *widgetNameLabel;
@property (strong) NSSwitch *enabledSwitch;
@property (strong) NSSlider *scaleSlider;
@property (strong) NSSlider *updateIntervalSlider;
@property (strong) NSColorWell *colorWell;
@property (strong) NSButton *iconButton;
@property (strong) NSTextField *iconPreview;
@property (copy) NSString *widgetName;
@property (copy) void (^updateHandler)(NSDictionary *config);
@end

@interface EnhancedMenuController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTabView *tabView;

// Appearance Tab
@property (strong) NSSlider *barHeightSlider;
@property (strong) NSSlider *cornerRadiusSlider;
@property (strong) NSSlider *blurRadiusSlider;
@property (strong) NSSlider *globalScaleSlider;
@property (strong) NSColorWell *barColorWell;
@property (strong) NSPopUpButton *themeSelector;
@property (strong) NSPopUpButton *fontFamilyMenu;
@property (strong) NSPopUpButton *fontStyleMenu;
@property (strong) NSSlider *fontSizeSlider;

// Widgets Tab
@property (strong) NSTableView *widgetsTable;
@property (strong) NSMutableArray *widgetsData;
@property (strong) WidgetConfigViewController *widgetConfig;

// Icons Tab
@property (strong) NSSearchField *iconSearchField;
@property (strong) IconPickerViewController *iconPicker;
@property (strong) NSPopUpButton *categoryFilter;
@property (strong) NSButton *importIconButton;
@property (strong) NSButton *exportIconButton;

// Spaces Tab
@property (strong) NSCollectionView *spacesCollection;
@property (strong) NSMutableArray *spacesData;

// Performance Tab
@property (strong) NSTextField *cpuUsageLabel;
@property (strong) NSTextField *memoryUsageLabel;
@property (strong) NSTextField *cacheHitsLabel;
@property (strong) NSTextField *updateRateLabel;
@property (strong) NSButton *daemonToggle;
@property (strong) NSPopUpButton *updateModeMenu;

// Live Preview
@property (strong) NSView *previewBar;
@property (strong) NSTimer *previewTimer;

@property (copy) NSString *configPath;
@property (copy) NSString *scriptsPath;
@property (copy) NSString *helpersPath;
@property (strong) NSMutableDictionary *state;
@end

@implementation IconPickerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    self.collectionView.collectionViewLayout = [self createLayout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerClass:[NSCollectionViewItem class]
                  forItemWithIdentifier:@"IconItem"];

    scrollView.documentView = self.collectionView;
    [self.view addSubview:scrollView];

    // Load icons from C helper
    [self loadIcons];
}

- (NSCollectionViewLayout *)createLayout {
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(80, 80);
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 10;
    layout.sectionInset = NSEdgeInsetsMake(10, 10, 10, 10);
    return layout;
}

- (void)loadIcons {
    // Call icon_manager to get all icons
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [NSString stringWithFormat:@"%@/bin/icon_manager",
                      NSHomeDirectory()];
    task.arguments = @[@"search", @""];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSError *error;
    self.icons = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    [self.collectionView reloadData];
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return self.icons.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    NSCollectionViewItem *item = [collectionView makeItemWithIdentifier:@"IconItem"
                                                            forIndexPath:indexPath];

    NSDictionary *icon = self.icons[indexPath.item];

    // Create custom view with icon glyph and name
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 80)];

    NSTextField *glyphField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 30, 80, 40)];
    glyphField.stringValue = icon[@"glyph"] ?: @"";
    glyphField.font = [NSFont fontWithName:@"Symbols Nerd Font" size:32];
    glyphField.alignment = NSTextAlignmentCenter;
    glyphField.editable = NO;
    glyphField.bezeled = NO;
    glyphField.backgroundColor = [NSColor clearColor];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 80, 20)];
    nameField.stringValue = icon[@"name"] ?: @"";
    nameField.font = [NSFont systemFontOfSize:10];
    nameField.alignment = NSTextAlignmentCenter;
    nameField.editable = NO;
    nameField.bezeled = NO;
    nameField.backgroundColor = [NSColor clearColor];

    [view addSubview:glyphField];
    [view addSubview:nameField];

    item.view = view;
    return item;
}

- (void)collectionView:(NSCollectionView *)collectionView
didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath && self.selectionHandler) {
        self.selectionHandler(self.icons[indexPath.item]);
    }
}

@end

@implementation WidgetConfigViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];

    CGFloat y = 260;

    // Widget name
    self.widgetNameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 360, 24)];
    self.widgetNameLabel.stringValue = @"Widget Configuration";
    self.widgetNameLabel.font = [NSFont boldSystemFontOfSize:16];
    self.widgetNameLabel.editable = NO;
    self.widgetNameLabel.bezeled = NO;
    self.widgetNameLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:self.widgetNameLabel];

    y -= 40;

    // Enabled switch
    NSTextField *enabledLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    enabledLabel.stringValue = @"Enabled:";
    enabledLabel.editable = NO;
    enabledLabel.bezeled = NO;
    enabledLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:enabledLabel];

    self.enabledSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(130, y, 60, 20)];
    [self.enabledSwitch setTarget:self];
    [self.enabledSwitch setAction:@selector(configChanged:)];
    [self.view addSubview:self.enabledSwitch];

    y -= 40;

    // Scale slider
    NSTextField *scaleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    scaleLabel.stringValue = @"Scale:";
    scaleLabel.editable = NO;
    scaleLabel.bezeled = NO;
    scaleLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:scaleLabel];

    self.scaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(130, y, 200, 20)];
    self.scaleSlider.minValue = 0.5;
    self.scaleSlider.maxValue = 2.0;
    self.scaleSlider.target = self;
    self.scaleSlider.action = @selector(configChanged:);
    [self.view addSubview:self.scaleSlider];

    y -= 40;

    // Update interval
    NSTextField *intervalLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    intervalLabel.stringValue = @"Update Rate:";
    intervalLabel.editable = NO;
    intervalLabel.bezeled = NO;
    intervalLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:intervalLabel];

    self.updateIntervalSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(130, y, 200, 20)];
    self.updateIntervalSlider.minValue = 0.1;
    self.updateIntervalSlider.maxValue = 60.0;
    self.updateIntervalSlider.target = self;
    self.updateIntervalSlider.action = @selector(configChanged:);
    [self.view addSubview:self.updateIntervalSlider];

    y -= 40;

    // Color
    NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    colorLabel.stringValue = @"Color:";
    colorLabel.editable = NO;
    colorLabel.bezeled = NO;
    colorLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:colorLabel];

    self.colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(130, y, 60, 20)];
    self.colorWell.target = self;
    self.colorWell.action = @selector(configChanged:);
    [self.view addSubview:self.colorWell];

    y -= 40;

    // Icon
    NSTextField *iconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    iconLabel.stringValue = @"Icon:";
    iconLabel.editable = NO;
    iconLabel.bezeled = NO;
    iconLabel.backgroundColor = [NSColor clearColor];
    [self.view addSubview:iconLabel];

    self.iconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 40, 30)];
    self.iconPreview.font = [NSFont fontWithName:@"Symbols Nerd Font" size:24];
    self.iconPreview.editable = NO;
    self.iconPreview.bezeled = NO;
    self.iconPreview.backgroundColor = [NSColor clearColor];
    [self.view addSubview:self.iconPreview];

    self.iconButton = [[NSButton alloc] initWithFrame:NSMakeRect(180, y, 100, 24)];
    self.iconButton.title = @"Choose Icon";
    self.iconButton.target = self;
    self.iconButton.action = @selector(chooseIcon:);
    [self.view addSubview:self.iconButton];
}

- (void)configChanged:(id)sender {
    if (self.updateHandler) {
        self.updateHandler(@{
            @"enabled": @(self.enabledSwitch.state == NSControlStateValueOn),
            @"scale": @(self.scaleSlider.doubleValue),
            @"updateInterval": @(self.updateIntervalSlider.doubleValue),
            @"color": [self hexStringFromColor:self.colorWell.color]
        });
    }
}

- (void)chooseIcon:(id)sender {
    // Open icon picker
    IconPickerViewController *picker = [[IconPickerViewController alloc] init];
    picker.selectionHandler = ^(NSDictionary *icon) {
        self.iconPreview.stringValue = icon[@"glyph"] ?: @"";
        if (self.updateHandler) {
            self.updateHandler(@{@"icon": icon[@"glyph"]});
        }
    };

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = picker;
    popover.behavior = NSPopoverBehaviorTransient;
    [popover showRelativeToRect:self.iconButton.bounds
                          ofView:self.iconButton
                   preferredEdge:NSRectEdgeMaxY];
}

- (NSString *)hexStringFromColor:(NSColor *)color {
    CGFloat r, g, b, a;
    [[color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]
        getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"0x%02X%02X%02X%02X",
            (int)(a * 255), (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

@end

@implementation EnhancedMenuController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
    self.scriptsPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scripts"];
    self.helpersPath = [self.configPath stringByAppendingPathComponent:@"bin"];

    [self loadState];
    [self buildWindow];

    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];

    // Start preview timer
    self.previewTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(updatePreview)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)loadState {
    // Call state_manager to get current state
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self.helpersPath stringByAppendingPathComponent:@"state_manager"];
    task.arguments = @[@"init"];
    [task launch];
    [task waitUntilExit];

    // Load state from file
    NSString *statePath = [self.configPath stringByAppendingPathComponent:@"state.json"];
    NSData *data = [NSData dataWithContentsOfFile:statePath];
    if (data) {
        NSError *error;
        self.state = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] mutableCopy];
    }
    if (!self.state) {
        self.state = [NSMutableDictionary dictionary];
    }
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1400, 900);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];

    [self.window setTitle:@"Sketchybar Advanced Controls"];
    [self.window setLevel:NSFloatingWindowLevel];
    self.window.delegate = self;
    [self.window setMinSize:NSMakeSize(1200, 800)];
    [self.window center];

    // Create tab view
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 50, frame.size.width, frame.size.height - 100)];
    self.tabView.delegate = self;

    // Add tabs
    [self buildAppearanceTab];
    [self buildWidgetsTab];
    [self buildIconsTab];
    [self buildSpacesTab];
    [self buildPerformanceTab];

    [self.window.contentView addSubview:self.tabView];

    // Add live preview bar at bottom
    [self buildPreviewBar];

    // Add apply/save buttons
    [self buildControlButtons];
}

- (void)buildAppearanceTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Appearance";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    CGFloat y = 700;
    CGFloat labelWidth = 150;
    CGFloat controlWidth = 300;
    CGFloat x = 50;

    // Bar Height
    [self addLabel:@"Bar Height:" at:NSMakePoint(x, y) to:view];
    self.barHeightSlider = [self addSlider:NSMakeRect(x + labelWidth, y, controlWidth, 24)
                                        min:20 max:50 to:view];
    self.barHeightSlider.intValue = [self.state[@"appearance"][@"bar_height"] intValue] ?: 28;

    y -= 40;

    // Corner Radius
    [self addLabel:@"Corner Radius:" at:NSMakePoint(x, y) to:view];
    self.cornerRadiusSlider = [self addSlider:NSMakeRect(x + labelWidth, y, controlWidth, 24)
                                           min:0 max:20 to:view];
    self.cornerRadiusSlider.intValue = [self.state[@"appearance"][@"corner_radius"] intValue] ?: 0;

    y -= 40;

    // Blur Radius
    [self addLabel:@"Blur Radius:" at:NSMakePoint(x, y) to:view];
    self.blurRadiusSlider = [self addSlider:NSMakeRect(x + labelWidth, y, controlWidth, 24)
                                         min:0 max:50 to:view];
    self.blurRadiusSlider.intValue = [self.state[@"appearance"][@"blur_radius"] intValue] ?: 30;

    y -= 40;

    // Global Scale
    [self addLabel:@"Widget Scale:" at:NSMakePoint(x, y) to:view];
    self.globalScaleSlider = [self addSlider:NSMakeRect(x + labelWidth, y, controlWidth, 24)
                                          min:0.5 max:2.0 to:view];
    self.globalScaleSlider.doubleValue = [self.state[@"appearance"][@"widget_scale"] doubleValue] ?: 1.0;

    y -= 40;

    // Bar Color
    [self addLabel:@"Bar Color:" at:NSMakePoint(x, y) to:view];
    self.barColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + labelWidth, y, 60, 24)];
    [view addSubview:self.barColorWell];

    y -= 40;

    // Theme Selector
    [self addLabel:@"Theme:" at:NSMakePoint(x, y) to:view];
    self.themeSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + labelWidth, y, 200, 24)];
    [self.themeSelector addItemsWithTitles:@[@"Default", @"Catppuccin Mocha", @"Dracula", @"Nord", @"Tokyo Night"]];
    [view addSubview:self.themeSelector];

    y -= 40;

    // Font Settings
    [self addLabel:@"Font Family:" at:NSMakePoint(x, y) to:view];
    self.fontFamilyMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + labelWidth, y, 200, 24)];
    [self.fontFamilyMenu addItemsWithTitles:@[@"SF Pro", @"Helvetica Neue", @"Menlo", @"Monaco"]];
    [view addSubview:self.fontFamilyMenu];

    y -= 40;

    [self addLabel:@"Font Style:" at:NSMakePoint(x, y) to:view];
    self.fontStyleMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + labelWidth, y, 200, 24)];
    [self.fontStyleMenu addItemsWithTitles:@[@"Regular", @"Semibold", @"Bold", @"Light"]];
    [view addSubview:self.fontStyleMenu];

    y -= 40;

    [self addLabel:@"Font Size:" at:NSMakePoint(x, y) to:view];
    self.fontSizeSlider = [self addSlider:NSMakeRect(x + labelWidth, y, controlWidth, 24)
                                       min:8 max:20 to:view];
    self.fontSizeSlider.doubleValue = 12.0;

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (void)buildWidgetsTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Widgets";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    // Left side - widget list
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 100, 400, 600)];
    self.widgetsTable = [[NSTableView alloc] initWithFrame:scrollView.bounds];

    NSTableColumn *enabledColumn = [[NSTableColumn alloc] initWithIdentifier:@"enabled"];
    enabledColumn.title = @"Enabled";
    enabledColumn.width = 60;
    [self.widgetsTable addTableColumn:enabledColumn];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Widget";
    nameColumn.width = 200;
    [self.widgetsTable addTableColumn:nameColumn];

    NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
    iconColumn.title = @"Icon";
    iconColumn.width = 60;
    [self.widgetsTable addTableColumn:iconColumn];

    scrollView.documentView = self.widgetsTable;
    scrollView.hasVerticalScroller = YES;
    [view addSubview:scrollView];

    // Right side - widget configuration
    self.widgetConfig = [[WidgetConfigViewController alloc] init];
    self.widgetConfig.view.frame = NSMakeRect(450, 300, 600, 400);
    [view addSubview:self.widgetConfig.view];

    // Load widgets data
    [self loadWidgetsData];

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (void)buildIconsTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Icons";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    // Search field
    self.iconSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(50, 700, 300, 24)];
    self.iconSearchField.placeholderString = @"Search icons...";
    self.iconSearchField.target = self;
    self.iconSearchField.action = @selector(searchIcons:);
    [view addSubview:self.iconSearchField];

    // Category filter
    self.categoryFilter = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(370, 700, 150, 24)];
    [self.categoryFilter addItemsWithTitles:@[@"All", @"System", @"Apps", @"Development", @"Files", @"Window", @"Gaming", @"Status"]];
    self.categoryFilter.target = self;
    self.categoryFilter.action = @selector(filterIcons:);
    [view addSubview:self.categoryFilter];

    // Import/Export buttons
    self.importIconButton = [[NSButton alloc] initWithFrame:NSMakeRect(900, 700, 100, 24)];
    self.importIconButton.title = @"Import";
    self.importIconButton.target = self;
    self.importIconButton.action = @selector(importIcons:);
    [view addSubview:self.importIconButton];

    self.exportIconButton = [[NSButton alloc] initWithFrame:NSMakeRect(1020, 700, 100, 24)];
    self.exportIconButton.title = @"Export";
    self.exportIconButton.target = self;
    self.exportIconButton.action = @selector(exportIcons:);
    [view addSubview:self.exportIconButton];

    // Icon picker
    self.iconPicker = [[IconPickerViewController alloc] init];
    self.iconPicker.view.frame = NSMakeRect(50, 50, 1300, 620);
    [view addSubview:self.iconPicker.view];

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (void)buildSpacesTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Spaces";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    // Spaces collection view
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(50, 100, 1300, 600)];

    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(150, 150);
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 20;

    self.spacesCollection = [[NSCollectionView alloc] initWithFrame:scrollView.bounds];
    self.spacesCollection.collectionViewLayout = layout;
    [self.spacesCollection registerClass:[NSCollectionViewItem class]
                    forItemWithIdentifier:@"SpaceItem"];

    scrollView.documentView = self.spacesCollection;
    [view addSubview:scrollView];

    // Load spaces data
    [self loadSpacesData];

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (void)buildPerformanceTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Performance";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    CGFloat y = 650;
    CGFloat x = 100;

    // Performance stats
    NSTextField *statsTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
    statsTitle.stringValue = @"Performance Statistics";
    statsTitle.font = [NSFont boldSystemFontOfSize:16];
    statsTitle.editable = NO;
    statsTitle.bezeled = NO;
    statsTitle.backgroundColor = [NSColor clearColor];
    [view addSubview:statsTitle];

    y -= 40;

    self.cpuUsageLabel = [self addLabel:@"CPU Usage: 0%" at:NSMakePoint(x, y) to:view];
    y -= 30;

    self.memoryUsageLabel = [self addLabel:@"Memory Usage: 0 MB" at:NSMakePoint(x, y) to:view];
    y -= 30;

    self.cacheHitsLabel = [self addLabel:@"Cache Hits: 0/0" at:NSMakePoint(x, y) to:view];
    y -= 30;

    self.updateRateLabel = [self addLabel:@"Update Rate: 0 Hz" at:NSMakePoint(x, y) to:view];

    y -= 60;

    // Daemon control
    NSTextField *daemonTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
    daemonTitle.stringValue = @"Widget Daemon";
    daemonTitle.font = [NSFont boldSystemFontOfSize:16];
    daemonTitle.editable = NO;
    daemonTitle.bezeled = NO;
    daemonTitle.backgroundColor = [NSColor clearColor];
    [view addSubview:daemonTitle];

    y -= 40;

    self.daemonToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 200, 24)];
    self.daemonToggle.buttonType = NSButtonTypeSwitch;
    self.daemonToggle.title = @"Enable Widget Daemon";
    self.daemonToggle.target = self;
    self.daemonToggle.action = @selector(toggleDaemon:);
    [view addSubview:self.daemonToggle];

    y -= 40;

    [self addLabel:@"Update Mode:" at:NSMakePoint(x, y) to:view];
    self.updateModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 120, y, 200, 24)];
    [self.updateModeMenu addItemsWithTitles:@[@"Event-driven", @"Polling", @"Hybrid"]];
    [view addSubview:self.updateModeMenu];

    // Update performance stats
    [self updatePerformanceStats];

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (void)buildPreviewBar {
    self.previewBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.window.frame.size.width, 50)];
    self.previewBar.wantsLayer = YES;
    self.previewBar.layer.backgroundColor = [[NSColor darkGrayColor] CGColor];

    // Add sample widgets to preview
    CGFloat x = 20;

    // Apple icon
    NSTextField *appleIcon = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 15, 30, 20)];
    appleIcon.stringValue = @"";
    appleIcon.font = [NSFont fontWithName:@"Symbols Nerd Font" size:16];
    appleIcon.textColor = [NSColor whiteColor];
    appleIcon.editable = NO;
    appleIcon.bezeled = NO;
    appleIcon.backgroundColor = [NSColor clearColor];
    [self.previewBar addSubview:appleIcon];

    x += 50;

    // Clock
    NSTextField *clock = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 15, 60, 20)];
    clock.stringValue = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                        dateStyle:NSDateFormatterNoStyle
                                                        timeStyle:NSDateFormatterShortStyle];
    clock.font = [NSFont systemFontOfSize:12];
    clock.textColor = [NSColor whiteColor];
    clock.editable = NO;
    clock.bezeled = NO;
    clock.backgroundColor = [NSColor clearColor];
    [self.previewBar addSubview:clock];

    [self.window.contentView addSubview:self.previewBar];
}

- (void)buildControlButtons {
    CGFloat buttonWidth = 100;
    CGFloat buttonHeight = 30;
    CGFloat spacing = 20;
    CGFloat x = self.window.frame.size.width - (buttonWidth * 3 + spacing * 2 + 20);
    CGFloat y = self.window.frame.size.height - 40;

    // Apply button
    NSButton *applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, buttonWidth, buttonHeight)];
    applyButton.title = @"Apply";
    applyButton.target = self;
    applyButton.action = @selector(applyChanges:);
    [self.window.contentView addSubview:applyButton];

    x += buttonWidth + spacing;

    // Save button
    NSButton *saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, buttonWidth, buttonHeight)];
    saveButton.title = @"Save";
    saveButton.target = self;
    saveButton.action = @selector(saveChanges:);
    [self.window.contentView addSubview:saveButton];

    x += buttonWidth + spacing;

    // Reload button
    NSButton *reloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, buttonWidth, buttonHeight)];
    reloadButton.title = @"Reload Bar";
    reloadButton.target = self;
    reloadButton.action = @selector(reloadBar:);
    [self.window.contentView addSubview:reloadButton];
}

// Helper methods
- (NSTextField *)addLabel:(NSString *)text at:(NSPoint)point to:(NSView *)parent {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(point.x, point.y, 200, 20)];
    label.stringValue = text;
    label.editable = NO;
    label.bezeled = NO;
    label.backgroundColor = [NSColor clearColor];
    [parent addSubview:label];
    return label;
}

- (NSSlider *)addSlider:(NSRect)frame min:(double)min max:(double)max to:(NSView *)parent {
    NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
    slider.minValue = min;
    slider.maxValue = max;
    slider.target = self;
    slider.action = @selector(sliderChanged:);
    [parent addSubview:slider];
    return slider;
}

- (void)loadWidgetsData {
    self.widgetsData = [NSMutableArray array];

    NSArray *widgets = @[@"system_info", @"network", @"clock", @"volume", @"battery"];
    for (NSString *widget in widgets) {
        NSMutableDictionary *data = [NSMutableDictionary dictionary];
        data[@"name"] = widget;
        data[@"enabled"] = self.state[@"widgets"][widget] ?: @YES;
        data[@"icon"] = @""; // Will be loaded from icon manager
        [self.widgetsData addObject:data];
    }

    [self.widgetsTable reloadData];
}

- (void)loadSpacesData {
    self.spacesData = [NSMutableArray array];

    for (int i = 1; i <= 10; i++) {
        NSMutableDictionary *space = [NSMutableDictionary dictionary];
        space[@"number"] = @(i);
        space[@"icon"] = self.state[@"space_icons"][[NSString stringWithFormat:@"%d", i]] ?: @"";
        space[@"mode"] = self.state[@"space_modes"][[NSString stringWithFormat:@"%d", i]] ?: @"float";
        [self.spacesData addObject:space];
    }

    [self.spacesCollection reloadData];
}

- (void)updatePerformanceStats {
    // Call widget_manager to get stats
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self.helpersPath stringByAppendingPathComponent:@"widget_manager"];
    task.arguments = @[@"stats"];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse and update labels
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"CPU Usage:"]) {
            self.cpuUsageLabel.stringValue = line;
        } else if ([line containsString:@"Memory Usage:"]) {
            self.memoryUsageLabel.stringValue = line;
        }
    }
}

- (void)updatePreview {
    // Update preview bar with current settings
    if (self.barColorWell.color) {
        self.previewBar.layer.backgroundColor = [self.barColorWell.color CGColor];
    }

    CGFloat height = self.barHeightSlider ? self.barHeightSlider.intValue : 28;
    NSRect frame = self.previewBar.frame;
    frame.size.height = height;
    self.previewBar.frame = frame;
}

// Action methods
- (void)applyChanges:(id)sender {
    // Update appearance
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self.helpersPath stringByAppendingPathComponent:@"state_manager"];

    NSMutableArray *args = [NSMutableArray array];
    [args addObject:@"appearance"];
    [args addObject:@"bar_height"];
    [args addObject:[NSString stringWithFormat:@"%d", (int)self.barHeightSlider.intValue]];

    task.arguments = args;
    [task launch];
    [task waitUntilExit];

    // Apply to SketchyBar
    NSTask *sbarTask = [[NSTask alloc] init];
    sbarTask.launchPath = @"/usr/local/bin/sketchybar";
    sbarTask.arguments = @[@"--bar",
                          [NSString stringWithFormat:@"height=%d", (int)self.barHeightSlider.intValue],
                          [NSString stringWithFormat:@"corner_radius=%d", (int)self.cornerRadiusSlider.intValue]];
    [sbarTask launch];
}

- (void)saveChanges:(id)sender {
    // Save all changes to state
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = [self.helpersPath stringByAppendingPathComponent:@"state_manager"];
    task.arguments = @[@"save"];
    [task launch];
    [task waitUntilExit];
}

- (void)reloadBar:(id)sender {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/local/bin/sketchybar";
    task.arguments = @[@"--reload"];
    [task launch];
}

- (void)toggleDaemon:(id)sender {
    if (self.daemonToggle.state == NSControlStateValueOn) {
        // Start daemon
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = [self.helpersPath stringByAppendingPathComponent:@"widget_manager"];
        task.arguments = @[@"daemon"];
        [task launch];
    } else {
        // Stop daemon
        system("pkill -f 'widget_manager daemon'");
    }
}

- (void)searchIcons:(id)sender {
    [self.iconPicker loadIcons];
}

- (void)filterIcons:(id)sender {
    // Filter icons by category
}

- (void)importIcons:(id)sender {
    // Import icon pack
}

- (void)exportIcons:(id)sender {
    // Export current icons
}

- (void)sliderChanged:(id)sender {
    [self updatePreview];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.previewTimer invalidate];
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        EnhancedMenuController *controller = [[EnhancedMenuController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}