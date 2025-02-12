#import "SwrveUtils.h"
#import "SwrveCommon.h"
#import "SwrveNotificationConstants.h"
#import <CommonCrypto/CommonHMAC.h>

#define Swrve_UIColorFromRGB(rgbValue, alphaValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0f green:((float)((rgbValue & 0xFF00) >> 8))/255.0f blue:((float)(rgbValue & 0xFF))/255.0f alpha:alphaValue]

@implementation SwrveUtils

+ (CGRect)deviceScreenBounds {
    UIScreen *screen   = [UIScreen mainScreen];
    CGRect bounds = [screen bounds];
    float screen_scale = (float)[[UIScreen mainScreen] scale];
    bounds.size.width  = bounds.size.width  * screen_scale;
    bounds.size.height = bounds.size.height * screen_scale;
    const int side_a = (int)bounds.size.width;
    const int side_b = (int)bounds.size.height;
    bounds.size.width  = (side_a > side_b)? side_b : side_a;
    bounds.size.height = (side_a > side_b)? side_a : side_b;
    return bounds;
}

+ (float)estimate_dpi {
    float scale = (float)[[UIScreen mainScreen] scale];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return 132.0f * scale;
    }
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return 163.0f * scale;
    }
    return 160.0f * scale;
}

+ (NSString *)hardwareMachineName {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = (char*)malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);
    return platform;
}

+ (NSDictionary *)parseURLQueryParams:(NSString *)queryString API_AVAILABLE(ios(12.0)) {
    NSMutableDictionary *queryParams = [NSMutableDictionary new];
    NSArray *queryElements = [queryString componentsSeparatedByString:@"&"];
    for (NSString *element in queryElements) {
        NSArray *keyVal = [element componentsSeparatedByString:@"="];
        if (keyVal.count > 0) {
            NSString *paramKey = [keyVal objectAtIndex:0];
            NSString *paramValue = (keyVal.count == 2) ? [[keyVal lastObject] stringByRemovingPercentEncoding] : nil;
            if (paramValue != nil) {
                [queryParams setObject:paramValue forKey:paramKey];
            }
        }
    }
    return queryParams;
}

+ (NSString *)getStringFromDic:(NSDictionary *)dic withKey:(NSString *)key {
    id value = [dic objectForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    } else {
        // return nil regarding couldn't find a valid string from this key.
        return nil;
    }
}

+ (UInt64)getTimeEpoch {
    struct timeval time;
    gettimeofday(&time, NULL);
    return (((UInt64) time.tv_sec) * 1000) + (((UInt64) time.tv_usec) / 1000);
}

+ (BOOL)supportsConversations {
#if TARGET_OS_IOS /** conversations are only supported in iOS **/
    return YES;
#endif
    return NO;
}


+ (NSString *)platformDeviceType {
#if TARGET_OS_TV
    return @"tv";
#elif TARGET_OS_OSX
    return @"desktop";
#endif
    return @"mobile";
}

+ (BOOL)isValidIDFA:(NSString *)idfa {
    NSString *noDashes = [idfa stringByReplacingOccurrencesOfString: @"-" withString:@""];
    NSString *idfaNoZerosOrDashes = [noDashes stringByReplacingOccurrencesOfString: @"0" withString:@""];
    return (idfaNoZerosOrDashes != nil && idfaNoZerosOrDashes.length != 0);
}

+ (NSString *)sha1:(NSData *)messageData {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    // SHA-1 hash has been calculated and stored in 'digest'
    unsigned int length = (unsigned int) [messageData length];
    NSMutableString* result = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    if (CC_SHA1([messageData bytes], length, digest)) {
        for (unsigned int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
            [result appendFormat:@"%02x", digest[i]];
        }
    }
    
    return result;
}

+ (NSDictionary *)combineDictionary:(NSDictionary*)rootDictionary withDictionary:(NSDictionary *)overiddingDictionary {
    NSMutableDictionary *combinedDictionary = nil;
    if (rootDictionary != nil) {
        NSArray *overiddingkeys = [overiddingDictionary allKeys];
        combinedDictionary = [rootDictionary mutableCopy];
        for (NSString *key in overiddingkeys) {
            NSString *value = [overiddingDictionary objectForKey:key];
            [combinedDictionary setValue:value forKey:key];
        }
    } else {
        combinedDictionary = [overiddingDictionary mutableCopy];
    }
    
    return combinedDictionary;
}

