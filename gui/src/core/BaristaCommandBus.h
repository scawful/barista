#import <Cocoa/Cocoa.h>

@interface BaristaCommandBus : NSObject
+ (instancetype)sharedBus;
- (void)reloadSketchyBar;
- (void)runScriptNamed:(NSString *)scriptName arguments:(NSArray<NSString *> *)arguments;
- (BOOL)openControlPanelForTab:(NSString *)tabIdentifier error:(NSError **)error;
- (BOOL)openOracleAgentManagerWithError:(NSError **)error;
@end
