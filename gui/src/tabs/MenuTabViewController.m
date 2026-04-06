#import "ConfigurationManager.h"
#import "MenuTabViewController.h"

@interface MenuTabViewController ()
@property (strong) NSArray<NSDictionary *> *tools;
@property (strong) NSArray<NSDictionary *> *sections;
@property (strong) NSScrollView *scrollView;
@property (strong) NSView *contentView;
@property (strong) NSButton *showMissingToggle;
@property (strong) NSButton *allowTerminalToggle;
@property (strong) NSColorWell *hoverColorWell;
@property (strong) NSColorWell *hoverBorderColorWell;
@property (strong) NSTextField *hoverBorderWidthField;
@property (strong) NSTextField *workDomainField;
@property (strong) NSTextField *workAppsFileField;
@property (strong) NSButton *applyWorkAppsButton;
@property (strong) NSButton *openWorkAppsFileButton;
@property (strong) NSButton *projectShortcutsToggle;
@property (strong) NSPopUpButton *projectDefaultActionPopup;
@property (strong) NSTextField *projectFileField;
@property (strong) NSButton *applyProjectsButton;
@property (strong) NSButton *discoverProjectsButton;
@property (strong) NSButton *openProjectsFileButton;
@end

@implementation MenuTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL yazeDefaultEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@NO] boolValue];

  self.tools = @[
    @{@"key": @"afs_browser", @"label": @"AFS Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"afs_context", @"label": @"AFS Context Query", @"icon": @"󰊕", @"default_enabled": @YES},
    @{@"key": @"afs_scratchpad", @"label": @"AFS Scratchpad", @"icon": @"󰏫", @"default_enabled": @NO},
    @{@"key": @"afs_studio", @"label": @"AFS Studio", @"icon": @"󰆍", @"default_enabled": @YES},
    @{@"key": @"afs_labeler", @"label": @"AFS Labeler", @"icon": @"󰓹", @"default_enabled": @YES},
    @{@"key": @"stemforge", @"label": @"StemForge", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"stem_sampler", @"label": @"StemSampler", @"icon": @"󰎈", @"default_enabled": @YES},
    @{@"key": @"yaze", @"label": @"Yaze", @"icon": @"󰯙", @"default_enabled": @(yazeDefaultEnabled)},
    @{@"key": @"mesen_oos", @"label": @"Mesen2 OoS", @"icon": @"󰁆", @"default_enabled": @YES},
    @{@"key": @"oracle_agent_manager", @"label": @"Oracle Agent Manager", @"icon": @"󰒋", @"default_enabled": @YES},
    @{@"key": @"help_center", @"label": @"Help Center", @"icon": @"󰘥", @"default_enabled": @YES},
    @{@"key": @"sys_manual", @"label": @"Sys Manual", @"icon": @"󰋜", @"default_enabled": @YES},
    @{@"key": @"icon_browser", @"label": @"Icon Browser", @"icon": @"󰈙", @"default_enabled": @YES},
    @{@"key": @"keyboard_overlay", @"label": @"Keyboard Overlay", @"icon": @"󰌌", @"default_enabled": @YES},
    @{@"key": @"barista_config", @"label": @"Barista Config", @"icon": @"󰒓", @"default_enabled": @YES},
    @{@"key": @"reload_bar", @"label": @"Reload SketchyBar", @"icon": @"󰑐", @"default_enabled": @YES}
  ];
  self.sections = @[
    @{@"key": @"apps", @"label": @"Apps", @"icon": @"󰀻"},
    @{@"key": @"oracle", @"label": @"Oracle", @"icon": @"󰊠"},
    @{@"key": @"controls", @"label": @"Controls", @"icon": @"󰒓"},
    @{@"key": @"work", @"label": @"Web Apps", @"icon": @"󰖟"},
    @{@"key": @"support", @"label": @"Support", @"icon": @"󰘥"},
    @{@"key": @"afs", @"label": @"AFS Tools", @"icon": @"󰈙"},
    @{@"key": @"audio", @"label": @"Audio", @"icon": @"󰎈"},
    @{@"key": @"custom", @"label": @"Custom", @"icon": @"󰘥"}
  ];

  NSStackView *rootStack = nil;
  self.scrollView = [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(28, 34, 34, 34) spacing:20];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Menu Composer";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hint.stringValue = @"Decide what the Apple menu owns and keep the sections intentional. Barista config belongs in Controls, Oracle actions belong in Oracle, and support tools stay clearly separated from daily apps.";
  hint.font = [NSFont systemFontOfSize:13];
  hint.textColor = [NSColor secondaryLabelColor];
  hint.bordered = NO;
  hint.editable = NO;
  hint.backgroundColor = [NSColor clearColor];
  hint.usesSingleLineMode = NO;
  hint.lineBreakMode = NSLineBreakByWordWrapping;
  [rootStack addView:hint inGravity:NSStackViewGravityTop];

  NSBox *heroBox = [[NSBox alloc] initWithFrame:NSZeroRect];
  heroBox.boxType = NSBoxCustom;
  heroBox.titlePosition = NSNoTitle;
  heroBox.cornerRadius = 14.0;
  heroBox.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08];
  heroBox.fillColor = [NSColor colorWithCalibratedRed:0.11 green:0.12 blue:0.15 alpha:0.95];
  heroBox.transparent = NO;
  [rootStack addView:heroBox inGravity:NSStackViewGravityTop];
  [heroBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *heroStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  heroStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  heroStack.alignment = NSLayoutAttributeLeading;
  heroStack.spacing = 8;
  heroStack.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
  heroBox.contentView = heroStack;

  NSTextField *heroTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  heroTitle.stringValue = @"The Apple menu should feel like a curated launcher, not a dumping ground.";
  heroTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  heroTitle.bordered = NO;
  heroTitle.editable = NO;
  heroTitle.backgroundColor = [NSColor clearColor];
  [heroStack addView:heroTitle inGravity:NSStackViewGravityTop];

  NSTextField *heroBody = [[NSTextField alloc] initWithFrame:NSZeroRect];
  heroBody.stringValue = @"Use section order, hover polish, and app discovery together so the popup reads like a system layer with a clear voice instead of a flat tool list.";
  heroBody.font = [NSFont systemFontOfSize:12];
  heroBody.textColor = [NSColor secondaryLabelColor];
  heroBody.bordered = NO;
  heroBody.editable = NO;
  heroBody.backgroundColor = [NSColor clearColor];
  heroBody.usesSingleLineMode = NO;
  heroBody.lineBreakMode = NSLineBreakByWordWrapping;
  [heroStack addView:heroBody inGravity:NSStackViewGravityTop];

  NSStackView *heroMeta = [[NSStackView alloc] initWithFrame:NSZeroRect];
  heroMeta.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  heroMeta.spacing = 14;
  [heroStack addView:heroMeta inGravity:NSStackViewGravityTop];
  for (NSString *meta in @[@"Apps", @"Oracle", @"Controls", @"Support"]) {
    NSTextField *metaLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    metaLabel.stringValue = meta;
    metaLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    metaLabel.textColor = [NSColor colorWithCalibratedRed:0.64 green:0.84 blue:1.0 alpha:1.0];
    metaLabel.bordered = NO;
    metaLabel.editable = NO;
    metaLabel.backgroundColor = [NSColor clearColor];
    [heroMeta addView:metaLabel inGravity:NSStackViewGravityLeading];
  }

  NSStackView *surfaceSection = nil;
  NSBox *surfaceBox = [self sectionBoxWithTitle:@"Menu Surface"
                                       subtitle:@"Adjust high-level popup behavior before you start editing individual tools."
                                    contentStack:&surfaceSection];
  [rootStack addView:surfaceBox inGravity:NSStackViewGravityTop];
  [surfaceBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  // Options row
  NSStackView *optionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  optionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  optionsRow.spacing = 20;
  [surfaceSection addView:optionsRow inGravity:NSStackViewGravityTop];

  BOOL showMissing = [[config valueForKeyPath:@"menus.apple.show_missing" defaultValue:@NO] boolValue];
  self.showMissingToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.showMissingToggle setButtonType:NSButtonTypeSwitch];
  self.showMissingToggle.title = @"Show missing tools";
  self.showMissingToggle.target = self;
  self.showMissingToggle.action = @selector(toggleShowMissing:);
  self.showMissingToggle.state = showMissing ? NSControlStateValueOn : NSControlStateValueOff;
  [optionsRow addView:self.showMissingToggle inGravity:NSStackViewGravityLeading];

  BOOL allowTerminal = [[config valueForKeyPath:@"menus.apple.terminal" defaultValue:@NO] boolValue];
  self.allowTerminalToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.allowTerminalToggle setButtonType:NSButtonTypeSwitch];
  self.allowTerminalToggle.title = @"Allow terminal-only tools";
  self.allowTerminalToggle.target = self;
  self.allowTerminalToggle.action = @selector(toggleAllowTerminal:);
  self.allowTerminalToggle.state = allowTerminal ? NSControlStateValueOn : NSControlStateValueOff;
  [optionsRow addView:self.allowTerminalToggle inGravity:NSStackViewGravityLeading];

  NSStackView *hoverSection = [[NSStackView alloc] initWithFrame:NSZeroRect];
  hoverSection.orientation = NSUserInterfaceLayoutOrientationVertical;
  hoverSection.spacing = 10;
  [surfaceSection addView:hoverSection inGravity:NSStackViewGravityTop];

  NSTextField *hoverTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hoverTitle.stringValue = @"Hover Style";
  hoverTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  hoverTitle.bordered = NO;
  hoverTitle.editable = NO;
  hoverTitle.backgroundColor = [NSColor clearColor];
  [hoverSection addView:hoverTitle inGravity:NSStackViewGravityTop];

  NSTextField *hoverHint = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hoverHint.stringValue = @"Tune the Apple-menu popup hover highlight without editing JSON by hand. Reset clears the menu-specific override and falls back to your global appearance settings.";
  hoverHint.font = [NSFont systemFontOfSize:12];
  hoverHint.textColor = [NSColor secondaryLabelColor];
  hoverHint.bordered = NO;
  hoverHint.editable = NO;
  hoverHint.backgroundColor = [NSColor clearColor];
  hoverHint.usesSingleLineMode = NO;
  hoverHint.lineBreakMode = NSLineBreakByWordWrapping;
  [hoverSection addView:hoverHint inGravity:NSStackViewGravityTop];

  NSStackView *hoverRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  hoverRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  hoverRow.spacing = 12;
  [hoverSection addView:hoverRow inGravity:NSStackViewGravityTop];

  NSTextField *hoverColorLabel = [self headerLabel:@"HOVER"];
  [hoverColorLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [hoverRow addView:hoverColorLabel inGravity:NSStackViewGravityLeading];

  self.hoverColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 54, 28)];
  self.hoverColorWell.target = self;
  self.hoverColorWell.action = @selector(hoverColorChanged:);
  [hoverRow addView:self.hoverColorWell inGravity:NSStackViewGravityLeading];

  NSTextField *hoverBorderColorLabel = [self headerLabel:@"BORDER"];
  [hoverBorderColorLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [hoverRow addView:hoverBorderColorLabel inGravity:NSStackViewGravityLeading];

  self.hoverBorderColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 54, 28)];
  self.hoverBorderColorWell.target = self;
  self.hoverBorderColorWell.action = @selector(hoverBorderColorChanged:);
  [hoverRow addView:self.hoverBorderColorWell inGravity:NSStackViewGravityLeading];

  NSTextField *hoverBorderWidthLabel = [self headerLabel:@"WIDTH"];
  [hoverBorderWidthLabel.widthAnchor constraintEqualToConstant:50].active = YES;
  [hoverRow addView:hoverBorderWidthLabel inGravity:NSStackViewGravityLeading];

  self.hoverBorderWidthField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.hoverBorderWidthField.placeholderString = @"Auto";
  self.hoverBorderWidthField.identifier = @"menu.hover.border_width";
  self.hoverBorderWidthField.delegate = self;
  [self.hoverBorderWidthField.widthAnchor constraintEqualToConstant:70].active = YES;
  [hoverRow addView:self.hoverBorderWidthField inGravity:NSStackViewGravityLeading];

  NSButton *resetHoverButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  resetHoverButton.title = @"Reset Hover";
  resetHoverButton.target = self;
  resetHoverButton.action = @selector(resetHoverOverrides:);
  [hoverRow addView:resetHoverButton inGravity:NSStackViewGravityLeading];

  [self refreshHoverControls];

  NSStackView *sectionsContainer = nil;
  NSBox *sectionsBox = [self sectionBoxWithTitle:@"Popup Sections"
                                        subtitle:@"Keep top-level categories clear and ordered so the Apple menu reads like a system launcher rather than a mixed bucket of tools."
                                     contentStack:&sectionsContainer];
  [rootStack addView:sectionsBox inGravity:NSStackViewGravityTop];
  [sectionsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSStackView *sectionsSection = [[NSStackView alloc] initWithFrame:NSZeroRect];
  sectionsSection.orientation = NSUserInterfaceLayoutOrientationVertical;
  sectionsSection.spacing = 10;
  [sectionsContainer addView:sectionsSection inGravity:NSStackViewGravityTop];

  NSGridView *sectionsGrid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  sectionsGrid.rowSpacing = 10;
  sectionsGrid.columnSpacing = 16;
  sectionsGrid.xPlacement = NSGridCellPlacementLeading;
  sectionsGrid.yPlacement = NSGridCellPlacementCenter;
  [sectionsSection addView:sectionsGrid inGravity:NSStackViewGravityTop];

  [sectionsGrid addRowWithViews:@[
    [self headerLabel:@"ICON"],
    [self headerLabel:@"LABEL"],
    [self headerLabel:@"ORDER"]
  ]];

  for (NSInteger index = 0; index < self.sections.count; index++) {
    NSDictionary *section = self.sections[index];
    NSString *key = section[@"key"] ?: @"";
    NSString *baseLabel = section[@"label"] ?: @"";
    NSString *baseIcon = section[@"icon"] ?: @"";

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [iconField.widthAnchor constraintEqualToConstant:50].active = YES;
    iconField.stringValue = [config valueForKeyPath:[NSString stringWithFormat:@"menus.apple.sections.%@.icon", key] defaultValue:baseIcon] ?: baseIcon;
    iconField.font = [self preferredIconFontWithSize:18];
    iconField.alignment = NSTextAlignmentCenter;
    iconField.tag = 1000 + index;
    iconField.identifier = @"section.icon";
    iconField.delegate = self;

    NSTextField *labelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [labelField.widthAnchor constraintEqualToConstant:220].active = YES;
    labelField.stringValue = [config valueForKeyPath:[NSString stringWithFormat:@"menus.apple.sections.%@.label", key] defaultValue:baseLabel] ?: baseLabel;
    labelField.font = [NSFont systemFontOfSize:13];
    labelField.tag = 1000 + index;
    labelField.identifier = @"section.label";
    labelField.delegate = self;

    NSTextField *orderField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [orderField.widthAnchor constraintEqualToConstant:70].active = YES;
    id orderValue = [config valueForKeyPath:[NSString stringWithFormat:@"menus.apple.sections.%@.order", key] defaultValue:nil];
    if ([orderValue isKindOfClass:[NSNumber class]]) orderField.stringValue = [(NSNumber *)orderValue stringValue];
    else if ([orderValue isKindOfClass:[NSString class]]) orderField.stringValue = (NSString *)orderValue;
    else orderField.placeholderString = @"Auto";
    orderField.tag = 1000 + index;
    orderField.identifier = @"section.order";
    orderField.delegate = self;

    [sectionsGrid addRowWithViews:@[iconField, labelField, orderField]];
  }

  NSStackView *workAppsContainer = nil;
  NSBox *workAppsBox = [self sectionBoxWithTitle:@"Web App Shortcuts"
                                        subtitle:@"Control the workspace-domain links that appear in the menu without hand-editing every JSON route each time."
                                     contentStack:&workAppsContainer];
  [rootStack addView:workAppsBox inGravity:NSStackViewGravityTop];
  [workAppsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  // Work apps controls
  NSStackView *workAppsSection = [[NSStackView alloc] initWithFrame:NSZeroRect];
  workAppsSection.orientation = NSUserInterfaceLayoutOrientationVertical;
  workAppsSection.spacing = 10;
  [workAppsContainer addView:workAppsSection inGravity:NSStackViewGravityTop];

  NSStackView *domainRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  domainRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  domainRow.spacing = 10;
  [workAppsSection addView:domainRow inGravity:NSStackViewGravityTop];

  NSTextField *domainLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  domainLabel.stringValue = @"Workspace Domain";
  domainLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  domainLabel.bordered = NO;
  domainLabel.editable = NO;
  domainLabel.backgroundColor = [NSColor clearColor];
  [domainLabel.widthAnchor constraintEqualToConstant:130].active = YES;
  [domainRow addView:domainLabel inGravity:NSStackViewGravityLeading];

  self.workDomainField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.workDomainField.placeholderString = @"company.com";
  self.workDomainField.stringValue = [config valueForKeyPath:@"menus.work.workspace_domain" defaultValue:@""] ?: @"";
  [self.workDomainField.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
  [self.workDomainField.widthAnchor constraintLessThanOrEqualToConstant:260].active = YES;
  [domainRow addView:self.workDomainField inGravity:NSStackViewGravityLeading];

  NSStackView *appsFileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  appsFileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  appsFileRow.spacing = 10;
  [workAppsSection addView:appsFileRow inGravity:NSStackViewGravityTop];

  NSTextField *appsFileLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  appsFileLabel.stringValue = @"Apps Data File";
  appsFileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  appsFileLabel.bordered = NO;
  appsFileLabel.editable = NO;
  appsFileLabel.backgroundColor = [NSColor clearColor];
  [appsFileLabel.widthAnchor constraintEqualToConstant:130].active = YES;
  [appsFileRow addView:appsFileLabel inGravity:NSStackViewGravityLeading];

  self.workAppsFileField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.workAppsFileField.placeholderString = @"data/work_apps.local.json";
  self.workAppsFileField.stringValue = [config valueForKeyPath:@"menus.work.apps_file" defaultValue:@"data/work_apps.local.json"] ?: @"data/work_apps.local.json";
  [self.workAppsFileField.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
  [self.workAppsFileField.widthAnchor constraintLessThanOrEqualToConstant:420].active = YES;
  [appsFileRow addView:self.workAppsFileField inGravity:NSStackViewGravityLeading];

  NSStackView *workActionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  workActionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  workActionsRow.spacing = 10;
  [workAppsSection addView:workActionsRow inGravity:NSStackViewGravityTop];

  self.applyWorkAppsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.applyWorkAppsButton.title = @"Apply Work Apps";
  self.applyWorkAppsButton.target = self;
  self.applyWorkAppsButton.action = @selector(applyWorkApps:);
  [workActionsRow addView:self.applyWorkAppsButton inGravity:NSStackViewGravityLeading];

  self.openWorkAppsFileButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.openWorkAppsFileButton.title = @"Open JSON";
  self.openWorkAppsFileButton.target = self;
  self.openWorkAppsFileButton.action = @selector(openWorkAppsFile:);
  [workActionsRow addView:self.openWorkAppsFileButton inGravity:NSStackViewGravityLeading];

  NSStackView *projectsContainer = nil;
  NSBox *projectsBox = [self sectionBoxWithTitle:@"App Launchers"
                                        subtitle:@"Control local app/project rows separately from Oracle tools and system utilities."
                                     contentStack:&projectsContainer];
  [rootStack addView:projectsBox inGravity:NSStackViewGravityTop];
  [projectsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  // Apps controls
  NSStackView *projectsSection = [[NSStackView alloc] initWithFrame:NSZeroRect];
  projectsSection.orientation = NSUserInterfaceLayoutOrientationVertical;
  projectsSection.spacing = 10;
  [projectsContainer addView:projectsSection inGravity:NSStackViewGravityTop];

  NSStackView *projectsOptionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  projectsOptionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  projectsOptionsRow.spacing = 16;
  [projectsSection addView:projectsOptionsRow inGravity:NSStackViewGravityTop];

  id projectsEnabledValue = [config valueForKeyPath:@"menus.apps.enabled" defaultValue:nil];
  if (!projectsEnabledValue) {
    projectsEnabledValue = [config valueForKeyPath:@"menus.projects.enabled" defaultValue:@YES];
  }
  BOOL projectsEnabled = [projectsEnabledValue boolValue];
  self.projectShortcutsToggle = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.projectShortcutsToggle setButtonType:NSButtonTypeSwitch];
  self.projectShortcutsToggle.title = @"Enable apps section";
  self.projectShortcutsToggle.state = projectsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  [projectsOptionsRow addView:self.projectShortcutsToggle inGravity:NSStackViewGravityLeading];

  NSTextField *projectActionLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  projectActionLabel.stringValue = @"Fallback Path Action";
  projectActionLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  projectActionLabel.bordered = NO;
  projectActionLabel.editable = NO;
  projectActionLabel.backgroundColor = [NSColor clearColor];
  [projectsOptionsRow addView:projectActionLabel inGravity:NSStackViewGravityLeading];

  self.projectDefaultActionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [self.projectDefaultActionPopup addItemsWithTitles:@[@"Terminal", @"Finder", @"VS Code"]];
  [self.projectDefaultActionPopup.widthAnchor constraintEqualToConstant:120].active = YES;
  [projectsOptionsRow addView:self.projectDefaultActionPopup inGravity:NSStackViewGravityLeading];

  NSString *projectAction = [config valueForKeyPath:@"menus.apps.default_action" defaultValue:nil];
  if (projectAction.length == 0) {
    projectAction = [config valueForKeyPath:@"menus.projects.default_action" defaultValue:@"terminal"] ?: @"terminal";
  }
  if ([projectAction isEqualToString:@"finder"] || [projectAction isEqualToString:@"open"]) {
    [self.projectDefaultActionPopup selectItemAtIndex:1];
  } else if ([projectAction isEqualToString:@"code"]) {
    [self.projectDefaultActionPopup selectItemAtIndex:2];
  } else {
    [self.projectDefaultActionPopup selectItemAtIndex:0];
  }

  NSStackView *projectFileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  projectFileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  projectFileRow.spacing = 10;
  [projectsSection addView:projectFileRow inGravity:NSStackViewGravityTop];

  NSTextField *projectFileLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  projectFileLabel.stringValue = @"Launchers JSON";
  projectFileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  projectFileLabel.bordered = NO;
  projectFileLabel.editable = NO;
  projectFileLabel.backgroundColor = [NSColor clearColor];
  [projectFileLabel.widthAnchor constraintEqualToConstant:130].active = YES;
  [projectFileRow addView:projectFileLabel inGravity:NSStackViewGravityLeading];

  self.projectFileField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.projectFileField.placeholderString = @"data/project_shortcuts.json";
  NSString *appsFile = [config valueForKeyPath:@"menus.apps.file" defaultValue:nil];
  if (appsFile.length == 0) {
    appsFile = [config valueForKeyPath:@"menus.projects.file" defaultValue:@"data/project_shortcuts.json"] ?: @"data/project_shortcuts.json";
  }
  self.projectFileField.stringValue = appsFile;
  [self.projectFileField.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
  [self.projectFileField.widthAnchor constraintLessThanOrEqualToConstant:420].active = YES;
  [projectFileRow addView:self.projectFileField inGravity:NSStackViewGravityLeading];

  NSStackView *projectActionsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  projectActionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  projectActionsRow.spacing = 10;
  [projectsSection addView:projectActionsRow inGravity:NSStackViewGravityTop];

  self.applyProjectsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.applyProjectsButton.title = @"Apply Apps Settings";
  self.applyProjectsButton.target = self;
  self.applyProjectsButton.action = @selector(applyProjectShortcuts:);
  [projectActionsRow addView:self.applyProjectsButton inGravity:NSStackViewGravityLeading];

  self.discoverProjectsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.discoverProjectsButton.title = @"Refresh Apps";
  self.discoverProjectsButton.target = self;
  self.discoverProjectsButton.action = @selector(discoverProjectShortcuts:);
  [projectActionsRow addView:self.discoverProjectsButton inGravity:NSStackViewGravityLeading];

  self.openProjectsFileButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  self.openProjectsFileButton.title = @"Open JSON";
  self.openProjectsFileButton.target = self;
  self.openProjectsFileButton.action = @selector(openProjectShortcutsFile:);
  [projectActionsRow addView:self.openProjectsFileButton inGravity:NSStackViewGravityLeading];

  NSStackView *toolsContainer = nil;
  NSBox *toolsBox = [self sectionBoxWithTitle:@"Tool Rows"
                                     subtitle:@"Enable or rename individual rows after the high-level section structure feels right."
                                  contentStack:&toolsContainer];
  [rootStack addView:toolsBox inGravity:NSStackViewGravityTop];
  [toolsBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  // Tools Grid
  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.rowSpacing = 12;
  grid.columnSpacing = 16;
  grid.xPlacement = NSGridCellPlacementLeading;
  grid.yPlacement = NSGridCellPlacementCenter;
  [toolsContainer addView:grid inGravity:NSStackViewGravityTop];

  // Header
  [grid addRowWithViews:@[
    [self headerLabel:@"ICON"],
    [self headerLabel:@"LABEL"],
    [self headerLabel:@"ENABLED"],
    [self headerLabel:@"COLOR"],
    [self headerLabel:@"ORDER"]
  ]];

  for (NSInteger index = 0; index < self.tools.count; index++) {
    NSDictionary *tool = self.tools[index];
    NSString *key = tool[@"key"];
    NSString *baseLabel = tool[@"label"] ?: @"";
    NSString *baseIcon = tool[@"icon"] ?: @"";

    NSString *labelKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.label", key];
    NSString *iconKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon", key];
    NSString *colorKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon_color", key];
    NSString *orderKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.order", key];
    NSString *enabledKeyPath = [NSString stringWithFormat:@"menus.apple.items.%@.enabled", key];

    NSTextField *iconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [iconField.widthAnchor constraintEqualToConstant:40].active = YES;
    iconField.stringValue = [config valueForKeyPath:iconKeyPath defaultValue:baseIcon] ?: baseIcon;
    iconField.font = [self preferredIconFontWithSize:18];
    iconField.alignment = NSTextAlignmentCenter;
    iconField.tag = index;
    iconField.identifier = @"tool.icon";
    iconField.delegate = self;

    NSTextField *labelField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [labelField.widthAnchor constraintEqualToConstant:220].active = YES;
    labelField.stringValue = [config valueForKeyPath:labelKeyPath defaultValue:baseLabel] ?: baseLabel;
    labelField.font = [NSFont systemFontOfSize:14];
    labelField.tag = index;
    labelField.identifier = @"tool.label";
    labelField.delegate = self;

    NSButton *toggle = [[NSButton alloc] initWithFrame:NSZeroRect];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.title = @"";
    toggle.tag = index;
    toggle.target = self;
    toggle.action = @selector(toggleItemEnabled:);
    id enabledValue = [config valueForKeyPath:enabledKeyPath defaultValue:nil];
    BOOL enabled = enabledValue ? [enabledValue boolValue] : [tool[@"default_enabled"] boolValue];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 50, 28)];
    colorWell.tag = index;
    colorWell.target = self;
    colorWell.action = @selector(iconColorChanged:);
    NSString *hexColor = [config valueForKeyPath:colorKeyPath defaultValue:nil];
    if ([hexColor isKindOfClass:[NSString class]] && [hexColor length] > 0) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) colorWell.color = color;
    }

    NSTextField *orderField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [orderField.widthAnchor constraintEqualToConstant:60].active = YES;
    id orderValue = [config valueForKeyPath:orderKeyPath defaultValue:nil];
    if ([orderValue isKindOfClass:[NSNumber class]]) orderField.stringValue = [(NSNumber *)orderValue stringValue];
    else if ([orderValue isKindOfClass:[NSString class]]) orderField.stringValue = (NSString *)orderValue;
    else orderField.placeholderString = @"Auto";
    orderField.tag = index;
    orderField.identifier = @"tool.order";
    orderField.delegate = self;

    [grid addRowWithViews:@[iconField, labelField, toggle, colorWell, orderField]];
  }
}

- (NSTextField *)headerLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text;
  label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (void)refreshHoverControls {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *hoverColor = [config valueForKeyPath:@"menus.apple.hover.color" defaultValue:nil];
  if (![hoverColor isKindOfClass:[NSString class]] || hoverColor.length == 0) {
    hoverColor = [config valueForKeyPath:@"appearance.hover_bg" defaultValue:nil];
  }
  NSString *borderColor = [config valueForKeyPath:@"menus.apple.hover.border_color" defaultValue:nil];
  if (![borderColor isKindOfClass:[NSString class]] || borderColor.length == 0) {
    borderColor = [config valueForKeyPath:@"appearance.hover_border_color" defaultValue:nil];
  }
  id borderWidth = [config valueForKeyPath:@"menus.apple.hover.border_width" defaultValue:nil];
  if (!borderWidth) {
    borderWidth = [config valueForKeyPath:@"appearance.hover_border_width" defaultValue:nil];
  }

  NSColor *hover = [self colorFromHexString:hoverColor] ?: [NSColor clearColor];
  NSColor *border = [self colorFromHexString:borderColor] ?: [NSColor clearColor];
  self.hoverColorWell.color = hover;
  self.hoverBorderColorWell.color = border;

  if ([borderWidth isKindOfClass:[NSNumber class]]) {
    self.hoverBorderWidthField.stringValue = [(NSNumber *)borderWidth stringValue];
  } else if ([borderWidth isKindOfClass:[NSString class]]) {
    self.hoverBorderWidthField.stringValue = (NSString *)borderWidth;
  } else {
    self.hoverBorderWidthField.stringValue = @"";
  }
}

- (void)hoverColorChanged:(NSColorWell *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *hexColor = [self hexStringFromColor:sender.color];
  if (!hexColor.length) {
    return;
  }
  [config setValue:hexColor forKeyPath:@"menus.apple.hover.color"];
  [config reloadSketchyBar];
}

- (void)hoverBorderColorChanged:(NSColorWell *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *hexColor = [self hexStringFromColor:sender.color];
  if (!hexColor.length) {
    return;
  }
  [config setValue:hexColor forKeyPath:@"menus.apple.hover.border_color"];
  [config reloadSketchyBar];
}

- (void)resetHoverOverrides:(id)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config performBatchUpdates:^{
    [config removeValueForKeyPath:@"menus.apple.hover.color"];
    [config removeValueForKeyPath:@"menus.apple.hover.border_color"];
    [config removeValueForKeyPath:@"menus.apple.hover.border_width"];
  }];
  [self refreshHoverControls];
  [config reloadSketchyBar];
}

