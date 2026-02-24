#import "ConfigurationManager.h"
#import <Cocoa/Cocoa.h>

@interface AppearanceTabViewController : NSViewController <NSTextFieldDelegate>
@property (strong) NSSlider *heightSlider;
@property (strong) NSTextField *heightValueLabel;
@property (strong) NSSlider *cornerSlider;
@property (strong) NSTextField *cornerValueLabel;
@property (strong) NSSlider *blurSlider;
@property (strong) NSTextField *blurValueLabel;
@property (strong) NSSlider *scaleSlider;
@property (strong) NSTextField *scaleValueLabel;
@property (strong) NSSlider *widgetCornerSlider;
@property (strong) NSTextField *widgetCornerValueLabel;
@property (strong) NSColorWell *barColorWell;
@property (strong) NSTextField *barColorHexField;
@property (strong) NSTextField *menuIconField;
@property (strong) NSTextField *menuIconPreview;
@property (strong) NSButton *menuIconBrowseButton;
@property (strong) NSTextField *fontIconField;
@property (strong) NSTextField *fontTextField;
@property (strong) NSTextField *fontNumbersField;
@property (strong) NSTextField *menuFontStyleField;
@property (strong) NSTextField *menuHeaderFontStyleField;
@property (strong) NSSlider *menuFontOffsetSlider;
@property (strong) NSTextField *menuFontOffsetValueLabel;
@property (strong) NSSlider *menuPopupOpacitySlider;
@property (strong) NSTextField *menuPopupOpacityValueLabel;
@property (strong) NSSlider *menuBorderContrastSlider;
@property (strong) NSTextField *menuBorderContrastValueLabel;
@property (strong) NSButton *applyButton;
@property (strong) NSView *previewBox;
@property (strong) NSTextField *previewBarView;
@end

@implementation AppearanceTabViewController

