#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface MenuController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate>
@property (strong) NSWindow *window;
@property (strong) NSDictionary<NSNumber *, NSString *> *widgetMap;
@property (strong) NSSlider *heightSlider;
@property (strong) NSSlider *cornerSlider;
@property (strong) NSPopUpButton *colorMenu;
@property (strong) NSSegmentedControl *shortcutToggle;
@property (strong) NSPopUpButton *widgetSelector;
@property (strong) NSPopUpButton *widgetColorMenu;
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconAppField;
@property (strong) NSTextField *iconGlyphField;
@property (strong) NSTextField *spaceIconField;
@property (strong) NSPopUpButton *clockFontMenu;
@property (strong) NSPopUpButton *appleIconMenu;
@property (strong) NSPopUpButton *questIconMenu;
@property (strong) NSPopUpButton *iconLibraryMenu;
@property (strong) NSDictionary<NSNumber *, NSString *> *systemInfoMap;
@property (strong) NSSlider *scaleSlider;
@property (strong) NSTextField *scaleValueLabel;
@property (strong) NSTextField *iconPreviewField;
@property (strong) NSTextField *spaceIconPreviewField;
@property (strong) NSColorWell *barColorWell;
@property (strong) NSTextField *barColorHexField;
@property (strong) NSColorWell *widgetColorWell;
@property (strong) NSTextField *widgetColorHexField;
@property (strong) NSTextField *appleIconPreviewField;
@property (strong) NSTextField *questIconPreviewField;
@property (strong) NSDictionary *workflowData;
@property (strong) NSTextField *clockFontFamilyField;
@property (copy) NSString *configPath;
@property (copy) NSString *codePath;
@property (strong) NSButton *yazeToggleButton;
@property (strong) NSButton *emacsToggleButton;
@property (strong) NSTextField *yazeStatusField;
@property (strong) NSTextField *emacsStatusField;
@property (strong) NSButton *yazeLaunchButton;
@property (strong) NSButton *emacsLaunchButton;
@property (copy) NSString *scriptsPath;
@property (copy) NSString *statePath;
@property (strong) NSDictionary *state;
@property (strong) NSArray<NSDictionary *> *iconLibrary;
@end

@implementation MenuController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  self.scriptsPath = config.scriptsPath;
  self.configPath = config.configPath;
  self.codePath = config.codePath;
  self.statePath = config.statePath;
  self.workflowData = [self loadWorkflowData];
  [self refreshState];
  [self buildWindow];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

- (NSDictionary *)loadState {
  NSData *data = [NSData dataWithContentsOfFile:self.statePath];
  if (!data) return @{};
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return json;
}

- (void)refreshState {
  self.state = [self loadState];
}

- (void)refreshStateAsync:(dispatch_block_t)completion {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self refreshState];
    if (completion) {
      completion();
    }
  });
}

