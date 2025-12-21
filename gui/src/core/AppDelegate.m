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
  // Set activation policy to regular app (shows in dock, stays open)
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  self.windowController = [[MainWindowController alloc] init];
  NSLog(@"[barista] windowController=%@", self.windowController);
  [self activateControlPanel];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [self activateControlPanel];
                 });
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  [self activateControlPanel];
  return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES; // Quit app when window is closed
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  [self activateControlPanel];
}

- (void)activateControlPanel {
  if (!self.windowController) { return; }
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateIgnoringOtherApps |
                                                                  NSApplicationActivateAllWindows)];
  [self.windowController showWindow:nil];
  NSWindow *window = self.windowController.window;
  if (!window) { return; }
  NSLog(@"[barista] window visible=%d frame=%@", window.isVisible, NSStringFromRect(window.frame));
  if (window.isMiniaturized) {
    [window deminiaturize:nil];
  }
  [window makeKeyAndOrderFront:nil];
  [window orderFrontRegardless];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  // Cleanup if needed
}

@end
