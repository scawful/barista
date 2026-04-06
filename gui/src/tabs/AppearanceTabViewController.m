#import "AppearanceTabViewController.h"
#import "ConfigurationManager.h"

@interface AppearanceTabViewController () <NSTextFieldDelegate>
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
@property (strong) NSPopUpButton *fontIconPopup;
@property (strong) NSTextField *fontIconPreviewLabel;
@property (strong) NSPopUpButton *fontTextPopup;
@property (strong) NSTextField *fontTextPreviewLabel;
@property (strong) NSPopUpButton *fontNumbersPopup;
@property (strong) NSTextField *fontNumbersPreviewLabel;
@property (strong) NSPopUpButton *menuFontStylePopup;
@property (strong) NSPopUpButton *menuHeaderFontStylePopup;
@property (strong) NSPopUpButton *clockFontStylePopup;
@property (strong) NSSlider *menuFontOffsetSlider;
@property (strong) NSTextField *menuFontOffsetValueLabel;
@property (strong) NSSlider *menuRowHeightSlider;
@property (strong) NSTextField *menuRowHeightValueLabel;
@property (strong) NSSlider *menuPaddingSlider;
@property (strong) NSTextField *menuPaddingValueLabel;
@property (strong) NSSlider *submenuDelaySlider;
@property (strong) NSTextField *submenuDelayValueLabel;
@property (strong) NSSlider *menuPopupOpacitySlider;
@property (strong) NSTextField *menuPopupOpacityValueLabel;
@property (strong) NSSlider *menuBorderContrastSlider;
@property (strong) NSTextField *menuBorderContrastValueLabel;

// Bar Geometry
@property (strong) NSSlider *barPaddingLeftSlider;
@property (strong) NSTextField *barPaddingLeftValueLabel;
@property (strong) NSSlider *barPaddingRightSlider;
@property (strong) NSTextField *barPaddingRightValueLabel;
@property (strong) NSSlider *barMarginSlider;
@property (strong) NSTextField *barMarginValueLabel;
@property (strong) NSSlider *barYOffsetSlider;
@property (strong) NSTextField *barYOffsetValueLabel;

// Bar Border
@property (strong) NSSlider *barBorderWidthSlider;
@property (strong) NSTextField *barBorderWidthValueLabel;
@property (strong) NSColorWell *barBorderColorWell;
@property (strong) NSTextField *barBorderColorHexField;

// Popup Geometry
@property (strong) NSSlider *popupCornerRadiusSlider;
@property (strong) NSTextField *popupCornerRadiusValueLabel;
@property (strong) NSSlider *popupBorderWidthSlider;
@property (strong) NSTextField *popupBorderWidthValueLabel;
@property (strong) NSSlider *popupItemCornerRadiusSlider;
@property (strong) NSTextField *popupItemCornerRadiusValueLabel;

// Hover & Animation
@property (strong) NSColorWell *hoverColorWell;
@property (strong) NSTextField *hoverColorHexField;
@property (strong) NSColorWell *hoverBorderColorWell;
@property (strong) NSTextField *hoverBorderColorHexField;
@property (strong) NSSlider *hoverBorderWidthSlider;
@property (strong) NSTextField *hoverBorderWidthValueLabel;
@property (strong) NSPopUpButton *hoverAnimCurvePopup;
@property (strong) NSSlider *hoverAnimDurationSlider;
@property (strong) NSTextField *hoverAnimDurationValueLabel;

// Group Styling
@property (strong) NSColorWell *groupBgColorWell;
@property (strong) NSTextField *groupBgColorHexField;
@property (strong) NSColorWell *groupBorderColorWell;
@property (strong) NSTextField *groupBorderColorHexField;
@property (strong) NSSlider *groupBorderWidthSlider;
@property (strong) NSTextField *groupBorderWidthValueLabel;
@property (strong) NSSlider *groupCornerRadiusSlider;
@property (strong) NSTextField *groupCornerRadiusValueLabel;

@property (strong) NSButton *applyButton;
@property (strong) NSView *previewBox;
@property (strong) NSTextField *previewBarView;
@property (strong) NSTextField *previewIconLabel;
@property (strong) NSTextField *previewClockLabel;
@end

