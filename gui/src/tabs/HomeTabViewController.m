#import "HomeTabViewController.h"

#import "BaristaCommandBus.h"
#import "BaristaPanelState.h"
#import "BaristaStyle.h"
#import "ConfigurationManager.h"

static NSString *const BaristaSelectTabNotification = @"BaristaSelectTabNotification";

@interface HomeTabViewController ()
@property (strong) NSTextField *statusLabel;
@end

@implementation HomeTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *profile = [config valueForKeyPath:@"profile" defaultValue:@"default"] ?: @"default";
  NSString *theme = [config valueForKeyPath:@"appearance.theme" defaultValue:@"default"] ?: @"default";
  NSString *panelMode = [config valueForKeyPath:@"control_panel.preferred" defaultValue:@"native"] ?: @"native";
  NSString *windowMode = [[BaristaPanelState sharedState] windowMode] ?: @"standard";

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(24, 28, 28, 28) spacing:18];

  [rootStack addView:[self titleLabel:@"Barista" fontSize:26] inGravity:NSStackViewGravityTop];
  [rootStack addView:[self helperLabel:@"SketchyBar settings, runtime controls, and local workflow exits."] inGravity:NSStackViewGravityTop];
  [rootStack addView:[self metadataLabelWithProfile:profile theme:theme panelMode:panelMode windowMode:windowMode]
           inGravity:NSStackViewGravityTop];

  [self addSectionWithTitle:@"Settings"
                   subtitle:@"Configure the menu bar without leaving the native panel."
                 buttonRows:@[
                   @[
                     [self tabButtonWithTitle:@"Appearance" tab:@"appearance"],
                     [self tabButtonWithTitle:@"Widgets" tab:@"widgets"]
                   ],
                   @[
                     [self tabButtonWithTitle:@"Spaces" tab:@"spaces"],
                     [self tabButtonWithTitle:@"Themes" tab:@"themes"]
                   ],
                   @[
                     [self tabButtonWithTitle:@"Menu" tab:@"menu"],
                     [self tabButtonWithTitle:@"Shortcuts" tab:@"shortcuts"]
                   ],
                   @[
                     [self tabButtonWithTitle:@"Icons" tab:@"icons"],
                     [self tabButtonWithTitle:@"Integrations" tab:@"integrations"]
                   ]
                 ]
                   toStack:rootStack];

  [self addSectionWithTitle:@"Runtime"
                   subtitle:@"Use these when the bar needs a reload, a diagnostic pass, or direct file access."
                 buttonRows:@[
                   @[
                     [self actionButtonWithTitle:@"Reload SketchyBar" action:@selector(reloadSketchyBar:)],
                     [self actionButtonWithTitle:@"Open Config Folder" action:@selector(openConfigFolder:)]
                   ],
                   @[
                     [self tabButtonWithTitle:@"Launch Agents" tab:@"launchAgents"],
                     [self tabButtonWithTitle:@"Performance" tab:@"performance"]
                   ],
                   @[
                     [self tabButtonWithTitle:@"Debug" tab:@"debug"],
                     [self tabButtonWithTitle:@"Advanced" tab:@"advanced"]
                   ],
                   @[
                     [self actionButtonWithTitle:@"Open README" action:@selector(openReadme:)],
                     [self actionButtonWithTitle:@"Open Oracle Hub" action:@selector(openOracleAgentManager:)]
                   ]
                 ]
                   toStack:rootStack];

  [self addSectionWithTitle:@"Local Workflows"
                   subtitle:@"Open the tools Barista already knows how to resolve on this machine."
                 buttonRows:@[
                   @[
                     [self workflowButtonWithTitle:@"Open Ghostty" workflow:@"ghostty"],
                     [self workflowButtonWithTitle:@"Open LM Studio" workflow:@"lmstudio"]
                   ],
                   @[
                     [self workflowButtonWithTitle:@"LM Studio Status" workflow:@"lmstudio-status"],
                     [self workflowButtonWithTitle:@"AFS Context Overview" workflow:@"afs-context"]
                   ],
                   @[
                     [self workflowButtonWithTitle:@"Launch AFS Studio" workflow:@"afs-studio"],
                     [self workflowButtonWithTitle:@"Open Barista Repo" workflow:@"barista-repo"]
                   ]
                 ]
                   toStack:rootStack];

  [self addSectionWithTitle:@"Projects"
                   subtitle:@"Jump to the local apps and repos that show up in the menu bar workflow."
                 buttonRows:@[
                   @[
                     [self workflowButtonWithTitle:@"Open scawfulbot" workflow:@"scawfulbot"],
                     [self workflowButtonWithTitle:@"Open Janice Code" workflow:@"janice"]
                   ],
                   @[
                     [self workflowButtonWithTitle:@"Launch Yaze" workflow:@"yaze"],
                     [self workflowButtonWithTitle:@"Launch z3ed" workflow:@"z3ed"]
                   ],
                   @[
                     [self workflowButtonWithTitle:@"Open Loom Studio" workflow:@"loom"],
                     [self workflowButtonWithTitle:@"Open Premia" workflow:@"premia"]
                   ]
                 ]
                   toStack:rootStack];

  self.statusLabel = [self helperLabel:@""];
  [rootStack addView:self.statusLabel inGravity:NSStackViewGravityTop];
}