- (void)buildWindow {
  NSRect frame = NSMakeRect(0, 0, 1280, 880);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  [self.window setTitle:@"Sketchybar Controls"];
  [self.window setLevel:NSFloatingWindowLevel];
  self.window.delegate = self;
  [self.window setMinSize:NSMakeSize(1080, 760)];
  [self.window center];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSNoBorder;
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  CGFloat documentHeight = frame.size.height + 360.0;
  CGFloat documentWidth = frame.size.width - 40.0;
  NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, documentWidth, documentHeight)];
  content.autoresizingMask = NSViewWidthSizable;
  scrollView.documentView = content;
  [self.window setContentView:scrollView];

  CGFloat columnSpacing = 20.0;
  CGFloat columnWidth = (content.bounds.size.width - columnSpacing * 4) / 3.0;
  CGFloat columnX[3] = {
    columnSpacing,
    columnSpacing * 2 + columnWidth,
    columnSpacing * 3 + columnWidth * 2
  };
  __block NSMutableArray<NSNumber *> *columnOrigins = [NSMutableArray arrayWithObjects:
    @(content.bounds.size.height - columnSpacing),
    @(content.bounds.size.height - columnSpacing),
    @(content.bounds.size.height - columnSpacing),
    nil
  ];
  CGFloat (^nextBoxOriginY)(NSInteger column, CGFloat height) = ^CGFloat(NSInteger column, CGFloat height) {
    if (column < 0 || column >= columnOrigins.count) {
      return content.bounds.size.height - columnSpacing - height;
    }
    CGFloat current = columnOrigins[column].doubleValue - height;
    columnOrigins[column] = @(current - columnSpacing);
    return current;
  };

  self.iconLibrary = @[
    // System & Hardware (VERIFIED Nerd Font glyphs)
    @{ @"title": @"Apple", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F179" },
    @{ @"title": @"Apple Alt", @"glyph": @"", @"font": @"Devicons", @"code": @"E711" },
    @{ @"title": @"CPU", @"glyph": @"󰻠", @"font": @"Material Design", @"code": @"F0EE0" },
    @{ @"title": @"CPU Chip", @"glyph": @"󰍛", @"font": @"Material Design", @"code": @"F035B" },
    @{ @"title": @"CPU Hot", @"glyph": @"󰈸", @"font": @"Material Design", @"code": @"F0238" },
    @{ @"title": @"CPU Warm", @"glyph": @"󰔄", @"font": @"Material Design", @"code": @"F0504" },
    @{ @"title": @"Memory", @"glyph": @"󰘚", @"font": @"Material Design", @"code": @"F061A" },
    @{ @"title": @"Disk", @"glyph": @"󰋊", @"font": @"Material Design", @"code": @"F02CA" },
    @{ @"title": @"Network", @"glyph": @"󰖩", @"font": @"Material Design", @"code": @"F05A9" },
    @{ @"title": @"Network Off", @"glyph": @"󰖪", @"font": @"Material Design", @"code": @"F05AA" },
    @{ @"title": @"Battery", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F240" },
    @{ @"title": @"Volume", @"glyph": @"󰕾", @"font": @"Material Design", @"code": @"F057E" },
    @{ @"title": @"Settings", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F013" },
    // Development
    @{ @"title": @"Terminal", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F120" },
    @{ @"title": @"Code", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F121" },
    @{ @"title": @"Git", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F1D3" },
    @{ @"title": @"GitHub", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F113" },
    @{ @"title": @"VSCode", @"glyph": @"󰨞", @"font": @"Material Design", @"code": @"F0A1E" },
    @{ @"title": @"Vim", @"glyph": @"", @"font": @"Seti", @"code": @"E62B" },
    @{ @"title": @"Emacs", @"glyph": @"", @"font": @"Seti", @"code": @"E632" },
    // Files & Folders
    @{ @"title": @"Folder", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F07B" },
    @{ @"title": @"Folder Open", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F07C" },
    @{ @"title": @"File", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F15B" },
    @{ @"title": @"Finder", @"glyph": @"󰀶", @"font": @"Material Design", @"code": @"F0036" },
    @{ @"title": @"Document", @"glyph": @"󰈙", @"font": @"Material Design", @"code": @"F0219" },
    // Apps
    @{ @"title": @"Safari", @"glyph": @"󰀹", @"font": @"Material Design", @"code": @"F0039" },
    @{ @"title": @"Chrome", @"glyph": @"", @"font": @"Devicons", @"code": @"E743" },
    @{ @"title": @"Firefox", @"glyph": @"", @"font": @"Devicons", @"code": @"E745" },
    @{ @"title": @"Calendar", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F073" },
    @{ @"title": @"Clock", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F017" },
    @{ @"title": @"Music", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F001" },
    @{ @"title": @"Messages", @"glyph": @"󰍦", @"font": @"Material Design", @"code": @"F0366" },
    @{ @"title": @"Mail", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F0E0" },
    // Window Management
    @{ @"title": @"Window BSP/Tile", @"glyph": @"󰆾", @"font": @"Material Design", @"code": @"F01BE" },
    @{ @"title": @"Window Stack", @"glyph": @"󰓩", @"font": @"Material Design", @"code": @"F04E9" },
    @{ @"title": @"Window Float", @"glyph": @"󰒄", @"font": @"Material Design", @"code": @"F0484" },
    @{ @"title": @"Layout Grid", @"glyph": @"󰕰", @"font": @"Material Design", @"code": @"F0570" },
    // Gaming & Entertainment
    @{ @"title": @"Gamepad", @"glyph": @"󰍳", @"font": @"Material Design", @"code": @"F0373" },
    @{ @"title": @"Quest/Goal", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F0B1" },
    @{ @"title": @"Triforce", @"glyph": @"󰊠", @"font": @"Material Design", @"code": @"F02A0" },
    @{ @"title": @"Controller", @"glyph": @"", @"font": @"FontAwesome", @"code": @"F11B" },
    // Misc
    @{ @"title": @"Star", @"glyph": @"" },
    @{ @"title": @"Heart", @"glyph": @"󰣐" },
    @{ @"title": @"Lightning", @"glyph": @"󰷓" },
    @{ @"title": @"Moon", @"glyph": @"󰽤" },
    @{ @"title": @"Sun", @"glyph": @"󰖙" },
    @{ @"title": @"Cloud", @"glyph": @"󰖐" }
  ];
  NSArray *widgets = @[ @"system_info", @"network", @"clock", @"volume", @"battery" ];
  NSArray *labels = @[ @"System Info", @"Network", @"Clock", @"Volume", @"Battery" ];
  self.widgetMap = @{@0:@"system_info", @1:@"network", @2:@"clock", @3:@"volume", @4:@"battery"};

  CGFloat widgetsHeight = 320.0;
  NSBox *widgetsBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[0], nextBoxOriginY(0, widgetsHeight), columnWidth, widgetsHeight)];
  [widgetsBox setTitle:@"Widgets"];
  [content addSubview:widgetsBox];
  NSView *widgetsContent = [widgetsBox contentView];
  CGFloat widgetY = widgetsContent.bounds.size.height - 30;
  for (NSInteger idx = 0; idx < widgets.count; idx++) {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(10, widgetY, 200, 24)];
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.title = labels[idx];
    checkbox.tag = idx;
    checkbox.target = self;
    checkbox.action = @selector(toggleWidget:);
    BOOL enabled = YES;
    NSDictionary *widgetState = self.state[@"widgets"];
    if ([widgetState isKindOfClass:[NSDictionary class]]) {
      id raw = widgetState[widgets[idx]];
      if ([raw isKindOfClass:[NSNumber class]]) {
        enabled = [raw boolValue];
      }
    }
    checkbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [widgetsContent addSubview:checkbox];
    widgetY -= 28;
  }

  self.systemInfoMap = @{@0:@"cpu", @1:@"mem", @2:@"disk", @3:@"net", @4:@"docs", @5:@"actions"};
  CGFloat systemInfoHeight = 140.0;
  NSBox *systemInfoBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[0], nextBoxOriginY(0, systemInfoHeight), columnWidth, systemInfoHeight)];
  [systemInfoBox setTitle:@"System Info Sections"];
  [content addSubview:systemInfoBox];
  NSView *systemInfoContent = [systemInfoBox contentView];
  NSDictionary *infoState = self.state[@"system_info_items"];
  for (NSInteger idx = 0; idx < 6; idx++) {
    NSInteger row = idx / 3;
    NSInteger col = idx % 3;
    CGFloat cellWidth = systemInfoContent.bounds.size.width / 3.0 - 15;
    CGFloat infoX = 10 + (col * (cellWidth + 10));
    CGFloat infoY = systemInfoContent.bounds.size.height - 35 - (row * 32);
    NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(infoX, infoY, cellWidth, 24)];
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.tag = idx;
    checkbox.target = self;
    checkbox.action = @selector(toggleSystemInfo:);
    switch (idx) {
      case 0: checkbox.title = @"CPU"; break;
      case 1: checkbox.title = @"Memory"; break;
      case 2: checkbox.title = @"Disk"; break;
      case 3: checkbox.title = @"Network"; break;
      case 4: checkbox.title = @"Docs"; break;
      case 5: checkbox.title = @"Actions"; break;
    }
    BOOL enabled = YES;
    if ([infoState isKindOfClass:[NSDictionary class]]) {
      id raw = infoState[self.systemInfoMap[@(idx)]];
      if ([raw isKindOfClass:[NSNumber class]]) {
        enabled = [raw boolValue];
      }
    }
    checkbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [systemInfoContent addSubview:checkbox];
  }

  CGFloat iconBoxHeight = 360.0;
  NSBox *iconBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[2], nextBoxOriginY(2, iconBoxHeight), columnWidth, iconBoxHeight)];
  [iconBox setTitle:@"Custom App Icon"];
  [content addSubview:iconBox];
  NSView *iconContent = [iconBox contentView];
  CGFloat iconWidth = iconContent.bounds.size.width - 20;
  CGFloat iconY = iconContent.bounds.size.height - 40;
  self.iconAppField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 24)];
  self.iconAppField.placeholderString = @"Application or Process";
  [iconContent addSubview:self.iconAppField];
  iconY -= 34;
  self.iconGlyphField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 24)];
  self.iconGlyphField.placeholderString = @"Glyph (e.g. 󰊠)";
  self.iconGlyphField.delegate = self;
  [iconContent addSubview:self.iconGlyphField];
  iconY -= 30;
  NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 18)];
  [previewLabel setBezeled:NO];
  [previewLabel setEditable:NO];
  [previewLabel setDrawsBackground:NO];
  [previewLabel setStringValue:@"Font Preview"];
  [iconContent addSubview:previewLabel];
  iconY -= 56;
  self.iconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 48)];
  [self.iconPreviewField setBezeled:NO];
  [self.iconPreviewField setEditable:NO];
  [self.iconPreviewField setDrawsBackground:NO];
  [self.iconPreviewField setAlignment:NSTextAlignmentCenter];
  NSFont *previewFont = [self preferredIconFontWithSize:40.0];
  [self.iconPreviewField setFont:previewFont];
  [iconContent addSubview:self.iconPreviewField];
  iconY -= 26;
  NSTextField *libraryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 18)];
  [libraryLabel setBezeled:NO];
  [libraryLabel setEditable:NO];
  [libraryLabel setDrawsBackground:NO];
  [libraryLabel setStringValue:@"Library Presets"];
  [iconContent addSubview:libraryLabel];
  iconY -= 28;
  self.iconLibraryMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, iconY, iconWidth, 26)];
  NSMenuItem *placeholder = [[NSMenuItem alloc] initWithTitle:@"Choose a preset" action:NULL keyEquivalent:@""];
  placeholder.representedObject = nil;
  [self.iconLibraryMenu.menu addItem:placeholder];
  [self.iconLibraryMenu selectItem:placeholder];
  for (NSDictionary *entry in self.iconLibrary) {
    NSMenuItem *option = [[NSMenuItem alloc] initWithTitle:entry[@"title"] action:nil keyEquivalent:@""];
    option.representedObject = entry[@"glyph"];
    [self.iconLibraryMenu.menu addItem:option];
  }
  self.iconLibraryMenu.target = self;
  self.iconLibraryMenu.action = @selector(iconLibraryChanged:);
  [iconContent addSubview:self.iconLibraryMenu];
  NSButton *openIconBrowser = [[NSButton alloc] initWithFrame:NSMakeRect(10, 82, iconWidth, 28)];
  [openIconBrowser setTitle:@"Browse Icon Library"];
  [openIconBrowser setButtonType:NSButtonTypeMomentaryPushIn];
  [openIconBrowser setBezelStyle:NSBezelStyleRounded];
  openIconBrowser.target = self;
  openIconBrowser.action = @selector(openIconBrowser:);
  [iconContent addSubview:openIconBrowser];
  NSButton *openIconMap = [[NSButton alloc] initWithFrame:NSMakeRect(10, 50, iconWidth, 26)];
  [openIconMap setTitle:@"Open icon_map.json"];
  [openIconMap setButtonType:NSButtonTypeMomentaryPushIn];
  [openIconMap setBezelStyle:NSBezelStyleRounded];
  openIconMap.target = self;
  openIconMap.action = @selector(openIconMap:);
  [iconContent addSubview:openIconMap];
  NSButton *saveIcon = [[NSButton alloc] initWithFrame:NSMakeRect(10, 15, iconWidth, 28)];
  [saveIcon setTitle:@"Save Icon"];
  [saveIcon setButtonType:NSButtonTypeMomentaryPushIn];
  [saveIcon setBezelStyle:NSBezelStyleRounded];
  saveIcon.target = self;
  saveIcon.action = @selector(saveIconMapping:);
  [iconContent addSubview:saveIcon];

  CGFloat spaceIconHeight = 200.0;
  NSBox *spaceIconBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[2], nextBoxOriginY(2, spaceIconHeight), columnWidth, spaceIconHeight)];
  [spaceIconBox setTitle:@"Space Icons"];
  [content addSubview:spaceIconBox];
  NSView *spaceIconContent = [spaceIconBox contentView];
  CGFloat spaceWidth = spaceIconContent.bounds.size.width - 20;
  CGFloat spaceTop = spaceIconContent.bounds.size.height - 40;
  self.spaceSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, spaceTop, 120, 26)];
  for (NSInteger idx = 1; idx <= 10; idx++) {
    [self.spaceSelector addItemWithTitle:[NSString stringWithFormat:@"%ld", (long)idx]];
  }
  self.spaceSelector.target = self;
  self.spaceSelector.action = @selector(spaceSelectionChanged:);
  [spaceIconContent addSubview:self.spaceSelector];
  self.spaceIconField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, spaceTop, spaceWidth - 130, 24)];
  self.spaceIconField.placeholderString = @"Glyph";
  self.spaceIconField.delegate = self;
  [spaceIconContent addSubview:self.spaceIconField];
  spaceTop -= 40;
  NSTextField *spacePreviewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, spaceTop, spaceWidth, 18)];
  [spacePreviewLabel setBezeled:NO];
  [spacePreviewLabel setEditable:NO];
  [spacePreviewLabel setDrawsBackground:NO];
  [spacePreviewLabel setStringValue:@"Preview"];
  [spaceIconContent addSubview:spacePreviewLabel];
  spaceTop -= 46;
  self.spaceIconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, spaceTop, spaceWidth, 40)];
  [self.spaceIconPreviewField setBezeled:NO];
  [self.spaceIconPreviewField setEditable:NO];
  [self.spaceIconPreviewField setDrawsBackground:NO];
  [self.spaceIconPreviewField setAlignment:NSTextAlignmentCenter];
  NSFont *spacePreviewFont = [self preferredIconFontWithSize:28.0];
  [self.spaceIconPreviewField setFont:spacePreviewFont];
  [spaceIconContent addSubview:self.spaceIconPreviewField];
  NSButton *saveSpaceIcon = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, spaceWidth, 26)];
  [saveSpaceIcon setTitle:@"Save Space Icon"];
  [saveSpaceIcon setButtonType:NSButtonTypeMomentaryPushIn];
  [saveSpaceIcon setBezelStyle:NSBezelStyleRounded];
  saveSpaceIcon.target = self;
  saveSpaceIcon.action = @selector(saveSpaceIcon:);
  [spaceIconContent addSubview:saveSpaceIcon];

  CGFloat workflowHeight = 340.0;
  NSBox *workflowBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[0], nextBoxOriginY(0, workflowHeight), columnWidth, workflowHeight)];
  [workflowBox setTitle:@"Workflow Shortcuts"];
  [content addSubview:workflowBox];
  NSView *workflowContent = [workflowBox contentView];
  CGFloat workflowWidth = workflowContent.bounds.size.width - 20;
  CGFloat workflowY = workflowContent.bounds.size.height - 40;

  NSTextField *docsHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(10, workflowY, workflowWidth, 18)];
  [docsHeader setBezeled:NO];
  [docsHeader setEditable:NO];
  [docsHeader setDrawsBackground:NO];
  [docsHeader setStringValue:@"Reference Files"];
  [workflowContent addSubview:docsHeader];
  workflowY -= 28;

  NSArray *docs = [self workflowArrayForKey:@"docs" fallback:nil];
  for (NSDictionary *doc in docs) {
    NSString *title = doc[@"title"] ?: @"Document";
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(10, workflowY, workflowWidth, 26)];
    [button setTitle:title];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    button.action = @selector(openDoc:);
    button.toolTip = doc[@"path"];
    [workflowContent addSubview:button];
    workflowY -= 32;
  }

  workflowY -= 6;
  NSTextField *actionsHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(10, workflowY, workflowWidth, 18)];
  [actionsHeader setBezeled:NO];
  [actionsHeader setEditable:NO];
  [actionsHeader setDrawsBackground:NO];
  [actionsHeader setStringValue:@"Quick Actions"];
  [workflowContent addSubview:actionsHeader];
  workflowY -= 30;

  NSArray *rawActions = [self workflowArrayForKey:@"actions" fallback:nil];
  NSMutableArray<NSDictionary *> *quickActions = [NSMutableArray array];
  for (NSDictionary *entry in rawActions) {
    NSString *selectorName = entry[@"selector"];
    if (selectorName.length == 0) continue;
    SEL selector = NSSelectorFromString(selectorName);
    if (selector && [self respondsToSelector:selector]) {
      NSString *title = entry[@"title"] ?: selectorName;
      [quickActions addObject:@{ @"title": title, @"selector": selectorName }];
    }
  }
  CGFloat quickButtonWidth = (workflowWidth - 10) / 2.0;
  for (NSInteger idx = 0; idx < quickActions.count; idx++) {
    NSInteger row = idx / 2;
    NSInteger col = idx % 2;
    CGFloat quickY = workflowY - (row * 36);
    NSDictionary *action = quickActions[idx];
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(10 + col * (quickButtonWidth + 10), quickY, quickButtonWidth, 28)];
    [button setTitle:action[@"title"]];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    [button setBezelStyle:NSBezelStyleRounded];
    button.target = self;
    NSString *selectorName = action[@"selector"];
    if (selectorName) {
      button.action = NSSelectorFromString(selectorName);
    }
    [workflowContent addSubview:button];
  }

  CGFloat appearanceHeight = 380.0;
  NSBox *appearanceBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[1], nextBoxOriginY(1, appearanceHeight), columnWidth, appearanceHeight)];
  [appearanceBox setTitle:@"Bar Appearance"];
  [content addSubview:appearanceBox];
  NSView *appearanceContent = [appearanceBox contentView];
  CGFloat appearanceWidth = appearanceContent.bounds.size.width - 20;
  CGFloat appearanceTop = appearanceContent.bounds.size.height - 40;
  NSTextField *heightLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, appearanceTop, 200, 20)];
  [heightLabel setBezeled:NO];
  [heightLabel setEditable:NO];
  [heightLabel setDrawsBackground:NO];
  [heightLabel setStringValue:@"Bar Height"];
  [appearanceContent addSubview:heightLabel];
  self.heightSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(10, appearanceTop - 30, appearanceWidth, 24)];
  self.heightSlider.minValue = 20;
  self.heightSlider.maxValue = 45;
  NSNumber *height = self.state[@"appearance"][@"bar_height"];
  self.heightSlider.doubleValue = height ? [height doubleValue] : 25;
  self.heightSlider.target = self;
  self.heightSlider.action = @selector(heightChanged:);
  [appearanceContent addSubview:self.heightSlider];
  NSTextField *cornerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, appearanceTop - 70, 200, 20)];
  [cornerLabel setBezeled:NO];
  [cornerLabel setEditable:NO];
  [cornerLabel setDrawsBackground:NO];
  [cornerLabel setStringValue:@"Corner Radius"];
  [appearanceContent addSubview:cornerLabel];
  self.cornerSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(10, appearanceTop - 100, appearanceWidth, 24)];
  self.cornerSlider.minValue = 0;
  self.cornerSlider.maxValue = 15;
  NSNumber *corner = self.state[@"appearance"][@"corner_radius"];
  self.cornerSlider.doubleValue = corner ? [corner doubleValue] : 0;
  self.cornerSlider.target = self;
  self.cornerSlider.action = @selector(cornerChanged:);
  [appearanceContent addSubview:self.cornerSlider];
  NSArray *colorOptions = @[
    @{ @"title": @"Default", @"value": @"0xD04C3B52" },
    @{ @"title": @"Lavender", @"value": @"0xFFb4befe" },
    @{ @"title": @"Emerald", @"value": @"0xffa6e3a1" },
    @{ @"title": @"Slate", @"value": @"0xCC1e1e2e" }
  ];
  NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, appearanceTop - 140, 200, 20)];
  [colorLabel setBezeled:NO];
  [colorLabel setEditable:NO];
  [colorLabel setDrawsBackground:NO];
  [colorLabel setStringValue:@"Bar Color"];
  [appearanceContent addSubview:colorLabel];
  self.colorMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, appearanceTop - 170, appearanceWidth, 26)];
  id currentColor = self.state[@"appearance"][@"bar_color"];
  for (NSDictionary *option in colorOptions) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"value"];
    [self.colorMenu.menu addItem:item];
  }
  self.colorMenu.target = self;
  self.colorMenu.action = @selector(colorChanged:);
  [appearanceContent addSubview:self.colorMenu];
  NSTextField *customBarColorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, appearanceTop - 205, 180, 20)];
  [customBarColorLabel setBezeled:NO];
  [customBarColorLabel setEditable:NO];
  [customBarColorLabel setDrawsBackground:NO];
  [customBarColorLabel setStringValue:@"Custom Color Picker"];
  [appearanceContent addSubview:customBarColorLabel];
  self.barColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(10, appearanceTop - 240, 44, 28)];
  self.barColorWell.target = self;
  self.barColorWell.action = @selector(barColorWellChanged:);
  [appearanceContent addSubview:self.barColorWell];
  self.barColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(64, appearanceTop - 236, appearanceWidth - 140, 24)];
  self.barColorHexField.placeholderString = @"0xFFAABBCC";
  self.barColorHexField.delegate = self;
  self.barColorHexField.target = self;
  self.barColorHexField.action = @selector(applyBarColorFromHex:);
  [appearanceContent addSubview:self.barColorHexField];
  NSButton *applyBarColorButton = [[NSButton alloc] initWithFrame:NSMakeRect(appearanceWidth - 70, appearanceTop - 237, 60, 26)];
  [applyBarColorButton setTitle:@"Set"];
  [applyBarColorButton setButtonType:NSButtonTypeMomentaryPushIn];
  [applyBarColorButton setBezelStyle:NSBezelStyleRounded];
  applyBarColorButton.target = self;
  applyBarColorButton.action = @selector(applyBarColorFromHex:);
  [appearanceContent addSubview:applyBarColorButton];
  NSTextField *scaleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, appearanceTop - 240, 200, 20)];
  [scaleLabel setBezeled:NO];
  [scaleLabel setEditable:NO];
  [scaleLabel setDrawsBackground:NO];
  [scaleLabel setStringValue:@"Widget Scale (More Space)"];
  [appearanceContent addSubview:scaleLabel];
  self.scaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(10, appearanceTop - 270, appearanceWidth - 70, 24)];
  self.scaleSlider.minValue = 0.85;
  self.scaleSlider.maxValue = 1.25;
  NSDictionary *appearanceState = self.state[@"appearance"];
  double initialScale = 1.0;
  if ([appearanceState isKindOfClass:[NSDictionary class]]) {
    id rawScale = appearanceState[@"widget_scale"];
    if ([rawScale isKindOfClass:[NSNumber class]]) {
      initialScale = [rawScale doubleValue];
    } else if ([rawScale isKindOfClass:[NSString class]]) {
      initialScale = [rawScale doubleValue];
    }
  }
  if (initialScale < 0.85 || initialScale > 1.25) {
    initialScale = 1.0;
  }
  self.scaleSlider.doubleValue = initialScale;
  self.scaleSlider.continuous = YES;
  self.scaleSlider.target = self;
  self.scaleSlider.action = @selector(scaleChanged:);
  [appearanceContent addSubview:self.scaleSlider];
  self.scaleValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(appearanceWidth - 55, appearanceTop - 265, 45, 18)];
  [self.scaleValueLabel setBezeled:NO];
  [self.scaleValueLabel setEditable:NO];
  [self.scaleValueLabel setDrawsBackground:NO];
  [self.scaleValueLabel setAlignment:NSTextAlignmentRight];
  [appearanceContent addSubview:self.scaleValueLabel];
  NSString *initialBarColor = nil;
  if ([currentColor isKindOfClass:[NSString class]]) {
    initialBarColor = (NSString *)currentColor;
  } else if ([currentColor respondsToSelector:@selector(stringValue)]) {
    initialBarColor = [currentColor stringValue];
  } else if ([colorOptions.firstObject isKindOfClass:[NSDictionary class]]) {
    initialBarColor = colorOptions.firstObject[@"value"];
  }
  [self syncBarColorInputsWithHex:initialBarColor];
  [self updateScaleIndicator:initialScale];

  CGFloat widgetColorHeight = 190.0;
  NSBox *widgetColorBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[1], nextBoxOriginY(1, widgetColorHeight), columnWidth, widgetColorHeight)];
  [widgetColorBox setTitle:@"Widget Color"];
  [content addSubview:widgetColorBox];
  NSView *widgetColorContent = [widgetColorBox contentView];
  CGFloat widgetColorWidth = widgetColorContent.bounds.size.width - 20;
  self.widgetSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, widgetColorContent.bounds.size.height - 40, widgetColorWidth, 26)];
  for (NSString *widget in widgets) {
    [self.widgetSelector addItemWithTitle:widget];
  }
  self.widgetSelector.target = self;
  self.widgetSelector.action = @selector(widgetSelectionChanged:);
  [widgetColorContent addSubview:self.widgetSelector];
  NSArray *widgetColorOptions = @[
    @{ @"title": @"Default", @"value": @"0x00000000" },
    @{ @"title": @"Catppuccin Blue", @"value": @"0xFF89b4fa" },
    @{ @"title": @"Catppuccin Mauve", @"value": @"0xFFcba6f7" },
    @{ @"title": @"Catppuccin Green", @"value": @"0xffa6e3a1" },
    @{ @"title": @"Slate", @"value": @"0xFF1e1e2e" }
  ];
  self.widgetColorMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, widgetColorContent.bounds.size.height - 75, widgetColorWidth, 26)];
  for (NSDictionary *option in widgetColorOptions) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"value"];
    [self.widgetColorMenu.menu addItem:item];
  }
  self.widgetColorMenu.target = self;
  self.widgetColorMenu.action = @selector(widgetColorChanged:);
  [widgetColorContent addSubview:self.widgetColorMenu];
  NSTextField *customWidgetColorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, widgetColorContent.bounds.size.height - 110, widgetColorWidth, 20)];
  [customWidgetColorLabel setBezeled:NO];
  [customWidgetColorLabel setEditable:NO];
  [customWidgetColorLabel setDrawsBackground:NO];
  [customWidgetColorLabel setStringValue:@"Custom Color"];
  [widgetColorContent addSubview:customWidgetColorLabel];
  self.widgetColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(10, widgetColorContent.bounds.size.height - 145, 44, 26)];
  self.widgetColorWell.target = self;
  self.widgetColorWell.action = @selector(widgetColorWellChanged:);
  [widgetColorContent addSubview:self.widgetColorWell];
  self.widgetColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(64, widgetColorContent.bounds.size.height - 142, widgetColorWidth - 130, 22)];
  self.widgetColorHexField.placeholderString = @"0xFF556677";
  self.widgetColorHexField.delegate = self;
  self.widgetColorHexField.target = self;
  self.widgetColorHexField.action = @selector(applyWidgetCustomColor:);
  [widgetColorContent addSubview:self.widgetColorHexField];
  NSButton *applyWidgetColorButton = [[NSButton alloc] initWithFrame:NSMakeRect(widgetColorWidth - 60, widgetColorContent.bounds.size.height - 144, 50, 26)];
  [applyWidgetColorButton setTitle:@"Set"];
  [applyWidgetColorButton setButtonType:NSButtonTypeMomentaryPushIn];
  [applyWidgetColorButton setBezelStyle:NSBezelStyleRounded];
  applyWidgetColorButton.target = self;
  applyWidgetColorButton.action = @selector(applyWidgetCustomColor:);
  [widgetColorContent addSubview:applyWidgetColorButton];
  [self refreshWidgetColorInputs];

  [self updateIconPreview];
  [self updateSpaceSelectionFromState];

  CGFloat menuIconHeight = 180.0;
  NSBox *menuIconBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[2], nextBoxOriginY(2, menuIconHeight), columnWidth, menuIconHeight)];
  [menuIconBox setTitle:@"Menu Icons"];
  [content addSubview:menuIconBox];
  NSView *menuIconContent = [menuIconBox contentView];
  NSArray *iconChoices = @[
    @{ @"title": @"Apple", @"glyph": @"" },
    @{ @"title": @"Alt Apple", @"glyph": @"" },
    @{ @"title": @"Gear", @"glyph": @"" },
    @{ @"title": @"Triforce", @"glyph": @"󰊠" },
    @{ @"title": @"Quest", @"glyph": @"" },
    @{ @"title": @"Gamepad", @"glyph": @"󰍳" }
  ];
  CGFloat menuWidth = menuIconContent.bounds.size.width;
  CGFloat halfWidth = (menuWidth - 30) / 2.0;
  self.appleIconMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, menuIconContent.bounds.size.height - 35, halfWidth, 26)];
  for (NSDictionary *option in iconChoices) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"glyph"];
    [self.appleIconMenu.menu addItem:item];
  }
  NSString *appleCurrent = self.state[@"icons"][@"apple"];
  if ([appleCurrent isKindOfClass:[NSString class]]) {
    for (NSMenuItem *item in self.appleIconMenu.itemArray) {
      if ([item.representedObject isEqual:appleCurrent]) {
        [self.appleIconMenu selectItem:item];
        break;
      }
    }
  }
  self.appleIconMenu.tag = 0;
  self.appleIconMenu.target = self;
  self.appleIconMenu.action = @selector(menuIconChanged:);
  [menuIconContent addSubview:self.appleIconMenu];

  self.questIconMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20 + halfWidth, menuIconContent.bounds.size.height - 35, halfWidth, 26)];
  for (NSDictionary *option in iconChoices) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"] action:NULL keyEquivalent:@""];
    item.representedObject = option[@"glyph"];
    [self.questIconMenu.menu addItem:item];
  }
  NSString *questCurrent = self.state[@"icons"][@"quest"];
  if ([questCurrent isKindOfClass:[NSString class]]) {
    for (NSMenuItem *item in self.questIconMenu.itemArray) {
      if ([item.representedObject isEqual:questCurrent]) {
        [self.questIconMenu selectItem:item];
        break;
      }
    }
  }
  self.questIconMenu.tag = 1;
  self.questIconMenu.target = self;
  self.questIconMenu.action = @selector(menuIconChanged:);
  [menuIconContent addSubview:self.questIconMenu];
  NSTextField *menuPreviewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10 + 40, menuWidth - 20, 16)];
  [menuPreviewLabel setBezeled:NO];
  [menuPreviewLabel setEditable:NO];
  [menuPreviewLabel setDrawsBackground:NO];
  [menuPreviewLabel setStringValue:@"Preview"];
  [menuIconContent addSubview:menuPreviewLabel];
  self.appleIconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, halfWidth, 36)];
  [self.appleIconPreviewField setBezeled:NO];
  [self.appleIconPreviewField setEditable:NO];
  [self.appleIconPreviewField setDrawsBackground:NO];
  [self.appleIconPreviewField setAlignment:NSTextAlignmentCenter];
  [self.appleIconPreviewField setFont:[self preferredIconFontWithSize:26.0]];
  [menuIconContent addSubview:self.appleIconPreviewField];
  self.questIconPreviewField = [[NSTextField alloc] initWithFrame:NSMakeRect(20 + halfWidth, 10, halfWidth, 36)];
  [self.questIconPreviewField setBezeled:NO];
  [self.questIconPreviewField setEditable:NO];
  [self.questIconPreviewField setDrawsBackground:NO];
  [self.questIconPreviewField setAlignment:NSTextAlignmentCenter];
  [self.questIconPreviewField setFont:[self preferredIconFontWithSize:26.0]];
  [menuIconContent addSubview:self.questIconPreviewField];
  [self updateMenuIconPreview];

  CGFloat themesHeight = 160.0;
  NSBox *themesBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[2], nextBoxOriginY(2, themesHeight), columnWidth, themesHeight)];
  [themesBox setTitle:@"Theme Presets"];
  [content addSubview:themesBox];
  NSView *themesContent = [themesBox contentView];
  CGFloat themeWidth = (themesContent.bounds.size.width - 30) / 2.0;

  NSArray *themes = @[
    @{ @"title": @"Liquid", @"value": @"liquid", @"icon": @"󰧱" },
    @{ @"title": @"Tinted", @"value": @"tinted", @"icon": @"󰧱" },
    @{ @"title": @"Classic", @"value": @"classic", @"icon": @"󰧱" },
    @{ @"title": @"Matte", @"value": @"solid", @"icon": @"󰧱" }
  ];

  for (NSInteger idx = 0; idx < themes.count; idx++) {
    NSDictionary *theme = themes[idx];
    NSInteger row = idx / 2;
    NSInteger col = idx % 2;
    CGFloat themeX = 10 + (col * (themeWidth + 10));
    CGFloat themeY = themesContent.bounds.size.height - 40 - (row * 40);

    NSButton *themeButton = [[NSButton alloc] initWithFrame:NSMakeRect(themeX, themeY, themeWidth, 32)];
    [themeButton setTitle:[NSString stringWithFormat:@"%@ %@", theme[@"icon"], theme[@"title"]]];
    [themeButton setButtonType:NSButtonTypeMomentaryPushIn];
    [themeButton setBezelStyle:NSBezelStyleRounded];
    themeButton.tag = idx;
    themeButton.toolTip = theme[@"value"];
    themeButton.target = self;
    themeButton.action = @selector(applyTheme:);
    [themesContent addSubview:themeButton];
  }

  CGFloat fontBoxHeight = 100.0;
  NSBox *fontBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[1], nextBoxOriginY(1, fontBoxHeight), columnWidth, fontBoxHeight)];
  [fontBox setTitle:@"Widget Fonts"];
  [content addSubview:fontBox];
  NSView *fontContent = [fontBox contentView];

  // Clock font selector
  NSTextField *clockFontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, fontContent.bounds.size.height - 25, 60, 18)];
  [clockFontLabel setBezeled:NO];
  [clockFontLabel setEditable:NO];
  [clockFontLabel setDrawsBackground:NO];
  [clockFontLabel setStringValue:@"Clock:"];
  [fontContent addSubview:clockFontLabel];

  self.clockFontMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, fontContent.bounds.size.height - 35, fontContent.bounds.size.width - 80, 26)];
  NSArray *fontOptions = @[ @"Regular", @"Medium", @"Semibold", @"Bold", @"Heavy" ];
  for (NSString *option in fontOptions) {
    [self.clockFontMenu addItemWithTitle:option];
  }
  NSString *currentFont = self.state[@"appearance"][@"clock_font_style"];
  if ([currentFont isKindOfClass:[NSString class]]) {
    [self.clockFontMenu selectItemWithTitle:currentFont];
  }
  self.clockFontMenu.target = self;
  self.clockFontMenu.action = @selector(clockFontChanged:);
  [fontContent addSubview:self.clockFontMenu];

  NSTextField *familyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, fontContent.bounds.size.height - 60, 60, 18)];
  [familyLabel setBezeled:NO];
  [familyLabel setEditable:NO];
  [familyLabel setDrawsBackground:NO];
  [familyLabel setStringValue:@"Family:"];
  [fontContent addSubview:familyLabel];

  self.clockFontFamilyField = [[NSTextField alloc] initWithFrame:NSMakeRect(70, fontContent.bounds.size.height - 65, fontContent.bounds.size.width - 150, 24)];
  NSString *currentFamily = self.state[@"appearance"][@"clock_font_family"];
  if ([currentFamily isKindOfClass:[NSString class]]) {
    [self.clockFontFamilyField setStringValue:currentFamily];
  } else {
    [self.clockFontFamilyField setPlaceholderString:@"SF Mono"];
  }
  [fontContent addSubview:self.clockFontFamilyField];

  NSButton *applyClockFamily = [[NSButton alloc] initWithFrame:NSMakeRect(fontContent.bounds.size.width - 70, fontContent.bounds.size.height - 66, 60, 26)];
  [applyClockFamily setTitle:@"Apply"];
  [applyClockFamily setButtonType:NSButtonTypeMomentaryPushIn];
  [applyClockFamily setBezelStyle:NSBezelStyleRounded];
  applyClockFamily.target = self;
  applyClockFamily.action = @selector(applyClockFontFamily:);
  [fontContent addSubview:applyClockFamily];

  CGFloat shortcutsHeight = 110.0;
  NSBox *shortcutsBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[1], nextBoxOriginY(1, shortcutsHeight), columnWidth, shortcutsHeight)];
  [shortcutsBox setTitle:@"Space Switching"];
  [content addSubview:shortcutsBox];
  NSView *shortcutsContent = [shortcutsBox contentView];
  self.shortcutToggle = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(10, shortcutsContent.bounds.size.height - 40, shortcutsContent.bounds.size.width - 20, 30)];
  [self.shortcutToggle setSegmentCount:2];
  [self.shortcutToggle setLabel:@"Yabai" forSegment:0];
  [self.shortcutToggle setLabel:@"Native" forSegment:1];
  BOOL shortcutsOn = YES;
  id toggle = self.state[@"toggles"][@"yabai_shortcuts"];
  if ([toggle isKindOfClass:[NSNumber class]]) {
    shortcutsOn = [toggle boolValue];
  }
  [self.shortcutToggle setSelected:shortcutsOn forSegment:0];
  [self.shortcutToggle setSelected:!shortcutsOn forSegment:1];
  self.shortcutToggle.target = self;
  self.shortcutToggle.action = @selector(shortcutModeChanged:);
  [shortcutsContent addSubview:self.shortcutToggle];

  CGFloat integrationsHeight = 190.0;
  NSBox *integrationsBox = [[NSBox alloc] initWithFrame:NSMakeRect(columnX[1], nextBoxOriginY(1, integrationsHeight), columnWidth, integrationsHeight)];
  [integrationsBox setTitle:@"Integration Status"];
  [content addSubview:integrationsBox];
  NSView *integrationsContent = [integrationsBox contentView];
  CGFloat integrationWidth = integrationsContent.bounds.size.width - 20;
  BOOL yazeEnabled = [self isIntegrationEnabled:@"yaze"];
  BOOL emacsEnabled = [self isIntegrationEnabled:@"emacs"];

  self.yazeToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, integrationsContent.bounds.size.height - 30, integrationWidth / 2 - 10, 20)];
  [self.yazeToggleButton setButtonType:NSButtonTypeSwitch];
  [self.yazeToggleButton setTitle:@"Enable Yaze"];
  [self.yazeToggleButton setState:yazeEnabled ? NSControlStateValueOn : NSControlStateValueOff];
  self.yazeToggleButton.target = self;
  self.yazeToggleButton.action = @selector(integrationToggleChanged:);
  self.yazeToggleButton.tag = 0;
  [integrationsContent addSubview:self.yazeToggleButton];

  self.emacsToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(integrationWidth / 2 + 10, integrationsContent.bounds.size.height - 30, integrationWidth / 2 - 10, 20)];
  [self.emacsToggleButton setButtonType:NSButtonTypeSwitch];
  [self.emacsToggleButton setTitle:@"Enable Emacs"];
  [self.emacsToggleButton setState:emacsEnabled ? NSControlStateValueOn : NSControlStateValueOff];
  self.emacsToggleButton.target = self;
  self.emacsToggleButton.action = @selector(integrationToggleChanged:);
  self.emacsToggleButton.tag = 1;
  [integrationsContent addSubview:self.emacsToggleButton];

  // Yaze status
  NSTextField *yazeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, integrationsContent.bounds.size.height - 60, 100, 20)];
  [yazeLabel setBezeled:NO];
  [yazeLabel setEditable:NO];
  [yazeLabel setDrawsBackground:NO];
  [yazeLabel setStringValue:@"󰊠 Yaze ROM:"];
  [integrationsContent addSubview:yazeLabel];

  self.yazeStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, integrationsContent.bounds.size.height - 60, integrationWidth - 110, 20)];
  [self.yazeStatusField setBezeled:NO];
  [self.yazeStatusField setEditable:NO];
  [self.yazeStatusField setDrawsBackground:NO];
  [integrationsContent addSubview:self.yazeStatusField];

  // Emacs status
  NSTextField *emacsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, integrationsContent.bounds.size.height - 90, 100, 20)];
  [emacsLabel setBezeled:NO];
  [emacsLabel setEditable:NO];
  [emacsLabel setDrawsBackground:NO];
  [emacsLabel setStringValue:@" Emacs:"];
  [integrationsContent addSubview:emacsLabel];

  self.emacsStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, integrationsContent.bounds.size.height - 90, integrationWidth - 110, 20)];
  [self.emacsStatusField setBezeled:NO];
  [self.emacsStatusField setEditable:NO];
  [self.emacsStatusField setDrawsBackground:NO];
  [integrationsContent addSubview:self.emacsStatusField];

  // Quick launch buttons
  self.yazeLaunchButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 20, integrationWidth / 2 - 10, 28)];
  [self.yazeLaunchButton setTitle:@"Launch Yaze"];
  [self.yazeLaunchButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.yazeLaunchButton setBezelStyle:NSBezelStyleRounded];
  self.yazeLaunchButton.target = self;
  self.yazeLaunchButton.action = @selector(launchYaze:);
  [integrationsContent addSubview:self.yazeLaunchButton];

  self.emacsLaunchButton = [[NSButton alloc] initWithFrame:NSMakeRect(integrationWidth / 2 + 10, 20, integrationWidth / 2 - 10, 28)];
  [self.emacsLaunchButton setTitle:@"Launch Emacs"];
  [self.emacsLaunchButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.emacsLaunchButton setBezelStyle:NSBezelStyleRounded];
  self.emacsLaunchButton.target = self;
  self.emacsLaunchButton.action = @selector(launchEmacs:);
  [integrationsContent addSubview:self.emacsLaunchButton];

  [self updateIntegrationStatusUI];

}

