#import <Cocoa/Cocoa.h>

@interface BaristaPanelState : NSObject
+ (instancetype)sharedState;
- (NSString *)lastSelectedTabIdentifier;
- (void)setLastSelectedTabIdentifier:(NSString *)identifier;
- (NSString *)windowAutosaveName;
- (NSString *)windowMode;
- (void)setWindowMode:(NSString *)windowMode;
- (BOOL)prefersUtilityWindowMode;
@end