- (NSString *)trimmedString:(NSString *)value {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)resolveWorkAppsPath:(NSString *)rawPath config:(ConfigurationManager *)config {
  NSString *trimmed = [self trimmedString:rawPath ?: @""];
  if (trimmed.length == 0) {
    return nil;
  }
  if ([trimmed hasPrefix:@"~/"]) {
    return [NSHomeDirectory() stringByAppendingPathComponent:[trimmed substringFromIndex:2]];
  }
  if ([trimmed hasPrefix:@"/"]) {
    return trimmed;
  }
  return [config.configPath stringByAppendingPathComponent:trimmed];
}

- (NSString *)resolveConfigRelativePath:(NSString *)rawPath config:(ConfigurationManager *)config {
  NSString *trimmed = [self trimmedString:rawPath ?: @""];
  if (trimmed.length == 0) {
    return nil;
  }
  if ([trimmed hasPrefix:@"~/"]) {
    return [NSHomeDirectory() stringByAppendingPathComponent:[trimmed substringFromIndex:2]];
  }
  if ([trimmed hasPrefix:@"/"]) {
    return trimmed;
  }
  return [config.configPath stringByAppendingPathComponent:trimmed];
}

- (NSString *)selectedProjectActionValue {
  switch (self.projectDefaultActionPopup.indexOfSelectedItem) {
    case 1:
      return @"finder";
    case 2:
      return @"code";
    default:
      return @"terminal";
  }
}