- (void)toggleWidget:(NSButton *)sender {
  NSString *widget = self.widgetMap[@(sender.tag)];
  if (!widget) return;
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"widget_toggle.sh"];
  NSString *state = sender.state == NSControlStateValueOn ? @"on" : @"off";
  [self runScript:script arguments:@[widget, state]];
}

- (void)heightChanged:(NSSlider *)sender {
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  [self runScript:script arguments:@[@"--height", [NSString stringWithFormat:@"%0.0f", sender.doubleValue]]];
}

- (void)cornerChanged:(NSSlider *)sender {
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  [self runScript:script arguments:@[@"--corner", [NSString stringWithFormat:@"%0.0f", sender.doubleValue]]];
}

- (void)colorChanged:(NSPopUpButton *)sender {
  NSString *value = sender.selectedItem.representedObject;
  NSString *normalized = [self normalizedColorString:value];
  if (!normalized) return;
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  [self syncBarColorInputsWithHex:normalized];
  [self runScript:script arguments:@[@"--color", normalized]];
  [self refreshStateAsync:nil];
}

- (void)scaleChanged:(NSSlider *)sender {
  double value = sender.doubleValue;
  [self updateScaleIndicator:value];
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  NSString *formatted = [NSString stringWithFormat:@"%0.2f", value];
  [self runScript:script arguments:@[@"--scale", formatted]];
}

