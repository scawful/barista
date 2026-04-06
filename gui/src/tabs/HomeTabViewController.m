#import "HomeTabViewController.h"

#import "BaristaCommandBus.h"
#import "BaristaPanelState.h"
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
  NSString *windowMode = [[BaristaPanelState sharedState] windowMode] ?: @"utility";

  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(24, 24, 28, 24) spacing:18];

  NSBox *heroBox = [self cardBox];
  [heroBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  [rootStack addView:heroBox inGravity:NSStackViewGravityTop];

  NSStackView *heroStack = [self verticalStackWithSpacing:8];
  heroStack.edgeInsets = NSEdgeInsetsMake(16, 18, 16, 18);
  heroBox.contentView = heroStack;

  NSTextField *eyebrow = [self eyebrowLabel:@"CONFIG HQ"];
  [heroStack addView:eyebrow inGravity:NSStackViewGravityTop];

  NSTextField *title = [self titleLabel:@"Barista Home" fontSize:28];
  [heroStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *subtitle = [self bodyLabel:@"Start here when you want to tune SketchyBar itself. Oracle work stays in Oracle Agent Manager, while this panel owns appearance, menus, shortcuts, integrations, and runtime controls."];
  [heroStack addView:subtitle inGravity:NSStackViewGravityTop];

  NSStackView *metaRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  metaRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  metaRow.spacing = 12;
  [heroStack addView:metaRow inGravity:NSStackViewGravityTop];
  [metaRow addView:[self chipLabel:[NSString stringWithFormat:@"Theme: %@", theme]] inGravity:NSStackViewGravityLeading];
  [metaRow addView:[self chipLabel:[NSString stringWithFormat:@"Profile: %@", profile]] inGravity:NSStackViewGravityLeading];
  [metaRow addView:[self chipLabel:[NSString stringWithFormat:@"Panel: %@", panelMode]] inGravity:NSStackViewGravityLeading];
  [metaRow addView:[self chipLabel:[NSString stringWithFormat:@"Window: %@", windowMode]] inGravity:NSStackViewGravityLeading];

  NSStackView *cardsRowOne = [[NSStackView alloc] initWithFrame:NSZeroRect];
  cardsRowOne.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  cardsRowOne.alignment = NSLayoutAttributeTop;
  cardsRowOne.distribution = NSStackViewDistributionFillEqually;
  cardsRowOne.spacing = 14;
  [rootStack addView:cardsRowOne inGravity:NSStackViewGravityTop];
  [cardsRowOne.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSBox *designBox = [self cardBox];
  [cardsRowOne addView:designBox inGravity:NSStackViewGravityLeading];
  [designBox setContentView:[self cardContentWithTitle:@"Shape the bar"
                                                   body:@"Tune the visual system first: theme, surface geometry, widget mix, and space behavior."
                                                buttons:@[
                                                  [self tabButtonWithTitle:@"Appearance" tab:@"appearance"],
                                                  [self tabButtonWithTitle:@"Widgets" tab:@"widgets"],
                                                  [self tabButtonWithTitle:@"Spaces" tab:@"spaces"],
                                                  [self tabButtonWithTitle:@"Themes" tab:@"themes"]
                                                ]]];

  NSBox *menuBox = [self cardBox];
  [cardsRowOne addView:menuBox inGravity:NSStackViewGravityLeading];
  [menuBox setContentView:[self cardContentWithTitle:@"Compose behavior"
                                                 body:@"Shape the Apple menu, shortcut layer, icon language, and external integrations without mixing in Oracle workflow state."
                                              buttons:@[
                                                [self tabButtonWithTitle:@"Menu" tab:@"menu"],
                                                [self tabButtonWithTitle:@"Shortcuts" tab:@"shortcuts"],
                                                [self tabButtonWithTitle:@"Icons" tab:@"icons"],
                                                [self tabButtonWithTitle:@"Integrations" tab:@"integrations"]
                                              ]]];

  NSStackView *cardsRowTwo = [[NSStackView alloc] initWithFrame:NSZeroRect];
  cardsRowTwo.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  cardsRowTwo.alignment = NSLayoutAttributeTop;
  cardsRowTwo.distribution = NSStackViewDistributionFillEqually;
  cardsRowTwo.spacing = 14;
  [rootStack addView:cardsRowTwo inGravity:NSStackViewGravityTop];
  [cardsRowTwo.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  NSBox *opsBox = [self cardBox];
  [cardsRowTwo addView:opsBox inGravity:NSStackViewGravityLeading];
  [opsBox setContentView:[self cardContentWithTitle:@"Operate the system"
                                                body:@"Use these when you are validating launch agents, runtime state, performance, or raw configuration data."
                                             buttons:@[
                                               [self tabButtonWithTitle:@"Launch Agents" tab:@"launchAgents"],
                                               [self tabButtonWithTitle:@"Performance" tab:@"performance"],
                                               [self tabButtonWithTitle:@"Debug" tab:@"debug"],
                                               [self tabButtonWithTitle:@"Advanced" tab:@"advanced"]
                                             ]]];

  NSBox *actionsBox = [self cardBox];
  [cardsRowTwo addView:actionsBox inGravity:NSStackViewGravityLeading];
  [actionsBox setContentView:[self cardContentWithTitle:@"Quick actions"
                                                    body:@"Fast exits from the config surface when you need to reload the bar, inspect files, or jump into Oracle tools."
                                                 buttons:@[
                                                   [self actionButtonWithTitle:@"Reload SketchyBar" action:@selector(reloadSketchyBar:)],
                                                   [self actionButtonWithTitle:@"Open Config Folder" action:@selector(openConfigFolder:)],
                                                   [self actionButtonWithTitle:@"Open Oracle Agent Manager" action:@selector(openOracleAgentManager:)],
                                                   [self actionButtonWithTitle:@"Open README" action:@selector(openReadme:)]
                                                 ]]];

  NSTextField *footer = [self bodyLabel:@"Barista config stays opinionated and local. Oracle sessions, patch loops, and debugging live outside this panel in Oracle Agent Manager."];
  [rootStack addView:footer inGravity:NSStackViewGravityTop];

  self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.statusLabel.stringValue = @"";
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  self.statusLabel.textColor = [NSColor secondaryLabelColor];
  self.statusLabel.bordered = NO;
  self.statusLabel.editable = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  [rootStack addView:self.statusLabel inGravity:NSStackViewGravityTop];
}

- (NSBox *)cardBox {
  NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
  box.boxType = NSBoxCustom;
  box.titlePosition = NSNoTitle;
  box.cornerRadius = 14.0;
  box.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08];
  box.fillColor = [NSColor colorWithCalibratedRed:0.11 green:0.12 blue:0.15 alpha:0.95];
  box.transparent = NO;
  return box;
}

- (NSStackView *)verticalStackWithSpacing:(CGFloat)spacing {
  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = spacing;
  return stack;
}

- (NSView *)cardContentWithTitle:(NSString *)title body:(NSString *)body buttons:(NSArray<NSButton *> *)buttons {
  NSStackView *stack = [self verticalStackWithSpacing:8];
  stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);

  [stack addView:[self eyebrowLabel:title.uppercaseString] inGravity:NSStackViewGravityTop];
  [stack addView:[self bodyLabel:body] inGravity:NSStackViewGravityTop];

  NSStackView *buttonStack = [self verticalStackWithSpacing:8];
  for (NSButton *button in buttons) {
    [buttonStack addView:button inGravity:NSStackViewGravityTop];
  }
  [stack addView:buttonStack inGravity:NSStackViewGravityTop];
  return stack;
}

- (NSTextField *)eyebrowLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (NSTextField *)bodyLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
  label.textColor = [NSColor secondaryLabelColor];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  label.usesSingleLineMode = NO;
  label.lineBreakMode = NSLineBreakByWordWrapping;
  return label;
}