- (NSTextField *)metadataLabelWithProfile:(NSString *)profile
                                    theme:(NSString *)theme
                                panelMode:(NSString *)panelMode
                               windowMode:(NSString *)windowMode {
  NSString *text = [NSString stringWithFormat:@"Theme: %@   Profile: %@   Panel: %@   Window: %@",
                                              theme ?: @"default",
                                              profile ?: @"default",
                                              panelMode ?: @"native",
                                              windowMode ?: @"standard"];
  NSTextField *label = [self helperLabel:text];
  label.usesSingleLineMode = YES;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (void)addSectionWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                 buttonRows:(NSArray<NSArray<NSButton *> *> *)buttonRows
                    toStack:(NSStackView *)rootStack {
  NSStackView *sectionStack = nil;
  NSBox *section = [self sectionBoxWithTitle:title
                                    subtitle:subtitle
                                contentStack:&sectionStack
                                  edgeInsets:NSEdgeInsetsMake(16, 16, 16, 16)
                                     spacing:10];
  [rootStack addView:section inGravity:NSStackViewGravityTop];
  [section.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  for (NSArray<NSButton *> *buttons in buttonRows) {
    [sectionStack addView:[self buttonRowWithButtons:buttons] inGravity:NSStackViewGravityTop];
  }
}

- (NSStackView *)buttonRowWithButtons:(NSArray<NSButton *> *)buttons {
  NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeCenterY;
  row.distribution = NSStackViewDistributionFillEqually;
  row.spacing = 10;
  for (NSButton *button in buttons) {
    [row addView:button inGravity:NSStackViewGravityLeading];
  }
  [row.widthAnchor constraintGreaterThanOrEqualToConstant:320.0].active = YES;
  return row;
}

- (NSButton *)tabButtonWithTitle:(NSString *)title tab:(NSString *)tabIdentifier {
  NSButton *button = [self actionButtonWithTitle:title action:@selector(selectTabFromButton:)];
  button.identifier = tabIdentifier;
  return button;
}

- (NSButton *)workflowButtonWithTitle:(NSString *)title workflow:(NSString *)workflowIdentifier {
  NSButton *button = [self actionButtonWithTitle:title action:@selector(launchWorkflowFromButton:)];
  button.identifier = workflowIdentifier;
  return button;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title action:(SEL)action {
  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  [button setButtonType:NSButtonTypeMomentaryPushIn];
  [button setBezelStyle:NSBezelStyleRounded];
  button.title = title ?: @"";
  button.font = [style interfaceFontOfSize:12.5 weight:NSFontWeightMedium];
  button.toolTip = title ?: @"";
  button.target = self;
  button.action = action;
  [button.widthAnchor constraintGreaterThanOrEqualToConstant:150.0].active = YES;
  return button;
}

- (void)selectTabFromButton:(NSButton *)sender {
  NSString *tabIdentifier = sender.identifier;
  if (!tabIdentifier.length) {
    return;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:BaristaSelectTabNotification
                                                      object:self
                                                    userInfo:@{ @"tab": tabIdentifier }];
}

- (void)launchWorkflowFromButton:(NSButton *)sender {
  NSString *workflowIdentifier = sender.identifier;
  if (!workflowIdentifier.length) {
    return;
  }

  NSError *error = nil;
  if ([[BaristaCommandBus sharedBus] launchLocalWorkflow:workflowIdentifier error:&error]) {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ launch requested.", sender.title ?: @"Workflow"];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
  } else {
    self.statusLabel.stringValue = error.localizedDescription ?: @"Local workflow launch failed.";
    self.statusLabel.textColor = [NSColor systemOrangeColor];
  }
}

- (void)reloadSketchyBar:(id)sender {
  (void)sender;
  [[BaristaCommandBus sharedBus] reloadSketchyBar];
  self.statusLabel.stringValue = @"SketchyBar reload requested.";
  self.statusLabel.textColor = [NSColor secondaryLabelColor];
}

- (void)openConfigFolder:(id)sender {
  (void)sender;
  NSString *configPath = [ConfigurationManager sharedManager].configPath;
  if (configPath.length) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:configPath]];
    self.statusLabel.stringValue = @"Opened Barista config folder.";
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
  }
}

- (void)openOracleAgentManager:(id)sender {
  (void)sender;
  NSError *error = nil;
  if ([[BaristaCommandBus sharedBus] openOracleAgentManagerWithError:&error]) {
    self.statusLabel.stringValue = @"Oracle Hub launch requested.";
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
  } else {
    self.statusLabel.stringValue = error.localizedDescription ?: @"Oracle Hub launch failed.";
    self.statusLabel.textColor = [NSColor systemOrangeColor];
  }
}

- (void)openReadme:(id)sender {
  (void)sender;
  NSString *readmePath = [[ConfigurationManager sharedManager].configPath stringByAppendingPathComponent:@"README.md"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:readmePath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:readmePath]];
    self.statusLabel.stringValue = @"Opened Barista README.";
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
  }
}

@end
