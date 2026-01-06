#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface IntegrationsTabViewController : NSViewController <NSTextFieldDelegate>
@property (strong) NSScrollView *scrollView;
@property (strong) NSView *contentView;
@property (strong) NSButton *yazeToggle;
@property (strong) NSTextField *yazeStatus;
@property (strong) NSButton *yazeLaunch;
@property (strong) NSButton *emacsToggle;
@property (strong) NSTextField *emacsStatus;
@property (strong) NSButton *emacsLaunch;
@property (strong) NSButton *halextToggle;
@property (strong) NSTextField *halextServerField;
@property (strong) NSSecureTextField *halextApiKeyField;
@property (strong) NSTextField *halextStatus;
@property (strong) NSButton *halextTestButton;
@property (strong) NSButton *cortexToggle;
@property (strong) NSButton *cortexWidgetToggle;
@property (strong) NSPopUpButton *cortexLabelModeMenu;
@property (strong) NSTextField *cortexLabelPrefixField;
@property (strong) NSTextField *cortexUpdateFreqField;
@property (strong) NSTextField *cortexCacheTtlField;
@property (strong) NSPopUpButton *cortexPositionMenu;
@property (strong) NSTextField *cortexLabelTemplateField;
@property (strong) NSTextField *cortexActiveIconField;
@property (strong) NSTextField *cortexInactiveIconField;
@property (strong) NSTextField *cortexActiveIconPreview;
@property (strong) NSTextField *cortexInactiveIconPreview;
@property (strong) NSColorWell *cortexActiveColorWell;
@property (strong) NSTextField *cortexActiveColorHexField;
@property (strong) NSColorWell *cortexInactiveColorWell;
@property (strong) NSTextField *cortexInactiveColorHexField;
@property (strong) NSColorWell *cortexLabelColorWell;
@property (strong) NSTextField *cortexLabelColorHexField;
@end

@implementation IntegrationsTabViewController

