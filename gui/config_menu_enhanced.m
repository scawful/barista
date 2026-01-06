#import "ConfigurationManager.h"
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

@interface EnhancedMenuController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate>
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

// Launch Agents Tab
@property (strong) NSTableView *launchAgentsTable;
@property (strong) NSSearchField *launchAgentSearchField;
@property (strong) NSTextField *launchAgentStatusLabel;
@property (strong) NSButton *startAgentButton;
@property (strong) NSButton *stopAgentButton;
@property (strong) NSButton *restartAgentButton;
@property (strong) NSMutableArray *launchAgents;
@property (strong) NSArray *filteredLaunchAgents;

// Debug Tab
@property (strong) NSButton *debugVerboseToggle;
@property (strong) NSButton *debugHotloadToggle;
@property (strong) NSButton *debugMenuHoverToggle;
@property (strong) NSSlider *debugRefreshSlider;
@property (strong) NSTextField *debugRefreshLabel;
@property (strong) NSTextField *debugStatusLabel;

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
    ConfigurationManager *config = [ConfigurationManager sharedManager];
    self.configPath = config.configPath;
    self.scriptsPath = config.scriptsPath;
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
    self.launchAgents = [NSMutableArray array];
    self.filteredLaunchAgents = @[];

    // Add tabs
    [self buildAppearanceTab];
    [self buildWidgetsTab];
    [self buildIconsTab];
    [self buildSpacesTab];
    [self buildPerformanceTab];
    [self buildLaunchAgentsTab];
    [self buildDebugTab];

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

- (void)buildLaunchAgentsTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Launch Agents";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    self.launchAgentSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(30, 700, 320, 24)];
    self.launchAgentSearchField.placeholderString = @"Filter by label or path";
    self.launchAgentSearchField.target = self;
    self.launchAgentSearchField.action = @selector(filterLaunchAgents:);
    [view addSubview:self.launchAgentSearchField];

    NSButton *refreshButton = [[NSButton alloc] initWithFrame:NSMakeRect(370, 700, 100, 24)];
    refreshButton.title = @"Refresh";
    refreshButton.target = self;
    refreshButton.action = @selector(loadLaunchAgents:);
    [view addSubview:refreshButton];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 120, 900, 560)];
    scrollView.hasVerticalScroller = YES;
    self.launchAgentsTable = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    self.launchAgentsTable.delegate = self;
    self.launchAgentsTable.dataSource = self;
    self.launchAgentsTable.rowHeight = 26.0;

    NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
    stateColumn.title = @"State";
    stateColumn.width = 140;
    [self.launchAgentsTable addTableColumn:stateColumn];

    NSTableColumn *labelColumn = [[NSTableColumn alloc] initWithIdentifier:@"label"];
    labelColumn.title = @"Label";
    labelColumn.width = 320;
    [self.launchAgentsTable addTableColumn:labelColumn];

    NSTableColumn *pidColumn = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
    pidColumn.title = @"PID";
    pidColumn.width = 80;
    [self.launchAgentsTable addTableColumn:pidColumn];

    NSTableColumn *statusColumn = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusColumn.title = @"Exit Status";
    statusColumn.width = 160;
    [self.launchAgentsTable addTableColumn:statusColumn];

    NSTableColumn *plistColumn = [[NSTableColumn alloc] initWithIdentifier:@"plist"];
    plistColumn.title = @"Plist";
    plistColumn.width = 180;
    [self.launchAgentsTable addTableColumn:plistColumn];

    scrollView.documentView = self.launchAgentsTable;
    [view addSubview:scrollView];

    CGFloat buttonY = 200;
    self.startAgentButton = [[NSButton alloc] initWithFrame:NSMakeRect(960, buttonY + 120, 160, 32)];
    self.startAgentButton.title = @"Start";
    self.startAgentButton.target = self;
    self.startAgentButton.action = @selector(startSelectedLaunchAgent:);
    [view addSubview:self.startAgentButton];

    self.stopAgentButton = [[NSButton alloc] initWithFrame:NSMakeRect(960, buttonY + 70, 160, 32)];
    self.stopAgentButton.title = @"Stop";
    self.stopAgentButton.target = self;
    self.stopAgentButton.action = @selector(stopSelectedLaunchAgent:);
    [view addSubview:self.stopAgentButton];

    self.restartAgentButton = [[NSButton alloc] initWithFrame:NSMakeRect(960, buttonY + 20, 160, 32)];
    self.restartAgentButton.title = @"Restart";
    self.restartAgentButton.target = self;
    self.restartAgentButton.action = @selector(restartSelectedLaunchAgent:);
    [view addSubview:self.restartAgentButton];

    self.launchAgentStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 80, 1090, 24)];
    self.launchAgentStatusLabel.editable = NO;
    self.launchAgentStatusLabel.bezeled = NO;
    self.launchAgentStatusLabel.backgroundColor = [NSColor clearColor];
    self.launchAgentStatusLabel.stringValue = @"No agents loaded.";
    [view addSubview:self.launchAgentStatusLabel];

    tab.view = view;
    [self.tabView addTabViewItem:tab];

    [self loadLaunchAgents:nil];
}

