#import <Cocoa/Cocoa.h>

@interface ConfigurationManager : NSObject
@property (copy, nonatomic) NSString *statePath;
@property (copy, nonatomic) NSString *configPath;
@property (copy, nonatomic) NSString *scriptsPath;
@property (copy, nonatomic) NSString *codePath;
@property (strong, nonatomic) NSMutableDictionary *state;

+ (instancetype)sharedManager;
- (BOOL)loadState;
- (BOOL)saveState;
- (void)performBatchUpdates:(dispatch_block_t)updates;
- (id)valueForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath;
- (void)removeValueForKeyPath:(NSString *)keyPath;
- (void)refreshPaths;
- (NSString *)resolveSketchyBarBinary;
- (void)reloadSketchyBar;
- (void)runScript:(NSString *)scriptName arguments:(NSArray *)args;
@end