- (void)loadView {
  self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 950, 700)];
  self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  
  NSStackView *rootStack = [[NSStackView alloc] initWithFrame:NSInsetRect(self.view.bounds, 40, 20)];
  rootStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  rootStack.alignment = NSLayoutAttributeLeading;
  rootStack.spacing = 24;
  rootStack.edgeInsets = NSEdgeInsetsMake(20, 0, 20, 0);
  [self.view addSubview:rootStack];

  // Title
  NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
  title.stringValue = @"Appearance Settings";
  title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
  title.bordered = NO;
  title.editable = NO;
  title.backgroundColor = [NSColor clearColor];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  // Bar Height Row
  NSStackView *heightRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  heightRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  heightRow.spacing = 12;
  
  NSTextField *heightLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  heightLabel.stringValue = @"Bar Height:";
  heightLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  heightLabel.bordered = NO;
  heightLabel.editable = NO;
  heightLabel.backgroundColor = [NSColor clearColor];
  [heightRow addView:heightLabel inGravity:NSStackViewGravityLeading];

  self.heightValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.heightValueLabel.bordered = NO;
  self.heightValueLabel.editable = NO;
  self.heightValueLabel.backgroundColor = [NSColor clearColor];
  self.heightValueLabel.alignment = NSTextAlignmentRight;
  [self.heightValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [heightRow addView:self.heightValueLabel inGravity:NSStackViewGravityLeading];

  self.heightSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.heightSlider.minValue = 20;
  self.heightSlider.maxValue = 50;
  self.heightSlider.doubleValue = [[config valueForKeyPath:@"appearance.bar_height" defaultValue:@28] doubleValue];
  self.heightSlider.target = self;
  self.heightSlider.action = @selector(sliderChanged:);
  [self.heightSlider.widthAnchor constraintEqualToConstant:400].active = YES;
  [heightRow addView:self.heightSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:heightRow inGravity:NSStackViewGravityTop];
  [self updateHeightLabel];

  // Corner Radius Row
  NSStackView *cornerRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  cornerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  cornerRow.spacing = 12;
  
  NSTextField *cornerLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  cornerLabel.stringValue = @"Corner Radius:";
  cornerLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  cornerLabel.bordered = NO;
  cornerLabel.editable = NO;
  cornerLabel.backgroundColor = [NSColor clearColor];
  [cornerRow addView:cornerLabel inGravity:NSStackViewGravityLeading];

  self.cornerValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.cornerValueLabel.bordered = NO;
  self.cornerValueLabel.editable = NO;
  self.cornerValueLabel.backgroundColor = [NSColor clearColor];
  self.cornerValueLabel.alignment = NSTextAlignmentRight;
  [self.cornerValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [cornerRow addView:self.cornerValueLabel inGravity:NSStackViewGravityLeading];

  self.cornerSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.cornerSlider.minValue = 0;
  self.cornerSlider.maxValue = 16;
  self.cornerSlider.doubleValue = [[config valueForKeyPath:@"appearance.corner_radius" defaultValue:@0] doubleValue];
  self.cornerSlider.target = self;
  self.cornerSlider.action = @selector(sliderChanged:);
  [self.cornerSlider.widthAnchor constraintEqualToConstant:400].active = YES;
  [cornerRow addView:self.cornerSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:cornerRow inGravity:NSStackViewGravityTop];
  [self updateCornerLabel];

  // Blur Radius Row
  NSStackView *blurRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  blurRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  blurRow.spacing = 12;
  
  NSTextField *blurLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  blurLabel.stringValue = @"Blur Radius:";
  blurLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  blurLabel.bordered = NO;
  blurLabel.editable = NO;
  blurLabel.backgroundColor = [NSColor clearColor];
  [blurRow addView:blurLabel inGravity:NSStackViewGravityLeading];

  self.blurValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.blurValueLabel.bordered = NO;
  self.blurValueLabel.editable = NO;
  self.blurValueLabel.backgroundColor = [NSColor clearColor];
  self.blurValueLabel.alignment = NSTextAlignmentRight;
  [self.blurValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [blurRow addView:self.blurValueLabel inGravity:NSStackViewGravityLeading];

  self.blurSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.blurSlider.minValue = 0;
  self.blurSlider.maxValue = 80;
  self.blurSlider.doubleValue = [[config valueForKeyPath:@"appearance.blur_radius" defaultValue:@30] doubleValue];
  self.blurSlider.target = self;
  self.blurSlider.action = @selector(sliderChanged:);
  [self.blurSlider.widthAnchor constraintEqualToConstant:400].active = YES;
  [blurRow addView:self.blurSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:blurRow inGravity:NSStackViewGravityTop];
  [self updateBlurLabel];

  // Widget Scale Row
  NSStackView *scaleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  scaleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  scaleRow.spacing = 12;
  
  NSTextField *scaleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  scaleLabel.stringValue = @"Widget Scale:";
  scaleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  scaleLabel.bordered = NO;
  scaleLabel.editable = NO;
  scaleLabel.backgroundColor = [NSColor clearColor];
  [scaleRow addView:scaleLabel inGravity:NSStackViewGravityLeading];

  self.scaleValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.scaleValueLabel.bordered = NO;
  self.scaleValueLabel.editable = NO;
  self.scaleValueLabel.backgroundColor = [NSColor clearColor];
  self.scaleValueLabel.alignment = NSTextAlignmentRight;
  [self.scaleValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [scaleRow addView:self.scaleValueLabel inGravity:NSStackViewGravityLeading];

  self.scaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.scaleSlider.minValue = 0.85;
  self.scaleSlider.maxValue = 1.25;
  self.scaleSlider.doubleValue = [[config valueForKeyPath:@"appearance.widget_scale" defaultValue:@1.0] doubleValue];
  self.scaleSlider.target = self;
  self.scaleSlider.action = @selector(sliderChanged:);
  [self.scaleSlider.widthAnchor constraintEqualToConstant:400].active = YES;
  [scaleRow addView:self.scaleSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:scaleRow inGravity:NSStackViewGravityTop];
  [self updateScaleLabel];

  // Widget Radius Row
  NSStackView *widgetRadiusRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  widgetRadiusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  widgetRadiusRow.spacing = 12;
  
  NSTextField *widgetRadiusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  widgetRadiusLabel.stringValue = @"Widget Radius:";
  widgetRadiusLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  widgetRadiusLabel.bordered = NO;
  widgetRadiusLabel.editable = NO;
  widgetRadiusLabel.backgroundColor = [NSColor clearColor];
  [widgetRadiusRow addView:widgetRadiusLabel inGravity:NSStackViewGravityLeading];

  self.widgetCornerValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.widgetCornerValueLabel.bordered = NO;
  self.widgetCornerValueLabel.editable = NO;
  self.widgetCornerValueLabel.backgroundColor = [NSColor clearColor];
  self.widgetCornerValueLabel.alignment = NSTextAlignmentRight;
  [self.widgetCornerValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [widgetRadiusRow addView:self.widgetCornerValueLabel inGravity:NSStackViewGravityLeading];

  self.widgetCornerSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.widgetCornerSlider.minValue = 0;
  self.widgetCornerSlider.maxValue = 16;
  self.widgetCornerSlider.doubleValue = [[config valueForKeyPath:@"appearance.widget_corner_radius" defaultValue:@6] doubleValue];
  self.widgetCornerSlider.target = self;
  self.widgetCornerSlider.action = @selector(sliderChanged:);
  [self.widgetCornerSlider.widthAnchor constraintEqualToConstant:400].active = YES;
  [widgetRadiusRow addView:self.widgetCornerSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:widgetRadiusRow inGravity:NSStackViewGravityTop];
  [self updateWidgetCornerLabel];

  // Bar Color
  NSStackView *colorRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  colorRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  colorRow.spacing = 12;
  
  NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  colorLabel.stringValue = @"Bar Color:";
  colorLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  colorLabel.bordered = NO;
  colorLabel.editable = NO;
  colorLabel.backgroundColor = [NSColor clearColor];
  [colorRow addView:colorLabel inGravity:NSStackViewGravityLeading];

  self.barColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 25)];
  self.barColorWell.target = self;
  self.barColorWell.action = @selector(colorChanged:);
  [self updateBarColorFromState];
  [colorRow addView:self.barColorWell inGravity:NSStackViewGravityLeading];

  self.barColorHexField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.barColorHexField.placeholderString = @"0xAARRGGBB";
  self.barColorHexField.delegate = self;
  [self.barColorHexField.widthAnchor constraintEqualToConstant:120].active = YES;
  [self updateBarColorHexField];
  [colorRow addView:self.barColorHexField inGravity:NSStackViewGravityLeading];
  [rootStack addView:colorRow inGravity:NSStackViewGravityTop];

  // System Menu Icon
  NSStackView *iconRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  iconRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  iconRow.spacing = 12;
  
  NSTextField *menuIconLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuIconLabel.stringValue = @"System Menu Icon:";
  menuIconLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuIconLabel.bordered = NO;
  menuIconLabel.editable = NO;
  menuIconLabel.backgroundColor = [NSColor clearColor];
  [iconRow addView:menuIconLabel inGravity:NSStackViewGravityLeading];

  self.menuIconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuIconField.placeholderString = @"Glyph";
  self.menuIconField.delegate = self;
  [self.menuIconField.widthAnchor constraintEqualToConstant:60].active = YES;
  NSString *currentMenuIcon = [config valueForKeyPath:@"icons.apple" defaultValue:@"󰒓"];
  self.menuIconField.stringValue = [currentMenuIcon isKindOfClass:[NSString class]] ? currentMenuIcon : @"";
  [iconRow addView:self.menuIconField inGravity:NSStackViewGravityLeading];

  self.menuIconPreview = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuIconPreview.bordered = NO;
  self.menuIconPreview.editable = NO;
  self.menuIconPreview.backgroundColor = [NSColor clearColor];
  self.menuIconPreview.alignment = NSTextAlignmentCenter;
  self.menuIconPreview.font = [NSFont fontWithName:@"Symbols Nerd Font" size:24] ?: [NSFont systemFontOfSize:24];
  [self.menuIconPreview.widthAnchor constraintEqualToConstant:40].active = YES;
  [iconRow addView:self.menuIconPreview inGravity:NSStackViewGravityLeading];

  self.menuIconBrowseButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.menuIconBrowseButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.menuIconBrowseButton setBezelStyle:NSBezelStyleRounded];
  self.menuIconBrowseButton.title = @"Icon Library";
  self.menuIconBrowseButton.target = self;
  self.menuIconBrowseButton.action = @selector(openIconBrowser:);
  [iconRow addView:self.menuIconBrowseButton inGravity:NSStackViewGravityLeading];
  [rootStack addView:iconRow inGravity:NSStackViewGravityTop];
  [self updateMenuIconPreview];

  // Fonts
  NSStackView *fontRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  fontRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  fontRow.spacing = 12;
  
  NSTextField *fontLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  fontLabel.stringValue = @"Fonts:";
  fontLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  fontLabel.bordered = NO;
  fontLabel.editable = NO;
  fontLabel.backgroundColor = [NSColor clearColor];
  [fontRow addView:fontLabel inGravity:NSStackViewGravityLeading];

  self.fontIconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontIconField.placeholderString = @"Icon Font";
  self.fontIconField.delegate = self;
  [self.fontIconField.widthAnchor constraintEqualToConstant:180].active = YES;
  self.fontIconField.stringValue = [config valueForKeyPath:@"appearance.font_icon" defaultValue:@""] ?: @"";
  [fontRow addView:self.fontIconField inGravity:NSStackViewGravityLeading];

  self.fontTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontTextField.placeholderString = @"Text Font";
  self.fontTextField.delegate = self;
  [self.fontTextField.widthAnchor constraintEqualToConstant:180].active = YES;
  self.fontTextField.stringValue = [config valueForKeyPath:@"appearance.font_text" defaultValue:@""] ?: @"";
  [fontRow addView:self.fontTextField inGravity:NSStackViewGravityLeading];

  self.fontNumbersField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontNumbersField.placeholderString = @"Numbers Font";
  self.fontNumbersField.delegate = self;
  [self.fontNumbersField.widthAnchor constraintEqualToConstant:180].active = YES;
  self.fontNumbersField.stringValue = [config valueForKeyPath:@"appearance.font_numbers" defaultValue:@""] ?: @"";
  [fontRow addView:self.fontNumbersField inGravity:NSStackViewGravityLeading];
  [rootStack addView:fontRow inGravity:NSStackViewGravityTop];

  // Menu readability controls
  NSTextField *menuReadabilityTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuReadabilityTitle.stringValue = @"Menu Readability";
  menuReadabilityTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  menuReadabilityTitle.bordered = NO;
  menuReadabilityTitle.editable = NO;
  menuReadabilityTitle.backgroundColor = [NSColor clearColor];
  [rootStack addView:menuReadabilityTitle inGravity:NSStackViewGravityTop];

  NSStackView *menuStyleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  menuStyleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  menuStyleRow.spacing = 12;

  NSTextField *menuStyleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuStyleLabel.stringValue = @"Menu Font Style:";
  menuStyleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuStyleLabel.bordered = NO;
  menuStyleLabel.editable = NO;
  menuStyleLabel.backgroundColor = [NSColor clearColor];
  [menuStyleRow addView:menuStyleLabel inGravity:NSStackViewGravityLeading];

  self.menuFontStyleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuFontStyleField.placeholderString = @"Semibold";
  self.menuFontStyleField.delegate = self;
  self.menuFontStyleField.stringValue = [config valueForKeyPath:@"appearance.menu_font_style" defaultValue:@"Bold"] ?: @"Bold";
  [self.menuFontStyleField.widthAnchor constraintEqualToConstant:160].active = YES;
  [menuStyleRow addView:self.menuFontStyleField inGravity:NSStackViewGravityLeading];

  NSTextField *menuHeaderStyleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuHeaderStyleLabel.stringValue = @"Header Style:";
  menuHeaderStyleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuHeaderStyleLabel.bordered = NO;
  menuHeaderStyleLabel.editable = NO;
  menuHeaderStyleLabel.backgroundColor = [NSColor clearColor];
  [menuStyleRow addView:menuHeaderStyleLabel inGravity:NSStackViewGravityLeading];

  self.menuHeaderFontStyleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuHeaderFontStyleField.placeholderString = @"Bold";
  self.menuHeaderFontStyleField.delegate = self;
  self.menuHeaderFontStyleField.stringValue = [config valueForKeyPath:@"appearance.menu_header_font_style" defaultValue:@"Bold"] ?: @"Bold";
  [self.menuHeaderFontStyleField.widthAnchor constraintEqualToConstant:160].active = YES;
  [menuStyleRow addView:self.menuHeaderFontStyleField inGravity:NSStackViewGravityLeading];
  [rootStack addView:menuStyleRow inGravity:NSStackViewGravityTop];

  NSStackView *menuOffsetRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  menuOffsetRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  menuOffsetRow.spacing = 12;

  NSTextField *menuOffsetLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuOffsetLabel.stringValue = @"Menu Font Size Offset:";
  menuOffsetLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuOffsetLabel.bordered = NO;
  menuOffsetLabel.editable = NO;
  menuOffsetLabel.backgroundColor = [NSColor clearColor];
  [menuOffsetRow addView:menuOffsetLabel inGravity:NSStackViewGravityLeading];

  self.menuFontOffsetValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuFontOffsetValueLabel.bordered = NO;
  self.menuFontOffsetValueLabel.editable = NO;
  self.menuFontOffsetValueLabel.backgroundColor = [NSColor clearColor];
  self.menuFontOffsetValueLabel.alignment = NSTextAlignmentRight;
  [self.menuFontOffsetValueLabel.widthAnchor constraintEqualToConstant:50].active = YES;
  [menuOffsetRow addView:self.menuFontOffsetValueLabel inGravity:NSStackViewGravityLeading];

  self.menuFontOffsetSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.menuFontOffsetSlider.minValue = -1;
  self.menuFontOffsetSlider.maxValue = 4;
  self.menuFontOffsetSlider.doubleValue = [[config valueForKeyPath:@"appearance.menu_font_size_offset" defaultValue:@1] doubleValue];
  self.menuFontOffsetSlider.target = self;
  self.menuFontOffsetSlider.action = @selector(sliderChanged:);
  [self.menuFontOffsetSlider.widthAnchor constraintEqualToConstant:260].active = YES;
  [menuOffsetRow addView:self.menuFontOffsetSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:menuOffsetRow inGravity:NSStackViewGravityTop];
  [self updateMenuFontOffsetLabel];

  NSString *menuPopupHex = [config valueForKeyPath:@"appearance.menu_popup_bg_color" defaultValue:@"0xE021162F"];
  NSColor *menuPopupColor = [self colorFromHexString:menuPopupHex];
  CGFloat popupAlpha = menuPopupColor ? menuPopupColor.alphaComponent : 0.88;

  NSStackView *menuOpacityRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  menuOpacityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  menuOpacityRow.spacing = 12;

  NSTextField *menuOpacityLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuOpacityLabel.stringValue = @"Popup Opacity:";
  menuOpacityLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuOpacityLabel.bordered = NO;
  menuOpacityLabel.editable = NO;
  menuOpacityLabel.backgroundColor = [NSColor clearColor];
  [menuOpacityRow addView:menuOpacityLabel inGravity:NSStackViewGravityLeading];

  self.menuPopupOpacityValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuPopupOpacityValueLabel.bordered = NO;
  self.menuPopupOpacityValueLabel.editable = NO;
  self.menuPopupOpacityValueLabel.backgroundColor = [NSColor clearColor];
  self.menuPopupOpacityValueLabel.alignment = NSTextAlignmentRight;
  [self.menuPopupOpacityValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [menuOpacityRow addView:self.menuPopupOpacityValueLabel inGravity:NSStackViewGravityLeading];

  self.menuPopupOpacitySlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.menuPopupOpacitySlider.minValue = 0.65;
  self.menuPopupOpacitySlider.maxValue = 1.0;
  self.menuPopupOpacitySlider.doubleValue = popupAlpha;
  self.menuPopupOpacitySlider.target = self;
  self.menuPopupOpacitySlider.action = @selector(sliderChanged:);
  [self.menuPopupOpacitySlider.widthAnchor constraintEqualToConstant:260].active = YES;
  [menuOpacityRow addView:self.menuPopupOpacitySlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:menuOpacityRow inGravity:NSStackViewGravityTop];
  [self updateMenuPopupOpacityLabel];

  NSString *menuBorderHex = [config valueForKeyPath:@"appearance.popup_border_color" defaultValue:@"0x60cdd6f4"];
  NSColor *menuBorderColor = [self colorFromHexString:menuBorderHex];
  CGFloat borderAlpha = menuBorderColor ? menuBorderColor.alphaComponent : 0.4;

  NSStackView *menuBorderRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  menuBorderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  menuBorderRow.spacing = 12;

  NSTextField *menuBorderLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  menuBorderLabel.stringValue = @"Border Contrast:";
  menuBorderLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  menuBorderLabel.bordered = NO;
  menuBorderLabel.editable = NO;
  menuBorderLabel.backgroundColor = [NSColor clearColor];
  [menuBorderRow addView:menuBorderLabel inGravity:NSStackViewGravityLeading];

  self.menuBorderContrastValueLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuBorderContrastValueLabel.bordered = NO;
  self.menuBorderContrastValueLabel.editable = NO;
  self.menuBorderContrastValueLabel.backgroundColor = [NSColor clearColor];
  self.menuBorderContrastValueLabel.alignment = NSTextAlignmentRight;
  [self.menuBorderContrastValueLabel.widthAnchor constraintEqualToConstant:60].active = YES;
  [menuBorderRow addView:self.menuBorderContrastValueLabel inGravity:NSStackViewGravityLeading];

  self.menuBorderContrastSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  self.menuBorderContrastSlider.minValue = 0.20;
  self.menuBorderContrastSlider.maxValue = 1.0;
  self.menuBorderContrastSlider.doubleValue = borderAlpha;
  self.menuBorderContrastSlider.target = self;
  self.menuBorderContrastSlider.action = @selector(sliderChanged:);
  [self.menuBorderContrastSlider.widthAnchor constraintEqualToConstant:260].active = YES;
  [menuBorderRow addView:self.menuBorderContrastSlider inGravity:NSStackViewGravityLeading];
  [rootStack addView:menuBorderRow inGravity:NSStackViewGravityTop];
  [self updateMenuBorderContrastLabel];

  // Live Preview Section
  NSView *previewContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  [previewContainer.heightAnchor constraintEqualToConstant:140].active = YES;
  [previewContainer.widthAnchor constraintEqualToConstant:600].active = YES;
  
  NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  previewLabel.stringValue = @"LIVE PREVIEW";
  previewLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
  previewLabel.textColor = [NSColor secondaryLabelColor];
  previewLabel.bordered = NO;
  previewLabel.editable = NO;
  previewLabel.backgroundColor = [NSColor clearColor];
  previewLabel.frame = NSMakeRect(0, 110, 200, 20);
  [previewContainer addSubview:previewLabel];

  self.previewBox = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 100)];
  self.previewBox.wantsLayer = YES;
  self.previewBox.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.2].CGColor;
  self.previewBox.layer.cornerRadius = 12;
  [previewContainer addSubview:self.previewBox];

  self.previewBarView = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 36, 560, 28)];
  self.previewBarView.bordered = NO;
  self.previewBarView.editable = NO;
  self.previewBarView.stringValue = @"   󰒓 SketchyBar Prototype";
  self.previewBarView.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  self.previewBarView.textColor = [NSColor whiteColor];
  self.previewBarView.backgroundColor = [self.barColorWell.color colorWithAlphaComponent:0.8];
  self.previewBarView.wantsLayer = YES;
  [self.previewBox addSubview:self.previewBarView];
  [rootStack addView:previewContainer inGravity:NSStackViewGravityTop];
  [self updatePreview];

  // Apply Button
  self.applyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply Changes & Restart SketchyBar";
  self.applyButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.applyButton.widthAnchor constraintEqualToConstant:300].active = YES;
  [self.applyButton.heightAnchor constraintEqualToConstant:40].active = YES;
  [rootStack addView:self.applyButton inGravity:NSStackViewGravityTop];
}