- (void)buildDebugTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] init];
    tab.label = @"Debug";

    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];

    CGFloat x = 60;
    CGFloat y = 680;

    NSTextField *togglesTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 24)];
    togglesTitle.stringValue = @"Runtime Toggles";
    togglesTitle.font = [NSFont boldSystemFontOfSize:16];
    togglesTitle.editable = NO;
    togglesTitle.bezeled = NO;
    togglesTitle.backgroundColor = [NSColor clearColor];
    [view addSubview:togglesTitle];

    y -= 40;
    self.debugVerboseToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
    self.debugVerboseToggle.buttonType = NSButtonTypeSwitch;
    self.debugVerboseToggle.title = @"Verbose logging";
    self.debugVerboseToggle.identifier = @"verbose_logging";
    self.debugVerboseToggle.target = self;
    self.debugVerboseToggle.action = @selector(toggleDebugOption:);
    [view addSubview:self.debugVerboseToggle];

    y -= 30;
    self.debugHotloadToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
    self.debugHotloadToggle.buttonType = NSButtonTypeSwitch;
    self.debugHotloadToggle.title = @"Enable hotload";
    self.debugHotloadToggle.identifier = @"hotload_enabled";
    self.debugHotloadToggle.target = self;
    self.debugHotloadToggle.action = @selector(toggleDebugOption:);
    [view addSubview:self.debugHotloadToggle];

    y -= 30;
    self.debugMenuHoverToggle = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, 260, 24)];
    self.debugMenuHoverToggle.buttonType = NSButtonTypeSwitch;
    self.debugMenuHoverToggle.title = @"Popup hover outline";
    self.debugMenuHoverToggle.identifier = @"popup_debug";
    self.debugMenuHoverToggle.target = self;
    self.debugMenuHoverToggle.action = @selector(toggleDebugOption:);
    [view addSubview:self.debugMenuHoverToggle];

    y -= 60;
    [self addLabel:@"Widget Refresh (ms):" at:NSMakePoint(x, y) to:view];
    self.debugRefreshSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(x + 200, y, 200, 24)];
    self.debugRefreshSlider.minValue = 100;
    self.debugRefreshSlider.maxValue = 2000;
    self.debugRefreshSlider.target = self;
    self.debugRefreshSlider.action = @selector(debugRefreshChanged:);
    [view addSubview:self.debugRefreshSlider];

    self.debugRefreshLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 420, y, 80, 24)];
    self.debugRefreshLabel.editable = NO;
    self.debugRefreshLabel.bezeled = NO;
    self.debugRefreshLabel.backgroundColor = [NSColor clearColor];
    self.debugRefreshLabel.stringValue = @"0 ms";
    [view addSubview:self.debugRefreshLabel];

    CGFloat buttonY = 320;
    NSButton *rebuildButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 120, 200, 32)];
    rebuildButton.title = @"Rebuild & Reload";
    rebuildButton.target = self;
    rebuildButton.action = @selector(rebuildAndReload:);
    [view addSubview:rebuildButton];

    NSButton *logsButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 70, 200, 32)];
    logsButton.title = @"Open Logs";
    logsButton.target = self;
    logsButton.action = @selector(openLogs:);
    [view addSubview:logsButton];

    NSButton *flushButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, buttonY + 20, 200, 32)];
    flushButton.title = @"Flush Menu Cache";
    flushButton.target = self;
    flushButton.action = @selector(flushMenuCache:);
    [view addSubview:flushButton];

    CGFloat wmX = x + 240;
    CGFloat wmTitleY = buttonY + 170;
    NSTextField *wmTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(wmX, wmTitleY, 260, 24)];
    wmTitle.stringValue = @"Window Manager";
    wmTitle.font = [NSFont boldSystemFontOfSize:14];
    wmTitle.editable = NO;
    wmTitle.bezeled = NO;
    wmTitle.backgroundColor = [NSColor clearColor];
    [view addSubview:wmTitle];

    NSButton *restartYabaiButton = [[NSButton alloc] initWithFrame:NSMakeRect(wmX, wmTitleY - 40, 220, 28)];
    restartYabaiButton.title = @"Restart Yabai";
    restartYabaiButton.target = self;
    restartYabaiButton.action = @selector(restartYabai:);
    [view addSubview:restartYabaiButton];

    NSButton *restartSkhdButton = [[NSButton alloc] initWithFrame:NSMakeRect(wmX, wmTitleY - 75, 220, 28)];
    restartSkhdButton.title = @"Restart Skhd";
    restartSkhdButton.target = self;
    restartSkhdButton.action = @selector(restartSkhd:);
    [view addSubview:restartSkhdButton];

    NSButton *doctorButton = [[NSButton alloc] initWithFrame:NSMakeRect(wmX, wmTitleY - 110, 220, 28)];
    doctorButton.title = @"Space Switch Diagnostics";
    doctorButton.target = self;
    doctorButton.action = @selector(runYabaiDoctor:);
    [view addSubview:doctorButton];

    NSButton *openSkhdButton = [[NSButton alloc] initWithFrame:NSMakeRect(wmX, wmTitleY - 145, 220, 28)];
    openSkhdButton.title = @"Open skhdrc";
    openSkhdButton.target = self;
    openSkhdButton.action = @selector(openSkhdConfig:);
    [view addSubview:openSkhdButton];

    NSButton *openYabaiButton = [[NSButton alloc] initWithFrame:NSMakeRect(wmX, wmTitleY - 180, 220, 28)];
    openYabaiButton.title = @"Open yabairc";
    openYabaiButton.target = self;
    openYabaiButton.action = @selector(openYabaiConfig:);
    [view addSubview:openYabaiButton];

    self.debugStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 180, 900, 24)];
    self.debugStatusLabel.editable = NO;
    self.debugStatusLabel.bezeled = NO;
    self.debugStatusLabel.backgroundColor = [NSColor clearColor];
    self.debugStatusLabel.stringValue = @"Ready.";
    [view addSubview:self.debugStatusLabel];

    [self loadDebugDefaults];

    tab.view = view;
    [self.tabView addTabViewItem:tab];
}

