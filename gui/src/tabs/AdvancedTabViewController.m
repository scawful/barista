#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface AdvancedTabViewController : NSViewController <NSTextViewDelegate>
@property (strong) NSTextView *jsonEditor;
@property (strong) NSButton *saveButton;
@property (strong) NSButton *reloadButton;
@property (strong) NSTextField *statusLabel;
@end

@implementation AdvancedTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Advanced Settings";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 50;

  // JSON Editor Label
  NSTextField *editorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 200, 20)];
  editorLabel.stringValue = @"Raw State JSON:";
  editorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  editorLabel.bordered = NO;
  editorLabel.editable = NO;
  editorLabel.backgroundColor = [NSColor clearColor];
  [self.view addSubview:editorLabel];
  y -= 30;

  // JSON Editor
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 100, self.view.bounds.size.width - 80, y - 100)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.jsonEditor = [[NSTextView alloc] initWithFrame:scrollView.bounds];
  self.jsonEditor.font = [NSFont fontWithName:@"SF Mono" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
  self.jsonEditor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.jsonEditor.delegate = self;

  scrollView.documentView = self.jsonEditor;
  [self.view addSubview:scrollView];

  [self loadJSON];

  // Buttons
  self.saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, 50, 120, 32)];
  [self.saveButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.saveButton setBezelStyle:NSBezelStyleRounded];
  self.saveButton.title = @"Save JSON";
  self.saveButton.target = self;
  self.saveButton.action = @selector(saveJSON:);
  [self.view addSubview:self.saveButton];

  self.reloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 130, 50, 140, 32)];
  [self.reloadButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.reloadButton setBezelStyle:NSBezelStyleRounded];
  self.reloadButton.title = @"Reload from Disk";
  self.reloadButton.target = self;
  self.reloadButton.action = @selector(reloadJSON:);
  [self.view addSubview:self.reloadButton];

  NSButton *openConfigButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 280, 50, 160, 32)];
  [openConfigButton setButtonType:NSButtonTypeMomentaryPushIn];
  [openConfigButton setBezelStyle:NSBezelStyleRounded];
  openConfigButton.title = @"Open Config Folder";
  openConfigButton.target = self;
  openConfigButton.action = @selector(openConfigFolder:);
  [self.view addSubview:openConfigButton];

  NSButton *reloadBarButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin + 450, 50, 140, 32)];
  [reloadBarButton setButtonType:NSButtonTypeMomentaryPushIn];
  [reloadBarButton setBezelStyle:NSBezelStyleRounded];
  reloadBarButton.title = @"Reload Bar";
  reloadBarButton.target = self;
  reloadBarButton.action = @selector(reloadBar:);
  [self.view addSubview:reloadBarButton];

  // Status
  self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, 20, 500, 20)];
  self.statusLabel.stringValue = @"";
  self.statusLabel.bordered = NO;
  self.statusLabel.editable = NO;
  self.statusLabel.backgroundColor = [NSColor clearColor];
  self.statusLabel.font = [NSFont systemFontOfSize:12];
  [self.view addSubview:self.statusLabel];

  // System Info
  NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, 10, 600, 8)];
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  infoLabel.stringValue = [NSString stringWithFormat:@"Config: %@ | State: %@",
                           config.configPath, config.statePath];
  infoLabel.bordered = NO;
  infoLabel.editable = NO;
  infoLabel.backgroundColor = [NSColor clearColor];
  infoLabel.font = [NSFont systemFontOfSize:9];
  infoLabel.textColor = [NSColor secondaryLabelColor];
  [self.view addSubview:infoLabel];
}

- (void)loadJSON {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config loadState];

  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config.state
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:&error];
  if (!error && jsonData) {
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    self.jsonEditor.string = jsonString;
  } else {
    self.jsonEditor.string = @"{}";
  }
}

- (void)saveJSON:(id)sender {
  NSString *jsonString = self.jsonEditor.string;

  NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  id parsedJSON = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];

  if (error || ![parsedJSON isKindOfClass:[NSDictionary class]]) {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"❌ Invalid JSON: %@", error.localizedDescription];
    self.statusLabel.textColor = [NSColor systemRedColor];
    NSBeep();
    return;
  }

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  config.state = [parsedJSON mutableCopy];

  if ([config saveState]) {
    self.statusLabel.stringValue = @"✓ Saved successfully";
    self.statusLabel.textColor = [NSColor systemGreenColor];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      self.statusLabel.stringValue = @"";
    });
  } else {
    self.statusLabel.stringValue = @"❌ Failed to save";
    self.statusLabel.textColor = [NSColor systemRedColor];
  }
}

- (void)reloadJSON:(id)sender {
  [self loadJSON];
  self.statusLabel.stringValue = @"✓ Reloaded from disk";
  self.statusLabel.textColor = [NSColor systemGreenColor];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.statusLabel.stringValue = @"";
  });
}

- (void)openConfigFolder:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:config.configPath]];
}

- (void)reloadBar:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  [config reloadSketchyBar];

  self.statusLabel.stringValue = @"✓ Sketchybar reloading...";
  self.statusLabel.textColor = [NSColor systemGreenColor];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.statusLabel.stringValue = @"";
  });
}

@end