- (void)sliderChanged:(NSSlider *)sender {
  if (sender == self.heightSlider) {
    [self updateHeightLabel];
    [self updatePreview];
  } else if (sender == self.cornerSlider) {
    [self updateCornerLabel];
    [self updatePreview];
  } else if (sender == self.blurSlider) {
    [self updateBlurLabel];
  } else if (sender == self.scaleSlider) {
    [self updateScaleLabel];
  } else if (sender == self.widgetCornerSlider) {
    [self updateWidgetCornerLabel];
  } else if (sender == self.menuFontOffsetSlider) {
    [self updateMenuFontOffsetLabel];
  } else if (sender == self.menuPopupOpacitySlider) {
    [self updateMenuPopupOpacityLabel];
  } else if (sender == self.menuBorderContrastSlider) {
    [self updateMenuBorderContrastLabel];
  }
}

- (void)colorChanged:(NSColorWell *)sender {
  [self updateBarColorHexField];
  [self updatePreview];
}

- (void)updateHeightLabel {
  self.heightValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.heightSlider.doubleValue];
}

- (void)updateCornerLabel {
  self.cornerValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.cornerSlider.doubleValue];
}

- (void)updateBlurLabel {
  self.blurValueLabel.stringValue = [NSString stringWithFormat:@"%d", (int)self.blurSlider.doubleValue];
}