- (NSString *)launchAgentHelperPath {
    return [self.configPath stringByAppendingPathComponent:@"helpers/launch_agent_manager.sh"];
}

- (void)loadLaunchAgents:(id)sender {
    NSString *helper = [self.launchAgentHelperPath stringByStandardizingPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
        self.launchAgentStatusLabel.stringValue = @"helpers/launch_agent_manager.sh not found (build agent helper first).";
        self.launchAgents = [NSMutableArray array];
        self.filteredLaunchAgents = @[];
        [self.launchAgentsTable reloadData];
        [self updateLaunchAgentButtons];
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = helper;
    task.arguments = @[@"list"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (task.terminationStatus != 0) {
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        self.launchAgentStatusLabel.stringValue = output.length ? output : @"Failed to list launch agents.";
        return;
    }

    NSError *error = nil;
    NSArray *agents = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (!agents || ![agents isKindOfClass:[NSArray class]]) {
        self.launchAgentStatusLabel.stringValue = @"Unable to parse launch agent JSON.";
        return;
    }

    self.launchAgents = [agents mutableCopy];
    [self applyLaunchAgentFilter];
}

- (void)filterLaunchAgents:(id)sender {
    [self applyLaunchAgentFilter];
}

- (void)applyLaunchAgentFilter {
    NSString *query = [[self.launchAgentSearchField stringValue] lowercaseString];
    if (!query) { query = @""; }

    if (query.length == 0) {
        self.filteredLaunchAgents = [self.launchAgents copy];
    } else {
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *agent in self.launchAgents) {
            NSString *label = [[agent[@"label"] description] lowercaseString];
            NSString *plist = [[agent[@"plist"] description] lowercaseString];
            if ((label && [label containsString:query]) || (plist && [plist containsString:query])) {
                [filtered addObject:agent];
            }
        }
        self.filteredLaunchAgents = filtered;
    }
    [self.launchAgentsTable reloadData];
    [self updateLaunchAgentButtons];
    self.launchAgentStatusLabel.stringValue = [NSString stringWithFormat:@"%lu agents", (unsigned long)self.filteredLaunchAgents.count];
}

- (NSDictionary *)selectedLaunchAgent {
    NSInteger row = self.launchAgentsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredLaunchAgents.count) {
        return nil;
    }
    return self.filteredLaunchAgents[row];
}