- (void)applyWorkApps:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *domain = [self trimmedString:self.workDomainField.stringValue ?: @""];
  NSString *appsFile = [self trimmedString:self.workAppsFileField.stringValue ?: @""];
  if (appsFile.length == 0) {
    appsFile = @"data/work_apps.local.json";
    self.workAppsFileField.stringValue = appsFile;
  }

  [config performBatchUpdates:^{
    [config setValue:appsFile forKeyPath:@"menus.work.apps_file"];
    [config setValue:domain forKeyPath:@"menus.work.workspace_domain"];
  }];

  NSMutableArray *args = [NSMutableArray arrayWithArray:@[
    @"--apps-only",
    @"--replace",
    @"--state", config.statePath,
    @"--work-apps-out-file", appsFile,
    @"--yes",
    @"--no-reload"
  ]];
  if (domain.length > 0) {
    [args addObjectsFromArray:@[@"--domain", domain]];
  }

  [config runScript:@"setup_machine.sh" arguments:args];
  [config reloadSketchyBar];
}

- (void)openWorkAppsFile:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *appsFile = [self trimmedString:self.workAppsFileField.stringValue ?: @""];
  if (appsFile.length == 0) {
    appsFile = @"data/work_apps.local.json";
  }
  NSString *resolvedPath = [self resolveWorkAppsPath:appsFile config:config];
  if (!resolvedPath.length) {
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [resolvedPath stringByDeletingLastPathComponent];
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  if (![fm fileExistsAtPath:resolvedPath]) {
    NSString *templatePath = [config.configPath stringByAppendingPathComponent:@"data/work_apps.work.json"];
    if ([fm fileExistsAtPath:templatePath]) {
      [fm copyItemAtPath:templatePath toPath:resolvedPath error:nil];
    } else {
      [@"[]\n" writeToFile:resolvedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
  }

  NSURL *fileURL = [NSURL fileURLWithPath:resolvedPath];
  [[NSWorkspace sharedWorkspace] openURL:fileURL];
}

- (void)applyProjectShortcuts:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *projectsFile = [self trimmedString:self.projectFileField.stringValue ?: @""];
  if (projectsFile.length == 0) {
    projectsFile = @"data/project_shortcuts.json";
    self.projectFileField.stringValue = projectsFile;
  }

  NSNumber *appsEnabled = @(self.projectShortcutsToggle.state == NSControlStateValueOn);
  NSString *defaultAction = [self selectedProjectActionValue];
  [config performBatchUpdates:^{
    [config setValue:appsEnabled forKeyPath:@"menus.apps.enabled"];
    [config setValue:projectsFile forKeyPath:@"menus.apps.file"];
    [config setValue:defaultAction forKeyPath:@"menus.apps.default_action"];
    [config setValue:appsEnabled forKeyPath:@"menus.projects.enabled"];
    [config setValue:projectsFile forKeyPath:@"menus.projects.file"];
    [config setValue:defaultAction forKeyPath:@"menus.projects.default_action"];
  }];
  [config reloadSketchyBar];
}

- (void)openProjectShortcutsFile:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *projectsFile = [self trimmedString:self.projectFileField.stringValue ?: @""];
  if (projectsFile.length == 0) {
    projectsFile = @"data/project_shortcuts.json";
    self.projectFileField.stringValue = projectsFile;
  }

  NSString *resolvedPath = [self resolveConfigRelativePath:projectsFile config:config];
  if (!resolvedPath.length) {
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [resolvedPath stringByDeletingLastPathComponent];
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  if (![fm fileExistsAtPath:resolvedPath]) {
    [@"[]\n" writeToFile:resolvedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }

  NSURL *fileURL = [NSURL fileURLWithPath:resolvedPath];
  [[NSWorkspace sharedWorkspace] openURL:fileURL];
}

- (void)discoverProjectShortcuts:(NSButton *)sender {
  (void)sender;
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *projectsFile = [self trimmedString:self.projectFileField.stringValue ?: @""];
  if (projectsFile.length == 0) {
    projectsFile = @"data/project_shortcuts.json";
    self.projectFileField.stringValue = projectsFile;
  }

  [self applyProjectShortcuts:nil];
  [config runScript:@"discover_project_shortcuts.sh" arguments:@[
    @"--state", config.statePath ?: @"",
    @"--output", projectsFile
  ]];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [config reloadSketchyBar];
  });
}