+ (BOOL)isDifferentUserForAuthenticatedPush:(NSDictionary *)authenticatedPushUserInfo userId:(NSString *)userId {
    BOOL isDifferentUser = NO;
    if ([SwrveUtils isAuthenticatedPush:authenticatedPushUserInfo]) {
        NSString *targetedUserId = authenticatedPushUserInfo[SwrveNotificationAuthenticatedUserKey];
        if (![targetedUserId isEqualToString:userId]) {
            [SwrveLogger warning:@"Swrve received authenticated push targeted for different user.", nil];
            isDifferentUser = YES;
        }
    }
    return isDifferentUser;
}

+ (BOOL)isAuthenticatedPush:(NSDictionary *)userInfo {
    BOOL isAuthenticatedPush = NO;
    NSString *authenticatedPush = userInfo[SwrveNotificationAuthenticatedUserKey];
    if (authenticatedPush && ![authenticatedPush isKindOfClass:[NSNull class]]) {
        isAuthenticatedPush = YES;
    }
    return isAuthenticatedPush;
}

+ (UIBackgroundTaskIdentifier)startBackgroundTaskCommon:(UIBackgroundTaskIdentifier)bgTask withName:(NSString *)name NS_EXTENSION_UNAVAILABLE_IOS("") {
    __block UIBackgroundTaskIdentifier taskID = UIBackgroundTaskInvalid;
    UIApplication *app = [SwrveCommon sharedUIApplication];
    if (app == nil) {
        return taskID;
    } else {
        taskID = [[SwrveCommon sharedUIApplication] beginBackgroundTaskWithName:name expirationHandler:^{
            [SwrveUtils stopBackgroundTaskCommon:taskID withName:name];
        }];
        [SwrveLogger debug:@"Start taskID: %lu name: %@", (unsigned long)taskID, name];
        return taskID;
    }
}

+ (void)stopBackgroundTaskCommon:(UIBackgroundTaskIdentifier)bgTask withName:(NSString *)name NS_EXTENSION_UNAVAILABLE_IOS("") {
    UIApplication *app = [SwrveCommon sharedUIApplication];
    if (bgTask != UIBackgroundTaskInvalid) {
        [SwrveLogger debug:@"Stop taskID: %lu name: %@", (unsigned long)bgTask, name];
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

+ (UIColor *)processHexColorValue:(NSString *)color {
    NSString *colorString = [[color stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    UIColor *returnColor = UIColor.clearColor;

    if ([colorString length] == 6) {
        unsigned int hexInt = 0;
        NSScanner *scanner = [NSScanner scannerWithString:colorString];
        [scanner scanHexInt:&hexInt];
        returnColor = Swrve_UIColorFromRGB(hexInt, 1.0f);

    } else if ([colorString length] == 8) {

        NSString *alphaSub = [colorString substringWithRange:NSMakeRange(0, 2)];
        NSString *colorSub = [colorString substringWithRange:NSMakeRange(2, 6)];

        unsigned hexComponent;
        unsigned int hexInt = 0;
        [[NSScanner scannerWithString:alphaSub] scanHexInt:&hexComponent];
        float alpha = hexComponent / 255.0f;

        NSScanner *scanner = [NSScanner scannerWithString:colorSub];
        [scanner scanHexInt:&hexInt];
        returnColor = Swrve_UIColorFromRGB(hexInt, alpha);
    }

    return returnColor;
}

+ (nullable NSMutableDictionary *)pushTrackingPayload:(NSDictionary *)userInfo {
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] init];
    NSString *trackingData = [userInfo objectForKey:SwrveNotificationTrackingDataKey];
    if (trackingData) {
        [payload setObject:trackingData forKey:@"trackingData"];
    }
    NSString *platform = [userInfo objectForKey:SwrveNotificationPlatformKey];
    if (platform) {
        [payload setObject:platform forKey:@"platform"];
    }
    return ([payload count] > 0) ? payload : nil;
}

@end