- (NSTextField *)chipLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
  label.textColor = [NSColor colorWithCalibratedRed:0.64 green:0.84 blue:1.0 alpha:1.0];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (NSButton *)tabButtonWithTitle:(NSString *)title tab:(NSString *)tabIdentifier {
  NSButton *button = [self actionButtonWithTitle:title action:@selector(selectTabFromButton:)];
  button.identifier = tabIdentifier;
  return button;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title action:(SEL)action {
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  [button setButtonType:NSButtonTypeMomentaryPushIn];
  [button setBezelStyle:NSBezelStyleRounded];
  button.bezelColor = [NSColor colorWithCalibratedRed:0.22 green:0.25 blue:0.34 alpha:1.0];
  button.title = title ?: @"";
  button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  button.target = self;
  button.action = action;
  [button.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
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

- (void)reloadSketchyBar:(id)sender {
  (void)sender;
  [[BaristaCommandBus sharedBus] reloadSketchyBar];
  self.statusLabel.stringValue = @"SketchyBar reload requested.";
}

- (void)openConfigFolder:(id)sender {
  (void)sender;
  NSString *configPath = [ConfigurationManager sharedManager].configPath;
  if (configPath.length) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:configPath]];
    self.statusLabel.stringValue = @"Opened Barista config folder.";
  }
}

- (void)openOracleAgentManager:(id)sender {
  (void)sender;
  NSError *error = nil;
  if ([[BaristaCommandBus sharedBus] openOracleAgentManagerWithError:&error]) {
    self.statusLabel.stringValue = @"Oracle Agent Manager launch requested.";
  } else {
    self.statusLabel.stringValue = error.localizedDescription ?: @"Oracle Agent Manager launch failed.";
  }
}

- (void)openReadme:(id)sender {
  (void)sender;
  NSString *readmePath = [[ConfigurationManager sharedManager].configPath stringByAppendingPathComponent:@"README.md"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:readmePath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:readmePath]];
    self.statusLabel.stringValue = @"Opened Barista README.";
  }
}

@end