- (void)startSelectedLaunchAgent:(id)sender {
    NSDictionary *agent = [[self selectedLaunchAgent] copy];
    if (!agent) return;
    [self runLaunchAgentCommand:@[@"start", agent[@"label"] ?: @""] successMessage:@"Agent started."];
}

- (void)stopSelectedLaunchAgent:(id)sender {
    NSDictionary *agent = [[self selectedLaunchAgent] copy];
    if (!agent) return;
    [self runLaunchAgentCommand:@[@"stop", agent[@"label"] ?: @""] successMessage:@"Agent stopped."];
}

- (void)restartSelectedLaunchAgent:(id)sender {
    NSDictionary *agent = [[self selectedLaunchAgent] copy];
    if (!agent) return;
    [self runLaunchAgentCommand:@[@"restart", agent[@"label"] ?: @""] successMessage:@"Agent restarted."];
}

- (void)runLaunchAgentCommand:(NSArray<NSString *> *)arguments successMessage:(NSString *)message {
    NSString *helper = [self.launchAgentHelperPath stringByStandardizingPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
        self.launchAgentStatusLabel.stringValue = @"launch_agent_manager.sh not found.";
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = helper;
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus == 0) {
        self.launchAgentStatusLabel.stringValue = output.length ? [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : message;
        [self loadLaunchAgents:nil];
    } else {
        self.launchAgentStatusLabel.stringValue = output.length ? output : @"Command failed.";
    }
}

- (void)updateLaunchAgentButtons {
    NSDictionary *agent = [self selectedLaunchAgent];
    if (!agent) {
        self.startAgentButton.enabled = NO;
        self.stopAgentButton.enabled = NO;
        self.restartAgentButton.enabled = NO;
        return;
    }
    BOOL running = [agent[@"running"] boolValue];
    self.startAgentButton.enabled = !running;
    self.stopAgentButton.enabled = running;
    self.restartAgentButton.enabled = YES;
}

- (void)loadDebugDefaults {
    NSMutableDictionary *debug = [self debugState];
    BOOL verbose = [debug[@"verbose_logging"] boolValue];
    BOOL hotload = [debug[@"hotload_enabled"] boolValue];
    BOOL popup = [debug[@"popup_debug"] boolValue];
    double refresh = debug[@"widget_refresh_ms"] ? [debug[@"widget_refresh_ms"] doubleValue] : 500.0;

    self.debugVerboseToggle.state = verbose ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugHotloadToggle.state = hotload ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugMenuHoverToggle.state = popup ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugRefreshSlider.doubleValue = refresh;
    self.debugRefreshLabel.stringValue = [NSString stringWithFormat:@"%.0f ms", refresh];
}

- (NSMutableDictionary *)debugState {
    NSMutableDictionary *debug = self.state[@"debug"];
    if (!debug) {
        debug = [NSMutableDictionary dictionary];
        self.state[@"debug"] = debug;
    }
    return debug;
}

- (void)toggleDebugOption:(NSButton *)sender {
    if (!sender.identifier) {
        return;
    }
    BOOL enabled = (sender.state == NSControlStateValueOn);
    NSMutableDictionary *debug = [self debugState];
    debug[sender.identifier] = @(enabled);
    [self persistStateToDisk];
    self.debugStatusLabel.stringValue = [NSString stringWithFormat:@"%@ %@", sender.title, enabled ? @"enabled" : @"disabled"];

    if ([sender.identifier isEqualToString:@"hotload_enabled"]) {
        [self runSketchybarCommand:@[@"--hotload", enabled ? @"on" : @"off"]];
    }
}

- (void)debugRefreshChanged:(id)sender {
    double value = self.debugRefreshSlider.doubleValue;
    self.debugRefreshLabel.stringValue = [NSString stringWithFormat:@"%.0f ms", value];
    NSMutableDictionary *debug = [self debugState];
    debug[@"widget_refresh_ms"] = @(value);
    [self persistStateToDisk];
}

- (void)persistStateToDisk {
    NSString *statePath = [self.configPath stringByAppendingPathComponent:@"state.json"];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.state options:NSJSONWritingPrettyPrinted error:&error];
    if (data) {
        [data writeToFile:statePath atomically:YES];
    }
}