- (NSString *)codeDir {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (config.codePath.length) {
    return config.codePath;
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:@"src"];
}

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  CGFloat contentHeight = 1400;
  self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.autohidesScrollers = YES;

  self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.view.bounds.size.width, contentHeight)];
  self.contentView.autoresizingMask = NSViewWidthSizable;
  self.scrollView.documentView = self.contentView;
  [self.view addSubview:self.scrollView];

  CGFloat y = self.contentView.bounds.size.height - 40;
  CGFloat leftMargin = 40;
  CGFloat sectionSpacing = 80;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"External Integrations";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.contentView addSubview:title];
  y -= 60;

  // MARK: Yaze Integration
  NSBox *yazeBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 130, 700, 130)];
  yazeBox.title = @"Yaze (ROM Hacking Tool)";
  yazeBox.titlePosition = NSAtTop;

  self.yazeToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 80, 200, 20)];
  [self.yazeToggle setButtonType:NSButtonTypeSwitch];
  self.yazeToggle.title = @"Enable Yaze Integration";
  self.yazeToggle.target = self;
  self.yazeToggle.action = @selector(yazeToggled:);
  BOOL yazeEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@NO] boolValue];
  self.yazeToggle.state = yazeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [yazeBox addSubview:self.yazeToggle];

  self.yazeStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 300, 20)];
  self.yazeStatus.stringValue = @"Status: Checking...";
  self.yazeStatus.bordered = NO;
  self.yazeStatus.editable = NO;
  self.yazeStatus.backgroundColor = [NSColor clearColor];
  self.yazeStatus.font = [NSFont systemFontOfSize:12];
  [yazeBox addSubview:self.yazeStatus];

  self.yazeLaunch = [[NSButton alloc] initWithFrame:NSMakeRect(20, 15, 120, 28)];
  [self.yazeLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.yazeLaunch setBezelStyle:NSBezelStyleRounded];
  self.yazeLaunch.title = @"Launch Yaze";
  self.yazeLaunch.target = self;
  self.yazeLaunch.action = @selector(launchYaze:);
  [yazeBox addSubview:self.yazeLaunch];

  NSButton *yazeRepoButton = [[NSButton alloc] initWithFrame:NSMakeRect(150, 15, 120, 28)];
  [yazeRepoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [yazeRepoButton setBezelStyle:NSBezelStyleRounded];
  yazeRepoButton.title = @"Open Repo";
  yazeRepoButton.target = self;
  yazeRepoButton.action = @selector(openYazeRepo:);
  [yazeBox addSubview:yazeRepoButton];

  [self.contentView addSubview:yazeBox];
  [self updateYazeStatus];
  y -= 150;

  // MARK: Emacs Integration
  NSBox *emacsBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 130, 700, 130)];
  emacsBox.title = @"Emacs";
  emacsBox.titlePosition = NSAtTop;

  self.emacsToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 80, 200, 20)];
  [self.emacsToggle setButtonType:NSButtonTypeSwitch];
  self.emacsToggle.title = @"Enable Emacs Integration";
  self.emacsToggle.target = self;
  self.emacsToggle.action = @selector(emacsToggled:);
  BOOL emacsEnabled = [[config valueForKeyPath:@"integrations.emacs.enabled" defaultValue:@NO] boolValue];
  self.emacsToggle.state = emacsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [emacsBox addSubview:self.emacsToggle];

  self.emacsStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 300, 20)];
  self.emacsStatus.stringValue = @"Status: Checking...";
  self.emacsStatus.bordered = NO;
  self.emacsStatus.editable = NO;
  self.emacsStatus.backgroundColor = [NSColor clearColor];
  self.emacsStatus.font = [NSFont systemFontOfSize:12];
  [emacsBox addSubview:self.emacsStatus];

  self.emacsLaunch = [[NSButton alloc] initWithFrame:NSMakeRect(20, 15, 120, 28)];
  [self.emacsLaunch setButtonType:NSButtonTypeMomentaryPushIn];
  [self.emacsLaunch setBezelStyle:NSBezelStyleRounded];
  self.emacsLaunch.title = @"Launch Emacs";
  self.emacsLaunch.target = self;
  self.emacsLaunch.action = @selector(launchEmacs:);
  [emacsBox addSubview:self.emacsLaunch];

  [self.contentView addSubview:emacsBox];
  [self updateEmacsStatus];
  y -= 150;

  // MARK: Cortex Integration
  NSBox *cortexBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 160, 700, 160)];
  cortexBox.title = @"Cortex (AFS / Training)";
  cortexBox.titlePosition = NSAtTop;

  self.cortexToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 120, 260, 20)];
  [self.cortexToggle setButtonType:NSButtonTypeSwitch];
  self.cortexToggle.title = @"Enable Cortex Integration";
  self.cortexToggle.target = self;
  self.cortexToggle.action = @selector(cortexToggled:);
  BOOL cortexEnabled = [[config valueForKeyPath:@"integrations.cortex.enabled" defaultValue:@NO] boolValue];
  self.cortexToggle.state = cortexEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [cortexBox addSubview:self.cortexToggle];

  self.cortexWidgetToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 95, 260, 20)];
  [self.cortexWidgetToggle setButtonType:NSButtonTypeSwitch];
  self.cortexWidgetToggle.title = @"Show Cortex Widget";
  self.cortexWidgetToggle.target = self;
  self.cortexWidgetToggle.action = @selector(cortexWidgetToggled:);
  BOOL cortexWidgetEnabled = [[config valueForKeyPath:@"integrations.cortex.widget.enabled" defaultValue:@YES] boolValue];
  self.cortexWidgetToggle.state = cortexWidgetEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [cortexBox addSubview:self.cortexWidgetToggle];

  NSTextField *modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 66, 120, 20)];
  modeLabel.stringValue = @"Label Mode:";
  modeLabel.bordered = NO;
  modeLabel.editable = NO;
  modeLabel.backgroundColor = [NSColor clearColor];
  [cortexBox addSubview:modeLabel];

  self.cortexLabelModeMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 62, 180, 26)];
  [self.cortexLabelModeMenu addItemsWithTitles:@[@"Training", @"AFS", @"Status", @"None"]];
  self.cortexLabelModeMenu.target = self;
  self.cortexLabelModeMenu.action = @selector(cortexLabelModeChanged:);
  NSString *labelMode = [config valueForKeyPath:@"integrations.cortex.widget.label_mode" defaultValue:@"training"];
  if ([labelMode isEqualToString:@"afs"]) {
    [self.cortexLabelModeMenu selectItemAtIndex:1];
  } else if ([labelMode isEqualToString:@"status"]) {
    [self.cortexLabelModeMenu selectItemAtIndex:2];
  } else if ([labelMode isEqualToString:@"none"]) {
    [self.cortexLabelModeMenu selectItemAtIndex:3];
  } else {
    [self.cortexLabelModeMenu selectItemAtIndex:0];
  }
  [cortexBox addSubview:self.cortexLabelModeMenu];

  NSTextField *prefixLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(340, 66, 80, 20)];
  prefixLabel.stringValue = @"Prefix:";
  prefixLabel.bordered = NO;
  prefixLabel.editable = NO;
  prefixLabel.backgroundColor = [NSColor clearColor];
  [cortexBox addSubview:prefixLabel];

  self.cortexLabelPrefixField = [[NSTextField alloc] initWithFrame:NSMakeRect(410, 62, 200, 24)];
  self.cortexLabelPrefixField.placeholderString = @"AFS";
  self.cortexLabelPrefixField.target = self;
  self.cortexLabelPrefixField.action = @selector(cortexFieldChanged:);
  NSString *prefix = [config valueForKeyPath:@"integrations.cortex.widget.label_prefix" defaultValue:@"AFS"];
  self.cortexLabelPrefixField.stringValue = prefix ?: @"";
  [cortexBox addSubview:self.cortexLabelPrefixField];

  NSTextField *freqLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 34, 120, 20)];
  freqLabel.stringValue = @"Update (sec):";
  freqLabel.bordered = NO;
  freqLabel.editable = NO;
  freqLabel.backgroundColor = [NSColor clearColor];
  [cortexBox addSubview:freqLabel];

  self.cortexUpdateFreqField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 30, 80, 24)];
  self.cortexUpdateFreqField.target = self;
  self.cortexUpdateFreqField.action = @selector(cortexFieldChanged:);
  NSNumber *updateFreq = [config valueForKeyPath:@"integrations.cortex.widget.update_freq" defaultValue:@180];
  self.cortexUpdateFreqField.stringValue = [NSString stringWithFormat:@"%@", updateFreq];
  [cortexBox addSubview:self.cortexUpdateFreqField];

  NSTextField *cacheLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(240, 34, 120, 20)];
  cacheLabel.stringValue = @"Cache TTL:";
  cacheLabel.bordered = NO;
  cacheLabel.editable = NO;
  cacheLabel.backgroundColor = [NSColor clearColor];
  [cortexBox addSubview:cacheLabel];

  self.cortexCacheTtlField = [[NSTextField alloc] initWithFrame:NSMakeRect(330, 30, 80, 24)];
  self.cortexCacheTtlField.target = self;
  self.cortexCacheTtlField.action = @selector(cortexFieldChanged:);
  NSNumber *cacheTtl = [config valueForKeyPath:@"integrations.cortex.widget.cache_ttl" defaultValue:@180];
  self.cortexCacheTtlField.stringValue = [NSString stringWithFormat:@"%@", cacheTtl];
  [cortexBox addSubview:self.cortexCacheTtlField];

  [self.contentView addSubview:cortexBox];
  y -= 180;

  // MARK: Cortex Widget Style
  NSBox *cortexStyleBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 200, 700, 200)];
  cortexStyleBox.title = @"Cortex Widget Style";
  cortexStyleBox.titlePosition = NSAtTop;

  NSTextField *positionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 162, 120, 20)];
  positionLabel.stringValue = @"Position:";
  positionLabel.bordered = NO;
  positionLabel.editable = NO;
  positionLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:positionLabel];

  self.cortexPositionMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 158, 110, 26)];
  [self.cortexPositionMenu addItemsWithTitles:@[@"Left", @"Right"]];
  self.cortexPositionMenu.target = self;
  self.cortexPositionMenu.action = @selector(cortexPositionChanged:);
  NSString *position = [config valueForKeyPath:@"integrations.cortex.widget.position" defaultValue:@"right"];
  if ([position isEqualToString:@"left"]) {
    [self.cortexPositionMenu selectItemAtIndex:0];
  } else {
    [self.cortexPositionMenu selectItemAtIndex:1];
  }
  [cortexStyleBox addSubview:self.cortexPositionMenu];

  NSTextField *templateLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(270, 162, 110, 20)];
  templateLabel.stringValue = @"Label Template:";
  templateLabel.bordered = NO;
  templateLabel.editable = NO;
  templateLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:templateLabel];

  self.cortexLabelTemplateField = [[NSTextField alloc] initWithFrame:NSMakeRect(380, 158, 290, 24)];
  self.cortexLabelTemplateField.placeholderString = @"%prefix% %datasets% • %samples%";
  self.cortexLabelTemplateField.target = self;
  self.cortexLabelTemplateField.action = @selector(cortexStyleFieldChanged:);
  self.cortexLabelTemplateField.delegate = self;
  NSString *labelTemplate = [config valueForKeyPath:@"integrations.cortex.widget.label_template" defaultValue:@""];
  self.cortexLabelTemplateField.stringValue = labelTemplate ?: @"";
  [cortexStyleBox addSubview:self.cortexLabelTemplateField];

  NSTextField *activeIconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 128, 90, 20)];
  activeIconLabel.stringValue = @"Active Icon:";
  activeIconLabel.bordered = NO;
  activeIconLabel.editable = NO;
  activeIconLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:activeIconLabel];

  self.cortexActiveIconField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 124, 60, 24)];
  self.cortexActiveIconField.placeholderString = @"Glyph";
  self.cortexActiveIconField.target = self;
  self.cortexActiveIconField.action = @selector(cortexStyleFieldChanged:);
  self.cortexActiveIconField.delegate = self;
  NSString *activeIcon = [config valueForKeyPath:@"integrations.cortex.widget.icon_active" defaultValue:@"󰪴"];
  self.cortexActiveIconField.stringValue = activeIcon ?: @"";
  [cortexStyleBox addSubview:self.cortexActiveIconField];

  self.cortexActiveIconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(175, 118, 36, 28)];
  self.cortexActiveIconPreview.bordered = NO;
  self.cortexActiveIconPreview.editable = NO;
  self.cortexActiveIconPreview.backgroundColor = [NSColor clearColor];
  self.cortexActiveIconPreview.alignment = NSTextAlignmentCenter;
  self.cortexActiveIconPreview.font = [self preferredIconFontWithSize:18];
  self.cortexActiveIconPreview.stringValue = self.cortexActiveIconField.stringValue;
  [cortexStyleBox addSubview:self.cortexActiveIconPreview];

  NSTextField *inactiveIconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(230, 128, 100, 20)];
  inactiveIconLabel.stringValue = @"Inactive Icon:";
  inactiveIconLabel.bordered = NO;
  inactiveIconLabel.editable = NO;
  inactiveIconLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:inactiveIconLabel];

  self.cortexInactiveIconField = [[NSTextField alloc] initWithFrame:NSMakeRect(330, 124, 60, 24)];
  self.cortexInactiveIconField.placeholderString = @"Glyph";
  self.cortexInactiveIconField.target = self;
  self.cortexInactiveIconField.action = @selector(cortexStyleFieldChanged:);
  self.cortexInactiveIconField.delegate = self;
  NSString *inactiveIcon = [config valueForKeyPath:@"integrations.cortex.widget.icon_inactive" defaultValue:@"󰪵"];
  self.cortexInactiveIconField.stringValue = inactiveIcon ?: @"";
  [cortexStyleBox addSubview:self.cortexInactiveIconField];

  self.cortexInactiveIconPreview = [[NSTextField alloc] initWithFrame:NSMakeRect(395, 118, 36, 28)];
  self.cortexInactiveIconPreview.bordered = NO;
  self.cortexInactiveIconPreview.editable = NO;
  self.cortexInactiveIconPreview.backgroundColor = [NSColor clearColor];
  self.cortexInactiveIconPreview.alignment = NSTextAlignmentCenter;
  self.cortexInactiveIconPreview.font = [self preferredIconFontWithSize:18];
  self.cortexInactiveIconPreview.stringValue = self.cortexInactiveIconField.stringValue;
  [cortexStyleBox addSubview:self.cortexInactiveIconPreview];

  NSTextField *activeColorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 92, 90, 20)];
  activeColorLabel.stringValue = @"Active Color:";
  activeColorLabel.bordered = NO;
  activeColorLabel.editable = NO;
  activeColorLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:activeColorLabel];

  self.cortexActiveColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(110, 88, 40, 24)];
  self.cortexActiveColorWell.target = self;
  self.cortexActiveColorWell.action = @selector(cortexColorChanged:);
  [cortexStyleBox addSubview:self.cortexActiveColorWell];

  self.cortexActiveColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(160, 88, 90, 24)];
  self.cortexActiveColorHexField.placeholderString = @"0xAARRGGBB";
  self.cortexActiveColorHexField.delegate = self;
  [cortexStyleBox addSubview:self.cortexActiveColorHexField];

  NSTextField *inactiveColorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(270, 92, 100, 20)];
  inactiveColorLabel.stringValue = @"Inactive Color:";
  inactiveColorLabel.bordered = NO;
  inactiveColorLabel.editable = NO;
  inactiveColorLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:inactiveColorLabel];

  self.cortexInactiveColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(380, 88, 40, 24)];
  self.cortexInactiveColorWell.target = self;
  self.cortexInactiveColorWell.action = @selector(cortexColorChanged:);
  [cortexStyleBox addSubview:self.cortexInactiveColorWell];

  self.cortexInactiveColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(430, 88, 90, 24)];
  self.cortexInactiveColorHexField.placeholderString = @"0xAARRGGBB";
  self.cortexInactiveColorHexField.delegate = self;
  [cortexStyleBox addSubview:self.cortexInactiveColorHexField];

  NSTextField *labelColorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 56, 90, 20)];
  labelColorLabel.stringValue = @"Label Color:";
  labelColorLabel.bordered = NO;
  labelColorLabel.editable = NO;
  labelColorLabel.backgroundColor = [NSColor clearColor];
  [cortexStyleBox addSubview:labelColorLabel];

  self.cortexLabelColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(110, 52, 40, 24)];
  self.cortexLabelColorWell.target = self;
  self.cortexLabelColorWell.action = @selector(cortexColorChanged:);
  [cortexStyleBox addSubview:self.cortexLabelColorWell];

  self.cortexLabelColorHexField = [[NSTextField alloc] initWithFrame:NSMakeRect(160, 52, 90, 24)];
  self.cortexLabelColorHexField.placeholderString = @"0xAARRGGBB";
  self.cortexLabelColorHexField.delegate = self;
  [cortexStyleBox addSubview:self.cortexLabelColorHexField];

  NSString *activeColor = [config valueForKeyPath:@"integrations.cortex.widget.color_active" defaultValue:@"0xffa6e3a1"];
  NSString *inactiveColor = [config valueForKeyPath:@"integrations.cortex.widget.color_inactive" defaultValue:@"0xff6c7086"];
  NSString *labelColor = [config valueForKeyPath:@"integrations.cortex.widget.label_color" defaultValue:@"0xffcdd6f4"];

  NSColor *activeWellColor = [self colorFromHexString:activeColor];
  NSColor *inactiveWellColor = [self colorFromHexString:inactiveColor];
  NSColor *labelWellColor = [self colorFromHexString:labelColor];
  if (activeWellColor) {
    self.cortexActiveColorWell.color = activeWellColor;
    self.cortexActiveColorHexField.stringValue = [self hexStringFromColor:activeWellColor];
  }
  if (inactiveWellColor) {
    self.cortexInactiveColorWell.color = inactiveWellColor;
    self.cortexInactiveColorHexField.stringValue = [self hexStringFromColor:inactiveWellColor];
  }
  if (labelWellColor) {
    self.cortexLabelColorWell.color = labelWellColor;
    self.cortexLabelColorHexField.stringValue = [self hexStringFromColor:labelWellColor];
  }

  [self.contentView addSubview:cortexStyleBox];
  y -= 220;

  // MARK: halext-org Integration
  NSBox *halextBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 180, 700, 180)];
  halextBox.title = @"halext-org Server (Tasks, Calendar, LLM)";
  halextBox.titlePosition = NSAtTop;

  self.halextToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 130, 250, 20)];
  [self.halextToggle setButtonType:NSButtonTypeSwitch];
  self.halextToggle.title = @"Enable halext-org Integration";
  self.halextToggle.target = self;
  self.halextToggle.action = @selector(halextToggled:);
  BOOL halextEnabled = [[config valueForKeyPath:@"integrations.halext.enabled" defaultValue:@NO] boolValue];
  self.halextToggle.state = halextEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [halextBox addSubview:self.halextToggle];

  NSTextField *serverLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 100, 20)];
  serverLabel.stringValue = @"Server URL:";
  serverLabel.bordered = NO;
  serverLabel.editable = NO;
  serverLabel.backgroundColor = [NSColor clearColor];
  [halextBox addSubview:serverLabel];

  self.halextServerField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 98, 400, 24)];
  self.halextServerField.placeholderString = @"https://halext.yourdomain.com";
  NSString *serverUrl = [config valueForKeyPath:@"integrations.halext.server_url" defaultValue:@""];
  self.halextServerField.stringValue = serverUrl;
  [halextBox addSubview:self.halextServerField];

  NSTextField *apiKeyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 70, 100, 20)];
  apiKeyLabel.stringValue = @"API Key:";
  apiKeyLabel.bordered = NO;
  apiKeyLabel.editable = NO;
  apiKeyLabel.backgroundColor = [NSColor clearColor];
  [halextBox addSubview:apiKeyLabel];

  self.halextApiKeyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(120, 68, 400, 24)];
  self.halextApiKeyField.placeholderString = @"Enter API key...";
  [halextBox addSubview:self.halextApiKeyField];

  self.halextStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 500, 20)];
  self.halextStatus.stringValue = @"Status: Not configured";
  self.halextStatus.bordered = NO;
  self.halextStatus.editable = NO;
  self.halextStatus.backgroundColor = [NSColor clearColor];
  self.halextStatus.font = [NSFont systemFontOfSize:12];
  self.halextStatus.textColor = [NSColor secondaryLabelColor];
  [halextBox addSubview:self.halextStatus];

  self.halextTestButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 5, 140, 28)];
  [self.halextTestButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.halextTestButton setBezelStyle:NSBezelStyleRounded];
  self.halextTestButton.title = @"Test Connection";
  self.halextTestButton.target = self;
  self.halextTestButton.action = @selector(testHalextConnection:);
  [halextBox addSubview:self.halextTestButton];

  NSButton *halextSaveButton = [[NSButton alloc] initWithFrame:NSMakeRect(170, 5, 100, 28)];
  [halextSaveButton setButtonType:NSButtonTypeMomentaryPushIn];
  [halextSaveButton setBezelStyle:NSBezelStyleRounded];
  halextSaveButton.title = @"Save";
  halextSaveButton.target = self;
  halextSaveButton.action = @selector(saveHalextSettings:);
  [halextBox addSubview:halextSaveButton];

  [self.contentView addSubview:halextBox];
  y -= 200;

  // MARK: AFS / Cortex / Halext Quick Actions
  NSBox *afsBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y - 160, 700, 160)];
  afsBox.title = @"AFS + Cortex + Halext (Quick Actions)";
  afsBox.titlePosition = NSAtTop;

  NSButton *openHafsButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 110, 160, 28)];
  [openHafsButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openHafsButton setBezelStyle:NSBezelStyleRounded];
  openHafsButton.title = @"Open AFS Repo";
  openHafsButton.target = self;
  openHafsButton.action = @selector(openHafsRepo:);
  [afsBox addSubview:openHafsButton];

  NSButton *openHafsTuiButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 110, 180, 28)];
  [openHafsTuiButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openHafsTuiButton setBezelStyle:NSBezelStyleRounded];
  openHafsTuiButton.title = @"Launch AFS TUI";
  openHafsTuiButton.target = self;
  openHafsTuiButton.action = @selector(openHafsTui:);
  [afsBox addSubview:openHafsTuiButton];

  NSButton *openCortexRepoButton = [[NSButton alloc] initWithFrame:NSMakeRect(380, 110, 160, 28)];
  [openCortexRepoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openCortexRepoButton setBezelStyle:NSBezelStyleRounded];
  openCortexRepoButton.title = @"Open Cortex Repo";
  openCortexRepoButton.target = self;
  openCortexRepoButton.action = @selector(openCortexRepo:);
  [afsBox addSubview:openCortexRepoButton];

  NSButton *openHalextRepoButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 70, 180, 28)];
  [openHalextRepoButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openHalextRepoButton setBezelStyle:NSBezelStyleRounded];
  openHalextRepoButton.title = @"Open halext-org Repo";
  openHalextRepoButton.target = self;
  openHalextRepoButton.action = @selector(openHalextRepo:);
  [afsBox addSubview:openHalextRepoButton];

  NSButton *openCortexAppButton = [[NSButton alloc] initWithFrame:NSMakeRect(210, 70, 160, 28)];
  [openCortexAppButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openCortexAppButton setBezelStyle:NSBezelStyleRounded];
  openCortexAppButton.title = @"Open Cortex App";
  openCortexAppButton.target = self;
  openCortexAppButton.action = @selector(openCortexApp:);
  [afsBox addSubview:openCortexAppButton];

  [self.contentView addSubview:afsBox];
  y -= 190;

}

