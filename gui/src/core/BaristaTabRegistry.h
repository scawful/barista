#import <Cocoa/Cocoa.h>

@interface BaristaTabRegistry : NSObject
+ (NSArray<NSDictionary *> *)defaultTabDescriptors;
+ (NSDictionary *)descriptorForIdentifier:(NSString *)identifier;
@end
