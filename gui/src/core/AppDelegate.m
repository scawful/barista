#import "MainWindowController.h"
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) MainWindowController *windowController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  // Set activation policy to regular app (shows in dock, stays open)
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.windowController = [[MainWindowController alloc] init];
  [self.windowController showWindow:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES; // Quit app when window is closed
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  // Cleanup if needed
}

@end