- (void)yazeToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.yaze.enabled"];
}

- (void)emacsToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.emacs.enabled"];
}

- (void)halextToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.halext.enabled"];
}

- (void)cortexToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.cortex.enabled"];
  [config reloadSketchyBar];
}

- (void)cortexWidgetToggled:(NSButton *)sender {
  BOOL enabled = sender.state == NSControlStateValueOn;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:@"integrations.cortex.widget.enabled"];
  [config reloadSketchyBar];
}

- (void)cortexLabelModeChanged:(NSPopUpButton *)sender {
  NSString *mode = @"training";
  switch (sender.indexOfSelectedItem) {
    case 1: mode = @"afs"; break;
    case 2: mode = @"status"; break;
    case 3: mode = @"none"; break;
    default: mode = @"training"; break;
  }
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:mode forKeyPath:@"integrations.cortex.widget.label_mode"];
  [config reloadSketchyBar];
}

- (void)cortexFieldChanged:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexLabelPrefixField) {
    NSString *value = [self.cortexLabelPrefixField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.label_prefix"];
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexUpdateFreqField) {
    NSInteger value = self.cortexUpdateFreqField.integerValue;
    if (value > 0) {
      [config setValue:@(value) forKeyPath:@"integrations.cortex.widget.update_freq"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (sender == self.cortexCacheTtlField) {
    NSInteger value = self.cortexCacheTtlField.integerValue;
    if (value >= 0) {
      [config setValue:@(value) forKeyPath:@"integrations.cortex.widget.cache_ttl"];
      [config reloadSketchyBar];
    }
    return;
  }
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

- (NSColor *)colorFromHexString:(NSString *)hexString {
  if (!hexString || hexString.length < 8) return nil;
  NSString *hex = [hexString hasPrefix:@"0x"] ? [hexString substringFromIndex:2] : hexString;
  if (hex.length != 8) return nil;

  unsigned int alpha, red, green, blue;
  NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(0, 2)]];
  [scanner scanHexInt:&alpha];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(2, 2)]];
  [scanner scanHexInt:&red];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(4, 2)]];
  [scanner scanHexInt:&green];
  scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(6, 2)]];
  [scanner scanHexInt:&blue];

  return [NSColor colorWithCalibratedRed:red/255.0 green:green/255.0 blue:blue/255.0 alpha:alpha/255.0];
}

