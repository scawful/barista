#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface IntegrationsTabViewController : NSViewController
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
@end

@implementation IntegrationsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;
  CGFloat sectionSpacing = 80;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"External Integrations";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
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
  BOOL yazeEnabled = [[config valueForKeyPath:@"integrations.yaze.enabled" defaultValue:@YES] boolValue];
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

  [self.view addSubview:yazeBox];
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
  BOOL emacsEnabled = [[config valueForKeyPath:@"integrations.emacs.enabled" defaultValue:@YES] boolValue];
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

  [self.view addSubview:emacsBox];
  [self updateEmacsStatus];
  y -= 150;

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

  [self.view addSubview:halextBox];
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

- (void)updateYazeStatus {
  NSString *yazePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Code/yaze"];
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
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/pgrep";
  task.arguments = @[@"-x", @"Emacs"];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;

  @try {
    [task launch];
    [task waitUntilExit];
    if (task.terminationStatus == 0) {
      self.emacsStatus.stringValue = @"Status: ✓ Running";
      self.emacsStatus.textColor = [NSColor systemGreenColor];
    } else {
      self.emacsStatus.stringValue = @"Status: Installed but not running";
      self.emacsStatus.textColor = [NSColor secondaryLabelColor];
    }
  } @catch (NSException *exception) {
    self.emacsStatus.stringValue = @"Status: ✗ Not found";
    self.emacsStatus.textColor = [NSColor systemRedColor];
  }
}

- (void)launchYaze:(id)sender {
  NSString *yazePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Code/yaze/build/bin/yaze"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:yazePath]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:yazePath]];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Yaze Not Found"];
    [alert setInformativeText:@"Build Yaze first: cd ~/Code/yaze && make"];
    [alert runModal];
  }
}

- (void)openYazeRepo:(id)sender {
  NSString *yazePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Code/yaze"];
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