- (void)updateScaleIndicator:(double)value {
  if (!self.scaleValueLabel) return;
  [self.scaleValueLabel setStringValue:[NSString stringWithFormat:@"%0.2fx", value]];
}

- (void)widgetSelectionChanged:(id)sender {
  [self refreshWidgetColorInputs];
}

- (void)barColorWellChanged:(NSColorWell *)sender {
  NSString *hex = [self hexStringFromColor:sender.color includeAlpha:YES];
  if (!hex) return;
  [self syncBarColorInputsWithHex:hex];
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  [self runScript:script arguments:@[@"--color", hex]];
  [self refreshStateAsync:nil];
}

- (void)applyBarColorFromHex:(id)sender {
  NSString *hex = [self normalizedColorString:self.barColorHexField.stringValue];
  if (!hex) {
    NSBeep();
    return;
  }
  [self syncBarColorInputsWithHex:hex];
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_appearance.sh"];
  [self runScript:script arguments:@[@"--color", hex]];
  [self refreshStateAsync:nil];
}

- (void)widgetColorWellChanged:(NSColorWell *)sender {
  NSString *hex = [self hexStringFromColor:sender.color includeAlpha:YES];
  if (!hex) return;
  [self applyWidgetColorHex:hex];
}

- (void)applyWidgetCustomColor:(id)sender {
  NSString *hex = [self normalizedColorString:self.widgetColorHexField.stringValue];
  if (!hex) {
    NSBeep();
    return;
  }
  [self applyWidgetColorHex:hex];
}