- (void)updateScaleLabel {
  self.scaleValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", self.scaleSlider.doubleValue];
}

- (void)updateMenuFontOffsetLabel {
  self.menuFontOffsetValueLabel.stringValue = [NSString stringWithFormat:@"%d", (int)self.menuFontOffsetSlider.doubleValue];
}

- (void)updateMenuPopupOpacityLabel {
  self.menuPopupOpacityValueLabel.stringValue = [NSString stringWithFormat:@"%0.0f%%", self.menuPopupOpacitySlider.doubleValue * 100.0];
}

- (void)updateMenuBorderContrastLabel {
  self.menuBorderContrastValueLabel.stringValue = [NSString stringWithFormat:@"%0.0f%%", self.menuBorderContrastSlider.doubleValue * 100.0];
}

- (void)updateBarColorFromState {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *hexColor = [config valueForKeyPath:@"appearance.bar_color" defaultValue:@"0xC021162F"];
  NSColor *color = [self colorFromHexString:hexColor];
  if (color) {
    self.barColorWell.color = color;
  }
}

- (void)updateBarColorHexField {
  NSString *hex = [self hexStringFromColor:self.barColorWell.color];
  self.barColorHexField.stringValue = hex;
}

- (void)updateMenuIconPreview {
  NSString *icon = self.menuIconField.stringValue ?: @"";
  self.menuIconPreview.stringValue = icon;
}

