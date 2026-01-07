#import "BaristaPanelView.h"
#import "BaristaStyle.h"

@implementation BaristaPanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _drawsGrid = YES;
    self.wantsLayer = YES;
  }
  return self;
}

- (BOOL)isOpaque {
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  BaristaStyle *style = [BaristaStyle sharedStyle];
  NSColor *background = style.panelColor ?: [NSColor blackColor];
  [background setFill];
  NSRectFill(dirtyRect);

  if (!self.drawsGrid) {
    return;
  }

  NSColor *grid = style.gridColor ?: [[NSColor whiteColor] colorWithAlphaComponent:0.04];
  [grid setStroke];

  NSBezierPath *gridPath = [NSBezierPath bezierPath];
  gridPath.lineWidth = 1.0;
  CGFloat spacing = 16.0;
  NSRect bounds = self.bounds;

  for (CGFloat x = 0.0; x <= NSMaxX(bounds); x += spacing) {
    [gridPath moveToPoint:NSMakePoint(x, 0.0)];
    [gridPath lineToPoint:NSMakePoint(x, NSMaxY(bounds))];
  }

  for (CGFloat y = 0.0; y <= NSMaxY(bounds); y += spacing) {
    [gridPath moveToPoint:NSMakePoint(0.0, y)];
    [gridPath lineToPoint:NSMakePoint(NSMaxX(bounds), y)];
  }
  [gridPath stroke];

  NSColor *edge = [style.accentColor colorWithAlphaComponent:0.4] ?: grid;
  [edge setFill];
  NSRect edgeRect = NSMakeRect(0.0, NSMaxY(bounds) - 1.0, bounds.size.width, 1.0);
  NSRectFill(edgeRect);
}

@end
