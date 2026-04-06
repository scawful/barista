#import "BaristaTabBaseViewController.h"

@interface SpacesTabViewController : BaristaTabBaseViewController
@property (strong) NSPopUpButton *spaceSelector;
@property (strong) NSTextField *iconField;
@property (strong) NSTextField *iconPreview;
@property (strong) NSSegmentedControl *modeSelector;
@property (strong) NSButton *applyButton;
@property (assign) NSInteger currentSpace;
@end

