#import "BaristaPanelView.h"
#import "BaristaStyle.h"

@implementation BaristaPanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _drawsGrid = NO;
    self.wantsLayer = YES;
  }
  return self;
}

- (BOOL)isOpaque {
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  NSColor *background = [[BaristaStyle sharedStyle] backgroundColor] ?: [NSColor windowBackgroundColor];
  [background setFill];
  NSRectFill(dirtyRect);
}

@end
