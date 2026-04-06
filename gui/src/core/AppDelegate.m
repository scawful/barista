#import "MainWindowController.h"
#import <Cocoa/Cocoa.h>

static void BaristaSetupLogging(void) {
  NSString *logPath = @"/tmp/barista_control_panel.log";
  const char *path = [logPath fileSystemRepresentation];
  FILE *stdoutFile = freopen(path, "a", stdout);
  FILE *stderrFile = freopen(path, "a", stderr);
  if (stdoutFile) { setvbuf(stdout, NULL, _IONBF, 0); }
  if (stderrFile) { setvbuf(stderr, NULL, _IONBF, 0); }
  NSLog(@"[barista] Control panel launching");
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) MainWindowController *windowController;
- (void)activateControlPanel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  BaristaSetupLogging();
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.windowController = [[MainWindowController alloc] init];
  NSLog(@"[barista] windowController=%@", self.windowController);
  [self activateControlPanel];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  [self activateControlPanel];
  return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES; // Quit app when window is closed
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  if (!self.windowController.window.isVisible) {
    [self activateControlPanel];
  }
}

- (void)activateControlPanel {
  if (!self.windowController) { return; }
  [NSApp activateIgnoringOtherApps:YES];
  [self.windowController showWindow:nil];
  NSWindow *window = self.windowController.window;
  if (!window) { return; }
  NSLog(@"[barista] window visible=%d frame=%@", window.isVisible, NSStringFromRect(window.frame));
  if (window.isMiniaturized) {
    [window deminiaturize:nil];
  }
  [window makeKeyAndOrderFront:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  // Cleanup if needed
}

@end
