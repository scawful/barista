#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface WidgetsTabViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSTableView *tableView;
@property (strong) NSArray *widgets;
@end

@implementation WidgetsTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.widgets = @[
    @{@"key": @"clock", @"name": @"Clock", @"icon": @""},
    @{@"key": @"battery", @"name": @"Battery", @"icon": @""},
    @{@"key": @"volume", @"name": @"Volume", @"icon": @"󰕾"},
    @{@"key": @"network", @"name": @"Network", @"icon": @"󰖩"},
    @{@"key": @"system_info", @"name": @"System Info", @"icon": @"󰍛"},
  ];

  CGFloat y = self.view.bounds.size.height - 40;
  CGFloat leftMargin = 40;

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, y, 400, 30)];
  title.stringValue = @"Widget Management";
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [self.view addSubview:title];
  y -= 60;

  // Table view
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftMargin, 60, 700, y - 60)];
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.borderType = NSBezelBorder;

  self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
  iconColumn.title = @"";
  iconColumn.width = 40;
  [self.tableView addTableColumn:iconColumn];

  NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  nameColumn.title = @"Widget";
  nameColumn.width = 200;
  [self.tableView addTableColumn:nameColumn];

  NSTableColumn *enabledColumn = [[NSTableColumn alloc] initWithIdentifier:@"enabled"];
  enabledColumn.title = @"Enabled";
  enabledColumn.width = 80;
  [self.tableView addTableColumn:enabledColumn];

  NSTableColumn *colorColumn = [[NSTableColumn alloc] initWithIdentifier:@"color"];
  colorColumn.title = @"Color";
  colorColumn.width = 120;
  [self.tableView addTableColumn:colorColumn];

  scrollView.documentView = self.tableView;
  [self.view addSubview:scrollView];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.widgets.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSDictionary *widget = self.widgets[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"icon"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
    textField.stringValue = widget[@"icon"];
    textField.font = [NSFont systemFontOfSize:16];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    return textField;
  }

  if ([identifier isEqualToString:@"name"]) {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
    textField.stringValue = widget[@"name"];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    return textField;
  }

  if ([identifier isEqualToString:@"enabled"]) {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20)];
    [checkbox setButtonType:NSButtonTypeSwitch];
    checkbox.title = @"";
    checkbox.tag = row;
    checkbox.target = self;
    checkbox.action = @selector(toggleWidget:);

    ConfigurationManager *config = [ConfigurationManager sharedManager];
    NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", widget[@"key"]];
    BOOL enabled = [[config valueForKeyPath:keyPath defaultValue:@YES] boolValue];
    checkbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    return checkbox;
  }

  if ([identifier isEqualToString:@"color"]) {
    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    colorWell.tag = row;
    colorWell.target = self;
    colorWell.action = @selector(widgetColorChanged:);
    // Load widget color from state
    ConfigurationManager *config = [ConfigurationManager sharedManager];
    NSString *keyPath = [NSString stringWithFormat:@"widget_colors.%@", widget[@"key"]];
    NSString *hexColor = [config valueForKeyPath:keyPath defaultValue:nil];
    if (hexColor) {
      NSColor *color = [self colorFromHexString:hexColor];
      if (color) {
        colorWell.color = color;
      }
    }
    return colorWell;
  }

  return nil;
}

- (void)toggleWidget:(NSButton *)sender {
  NSDictionary *widget = self.widgets[sender.tag];
  BOOL enabled = sender.state == NSControlStateValueOn;

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widgets.%@", widget[@"key"]];
  [config setValue:@(enabled) forKeyPath:keyPath];
  [config reloadSketchyBar];
}

- (void)widgetColorChanged:(NSColorWell *)sender {
  NSDictionary *widget = self.widgets[sender.tag];
  NSColor *color = sender.color;

  // Convert to hex and save
  NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  int alpha = (int)(rgbColor.alphaComponent * 255);
  int red = (int)(rgbColor.redComponent * 255);
  int green = (int)(rgbColor.greenComponent * 255);
  int blue = (int)(rgbColor.blueComponent * 255);
  NSString *hexColor = [NSString stringWithFormat:@"0x%02X%02X%02X%02X", alpha, red, green, blue];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *keyPath = [NSString stringWithFormat:@"widget_colors.%@", widget[@"key"]];
  [config setValue:hexColor forKeyPath:keyPath];
  [config reloadSketchyBar];
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

@end