- (void)applyWidgetColorHex:(NSString *)hex {
  NSMenuItem *selected = self.widgetSelector.selectedItem;
  if (!selected) {
    NSBeep();
    return;
  }
  NSString *widget = selected.title;
  NSString *normalized = [self normalizedColorString:hex];
  if (!widget || !normalized) {
    NSBeep();
    return;
  }
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_widget_color.sh"];
  [self runScript:script arguments:@[widget, normalized]];
  [self syncWidgetColorInputsWithHex:normalized];
  __weak typeof(self) weakSelf = self;
  [self refreshStateAsync:^{ [weakSelf refreshWidgetColorInputs]; }];
}

- (void)shortcutModeChanged:(NSSegmentedControl *)sender {
  BOOL shortcutsOn = sender.selectedSegment == 0;
  NSString *mode = shortcutsOn ? @"on" : @"off";
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"toggle_yabai_shortcuts.sh"];
  [self runScript:script arguments:@[mode]];
}

- (void)widgetColorChanged:(NSPopUpButton *)sender {
  NSString *widget = self.widgetSelector.selectedItem.title;
  NSString *color = sender.selectedItem.representedObject;
  if (!widget || !color) return;
  [self applyWidgetColorHex:color];
}

- (void)saveIconMapping:(id)sender {
  NSString *appName = self.iconAppField.stringValue;
  NSString *glyph = self.iconGlyphField.stringValue;
  if (appName.length == 0 || glyph.length == 0) return;
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_app_icon.sh"];
  [self runScript:script arguments:@[appName, glyph]];
}

