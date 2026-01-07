#import <Cocoa/Cocoa.h>

@class AppearanceTabViewController;
@class WidgetsTabViewController;
@class SpacesTabViewController;
@class IconsTabViewController;
@class MenuTabViewController;
@class IntegrationsTabViewController;
@class ThemesTabViewController;
@class ShortcutsTabViewController;
@class LaunchAgentsTabViewController;
@class DebugTabViewController;
@class PerformanceTabViewController;
@class AdvancedTabViewController;

@interface MainWindowController : NSWindowController <NSWindowDelegate, NSTabViewDelegate>
@property (strong) NSTabView *tabView;
@property (strong) AppearanceTabViewController *appearanceTab;
@property (strong) WidgetsTabViewController *widgetsTab;
@property (strong) SpacesTabViewController *spacesTab;
@property (strong) IconsTabViewController *iconsTab;
@property (strong) MenuTabViewController *menuTab;
@property (strong) IntegrationsTabViewController *integrationsTab;
@property (strong) ThemesTabViewController *themesTab;
@property (strong) ShortcutsTabViewController *shortcutsTab;
@property (strong) LaunchAgentsTabViewController *launchAgentsTab;
@property (strong) DebugTabViewController *debugTab;
@property (strong) PerformanceTabViewController *performanceTab;
@property (strong) AdvancedTabViewController *advancedTab;
@end