- (NSString *)runTask:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus != 0 && output.length == 0) {
        output = [NSString stringWithFormat:@"%@ exited with %d", [launchPath lastPathComponent], task.terminationStatus];
    }
    return output;
}

- (void)rebuildAndReload:(id)sender {
    NSString *helpersDir = [self.configPath stringByAppendingPathComponent:@"helpers"];
    NSString *guiDir = [self.configPath stringByAppendingPathComponent:@"gui"];
    NSMutableArray *messages = [NSMutableArray array];

    if ([[NSFileManager defaultManager] fileExistsAtPath:helpersDir]) {
        NSString *msg = [self runTask:@"/usr/bin/make" arguments:@[@"-C", helpersDir, @"all"]];
        [messages addObject:msg];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:guiDir]) {
        NSString *msg = [self runTask:@"/usr/bin/make" arguments:@[@"-C", guiDir, @"all"]];
        [messages addObject:msg];
    }

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:[self launchAgentHelperPath]]) {
        [self runLaunchAgentCommand:@[@"restart", @"homebrew.mxcl.sketchybar"] successMessage:@"SketchyBar restarted via launch agent."];
    } else {
        NSString *reloadMsg = [self runTask:@"/opt/homebrew/opt/sketchybar/bin/sketchybar" arguments:@[@"--reload"]];
        [messages addObject:reloadMsg];
    }

    self.debugStatusLabel.stringValue = [messages componentsJoinedByString:@" • "];
}

- (void)openLogs:(id)sender {
    NSString *pluginScript = [self.configPath stringByAppendingPathComponent:@"plugins/bar_logs.sh"];
    NSString *logScript = pluginScript;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:logScript]) {
        NSString *legacyScript = [self.scriptsPath stringByAppendingPathComponent:@"bar_logs.sh"];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:legacyScript]) {
            logScript = legacyScript;
        } else {
            self.debugStatusLabel.stringValue = @"bar_logs.sh not found in plugins or scripts.";
            return;
        }
    }
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = logScript;
    task.arguments = @[@"sketchybar", @"80"];
    [task launch];
    self.debugStatusLabel.stringValue = @"Streaming logs via bar_logs.sh (check Terminal).";
}

