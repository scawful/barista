#import "BaristaPanelWindow.h"

@implementation BaristaPanelWindow

- (instancetype)initWithContentRect:(NSRect)contentRect {
  self = [super initWithContentRect:contentRect
                          styleMask:(NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable)
                            backing:NSBackingStoreBuffered
                              defer:NO];
  if (self) {
    self.floatingPanel = NO;
    self.hidesOnDeactivate = NO;
    self.releasedWhenClosed = NO;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.animationBehavior = NSWindowAnimationBehaviorDocumentWindow;
  }
  return self;
}

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (BOOL)canBecomeMainWindow {
  return YES;
}

@end