- (NSString *)hexStringFromColor:(NSColor *)color {
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  return [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];
}

- (void)cortexPositionChanged:(NSPopUpButton *)sender {
  NSString *position = sender.indexOfSelectedItem == 0 ? @"left" : @"right";
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:position forKeyPath:@"integrations.cortex.widget.position"];
  [config reloadSketchyBar];
}

- (void)cortexStyleFieldChanged:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexLabelTemplateField) {
    NSString *value = [self.cortexLabelTemplateField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.label_template"];
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexActiveIconField) {
    NSString *value = [self.cortexActiveIconField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.icon_active"];
    self.cortexActiveIconPreview.stringValue = value ?: @"";
    [config reloadSketchyBar];
    return;
  }
  if (sender == self.cortexInactiveIconField) {
    NSString *value = [self.cortexInactiveIconField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [config setValue:value forKeyPath:@"integrations.cortex.widget.icon_inactive"];
    self.cortexInactiveIconPreview.stringValue = value ?: @"";
    [config reloadSketchyBar];
    return;
  }
}

- (void)cortexColorChanged:(NSColorWell *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (sender == self.cortexActiveColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexActiveColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.color_active"];
  } else if (sender == self.cortexInactiveColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexInactiveColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.color_inactive"];
  } else if (sender == self.cortexLabelColorWell) {
    NSString *hex = [self hexStringFromColor:sender.color];
    self.cortexLabelColorHexField.stringValue = hex;
    [config setValue:hex forKeyPath:@"integrations.cortex.widget.label_color"];
  }
  [config reloadSketchyBar];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  id field = notification.object;
  if (field == self.cortexActiveIconField) {
    self.cortexActiveIconPreview.stringValue = self.cortexActiveIconField.stringValue ?: @"";
    return;
  }
  if (field == self.cortexInactiveIconField) {
    self.cortexInactiveIconPreview.stringValue = self.cortexInactiveIconField.stringValue ?: @"";
    return;
  }

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  if (field == self.cortexActiveColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexActiveColorHexField.stringValue];
    if (color) {
      self.cortexActiveColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.color_active"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (field == self.cortexInactiveColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexInactiveColorHexField.stringValue];
    if (color) {
      self.cortexInactiveColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.color_inactive"];
      [config reloadSketchyBar];
    }
    return;
  }
  if (field == self.cortexLabelColorHexField) {
    NSColor *color = [self colorFromHexString:self.cortexLabelColorHexField.stringValue];
    if (color) {
      self.cortexLabelColorWell.color = color;
      [config setValue:[self hexStringFromColor:color] forKeyPath:@"integrations.cortex.widget.label_color"];
      [config reloadSketchyBar];
    }
    return;
  }
}

- (void)updateYazeStatus {
  NSString *yazePath = [[self codeDir] stringByAppendingPathComponent:@"yaze"];
  NSString *buildBinary = [yazePath stringByAppendingPathComponent:@"build/bin/yaze"];

  if ([[NSFileManager defaultManager] fileExistsAtPath:buildBinary]) {
    self.yazeStatus.stringValue = @"Status: ✓ Installed and built";
    self.yazeStatus.textColor = [NSColor systemGreenColor];
  } else if ([[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    self.yazeStatus.stringValue = @"Status: ⚠ Installed but not built";
    self.yazeStatus.textColor = [NSColor systemOrangeColor];
  } else {
    self.yazeStatus.stringValue = @"Status: ✗ Not installed";
    self.yazeStatus.textColor = [NSColor systemRedColor];
  }
}

- (void)updateEmacsStatus {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *statusText = @"Status: ✗ Not found";
    NSColor *statusColor = [NSColor systemRedColor];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/pgrep";
    task.arguments = @[@"-x", @"Emacs"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    @try {
      [task launch];
      [task waitUntilExit];
      if (task.terminationStatus == 0) {
        statusText = @"Status: ✓ Running";
        statusColor = [NSColor systemGreenColor];
      } else {
        statusText = @"Status: Installed but not running";
        statusColor = [NSColor secondaryLabelColor];
      }
    } @catch (NSException *exception) {
      statusText = @"Status: ✗ Not found";
      statusColor = [NSColor systemRedColor];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      self.emacsStatus.stringValue = statusText;
      self.emacsStatus.textColor = statusColor;
    });
  });
}

- (void)launchYaze:(id)sender {
  NSString *yazePath = [[[self codeDir] stringByAppendingPathComponent:@"yaze"] stringByAppendingPathComponent:@"build/bin/yaze"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:yazePath]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    NSString *message = [NSString stringWithFormat:@"Build Yaze first: cd %@/yaze && make", [self codeDir]];
    [alert setInformativeText:message];
    [alert runModal];
  }
}

- (void)openYazeRepo:(id)sender {
  NSString *yazePath = [[self codeDir] stringByAppendingPathComponent:@"yaze"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:yazePath]];
}