- (void)toggleShowMissing:(NSButton *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL enabled = sender.state == NSControlStateValueOn;
  [config setValue:@(enabled) forKeyPath:@"menus.apple.show_missing"];
  [config reloadSketchyBar];
}

- (void)toggleItemEnabled:(NSButton *)sender {
  if (sender.tag < 0 || sender.tag >= self.tools.count) {
    return;
  }
  NSString *key = self.tools[sender.tag][@"key"];
  BOOL enabled = sender.state == NSControlStateValueOn;
  NSString *keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.enabled", key];
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:@(enabled) forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)toggleAllowTerminal:(NSButton *)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  BOOL enabled = sender.state == NSControlStateValueOn;
  [config setValue:@(enabled) forKeyPath:@"menus.apple.terminal"];
  [config reloadSketchyBar];
}

- (void)iconColorChanged:(NSColorWell *)sender {
  if (sender.tag < 0 || sender.tag >= self.tools.count) {
    return;
  }
  NSString *key = self.tools[sender.tag][@"key"];
  NSString *keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon_color", key];
  NSString *hexColor = [self hexStringFromColor:sender.color];
  if (!hexColor.length) {
    return;
  }
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config setValue:hexColor forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
  NSTextField *field = notification.object;
  if (![field isKindOfClass:[NSTextField class]]) {
    return;
  }
  NSString *value = field.stringValue ?: @"";
  NSString *identifier = field.identifier ?: @"";

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

  if ([identifier isEqualToString:@"menu.hover.border_width"]) {
    if (trimmed.length == 0) {
      [config removeValueForKeyPath:@"menus.apple.hover.border_width"];
      [config reloadSketchyBar];
      [self refreshHoverControls];
      return;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger number = 0;
    if ([scanner scanInteger:&number] && scanner.isAtEnd) {
      [config setValue:@(number) forKeyPath:@"menus.apple.hover.border_width"];
      [config reloadSketchyBar];
    }
    return;
  }

  NSString *keyPath = nil;
  BOOL isOrderField = NO;

  if (field.tag >= 1000 && field.tag < 1000 + self.sections.count) {
    NSString *key = self.sections[field.tag - 1000][@"key"];
    if ([identifier isEqualToString:@"section.label"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.sections.%@.label", key];
    } else if ([identifier isEqualToString:@"section.icon"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.sections.%@.icon", key];
    } else if ([identifier isEqualToString:@"section.order"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.sections.%@.order", key];
      isOrderField = YES;
    }
  } else if (field.tag >= 0 && field.tag < self.tools.count) {
    NSString *key = self.tools[field.tag][@"key"];
    if ([identifier isEqualToString:@"tool.label"] || [identifier isEqualToString:@"label"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.label", key];
    } else if ([identifier isEqualToString:@"tool.icon"] || [identifier isEqualToString:@"icon"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.icon", key];
    } else if ([identifier isEqualToString:@"tool.order"] || [identifier isEqualToString:@"order"]) {
      keyPath = [NSString stringWithFormat:@"menus.apple.items.%@.order", key];
      isOrderField = YES;
    }
  }

  if (!keyPath.length) {
    return;
  }

  if (trimmed.length == 0) {
    [config removeValueForKeyPath:keyPath];
    [config reloadSketchyBar];
    return;
  }

  if (isOrderField) {
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger number = 0;
    if ([scanner scanInteger:&number] && scanner.isAtEnd) {
      [config setValue:@(number) forKeyPath:keyPath];
      [config reloadSketchyBar];
    }
    return;
  }

  [config setValue:trimmed forKeyPath:keyPath];
  [config reloadSketchyBar];
}


@end