- (void)iconLibraryChanged:(NSPopUpButton *)sender {
  NSString *glyph = sender.selectedItem.representedObject;
  if (!glyph) return;
  [self.iconGlyphField setStringValue:glyph];
  [self updateIconPreview];
}

- (void)saveSpaceIcon:(id)sender {
  NSString *space = self.spaceSelector.selectedItem.title;
  NSString *glyph = self.spaceIconField.stringValue;
  if (space.length == 0 || glyph.length == 0) return;
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_space_icon.sh"];
  [self runScript:script arguments:@[space, glyph]];
  [self updateSpaceIconPreview];
  [self refreshStateAndUpdateSpaceIcons];
}

- (void)spaceSelectionChanged:(id)sender {
  [self updateSpaceSelectionFromState];
}

- (NSString *)glyphForSpace:(NSString *)space {
  if (space.length == 0) return @"";
  NSDictionary *icons = self.state[@"space_icons"];
  if ([icons isKindOfClass:[NSDictionary class]]) {
    id value = icons[space];
    if ([value isKindOfClass:[NSString class]]) {
      return value;
    }
  }
  return @"";
}

- (void)updateSpaceSelectionFromState {
  if (!self.spaceSelector || !self.spaceIconField) return;
  NSString *space = self.spaceSelector.selectedItem.title ?: @"";
  NSString *glyph = [self glyphForSpace:space];
  if (glyph.length > 0) {
    [self.spaceIconField setStringValue:glyph];
  } else {
    [self.spaceIconField setStringValue:@""];
  }
  [self updateSpaceIconPreview];
}

- (void)refreshStateAndUpdateSpaceIcons {
  __weak typeof(self) weakSelf = self;
  [self refreshStateAsync:^{ [weakSelf updateSpaceSelectionFromState]; }];
}