- (void)flushMenuCache:(id)sender {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-lc", @"rm -f /tmp/sketchybar_menu_*.cache 2>/dev/null || true"];
    [task launch];
    [task waitUntilExit];
    self.debugStatusLabel.stringValue = @"Cleared cached menu render files.";
}

- (void)restartYabai:(id)sender {
    NSString *output = [self runTask:@"/bin/bash" arguments:@[@"-lc", @"yabai --restart-service 2>&1 || brew services restart yabai 2>&1"]];
    self.debugStatusLabel.stringValue = output.length ? [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"yabai restarted.";
}

- (void)restartSkhd:(id)sender {
    NSString *output = [self runTask:@"/bin/bash" arguments:@[@"-lc", @"skhd --restart-service 2>&1 || brew services restart skhd 2>&1"]];
    self.debugStatusLabel.stringValue = output.length ? [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"skhd restarted.";
}

- (void)runYabaiDoctor:(id)sender {
    NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"yabai_control.sh"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
        NSString *path = self.scriptsPath ?: @"(unknown scripts directory)";
        self.debugStatusLabel.stringValue = [NSString stringWithFormat:@"yabai_control.sh not found in %@", path];
        return;
    }
    NSString *output = [self runTask:script arguments:@[@"doctor"]];
    self.debugStatusLabel.stringValue = output.length ? [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"Diagnostics complete.";
}

- (void)openSkhdConfig:(id)sender {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/skhd/skhdrc"];
    [self runTask:@"/usr/bin/open" arguments:@[path]];
    self.debugStatusLabel.stringValue = @"Opened skhdrc.";
}

- (void)openYabaiConfig:(id)sender {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/yabai/yabairc"];
    [self runTask:@"/usr/bin/open" arguments:@[path]];
    self.debugStatusLabel.stringValue = @"Opened yabairc.";
}

- (void)runSketchybarCommand:(NSArray<NSString *> *)arguments {
    NSString *binary = @"/opt/homebrew/opt/sketchybar/bin/sketchybar";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:binary]) {
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = binary;
    task.arguments = arguments;
    [task launch];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.launchAgentsTable) {
        return self.filteredLaunchAgents.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.launchAgentsTable) {
        return nil;
    }
    NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 24)];
        NSTextField *textField = [[NSTextField alloc] initWithFrame:cell.bounds];
        textField.autoresizingMask = NSViewWidthSizable;
        textField.editable = NO;
        textField.bezeled = NO;
        textField.backgroundColor = [NSColor clearColor];
        textField.font = [NSFont systemFontOfSize:12];
        cell.textField = textField;
        cell.identifier = tableColumn.identifier;
        [cell addSubview:textField];
    }

    NSDictionary *agent = self.filteredLaunchAgents[row];
    NSString *value = @"";
    if ([tableColumn.identifier isEqualToString:@"state"]) {
        BOOL running = [agent[@"running"] boolValue];
        value = running ? @"● Running" : @"○ Stopped";
    } else if ([tableColumn.identifier isEqualToString:@"label"]) {
        value = [agent[@"label"] description] ?: @"";
    } else if ([tableColumn.identifier isEqualToString:@"pid"]) {
        id pid = agent[@"pid"];
        value = (pid && pid != [NSNull null]) ? [pid stringValue] : @"—";
    } else if ([tableColumn.identifier isEqualToString:@"status"]) {
        id status = agent[@"status"];
        if (!status || status == [NSNull null]) {
            value = @"—";
        } else if ([status isKindOfClass:[NSNumber class]]) {
            value = [NSString stringWithFormat:@"%@", status];
        } else {
            value = [status description];
        }
    } else if ([tableColumn.identifier isEqualToString:@"plist"]) {
        value = [[agent[@"plist"] description] stringByAbbreviatingWithTildeInPath] ?: @"";
    }
    cell.textField.stringValue = value ?: @"";
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.launchAgentsTable) {
        [self updateLaunchAgentButtons];
    }
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