@implementation AppearanceTabViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  ConfigurationManager *config = [ConfigurationManager sharedManager];
  NSStackView *rootStack = nil;
  [self scrollViewWithRootStack:&rootStack edgeInsets:NSEdgeInsetsMake(24, 24, 28, 24) spacing:18];

  NSString *currentTheme = [config valueForKeyPath:@"appearance.theme" defaultValue:@"default"] ?: @"default";
  NSString *currentProfile = [config valueForKeyPath:@"profile" defaultValue:@"default"] ?: @"default";
  NSString *currentMenuIcon = [config valueForKeyPath:@"icons.apple" defaultValue:@"󰒓"] ?: @"󰒓";

  NSTextField *title = [self titleLabel:@"Appearance" fontSize:26];
  [rootStack addView:title inGravity:NSStackViewGravityTop];

  NSTextField *subtitle = [self helperLabel:@"Tune the bar like a native inspector: surface first, then type, then popup behavior. Keep it calm, readable, and deliberate."];
  [rootStack addView:subtitle inGravity:NSStackViewGravityTop];

  NSStackView *metaRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  metaRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  metaRow.spacing = 14;
  [rootStack addView:metaRow inGravity:NSStackViewGravityTop];
  for (NSString *meta in @[
    [NSString stringWithFormat:@"Theme: %@", currentTheme],
    [NSString stringWithFormat:@"Profile: %@", currentProfile],
    [NSString stringWithFormat:@"Menu icon: %@", currentMenuIcon]
  ]) {
    [metaRow addView:[self metaLabel:meta] inGravity:NSStackViewGravityLeading];
  }

  NSStackView *previewSection = nil;
  NSBox *previewBoxSection = [self sectionBoxWithTitle:@"Live Preview"
                                              subtitle:@"Preview the overall bar character before applying changes. The preview updates as you tune geometry, color, and the Apple-menu glyph."
                                           contentStack:&previewSection
                                             edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                                spacing:10];
  [rootStack addView:previewBoxSection inGravity:NSStackViewGravityTop];
  [previewBoxSection.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;

  self.previewBox = [[NSView alloc] initWithFrame:NSZeroRect];
  self.previewBox.wantsLayer = YES;
  self.previewBox.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.22].CGColor;
  self.previewBox.layer.cornerRadius = 14.0;
  self.previewBox.layer.borderWidth = 1.0;
  self.previewBox.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08].CGColor;
  [self.previewBox.heightAnchor constraintEqualToConstant:156].active = YES;
  [self.previewBox.widthAnchor constraintGreaterThanOrEqualToConstant:420].active = YES;
  [previewSection addView:self.previewBox inGravity:NSStackViewGravityTop];

  self.previewBarView = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 54, 360, 28)];
  self.previewBarView.bordered = NO;
  self.previewBarView.editable = NO;
  self.previewBarView.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  self.previewBarView.textColor = [NSColor whiteColor];
  self.previewBarView.backgroundColor = [NSColor clearColor];
  self.previewBarView.wantsLayer = YES;
  self.previewBarView.layer.masksToBounds = YES;
  [self.previewBox addSubview:self.previewBarView];

  self.previewIconLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 54, 30, 20)];
  self.previewIconLabel.bordered = NO;
  self.previewIconLabel.editable = NO;
  self.previewIconLabel.backgroundColor = [NSColor clearColor];
  self.previewIconLabel.textColor = [NSColor whiteColor];
  [self.previewBox addSubview:self.previewIconLabel];

  self.previewClockLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 54, 150, 20)];
  self.previewClockLabel.bordered = NO;
  self.previewClockLabel.editable = NO;
  self.previewClockLabel.backgroundColor = [NSColor clearColor];
  self.previewClockLabel.textColor = [NSColor whiteColor];
  self.previewClockLabel.alignment = NSTextAlignmentRight;
  [self.previewBox addSubview:self.previewClockLabel];

  NSStackView *surfaceSection = nil;
  NSBox *surfaceBox = [self sectionBoxWithTitle:@"Bar Surface"
                                        subtitle:@"Core geometry and tint. These settings determine the first impression of the bar before any widget details matter."
                                     contentStack:&surfaceSection
                                       edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                          spacing:10];
  [rootStack addView:surfaceBox inGravity:NSStackViewGravityTop];
  [surfaceBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *surfaceGrid = [self formGrid];
  [surfaceSection addView:surfaceGrid inGravity:NSStackViewGravityTop];

  self.heightSlider = [self configuredSliderWithMin:20 max:50 value:[[config valueForKeyPath:@"appearance.bar_height" defaultValue:@28] doubleValue]];
  self.heightValueLabel = [self metricValueLabelWithWidth:64.0];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Bar height" width:150], [self sliderControlWithSlider:self.heightSlider valueLabel:self.heightValueLabel minimumWidth:220.0]]];
  [self updateHeightLabel];

  self.cornerSlider = [self configuredSliderWithMin:0 max:16 value:[[config valueForKeyPath:@"appearance.corner_radius" defaultValue:@0] doubleValue]];
  self.cornerValueLabel = [self metricValueLabelWithWidth:64.0];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Corner radius" width:150], [self sliderControlWithSlider:self.cornerSlider valueLabel:self.cornerValueLabel minimumWidth:220.0]]];
  [self updateCornerLabel];

  self.blurSlider = [self configuredSliderWithMin:0 max:80 value:[[config valueForKeyPath:@"appearance.blur_radius" defaultValue:@30] doubleValue]];
  self.blurValueLabel = [self metricValueLabelWithWidth:64.0];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Blur radius" width:150], [self sliderControlWithSlider:self.blurSlider valueLabel:self.blurValueLabel minimumWidth:220.0]]];
  [self updateBlurLabel];

  self.scaleSlider = [self configuredSliderWithMin:0.85 max:1.25 value:[[config valueForKeyPath:@"appearance.widget_scale" defaultValue:@1.0] doubleValue]];
  self.scaleValueLabel = [self metricValueLabelWithWidth:64.0];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Widget scale" width:150], [self sliderControlWithSlider:self.scaleSlider valueLabel:self.scaleValueLabel minimumWidth:220.0]]];
  [self updateScaleLabel];

  self.widgetCornerSlider = [self configuredSliderWithMin:0 max:16 value:[[config valueForKeyPath:@"appearance.widget_corner_radius" defaultValue:@6] doubleValue]];
  self.widgetCornerValueLabel = [self metricValueLabelWithWidth:64.0];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Widget radius" width:150], [self sliderControlWithSlider:self.widgetCornerSlider valueLabel:self.widgetCornerValueLabel minimumWidth:220.0]]];
  [self updateWidgetCornerLabel];

  self.barColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 54, 28)];
  self.barColorWell.target = self;
  self.barColorWell.action = @selector(colorChanged:);
  [self updateBarColorFromState];

  self.barColorHexField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.barColorHexField.placeholderString = @"0xAARRGGBB";
  self.barColorHexField.delegate = self;
  [self.barColorHexField.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
  [self.barColorHexField.widthAnchor constraintLessThanOrEqualToConstant:180].active = YES;
  [self updateBarColorHexField];

  NSStackView *colorControl = [[NSStackView alloc] initWithFrame:NSZeroRect];
  colorControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  colorControl.spacing = 12;
  [colorControl addView:self.barColorWell inGravity:NSStackViewGravityLeading];
  [colorControl addView:self.barColorHexField inGravity:NSStackViewGravityLeading];
  [surfaceGrid addRowWithViews:@[[self fieldLabel:@"Bar tint" width:150], colorControl]];

  NSStackView *typeSection = nil;
  NSBox *typeBox = [self sectionBoxWithTitle:@"Typography & Icons"
                                     subtitle:@"Keep the type stack coherent. The system menu icon and font families should feel like part of the same voice."
                                  contentStack:&typeSection
                                    edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                       spacing:10];
  [rootStack addView:typeBox inGravity:NSStackViewGravityTop];
  [typeBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *typeGrid = [self formGrid];
  [typeSection addView:typeGrid inGravity:NSStackViewGravityTop];

  self.menuIconField = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuIconField.placeholderString = @"Glyph";
  self.menuIconField.delegate = self;
  [self.menuIconField.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
  [self.menuIconField.widthAnchor constraintLessThanOrEqualToConstant:96].active = YES;
  self.menuIconField.stringValue = currentMenuIcon;

  self.menuIconPreview = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.menuIconPreview.bordered = NO;
  self.menuIconPreview.editable = NO;
  self.menuIconPreview.backgroundColor = [NSColor clearColor];
  self.menuIconPreview.alignment = NSTextAlignmentCenter;
  self.menuIconPreview.font = [NSFont fontWithName:@"Symbols Nerd Font" size:22] ?: [NSFont systemFontOfSize:22];
  [self.menuIconPreview.widthAnchor constraintEqualToConstant:40].active = YES;

  self.menuIconBrowseButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.menuIconBrowseButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.menuIconBrowseButton setBezelStyle:NSBezelStyleRounded];
  self.menuIconBrowseButton.title = @"Browse Icons";
  self.menuIconBrowseButton.target = self;
  self.menuIconBrowseButton.action = @selector(openIconBrowser:);

  NSStackView *iconControl = [[NSStackView alloc] initWithFrame:NSZeroRect];
  iconControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  iconControl.spacing = 12;
  [iconControl addView:self.menuIconField inGravity:NSStackViewGravityLeading];
  [iconControl addView:self.menuIconPreview inGravity:NSStackViewGravityLeading];
  [iconControl addView:self.menuIconBrowseButton inGravity:NSStackViewGravityLeading];
  [typeGrid addRowWithViews:@[[self fieldLabel:@"Apple-menu icon" width:150], iconControl]];
  [self updateMenuIconPreview];

  // Icon font popup + preview
  NSString *currentIconFont = [config valueForKeyPath:@"appearance.font_icon" defaultValue:@""];
  self.fontIconPopup = [self fontFamilyPopupWithSelection:currentIconFont width:200 target:self action:@selector(fontPopupChanged:)];

  self.fontIconPreviewLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontIconPreviewLabel.stringValue = @"ABC 123";
  self.fontIconPreviewLabel.bordered = NO;
  self.fontIconPreviewLabel.editable = NO;
  self.fontIconPreviewLabel.backgroundColor = [NSColor clearColor];
  self.fontIconPreviewLabel.textColor = [NSColor secondaryLabelColor];
  [self updateFontPreviewLabel:self.fontIconPreviewLabel fromPopup:self.fontIconPopup];

  NSStackView *iconFontRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  iconFontRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  iconFontRow.spacing = 12;
  [iconFontRow addView:self.fontIconPopup inGravity:NSStackViewGravityLeading];
  [iconFontRow addView:self.fontIconPreviewLabel inGravity:NSStackViewGravityLeading];
  [typeGrid addRowWithViews:@[[self fieldLabel:@"Icon font" width:150], iconFontRow]];

  // Text font popup + preview
  NSString *currentTextFont = [config valueForKeyPath:@"appearance.font_text" defaultValue:@""];
  self.fontTextPopup = [self fontFamilyPopupWithSelection:currentTextFont width:200 target:self action:@selector(fontPopupChanged:)];

  self.fontTextPreviewLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontTextPreviewLabel.stringValue = @"ABC 123";
  self.fontTextPreviewLabel.bordered = NO;
  self.fontTextPreviewLabel.editable = NO;
  self.fontTextPreviewLabel.backgroundColor = [NSColor clearColor];
  self.fontTextPreviewLabel.textColor = [NSColor secondaryLabelColor];
  [self updateFontPreviewLabel:self.fontTextPreviewLabel fromPopup:self.fontTextPopup];

  NSStackView *textFontRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  textFontRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  textFontRow.spacing = 12;
  [textFontRow addView:self.fontTextPopup inGravity:NSStackViewGravityLeading];
  [textFontRow addView:self.fontTextPreviewLabel inGravity:NSStackViewGravityLeading];
  [typeGrid addRowWithViews:@[[self fieldLabel:@"Text font" width:150], textFontRow]];

  // Numbers font popup + preview
  NSString *currentNumbersFont = [config valueForKeyPath:@"appearance.font_numbers" defaultValue:@""];
  self.fontNumbersPopup = [self fontFamilyPopupWithSelection:currentNumbersFont width:200 target:self action:@selector(fontPopupChanged:)];

  self.fontNumbersPreviewLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
  self.fontNumbersPreviewLabel.stringValue = @"ABC 123";
  self.fontNumbersPreviewLabel.bordered = NO;
  self.fontNumbersPreviewLabel.editable = NO;
  self.fontNumbersPreviewLabel.backgroundColor = [NSColor clearColor];
  self.fontNumbersPreviewLabel.textColor = [NSColor secondaryLabelColor];
  [self updateFontPreviewLabel:self.fontNumbersPreviewLabel fromPopup:self.fontNumbersPopup];

  NSStackView *numbersFontRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
  numbersFontRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  numbersFontRow.spacing = 12;
  [numbersFontRow addView:self.fontNumbersPopup inGravity:NSStackViewGravityLeading];
  [numbersFontRow addView:self.fontNumbersPreviewLabel inGravity:NSStackViewGravityLeading];
  [typeGrid addRowWithViews:@[[self fieldLabel:@"Numbers font" width:150], numbersFontRow]];

  // Clock font style popup
  NSString *currentClockStyle = [config valueForKeyPath:@"appearance.clock_font_style" defaultValue:@"Semibold"];
  self.clockFontStylePopup = [self fontStylePopupWithSelection:currentClockStyle width:160 target:self action:@selector(fontStylePopupChanged:)];
  [typeGrid addRowWithViews:@[[self fieldLabel:@"Clock font style" width:150], self.clockFontStylePopup]];

  NSStackView *popupSection = nil;
  NSBox *popupBox = [self sectionBoxWithTitle:@"Popup Surface"
                                      subtitle:@"Tune the Apple-menu reading experience without hand-editing state. Keep it dense enough to scan, but loose enough to breathe."
                                   contentStack:&popupSection
                                     edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                        spacing:10];
  [rootStack addView:popupBox inGravity:NSStackViewGravityTop];
  [popupBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *popupGrid = [self formGrid];
  [popupSection addView:popupGrid inGravity:NSStackViewGravityTop];

  NSString *currentMenuStyle = [config valueForKeyPath:@"appearance.menu_font_style" defaultValue:@"Bold"];
  self.menuFontStylePopup = [self fontStylePopupWithSelection:currentMenuStyle width:160 target:self action:@selector(fontStylePopupChanged:)];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Menu font style" width:150], self.menuFontStylePopup]];

  NSString *currentHeaderStyle = [config valueForKeyPath:@"appearance.menu_header_font_style" defaultValue:@"Bold"];
  self.menuHeaderFontStylePopup = [self fontStylePopupWithSelection:currentHeaderStyle width:160 target:self action:@selector(fontStylePopupChanged:)];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Section header style" width:150], self.menuHeaderFontStylePopup]];

  self.menuFontOffsetSlider = [self configuredSliderWithMin:-1 max:4 value:[[config valueForKeyPath:@"appearance.menu_font_size_offset" defaultValue:@1] doubleValue]];
  self.menuFontOffsetValueLabel = [self metricValueLabelWithWidth:58.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Font size offset" width:150], [self sliderControlWithSlider:self.menuFontOffsetSlider valueLabel:self.menuFontOffsetValueLabel minimumWidth:220.0]]];
  [self updateMenuFontOffsetLabel];

  self.menuRowHeightSlider = [self configuredSliderWithMin:0 max:36 value:[[config valueForKeyPath:@"appearance.menu_item_height" defaultValue:@0] doubleValue]];
  self.menuRowHeightValueLabel = [self metricValueLabelWithWidth:72.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Popup row height" width:150], [self sliderControlWithSlider:self.menuRowHeightSlider valueLabel:self.menuRowHeightValueLabel minimumWidth:220.0]]];
  [self updateMenuRowHeightLabel];

  self.menuPaddingSlider = [self configuredSliderWithMin:4 max:16 value:[[config valueForKeyPath:@"appearance.menu_padding" defaultValue:@8] doubleValue]];
  self.menuPaddingValueLabel = [self metricValueLabelWithWidth:72.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Popup padding" width:150], [self sliderControlWithSlider:self.menuPaddingSlider valueLabel:self.menuPaddingValueLabel minimumWidth:220.0]]];
  [self updateMenuPaddingLabel];

  self.submenuDelaySlider = [self configuredSliderWithMin:0.05 max:0.60 value:[[config valueForKeyPath:@"appearance.submenu_close_delay" defaultValue:@0.25] doubleValue]];
  self.submenuDelayValueLabel = [self metricValueLabelWithWidth:72.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Fly-out delay" width:150], [self sliderControlWithSlider:self.submenuDelaySlider valueLabel:self.submenuDelayValueLabel minimumWidth:220.0]]];
  [self updateSubmenuDelayLabel];

  NSString *menuPopupHex = [config valueForKeyPath:@"appearance.menu_popup_bg_color" defaultValue:@"0xE021162F"];
  NSColor *menuPopupColor = [self colorFromHexString:menuPopupHex];
  CGFloat popupAlpha = menuPopupColor ? menuPopupColor.alphaComponent : 0.88;
  self.menuPopupOpacitySlider = [self configuredSliderWithMin:0.65 max:1.0 value:popupAlpha];
  self.menuPopupOpacityValueLabel = [self metricValueLabelWithWidth:72.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Popup opacity" width:150], [self sliderControlWithSlider:self.menuPopupOpacitySlider valueLabel:self.menuPopupOpacityValueLabel minimumWidth:220.0]]];
  [self updateMenuPopupOpacityLabel];

  NSString *menuBorderHex = [config valueForKeyPath:@"appearance.popup_border_color" defaultValue:@"0x60cdd6f4"];
  NSColor *menuBorderColor = [self colorFromHexString:menuBorderHex];
  CGFloat borderAlpha = menuBorderColor ? menuBorderColor.alphaComponent : 0.4;
  self.menuBorderContrastSlider = [self configuredSliderWithMin:0.20 max:1.0 value:borderAlpha];
  self.menuBorderContrastValueLabel = [self metricValueLabelWithWidth:72.0];
  [popupGrid addRowWithViews:@[[self fieldLabel:@"Border contrast" width:150], [self sliderControlWithSlider:self.menuBorderContrastSlider valueLabel:self.menuBorderContrastValueLabel minimumWidth:220.0]]];
  [self updateMenuBorderContrastLabel];

  // ── Section: Bar Geometry ──────────────────────────────────────────
  NSStackView *barGeomSection = nil;
  NSBox *barGeomBox = [self sectionBoxWithTitle:@"Bar Geometry"
                                       subtitle:@"Fine-tune bar positioning and padding."
                                    contentStack:&barGeomSection
                                      edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                         spacing:10];
  [rootStack addView:barGeomBox inGravity:NSStackViewGravityTop];
  [barGeomBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *barGeomGrid = [self formGrid];
  [barGeomSection addView:barGeomGrid inGravity:NSStackViewGravityTop];

  self.barPaddingLeftSlider = [self configuredSliderWithMin:0 max:30 value:[[config valueForKeyPath:@"appearance.bar_padding_left" defaultValue:@14] doubleValue]];
  self.barPaddingLeftValueLabel = [self metricValueLabelWithWidth:64.0];
  [barGeomGrid addRowWithViews:@[[self fieldLabel:@"Padding left" width:150], [self sliderControlWithSlider:self.barPaddingLeftSlider valueLabel:self.barPaddingLeftValueLabel minimumWidth:220.0]]];
  [self updateBarPaddingLeftLabel];

  self.barPaddingRightSlider = [self configuredSliderWithMin:0 max:30 value:[[config valueForKeyPath:@"appearance.bar_padding_right" defaultValue:@14] doubleValue]];
  self.barPaddingRightValueLabel = [self metricValueLabelWithWidth:64.0];
  [barGeomGrid addRowWithViews:@[[self fieldLabel:@"Padding right" width:150], [self sliderControlWithSlider:self.barPaddingRightSlider valueLabel:self.barPaddingRightValueLabel minimumWidth:220.0]]];
  [self updateBarPaddingRightLabel];

  self.barMarginSlider = [self configuredSliderWithMin:0 max:20 value:[[config valueForKeyPath:@"appearance.bar_margin" defaultValue:@0] doubleValue]];
  self.barMarginValueLabel = [self metricValueLabelWithWidth:64.0];
  [barGeomGrid addRowWithViews:@[[self fieldLabel:@"Margin" width:150], [self sliderControlWithSlider:self.barMarginSlider valueLabel:self.barMarginValueLabel minimumWidth:220.0]]];
  [self updateBarMarginLabel];

  self.barYOffsetSlider = [self configuredSliderWithMin:-10 max:10 value:[[config valueForKeyPath:@"appearance.bar_y_offset" defaultValue:@0] doubleValue]];
  self.barYOffsetValueLabel = [self metricValueLabelWithWidth:64.0];
  [barGeomGrid addRowWithViews:@[[self fieldLabel:@"Y offset" width:150], [self sliderControlWithSlider:self.barYOffsetSlider valueLabel:self.barYOffsetValueLabel minimumWidth:220.0]]];
  [self updateBarYOffsetLabel];

  // ── Section: Bar Border ────────────────────────────────────────────
  NSStackView *barBorderSection = nil;
  NSBox *barBorderBox = [self sectionBoxWithTitle:@"Bar Border"
                                          subtitle:@"Add a border to the bar."
                                       contentStack:&barBorderSection
                                         edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                            spacing:10];
  [rootStack addView:barBorderBox inGravity:NSStackViewGravityTop];
  [barBorderBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *barBorderGrid = [self formGrid];
  [barBorderSection addView:barBorderGrid inGravity:NSStackViewGravityTop];

  self.barBorderWidthSlider = [self configuredSliderWithMin:0 max:4 value:[[config valueForKeyPath:@"appearance.bar_border_width" defaultValue:@0] doubleValue]];
  self.barBorderWidthValueLabel = [self metricValueLabelWithWidth:64.0];
  [barBorderGrid addRowWithViews:@[[self fieldLabel:@"Border width" width:150], [self sliderControlWithSlider:self.barBorderWidthSlider valueLabel:self.barBorderWidthValueLabel minimumWidth:220.0]]];
  [self updateBarBorderWidthLabel];

  NSString *barBorderColorHex = [config valueForKeyPath:@"appearance.bar_border_color" defaultValue:@"0x00000000"];
  { NSColorWell *w; NSTextField *h;
    NSView *ctrl = [self colorControlWithWell:&w hexField:&h initialColor:barBorderColorHex];
    self.barBorderColorWell = w; self.barBorderColorHexField = h;
    [barBorderGrid addRowWithViews:@[[self fieldLabel:@"Border color" width:150], ctrl]];
  }

  // ── Section: Popup Geometry ────────────────────────────────────────
  NSStackView *popupGeomSection = nil;
  NSBox *popupGeomBox = [self sectionBoxWithTitle:@"Popup Geometry"
                                          subtitle:@"Popup corner radius and border geometry."
                                       contentStack:&popupGeomSection
                                         edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                            spacing:10];
  [rootStack addView:popupGeomBox inGravity:NSStackViewGravityTop];
  [popupGeomBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *popupGeomGrid = [self formGrid];
  [popupGeomSection addView:popupGeomGrid inGravity:NSStackViewGravityTop];

  self.popupCornerRadiusSlider = [self configuredSliderWithMin:0 max:16 value:[[config valueForKeyPath:@"appearance.popup_corner_radius" defaultValue:@8] doubleValue]];
  self.popupCornerRadiusValueLabel = [self metricValueLabelWithWidth:64.0];
  [popupGeomGrid addRowWithViews:@[[self fieldLabel:@"Corner radius" width:150], [self sliderControlWithSlider:self.popupCornerRadiusSlider valueLabel:self.popupCornerRadiusValueLabel minimumWidth:220.0]]];
  [self updatePopupCornerRadiusLabel];

  self.popupBorderWidthSlider = [self configuredSliderWithMin:0 max:4 value:[[config valueForKeyPath:@"appearance.popup_border_width" defaultValue:@2] doubleValue]];
  self.popupBorderWidthValueLabel = [self metricValueLabelWithWidth:64.0];
  [popupGeomGrid addRowWithViews:@[[self fieldLabel:@"Border width" width:150], [self sliderControlWithSlider:self.popupBorderWidthSlider valueLabel:self.popupBorderWidthValueLabel minimumWidth:220.0]]];
  [self updatePopupBorderWidthLabel];

  self.popupItemCornerRadiusSlider = [self configuredSliderWithMin:0 max:8 value:[[config valueForKeyPath:@"appearance.popup_item_corner_radius" defaultValue:@4] doubleValue]];
  self.popupItemCornerRadiusValueLabel = [self metricValueLabelWithWidth:64.0];
  [popupGeomGrid addRowWithViews:@[[self fieldLabel:@"Item corner radius" width:150], [self sliderControlWithSlider:self.popupItemCornerRadiusSlider valueLabel:self.popupItemCornerRadiusValueLabel minimumWidth:220.0]]];
  [self updatePopupItemCornerRadiusLabel];

  // ── Section: Hover & Animation ─────────────────────────────────────
  NSStackView *hoverSection = nil;
  NSBox *hoverBox = [self sectionBoxWithTitle:@"Hover & Animation"
                                      subtitle:@"Hover highlight and transition behavior."
                                   contentStack:&hoverSection
                                     edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                        spacing:10];
  [rootStack addView:hoverBox inGravity:NSStackViewGravityTop];
  [hoverBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *hoverGrid = [self formGrid];
  [hoverSection addView:hoverGrid inGravity:NSStackViewGravityTop];

  NSString *hoverColorHex = [config valueForKeyPath:@"appearance.hover_color" defaultValue:@"0x40f5c2e7"];
  { NSColorWell *w; NSTextField *h;
    NSView *ctrl = [self colorControlWithWell:&w hexField:&h initialColor:hoverColorHex];
    self.hoverColorWell = w; self.hoverColorHexField = h;
    [hoverGrid addRowWithViews:@[[self fieldLabel:@"Hover color" width:150], ctrl]];
  }

  NSString *hoverBorderColorHex = [config valueForKeyPath:@"appearance.hover_border_color" defaultValue:@"0x60cdd6f4"];
  { NSColorWell *w; NSTextField *h;
    NSView *ctrl = [self colorControlWithWell:&w hexField:&h initialColor:hoverBorderColorHex];
    self.hoverBorderColorWell = w; self.hoverBorderColorHexField = h;
    [hoverGrid addRowWithViews:@[[self fieldLabel:@"Hover border color" width:150], ctrl]];
  }

  self.hoverBorderWidthSlider = [self configuredSliderWithMin:0 max:4 value:[[config valueForKeyPath:@"appearance.hover_border_width" defaultValue:@1] doubleValue]];
  self.hoverBorderWidthValueLabel = [self metricValueLabelWithWidth:64.0];
  [hoverGrid addRowWithViews:@[[self fieldLabel:@"Hover border width" width:150], [self sliderControlWithSlider:self.hoverBorderWidthSlider valueLabel:self.hoverBorderWidthValueLabel minimumWidth:220.0]]];
  [self updateHoverBorderWidthLabel];

  self.hoverAnimCurvePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  [self.hoverAnimCurvePopup addItemsWithTitles:@[@"sin", @"quadratic", @"tanh", @"linear"]];
  NSString *currentAnimCurve = [config valueForKeyPath:@"appearance.hover_animation_curve" defaultValue:@"sin"];
  [self.hoverAnimCurvePopup selectItemWithTitle:currentAnimCurve];
  if (!self.hoverAnimCurvePopup.selectedItem) [self.hoverAnimCurvePopup selectItemAtIndex:0];
  [self.hoverAnimCurvePopup.widthAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;
  [hoverGrid addRowWithViews:@[[self fieldLabel:@"Animation curve" width:150], self.hoverAnimCurvePopup]];

  self.hoverAnimDurationSlider = [self configuredSliderWithMin:1 max:30 value:[[config valueForKeyPath:@"appearance.hover_animation_duration" defaultValue:@8] doubleValue]];
  self.hoverAnimDurationValueLabel = [self metricValueLabelWithWidth:64.0];
  [hoverGrid addRowWithViews:@[[self fieldLabel:@"Animation duration" width:150], [self sliderControlWithSlider:self.hoverAnimDurationSlider valueLabel:self.hoverAnimDurationValueLabel minimumWidth:220.0]]];
  [self updateHoverAnimDurationLabel];

  // ── Section: Group Styling ─────────────────────────────────────────
  NSStackView *groupSection = nil;
  NSBox *groupBox = [self sectionBoxWithTitle:@"Group Styling"
                                      subtitle:@"Background and border for widget groups."
                                   contentStack:&groupSection
                                     edgeInsets:NSEdgeInsetsMake(14, 14, 14, 14)
                                        spacing:10];
  [rootStack addView:groupBox inGravity:NSStackViewGravityTop];
  [groupBox.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor].active = YES;
  NSGridView *groupGrid = [self formGrid];
  [groupSection addView:groupGrid inGravity:NSStackViewGravityTop];

  NSString *groupBgColorHex = [config valueForKeyPath:@"appearance.group_bg_color" defaultValue:@"0x30313244"];
  { NSColorWell *w; NSTextField *h;
    NSView *ctrl = [self colorControlWithWell:&w hexField:&h initialColor:groupBgColorHex];
    self.groupBgColorWell = w; self.groupBgColorHexField = h;
    [groupGrid addRowWithViews:@[[self fieldLabel:@"BG color" width:150], ctrl]];
  }

  NSString *groupBorderColorHex = [config valueForKeyPath:@"appearance.group_border_color" defaultValue:@"0x20585b70"];
  { NSColorWell *w; NSTextField *h;
    NSView *ctrl = [self colorControlWithWell:&w hexField:&h initialColor:groupBorderColorHex];
    self.groupBorderColorWell = w; self.groupBorderColorHexField = h;
    [groupGrid addRowWithViews:@[[self fieldLabel:@"Border color" width:150], ctrl]];
  }

  self.groupBorderWidthSlider = [self configuredSliderWithMin:0 max:4 value:[[config valueForKeyPath:@"appearance.group_border_width" defaultValue:@1] doubleValue]];
  self.groupBorderWidthValueLabel = [self metricValueLabelWithWidth:64.0];
  [groupGrid addRowWithViews:@[[self fieldLabel:@"Border width" width:150], [self sliderControlWithSlider:self.groupBorderWidthSlider valueLabel:self.groupBorderWidthValueLabel minimumWidth:220.0]]];
  [self updateGroupBorderWidthLabel];

  self.groupCornerRadiusSlider = [self configuredSliderWithMin:0 max:16 value:[[config valueForKeyPath:@"appearance.group_corner_radius" defaultValue:@6] doubleValue]];
  self.groupCornerRadiusValueLabel = [self metricValueLabelWithWidth:64.0];
  [groupGrid addRowWithViews:@[[self fieldLabel:@"Corner radius" width:150], [self sliderControlWithSlider:self.groupCornerRadiusSlider valueLabel:self.groupCornerRadiusValueLabel minimumWidth:220.0]]];
  [self updateGroupCornerRadiusLabel];

  NSStackView *footer = [[NSStackView alloc] initWithFrame:NSZeroRect];
  footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  footer.spacing = 14;
  footer.alignment = NSLayoutAttributeCenterY;
  [rootStack addView:footer inGravity:NSStackViewGravityTop];

  self.applyButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  [self.applyButton setButtonType:NSButtonTypeMomentaryPushIn];
  [self.applyButton setBezelStyle:NSBezelStyleRounded];
  self.applyButton.title = @"Apply Appearance Changes";
  self.applyButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  self.applyButton.target = self;
  self.applyButton.action = @selector(applySettings:);
  [self.applyButton.widthAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
  [self.applyButton.heightAnchor constraintEqualToConstant:34].active = YES;
  [footer addView:self.applyButton inGravity:NSStackViewGravityLeading];

  NSTextField *footerNote = [self helperLabel:@"Changes save to state, then reload SketchyBar once so the bar updates as a single coherent pass."];
  [footerNote.widthAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
  [footer addView:footerNote inGravity:NSStackViewGravityLeading];

  [self updatePreview];
}

- (void)viewDidLayout {
  [super viewDidLayout];
  [self updatePreview];
}

- (NSTextField *)metaLabel:(NSString *)text {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text ?: @"";
  label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
  label.textColor = [NSColor colorWithCalibratedRed:0.64 green:0.84 blue:1.0 alpha:1.0];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  return label;
}

- (NSTextField *)metricValueLabelWithWidth:(CGFloat)width {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.bordered = NO;
  label.editable = NO;
  label.backgroundColor = [NSColor clearColor];
  label.alignment = NSTextAlignmentRight;
  label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  label.textColor = [NSColor secondaryLabelColor];
  [label.widthAnchor constraintEqualToConstant:width].active = YES;
  return label;
}

- (NSGridView *)formGrid {
  NSGridView *grid = [[NSGridView alloc] initWithFrame:NSZeroRect];
  grid.rowSpacing = 12;
  grid.columnSpacing = 16;
  grid.xPlacement = NSGridCellPlacementLeading;
  grid.yPlacement = NSGridCellPlacementCenter;
  return grid;
}

- (NSSlider *)configuredSliderWithMin:(double)minimum max:(double)maximum value:(double)value {
  NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
  slider.minValue = minimum;
  slider.maxValue = maximum;
  slider.doubleValue = value;
  slider.target = self;
  slider.action = @selector(sliderChanged:);
  return slider;
}

- (NSView *)sliderControlWithSlider:(NSSlider *)slider valueLabel:(NSTextField *)valueLabel minimumWidth:(CGFloat)minimumWidth {
  [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [slider setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [slider.widthAnchor constraintGreaterThanOrEqualToConstant:minimumWidth].active = YES;

  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  stack.alignment = NSLayoutAttributeCenterY;
  stack.spacing = 12;
  [stack addView:slider inGravity:NSStackViewGravityLeading];
  [stack addView:valueLabel inGravity:NSStackViewGravityLeading];
  return stack;
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
  } else if (sender == self.menuRowHeightSlider) {
    [self updateMenuRowHeightLabel];
  } else if (sender == self.menuPaddingSlider) {
    [self updateMenuPaddingLabel];
  } else if (sender == self.submenuDelaySlider) {
    [self updateSubmenuDelayLabel];
  } else if (sender == self.menuPopupOpacitySlider) {
    [self updateMenuPopupOpacityLabel];
  } else if (sender == self.menuBorderContrastSlider) {
    [self updateMenuBorderContrastLabel];
  } else if (sender == self.barPaddingLeftSlider) {
    [self updateBarPaddingLeftLabel];
  } else if (sender == self.barPaddingRightSlider) {
    [self updateBarPaddingRightLabel];
  } else if (sender == self.barMarginSlider) {
    [self updateBarMarginLabel];
  } else if (sender == self.barYOffsetSlider) {
    [self updateBarYOffsetLabel];
  } else if (sender == self.barBorderWidthSlider) {
    [self updateBarBorderWidthLabel];
  } else if (sender == self.popupCornerRadiusSlider) {
    [self updatePopupCornerRadiusLabel];
  } else if (sender == self.popupBorderWidthSlider) {
    [self updatePopupBorderWidthLabel];
  } else if (sender == self.popupItemCornerRadiusSlider) {
    [self updatePopupItemCornerRadiusLabel];
  } else if (sender == self.hoverBorderWidthSlider) {
    [self updateHoverBorderWidthLabel];
  } else if (sender == self.hoverAnimDurationSlider) {
    [self updateHoverAnimDurationLabel];
  } else if (sender == self.groupBorderWidthSlider) {
    [self updateGroupBorderWidthLabel];
  } else if (sender == self.groupCornerRadiusSlider) {
    [self updateGroupCornerRadiusLabel];
  }
}

- (void)colorChanged:(NSColorWell *)sender {
  if (sender == self.barColorWell) {
    [self updateBarColorHexField];
    [self updatePreview];
  } else if (sender == self.barBorderColorWell) {
    self.barBorderColorHexField.stringValue = [self hexStringFromColor:sender.color];
  } else if (sender == self.hoverColorWell) {
    self.hoverColorHexField.stringValue = [self hexStringFromColor:sender.color];
  } else if (sender == self.hoverBorderColorWell) {
    self.hoverBorderColorHexField.stringValue = [self hexStringFromColor:sender.color];
  } else if (sender == self.groupBgColorWell) {
    self.groupBgColorHexField.stringValue = [self hexStringFromColor:sender.color];
  } else if (sender == self.groupBorderColorWell) {
    self.groupBorderColorHexField.stringValue = [self hexStringFromColor:sender.color];
  }
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

- (void)updateMenuRowHeightLabel {
  int value = (int)self.menuRowHeightSlider.doubleValue;
  self.menuRowHeightValueLabel.stringValue = value <= 0 ? @"Auto" : [NSString stringWithFormat:@"%d px", value];
}

- (void)updateMenuPaddingLabel {
  self.menuPaddingValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.menuPaddingSlider.doubleValue];
}

- (void)updateSubmenuDelayLabel {
  self.submenuDelayValueLabel.stringValue = [NSString stringWithFormat:@"%.2fs", self.submenuDelaySlider.doubleValue];
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
    [self updatePreview];
  } else if (field == self.barBorderColorHexField) {
    NSColor *c = [self colorFromHexString:self.barBorderColorHexField.stringValue];
    if (c) self.barBorderColorWell.color = c;
  } else if (field == self.hoverColorHexField) {
    NSColor *c = [self colorFromHexString:self.hoverColorHexField.stringValue];
    if (c) self.hoverColorWell.color = c;
  } else if (field == self.hoverBorderColorHexField) {
    NSColor *c = [self colorFromHexString:self.hoverBorderColorHexField.stringValue];
    if (c) self.hoverBorderColorWell.color = c;
  } else if (field == self.groupBgColorHexField) {
    NSColor *c = [self colorFromHexString:self.groupBgColorHexField.stringValue];
    if (c) self.groupBgColorWell.color = c;
  } else if (field == self.groupBorderColorHexField) {
    NSColor *c = [self colorFromHexString:self.groupBorderColorHexField.stringValue];
    if (c) self.groupBorderColorWell.color = c;
  }
}

- (void)fontPopupChanged:(NSPopUpButton *)sender {
  if (sender == self.fontIconPopup) {
    [self updateFontPreviewLabel:self.fontIconPreviewLabel fromPopup:self.fontIconPopup];
  } else if (sender == self.fontTextPopup) {
    [self updateFontPreviewLabel:self.fontTextPreviewLabel fromPopup:self.fontTextPopup];
  } else if (sender == self.fontNumbersPopup) {
    [self updateFontPreviewLabel:self.fontNumbersPreviewLabel fromPopup:self.fontNumbersPopup];
  }
  [self updatePreview];
}

- (void)fontStylePopupChanged:(NSPopUpButton *)sender {
  [self updatePreview];
}

- (void)updateFontPreviewLabel:(NSTextField *)label fromPopup:(NSPopUpButton *)popup {
  NSString *fontName = popup.selectedItem.title;
  NSFont *font = nil;
  if (![fontName isEqualToString:@"(System Default)"]) {
    font = [NSFont fontWithName:fontName size:13];
  }
  label.font = font ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
}

- (void)updatePreview {
  if (!self.previewBox || !self.previewBarView) return;

  CGFloat height = self.heightSlider.doubleValue;
  CGFloat corner = self.cornerSlider.doubleValue;
  NSColor *color = [self.barColorWell.color colorWithAlphaComponent:0.8];
  NSString *menuIcon = self.menuIconField.stringValue.length > 0 ? self.menuIconField.stringValue : @"󰒓";

  // Position and style bar
  CGRect frame = self.previewBarView.frame;
  frame.origin.x = 18.0;
  frame.size.width = MAX(220.0, self.previewBox.bounds.size.width - 36.0);
  frame.size.height = height;
  frame.origin.y = floor((self.previewBox.bounds.size.height - height) / 2.0);
  self.previewBarView.frame = frame;
  self.previewBarView.stringValue = @"";
  self.previewBarView.drawsBackground = NO;
  self.previewBarView.layer.backgroundColor = color.CGColor;
  self.previewBarView.layer.cornerRadius = corner;

  // Resolve fonts from popups
  NSString *iconFontName = self.fontIconPopup.selectedItem.title;
  NSString *textFontName = self.fontTextPopup.selectedItem.title;
  NSFont *iconFont = (![iconFontName isEqualToString:@"(System Default)"])
    ? [NSFont fontWithName:iconFontName size:14] : nil;
  NSFont *textFont = (![textFontName isEqualToString:@"(System Default)"])
    ? [NSFont fontWithName:textFontName size:12] : nil;

  // Icon label (left side of bar)
  self.previewIconLabel.font = iconFont ?: [self preferredIconFontWithSize:14];
  self.previewIconLabel.stringValue = menuIcon;
  CGFloat iconY = frame.origin.y + floor((height - 18) / 2.0);
  self.previewIconLabel.frame = NSMakeRect(frame.origin.x + 10, iconY, 24, 18);

  // Clock label (right side of bar)
  self.previewClockLabel.font = textFont ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightSemibold];
  NSDateFormatter *df = [[NSDateFormatter alloc] init];
  df.dateFormat = @"h:mm a";
  self.previewClockLabel.stringValue = [df stringFromDate:[NSDate date]];
  CGFloat clockW = 100;
  self.previewClockLabel.frame = NSMakeRect(frame.origin.x + frame.size.width - clockW - 10, iconY, clockW, 18);
}

- (void)applySettings:(id)sender {
  ConfigurationManager *config = [ConfigurationManager sharedManager];

  NSString *hexColor = [self hexStringFromColor:self.barColorWell.color];
  NSString *menuIcon = self.menuIconField.stringValue ?: @"";
  NSString *menuFontStyle = self.menuFontStylePopup.selectedItem.title;
  NSString *menuHeaderFontStyle = self.menuHeaderFontStylePopup.selectedItem.title;

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

  [config performBatchUpdates:^{
    [config setValue:@((int)self.heightSlider.doubleValue) forKeyPath:@"appearance.bar_height"];
    [config setValue:@((int)self.cornerSlider.doubleValue) forKeyPath:@"appearance.corner_radius"];
    [config setValue:@((int)self.blurSlider.doubleValue) forKeyPath:@"appearance.blur_radius"];
    [config setValue:@(self.scaleSlider.doubleValue) forKeyPath:@"appearance.widget_scale"];
    [config setValue:@((int)self.widgetCornerSlider.doubleValue) forKeyPath:@"appearance.widget_corner_radius"];
    [config setValue:hexColor forKeyPath:@"appearance.bar_color"];
    [config setValue:menuIcon forKeyPath:@"icons.apple"];

    NSString *iconFont = self.fontIconPopup.selectedItem.title;
    if (![iconFont isEqualToString:@"(System Default)"]) {
      [config setValue:iconFont forKeyPath:@"appearance.font_icon"];
    }
    NSString *textFont = self.fontTextPopup.selectedItem.title;
    if (![textFont isEqualToString:@"(System Default)"]) {
      [config setValue:textFont forKeyPath:@"appearance.font_text"];
    }
    NSString *numbersFont = self.fontNumbersPopup.selectedItem.title;
    if (![numbersFont isEqualToString:@"(System Default)"]) {
      [config setValue:numbersFont forKeyPath:@"appearance.font_numbers"];
    }
    [config setValue:menuFontStyle forKeyPath:@"appearance.menu_font_style"];
    [config setValue:menuHeaderFontStyle forKeyPath:@"appearance.menu_header_font_style"];
    [config setValue:self.clockFontStylePopup.selectedItem.title forKeyPath:@"appearance.clock_font_style"];

    [config setValue:@((int)self.menuFontOffsetSlider.doubleValue) forKeyPath:@"appearance.menu_font_size_offset"];
    [config setValue:@((int)self.menuRowHeightSlider.doubleValue) forKeyPath:@"appearance.menu_item_height"];
    [config setValue:@((int)self.menuPaddingSlider.doubleValue) forKeyPath:@"appearance.menu_padding"];
    [config setValue:@(self.submenuDelaySlider.doubleValue) forKeyPath:@"appearance.submenu_close_delay"];
    [config setValue:[self hexStringFromColor:menuPopupUpdated] forKeyPath:@"appearance.menu_popup_bg_color"];
    [config setValue:[self hexStringFromColor:menuBorderUpdated] forKeyPath:@"appearance.popup_border_color"];

    // Bar Geometry
    [config setValue:@((int)self.barPaddingLeftSlider.doubleValue) forKeyPath:@"appearance.bar_padding_left"];
    [config setValue:@((int)self.barPaddingRightSlider.doubleValue) forKeyPath:@"appearance.bar_padding_right"];
    [config setValue:@((int)self.barMarginSlider.doubleValue) forKeyPath:@"appearance.bar_margin"];
    [config setValue:@((int)self.barYOffsetSlider.doubleValue) forKeyPath:@"appearance.bar_y_offset"];

    // Bar Border
    [config setValue:@((int)self.barBorderWidthSlider.doubleValue) forKeyPath:@"appearance.bar_border_width"];
    [config setValue:[self hexStringFromColor:self.barBorderColorWell.color] forKeyPath:@"appearance.bar_border_color"];

    // Popup Geometry
    [config setValue:@((int)self.popupCornerRadiusSlider.doubleValue) forKeyPath:@"appearance.popup_corner_radius"];
    [config setValue:@((int)self.popupBorderWidthSlider.doubleValue) forKeyPath:@"appearance.popup_border_width"];
    [config setValue:@((int)self.popupItemCornerRadiusSlider.doubleValue) forKeyPath:@"appearance.popup_item_corner_radius"];

    // Hover & Animation
    [config setValue:[self hexStringFromColor:self.hoverColorWell.color] forKeyPath:@"appearance.hover_color"];
    [config setValue:[self hexStringFromColor:self.hoverBorderColorWell.color] forKeyPath:@"appearance.hover_border_color"];
    [config setValue:@((int)self.hoverBorderWidthSlider.doubleValue) forKeyPath:@"appearance.hover_border_width"];
    [config setValue:self.hoverAnimCurvePopup.selectedItem.title forKeyPath:@"appearance.hover_animation_curve"];
    [config setValue:@((int)self.hoverAnimDurationSlider.doubleValue) forKeyPath:@"appearance.hover_animation_duration"];

    // Group Styling
    [config setValue:[self hexStringFromColor:self.groupBgColorWell.color] forKeyPath:@"appearance.group_bg_color"];
    [config setValue:[self hexStringFromColor:self.groupBorderColorWell.color] forKeyPath:@"appearance.group_border_color"];
    [config setValue:@((int)self.groupBorderWidthSlider.doubleValue) forKeyPath:@"appearance.group_border_width"];
    [config setValue:@((int)self.groupCornerRadiusSlider.doubleValue) forKeyPath:@"appearance.group_corner_radius"];
  }];

  [config reloadSketchyBar];

  // Visual feedback
  self.applyButton.title = @"Applied Appearance";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.applyButton.title = @"Apply Appearance Changes";
  });
}

- (void)updateWidgetCornerLabel {
  if (!self.widgetCornerValueLabel) return;
  [self.widgetCornerValueLabel setStringValue:[NSString stringWithFormat:@"%0.0f", self.widgetCornerSlider.doubleValue]];
}

// ── Bar Geometry update labels ───────────────────────────────────────

- (void)updateBarPaddingLeftLabel {
  self.barPaddingLeftValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.barPaddingLeftSlider.doubleValue];
}

- (void)updateBarPaddingRightLabel {
  self.barPaddingRightValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.barPaddingRightSlider.doubleValue];
}

- (void)updateBarMarginLabel {
  self.barMarginValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.barMarginSlider.doubleValue];
}

- (void)updateBarYOffsetLabel {
  self.barYOffsetValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.barYOffsetSlider.doubleValue];
}

// ── Bar Border update label ──────────────────────────────────────────

- (void)updateBarBorderWidthLabel {
  self.barBorderWidthValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.barBorderWidthSlider.doubleValue];
}

// ── Popup Geometry update labels ─────────────────────────────────────

- (void)updatePopupCornerRadiusLabel {
  self.popupCornerRadiusValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.popupCornerRadiusSlider.doubleValue];
}

- (void)updatePopupBorderWidthLabel {
  self.popupBorderWidthValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.popupBorderWidthSlider.doubleValue];
}

- (void)updatePopupItemCornerRadiusLabel {
  self.popupItemCornerRadiusValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.popupItemCornerRadiusSlider.doubleValue];
}

// ── Hover & Animation update labels ──────────────────────────────────

- (void)updateHoverBorderWidthLabel {
  self.hoverBorderWidthValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.hoverBorderWidthSlider.doubleValue];
}

- (void)updateHoverAnimDurationLabel {
  self.hoverAnimDurationValueLabel.stringValue = [NSString stringWithFormat:@"%d", (int)self.hoverAnimDurationSlider.doubleValue];
}

// ── Group Styling update labels ──────────────────────────────────────

- (void)updateGroupBorderWidthLabel {
  self.groupBorderWidthValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.groupBorderWidthSlider.doubleValue];
}

- (void)updateGroupCornerRadiusLabel {
  self.groupCornerRadiusValueLabel.stringValue = [NSString stringWithFormat:@"%d px", (int)self.groupCornerRadiusSlider.doubleValue];
}

// ── Color control helper ─────────────────────────────────────────────

- (NSView *)colorControlWithWell:(NSColorWell **)outWell
                        hexField:(NSTextField **)outHex
                    initialColor:(NSString *)hexString {
  NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 54, 28)];
  well.target = self;
  well.action = @selector(colorChanged:);
  NSColor *color = [self colorFromHexString:hexString];
  if (color) well.color = color;

  NSTextField *hex = [[NSTextField alloc] initWithFrame:NSZeroRect];
  hex.placeholderString = @"0xAARRGGBB";
  hex.delegate = self;
  hex.stringValue = [hexString isKindOfClass:[NSString class]] ? hexString : (hexString ? [NSString stringWithFormat:@"%@", hexString] : @"");
  [hex.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
  [hex.widthAnchor constraintLessThanOrEqualToConstant:180].active = YES;

  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
  stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  stack.spacing = 12;
  [stack addView:well inGravity:NSStackViewGravityLeading];
  [stack addView:hex inGravity:NSStackViewGravityLeading];

  if (outWell) *outWell = well;
  if (outHex) *outHex = hex;
  return stack;
}

@end