- (BOOL)isIntegrationEnabled:(NSString *)name {
  NSDictionary *integrations = self.state[@"integrations"];
  NSDictionary *entry = [integrations isKindOfClass:[NSDictionary class]] ? integrations[name] : nil;
  if ([entry isKindOfClass:[NSDictionary class]]) {
    id raw = entry[@"enabled"];
    if ([raw respondsToSelector:@selector(boolValue)]) {
      return [raw boolValue];
    }
  }
  return NO;
}

- (void)integrationToggleChanged:(NSButton *)sender {
  NSString *target = sender.tag == 0 ? @"yaze" : @"emacs";
  BOOL enabled = sender.state == NSControlStateValueOn;
  [self runIntegrationToggle:target enabled:enabled];
}

- (void)runIntegrationToggle:(NSString *)name enabled:(BOOL)enabled {
  NSString *script = [self.configPath stringByAppendingPathComponent:@"plugins/set_integration_enabled.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    NSBeep();
    return;
  }
  NSString *state = enabled ? @"on" : @"off";
  [self runCommand:script arguments:@[name, state]];
  __weak typeof(self) weakSelf = self;
  [self refreshStateAsync:^{ [weakSelf updateIntegrationStatusUI]; }];
}

- (void)updateIntegrationStatusUI {
  BOOL yazeEnabled = [self isIntegrationEnabled:@"yaze"];
  BOOL emacsEnabled = [self isIntegrationEnabled:@"emacs"];
  if (self.yazeToggleButton) {
    [self.yazeToggleButton setState:yazeEnabled ? NSControlStateValueOn : NSControlStateValueOff];
  }
  if (self.emacsToggleButton) {
    [self.emacsToggleButton setState:emacsEnabled ? NSControlStateValueOn : NSControlStateValueOff];
  }
  if (self.yazeStatusField) {
    if (yazeEnabled) {
      NSString *yazeBuild = [self checkYazeBuildStatus];
      [self.yazeStatusField setStringValue:yazeBuild];
      if ([yazeBuild isEqualToString:@"✨ Ready"]) {
        [self.yazeStatusField setTextColor:[NSColor systemGreenColor]];
      } else if ([yazeBuild isEqualToString:@"⚠ Not Built"]) {
        [self.yazeStatusField setTextColor:[NSColor systemOrangeColor]];
      } else {
        [self.yazeStatusField setTextColor:[NSColor secondaryLabelColor]];
      }
    } else {
      [self.yazeStatusField setStringValue:@"Disabled for this profile"];
      [self.yazeStatusField setTextColor:[NSColor secondaryLabelColor]];
    }
  }
  if (self.emacsStatusField) {
    if (emacsEnabled) {
      BOOL running = [self checkEmacsRunning];
      if (running) {
        [self.emacsStatusField setStringValue:@"✓ Running"];
        [self.emacsStatusField setTextColor:[NSColor systemGreenColor]];
      } else {
        [self.emacsStatusField setStringValue:@"○ Not Running"];
        [self.emacsStatusField setTextColor:[NSColor secondaryLabelColor]];
      }
    } else {
      [self.emacsStatusField setStringValue:@"Disabled for this profile"];
      [self.emacsStatusField setTextColor:[NSColor secondaryLabelColor]];
    }
  }
  if (self.yazeLaunchButton) {
    [self.yazeLaunchButton setEnabled:yazeEnabled];
  }
  if (self.emacsLaunchButton) {
    [self.emacsLaunchButton setEnabled:emacsEnabled];
  }
}

- (void)updateIconPreview {
  NSString *glyph = self.iconGlyphField.stringValue ?: @"";
  [self updateGlyphPreviewField:self.iconPreviewField withGlyph:glyph placeholder:@"Preview"];
}

- (void)updateSpaceIconPreview {
  NSString *glyph = self.spaceIconField.stringValue ?: @"";
  [self updateGlyphPreviewField:self.spaceIconPreviewField withGlyph:glyph placeholder:@"Preview"];
}

- (void)updateMenuIconPreview {
  NSString *appleGlyph = self.appleIconMenu.selectedItem.representedObject;
  NSString *questGlyph = self.questIconMenu.selectedItem.representedObject;
  [self updateGlyphPreviewField:self.appleIconPreviewField withGlyph:appleGlyph placeholder:@"–"];
  [self updateGlyphPreviewField:self.questIconPreviewField withGlyph:questGlyph placeholder:@"–"];
}

- (void)updateGlyphPreviewField:(NSTextField *)field withGlyph:(NSString *)glyph placeholder:(NSString *)placeholder {
  if (!field) return;
  NSString *value = glyph ?: @"";
  if (value.length == 0) {
    [field setStringValue:placeholder ?: @"Preview"];
    [field setTextColor:[NSColor secondaryLabelColor]];
  } else {
    [field setStringValue:value];
    [field setTextColor:[NSColor labelColor]];
  }
}

- (void)updateAppearanceKey:(NSString *)key value:(NSString *)value {
  if (!key) return;
  NSMutableDictionary *mutableState = [self.state mutableCopy];
  if (!mutableState) mutableState = [NSMutableDictionary dictionary];
  NSMutableDictionary *appearance = [mutableState[@"appearance"] mutableCopy];
  if (!appearance) appearance = [NSMutableDictionary dictionary];
  if (value && value.length > 0) {
    appearance[key] = value;
  } else {
    [appearance removeObjectForKey:key];
  }
  mutableState[@"appearance"] = appearance;
  NSError *error = nil;
  NSData *json = [NSJSONSerialization dataWithJSONObject:mutableState options:NSJSONWritingPrettyPrinted error:&error];
  if (!json || error) {
    return;
  }
  if ([json writeToFile:self.statePath atomically:YES]) {
    self.state = mutableState;
  }
}

- (void)refreshWidgetColorInputs {
  NSMenuItem *selected = self.widgetSelector.selectedItem;
  if (!selected) return;
  NSString *widget = selected.title;
  NSString *current = [self currentColorForWidget:widget];
  [self syncWidgetColorInputsWithHex:current];
}

- (NSString *)currentColorForWidget:(NSString *)widget {
  if (!widget) return nil;
  NSDictionary *colors = self.state[@"widget_colors"];
  id raw = colors[widget];
  if ([raw isKindOfClass:[NSString class]]) {
    return raw;
  }
  return nil;
}

- (void)syncBarColorInputsWithHex:(NSString *)hex {
  if (!self.barColorHexField || !self.barColorWell) return;
  NSString *normalized = [self normalizedColorString:hex];
  if (!normalized) return;
  self.barColorHexField.stringValue = normalized;
  NSColor *color = [self colorFromHexString:normalized];
  if (color) {
    [self.barColorWell setColor:color];
  }
  [self selectMenu:self.colorMenu matchingHex:normalized];
}

- (void)syncWidgetColorInputsWithHex:(NSString *)hex {
  if (!self.widgetColorHexField || !self.widgetColorWell) return;
  NSString *normalized = [self normalizedColorString:hex];
  if (!normalized) {
    self.widgetColorHexField.stringValue = @"";
    [self.widgetColorWell setColor:[NSColor colorWithCalibratedWhite:0.6 alpha:0.2]];
    [self.widgetColorMenu selectItem:nil];
    return;
  }
  self.widgetColorHexField.stringValue = normalized;
  NSColor *color = [self colorFromHexString:normalized];
  if (color) {
    [self.widgetColorWell setColor:color];
  }
  [self selectMenu:self.widgetColorMenu matchingHex:normalized];
}

- (void)selectMenu:(NSPopUpButton *)menu matchingHex:(NSString *)hex {
  if (!menu) return;
  NSString *normalized = [self normalizedColorString:hex];
  BOOL matched = NO;
  if (normalized) {
    for (NSMenuItem *item in menu.itemArray) {
      NSString *value = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : nil;
      NSString *itemHex = [self normalizedColorString:value];
      if (itemHex && [itemHex isEqualToString:normalized]) {
        [menu selectItem:item];
        matched = YES;
        break;
      }
    }
  }
  if (!matched) {
    [menu selectItem:nil];
  }
}