- (void)openIconBrowser:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSString *configDir = config.configPath ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
  NSString *iconBrowserPath = [configDir stringByAppendingPathComponent:@"gui/bin/icon_browser"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:iconBrowserPath]) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = iconBrowserPath;
    [task launch];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Icon Browser Not Found";
    alert.informativeText = [NSString stringWithFormat:@"Build icon_browser first: cd %@/gui && make icon_browser", configDir];
    [alert runModal];
  }
}

- (void)controlTextDidChange:(NSNotification *)notification {
  id field = notification.object;
  if (field == self.barColorHexField) {
    NSColor *color = [self colorFromHexString:self.barColorHexField.stringValue];
    if (color) {
      self.barColorWell.color = color;
      [self updatePreview];
    }
  } else if (field == self.menuIconField) {
    [self updateMenuIconPreview];
  }
}

- (void)updatePreview {
  CGFloat height = self.heightSlider.doubleValue;
  CGFloat corner = self.cornerSlider.doubleValue;
  NSColor *color = [self.barColorWell.color colorWithAlphaComponent:0.8];

  CGRect frame = self.previewBarView.frame;
  frame.size.height = height;
  frame.origin.y = (self.previewBox.bounds.size.height - height) / 2;
  self.previewBarView.frame = frame;
  self.previewBarView.backgroundColor = color;
  self.previewBarView.layer.cornerRadius = corner;
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

- (void)applySettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  [config setValue:@((int)self.heightSlider.doubleValue) forKeyPath:@"appearance.bar_height"];
  [config setValue:@((int)self.cornerSlider.doubleValue) forKeyPath:@"appearance.corner_radius"];
  [config setValue:@((int)self.blurSlider.doubleValue) forKeyPath:@"appearance.blur_radius"];
  [config setValue:@(self.scaleSlider.doubleValue) forKeyPath:@"appearance.widget_scale"];
  [config setValue:@((int)self.widgetCornerSlider.doubleValue) forKeyPath:@"appearance.widget_corner_radius"];

  NSString *hexColor = [self hexStringFromColor:self.barColorWell.color];
  [config setValue:hexColor forKeyPath:@"appearance.bar_color"];

  NSString *menuIcon = self.menuIconField.stringValue ?: @"";
  [config setValue:menuIcon forKeyPath:@"icons.apple"];

  if (self.fontIconField.stringValue.length > 0) {
    [config setValue:self.fontIconField.stringValue forKeyPath:@"appearance.font_icon"];
  }
  if (self.fontTextField.stringValue.length > 0) {
    [config setValue:self.fontTextField.stringValue forKeyPath:@"appearance.font_text"];
  }
  if (self.fontNumbersField.stringValue.length > 0) {
    [config setValue:self.fontNumbersField.stringValue forKeyPath:@"appearance.font_numbers"];
  }

  NSString *menuFontStyle = [self.menuFontStyleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (menuFontStyle.length > 0) {
    [config setValue:menuFontStyle forKeyPath:@"appearance.menu_font_style"];
  }
  NSString *menuHeaderFontStyle = [self.menuHeaderFontStyleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (menuHeaderFontStyle.length > 0) {
    [config setValue:menuHeaderFontStyle forKeyPath:@"appearance.menu_header_font_style"];
  }

  [config setValue:@((int)self.menuFontOffsetSlider.doubleValue) forKeyPath:@"appearance.menu_font_size_offset"];

  NSString *menuPopupHexCurrent = [config valueForKeyPath:@"appearance.menu_popup_bg_color" defaultValue:@"0xE021162F"];
  NSColor *menuPopupBase = [self colorFromHexString:menuPopupHexCurrent];
  if (!menuPopupBase) {
    menuPopupBase = [self colorFromHexString:@"0xE021162F"];
  }
  NSColor *menuPopupUpdated = [menuPopupBase colorWithAlphaComponent:self.menuPopupOpacitySlider.doubleValue];
  [config setValue:[self hexStringFromColor:menuPopupUpdated] forKeyPath:@"appearance.menu_popup_bg_color"];

  NSString *menuBorderHexCurrent = [config valueForKeyPath:@"appearance.popup_border_color" defaultValue:@"0x60cdd6f4"];
  NSColor *menuBorderBase = [self colorFromHexString:menuBorderHexCurrent];
  if (!menuBorderBase) {
    menuBorderBase = [self colorFromHexString:@"0x60cdd6f4"];
  }
  NSColor *menuBorderUpdated = [menuBorderBase colorWithAlphaComponent:self.menuBorderContrastSlider.doubleValue];
  [config setValue:[self hexStringFromColor:menuBorderUpdated] forKeyPath:@"appearance.popup_border_color"];

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"✓ Applied!";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply & Reload Bar";
  });
}

- (void)updateWidgetCornerLabel {
  if (!self.widgetCornerValueLabel) return;
  [self.widgetCornerValueLabel setStringValue:[NSString stringWithFormat:@"%0.0f", self.widgetCornerSlider.doubleValue]];
}

@end
