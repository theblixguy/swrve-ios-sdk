#import <Foundation/Foundation.h>
#import "Swrve.h"

@interface SwrveFileManagement : NSObject

+ (NSString *) applicationSupportPath;
+ (NSError*) createApplicationSupportPath;

@end