- (NSColor *)colorFromHexString:(NSString *)hexString {
  NSString *normalized = [self normalizedColorString:hexString];
  if (!normalized) return nil;
  unsigned int value = 0;
  NSScanner *scanner = [NSScanner scannerWithString:[normalized substringFromIndex:2]];
  if (![scanner scanHexInt:&value]) {
    return nil;
  }
  CGFloat a = ((value >> 24) & 0xFF) / 255.0;
  CGFloat r = ((value >> 16) & 0xFF) / 255.0;
  CGFloat g = ((value >> 8) & 0xFF) / 255.0;
  CGFloat b = (value & 0xFF) / 255.0;
  return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

- (NSString *)hexStringFromColor:(NSColor *)color includeAlpha:(BOOL)includeAlpha {
  if (!color) return nil;
  NSColor *srgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
  CGFloat r = 0, g = 0, b = 0, a = 0;
  [srgb getRed:&r green:&g blue:&b alpha:&a];
  CGFloat clippedAlpha = MAX(0.0, MIN(1.0, a));
  CGFloat clippedRed = MAX(0.0, MIN(1.0, r));
  CGFloat clippedGreen = MAX(0.0, MIN(1.0, g));
  CGFloat clippedBlue = MAX(0.0, MIN(1.0, b));
  NSUInteger alpha = includeAlpha ? (NSUInteger)(clippedAlpha * 255.0 + 0.5) : 0xFF;
  NSUInteger red = (NSUInteger)(clippedRed * 255.0 + 0.5);
  NSUInteger green = (NSUInteger)(clippedGreen * 255.0 + 0.5);
  NSUInteger blue = (NSUInteger)(clippedBlue * 255.0 + 0.5);
  return [NSString stringWithFormat:@"0x%02lX%02lX%02lX%02lX", (unsigned long)alpha, (unsigned long)red, (unsigned long)green, (unsigned long)blue];
}

- (NSString *)normalizedColorString:(NSString *)hexString {
  if (![hexString isKindOfClass:[NSString class]]) return nil;
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSString *clean = [[hexString stringByTrimmingCharactersInSet:whitespace] uppercaseString];
  clean = [clean stringByReplacingOccurrencesOfString:@"#" withString:@""];
  if ([clean hasPrefix:@"0X"]) {
    clean = [clean substringFromIndex:2];
  }
  if (clean.length == 0) {
    return nil;
  }
  if (clean.length == 6) {
    clean = [@"FF" stringByAppendingString:clean];
  }
  if (clean.length != 8) {
    return nil;
  }
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
  if ([clean rangeOfCharacterFromSet:invalid].location != NSNotFound) {
    return nil;
  }
  return [NSString stringWithFormat:@"0x%@", clean];
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

- (NSArray *)workflowArrayForKey:(NSString *)key fallback:(NSArray *)fallback {
  id value = self.workflowData[key];
  if ([value isKindOfClass:[NSArray class]]) {
    return value;
  }
  return fallback ?: @[];
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

- (void)menuIconChanged:(NSPopUpButton *)sender {
  NSString *glyph = sender.selectedItem.representedObject;
  if (!glyph) return;
  NSString *target = sender.tag == 0 ? @"apple" : @"quest";
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_menu_icon.sh"];
  [self runScript:script arguments:@[target, glyph]];
  [self updateMenuIconPreview];
}

- (void)toggleSystemInfo:(NSButton *)sender {
  NSString *key = self.systemInfoMap[@(sender.tag)];
  if (!key) return;
  NSString *state = sender.state == NSControlStateValueOn ? @"on" : @"off";
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"toggle_system_info_item.sh"];
  [self runScript:script arguments:@[key, state]];
}

- (void)clockFontChanged:(NSPopUpButton *)sender {
  NSString *style = sender.selectedItem.title;
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"set_clock_font.sh"];
  [self runScript:script arguments:@[style]];
}

- (void)applyClockFontFamily:(id)sender {
  NSString *family = self.clockFontFamilyField.stringValue;
  if (family.length == 0) {
    [self updateAppearanceKey:@"clock_font_family" value:nil];
  } else {
    [self updateAppearanceKey:@"clock_font_family" value:family];
  }
}

- (void)reloadBar:(id)sender {
  [self runCommand:@"/opt/homebrew/opt/sketchybar/bin/sketchybar" arguments:@[@"--reload"]];
}

- (void)openLogs:(id)sender {
  NSURL *url = [NSURL fileURLWithPath:@"/opt/homebrew/var/log/sketchybar"];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openIconBrowser:(id)sender {
  NSString *guiPath = [self.configPath stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:guiPath]) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Icon Browser Not Found"];
    NSString *message = [NSString stringWithFormat:@"The icon browser binary is not built. Run 'make' in %@/gui.", self.configPath];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return;
  }
  [self runCommand:guiPath arguments:@[]];
}

- (void)openControlPanel:(id)sender {
  NSString *script = [self.configPath stringByAppendingPathComponent:@"bin/open_control_panel.sh"];
  [self runScript:script arguments:@[]];
}

- (void)toggleWhichKey:(id)sender {
  [self runCommand:@"/opt/homebrew/opt/sketchybar/bin/sketchybar" arguments:@[@"--trigger", @"whichkey_toggle"]];
}

- (void)openIconMap:(id)sender {
  NSString *path = [self.configPath stringByAppendingPathComponent:@"icon_map.json"];
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    NSData *empty = [@"{}\n" dataUsingEncoding:NSUTF8StringEncoding];
    [fm createFileAtPath:path contents:empty attributes:nil];
  }
  NSURL *url = [NSURL fileURLWithPath:path];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openDoc:(NSButton *)sender {
  NSString *path = sender.toolTip;
  if (!path) return;
  NSString *fullPath = [self expandedWorkflowPath:path];
  if (!fullPath) return;
  NSURL *url = [NSURL fileURLWithPath:fullPath];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)runAccessibilityFix:(id)sender {
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"yabai_accessibility_fix.sh"];
  [self runScript:script arguments:@[]];
}

- (NSString *)checkYazeBuildStatus {
  NSString *codeDir = self.codePath ?: [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
  NSString *yazePath = [codeDir stringByAppendingPathComponent:@"yaze"];
  NSString *buildBinary = [yazePath stringByAppendingPathComponent:@"build/bin/yaze"];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:yazePath]) {
    return @"Not Installed";
  }

  if ([fm fileExistsAtPath:buildBinary]) {
    return @"✨ Ready";
  } else {
    return @"⚠ Not Built";
  }
}

- (BOOL)checkEmacsRunning {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/pgrep";
  task.arguments = @[@"-x", @"Emacs"];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  @try {
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
  } @catch (NSException *exception) {
    return NO;
  }
}

- (void)launchYaze:(id)sender {
  NSString *codeDir = self.codePath ?: [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
  NSString *yazePath = [[codeDir stringByAppendingPathComponent:@"yaze"] stringByAppendingPathComponent:@"build/bin/yaze"];

  if (![[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    NSString *message = [NSString stringWithFormat:@"Build Yaze first: cd %@/yaze && make", codeDir];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return;
  }

  [self runCommand:yazePath arguments:@[]];
}

- (void)launchEmacs:(id)sender {
  NSString *emacsPath = @"/Applications/Emacs.app";

  if (![[NSFileManager defaultManager] fileExistsAtPath:emacsPath]) {
    emacsPath = @"/opt/homebrew/Cellar/emacs-plus@30/30.0.92/Emacs.app";
  }

  if ([[NSFileManager defaultManager] fileExistsAtPath:emacsPath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:emacsPath]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Emacs Not Found"];
    [alert setInformativeText:@"Install Emacs first"];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  }
}

- (void)focusEmacsSpace:(id)sender {
  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"yabai_control.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    NSBeep();
    return;
  }
  [self runScript:script arguments:@[@"space-focus-app", @"Emacs"]];
}

- (void)applyTheme:(NSButton *)sender {
  NSString *theme = sender.toolTip;
  if (!theme || theme.length == 0) return;

  NSString *script = [self.scriptsPath stringByAppendingPathComponent:@"runtime_update.sh"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Runtime Script Not Found"];
    NSString *path = self.scriptsPath ?: @"(unknown scripts directory)";
    [alert setInformativeText:[NSString stringWithFormat:@"Cannot find runtime_update.sh in %@", path]];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return;
  }

  [self runScript:script arguments:@[@"theme", theme]];

  // Show confirmation
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:[NSString stringWithFormat:@"Applied %@ Theme", [sender.title substringFromIndex:2]]];
  [alert setInformativeText:@"Theme changes applied in real-time"];
  [alert addButtonWithTitle:@"OK"];
  alert.alertStyle = NSAlertStyleInformational;
  [alert runModal];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == self.iconGlyphField) {
    [self updateIconPreview];
  } else if (notification.object == self.spaceIconField) {
    [self updateSpaceIconPreview];
  } else if (notification.object == self.barColorHexField) {
    NSString *hex = [self normalizedColorString:self.barColorHexField.stringValue];
    NSColor *color = [self colorFromHexString:hex];
    if (color) {
      [self.barColorWell setColor:color];
    }
  } else if (notification.object == self.widgetColorHexField) {
    NSString *hex = [self normalizedColorString:self.widgetColorHexField.stringValue];
    NSColor *color = [self colorFromHexString:hex];
    if (color) {
      [self.widgetColorWell setColor:color];
    }
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
  [task launch];
}

- (void)windowDidResignKey:(NSNotification *)notification {
  [NSApp terminate:nil];
}

@end

int main(int argc, const char **argv) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    MenuController *delegate = [MenuController new];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [app run];
  }
  return 0;
}