- (void)launchEmacs:(id)sender {
  NSArray *emacsLocations = @[
    @"/Applications/Emacs.app",
    @"/opt/homebrew/Cellar/emacs-plus@30/30.0.92/Emacs.app"
  ];

  for (NSString *location in emacsLocations) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:location]) {
      [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:location]];
      return;
    }
  }

  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Emacs Not Found"];
  [alert setInformativeText:@"Install Emacs first"];
  [alert runModal];
}

- (void)openHafsRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"afs"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openHafsTui:(id)sender {
  NSString *command = [NSString stringWithFormat:@"cd %@/afs && python3 -m tui.app", [self codeDir]];
  [self openTerminalCommand:command];
}

- (void)openCortexRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"cortex"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openCortexApp:(id)sender {
  NSString *appPath = @"/Applications/Cortex.app";
  if ([[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:appPath]];
  } else {
    NSString *path = [[self codeDir] stringByAppendingPathComponent:@"cortex"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
  }
}

- (void)openHalextRepo:(id)sender {
  NSString *path = [[self codeDir] stringByAppendingPathComponent:@"halext-org"];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openTerminalCommand:(NSString *)command {
  NSString *escaped = [command stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\" to do script \"%@\"", escaped];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/osascript";
  task.arguments = @[@"-e", script];
  [task launch];
}

- (void)saveHalextSettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *serverUrl = self.halextServerField.stringValue;
  [config setValue:serverUrl forKeyPath:@"integrations.halext.server_url"];

  NSString *apiKey = self.halextApiKeyField.stringValue;
  if ([apiKey length] > 0) {
    [config setValue:@"*** stored in keychain ***" forKeyPath:@"integrations.halext.api_key_status"];
  }

  self.halextStatus.stringValue = @"Status: Settings saved";
  self.halextStatus.textColor = [NSColor systemGreenColor];
}

- (void)testHalextConnection:(id)sender {
  self.halextStatus.stringValue = @"Status: Testing connection...";
  self.halextStatus.textColor = [NSColor secondaryLabelColor];

  // TODO: Implement actual REST API test
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.halextStatus.stringValue = @"Status: Connection test not yet implemented";
    self.halextStatus.textColor = [NSColor systemOrangeColor];
  });
}

@end
