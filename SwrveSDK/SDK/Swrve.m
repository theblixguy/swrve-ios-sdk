#if !__has_feature(objc_arc)
    #error Please enable ARC for this project (Project Settings > Build Settings), or add the -fobjc-arc compiler flag to each of the files in the Swrve SDK (Project Settings > Build Phases > Compile Sources)
#endif

#if defined(SWRVE_NO_ADDRESS_BOOK) || defined(SWRVE_NO_LOCATION) || defined(SWRVE_NO_PHOTO_LIBRARY) || defined(SWRVE_NO_PHOTO_CAMERA)
    #error These flags have been inverted as of SDK 5.0. The permissions are disabled by default and only enabled with SWRVE_X permission flags. Check docs.swrve.com for more information.
#endif

#import <sys/time.h>
#import "Swrve.h"
#import "SwrveCampaign.h"
#if __has_include(<SwrveSDKCommon/SwrveRESTClient.h>)
#import <SwrveSDKCommon/SwrveRESTClient.h>
#import <SwrveSDKCommon/SwrveQA.h>
#import <SwrveSDKCommon/SwrveUser.h>
#import <SwrveSDKCommon/SwrveNotificationManager.h>
#import <SwrveSDKCommon/SwrvePermissions.h>
#else
#import "SwrveQA.h"
#import "SwrveRESTClient.h"
#import "SwrveUser.h"
#import "SwrveNotificationManager.h"
#import "SwrvePermissions.h"
#endif
#import "SwrveMigrationsManager.h"
#import "SwrveMessageController+Private.h"
#import "SwrveDeviceProperties.h"
#import "SwrveEventsManager.h"

#if __has_include(<SwrveConversationSDK/SwrveConversationEvents.h>)
#import <SwrveConversationSDK/SwrveConversationEvents.h>
#else
#import "SwrveConversationEvents.h"
#endif

#import "SwrveProfileManager.h"
#import "SwrveEventQueueItem.h"

#if SWRVE_TEST_BUILD
#define SWRVE_STATIC_UNLESS_TEST_BUILD
#else
#define SWRVE_STATIC_UNLESS_TEST_BUILD static
#endif

#define NullableNSString(x) ((x == nil)? [NSNull null] : x)
#define KB(x) (1024*(x))
#define MB(x) (1024*KB((x)))

@interface SwrveSendContext : NSObject
@property(atomic, weak) Swrve *swrveReference;
@property(atomic) long swrveInstanceID;
@property(atomic, retain) NSArray *buffer;
@property(atomic) int bufferLength;
@end

@implementation SwrveSendContext
@synthesize swrveReference;
@synthesize swrveInstanceID;
@synthesize buffer;
@synthesize bufferLength;
@end

@interface SwrveSendEventfileContext : NSObject
@property(atomic, weak) Swrve *swrveReference;
@property(atomic) long swrveInstanceID;
@end

@implementation SwrveSendEventfileContext
@synthesize swrveReference;
@synthesize swrveInstanceID;
@end

enum
{
    SWRVE_TRUNCATE_FILE,
    SWRVE_APPEND_TO_FILE,
    SWRVE_TRUNCATE_IF_TOO_LARGE,
};

@interface SwrveInstanceIDRecorder : NSObject
{
    NSMutableSet *swrveInstanceIDs;
    long nextInstanceID;
}

+ (SwrveInstanceIDRecorder *)sharedInstance;

- (BOOL)hasSwrveInstanceID:(long)instanceID;
- (long)addSwrveInstanceID;
- (void)removeSwrveInstanceID:(long)instanceID;

@end

@interface SwrveResourceManager ()

- (void)setResourcesFromArray:(NSArray *)json;
- (void)setABTestDetailsFromDictionary:(NSDictionary *)json;

@end


@interface SwrveProfileManager ()

- (void)switchUser:(NSString*)userId;
- (void)updateSwrveUserWithId:(NSString *)swrveUserId externalUserId:(NSString *)externalUserId;
- (void)saveSwrveUser:(SwrveUser *)swrveUser;
- (NSArray *)swrveUsers;
- (instancetype)initWithIdentityUrl:(NSString *)identityBaseUrl deviceUUID:(NSString *)deviceUUID restClient:(SwrveRESTClient *)restClient appId:(long)_appId apiKey:(NSString*)_apiKey;
- (void)identify:(NSString *)externalUserId onSuccess:(void (^)(NSString *status, NSString *swrveUserId))onSuccess
         onError:(void (^)(NSInteger httpCode, NSString *errorMessage))onError;
- (void)identify:(NSString *)externalUserId swrveUserId:(NSString *)swrveUserId
       onSuccess:(void (^)(NSString *status, NSString *swrveUserId))onSuccess
         onError:(void (^)(NSInteger httpCode, NSString *errorMessage))onError;
- (SwrveUser *)swrveUserWithId:(NSString *)aUserId;
- (void)removeSwrveUserWithId:(NSString *)aUserId;
@end

@interface SwrveUser ()
- (instancetype)initWithExternalId:(NSString *)externalId swrveId:(NSString *)swrveId verified:(BOOL)verified;

@property(nonatomic, strong) NSString *swrveId;
@property(nonatomic, strong) NSString *externalId;
@property(nonatomic) BOOL verified;

@end

@interface SwrveMessageController ()

@property(nonatomic, retain) NSArray *campaigns;
@property(nonatomic) bool autoShowMessagesEnabled;

- (void)updateCampaigns:(NSDictionary *)campaignJson;
- (NSString *)campaignQueryString;
- (void)writeToCampaignCache:(NSData *)campaignData;
- (void)autoShowMessages;

@end

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
@interface SwrvePush (SwrvePushInternalAccess)

+ (SwrvePush *)sharedInstanceWithPushDelegate:(id <SwrvePushDelegate>)pushDelegate andCommonDelegate:(id <SwrveCommonDelegate>)commonDelegate;
+ (void)resetSharedInstance;
- (void)setResponseDelegate:(id <SwrvePushResponseDelegate>)responseDelegate;
- (BOOL)observeSwizzling;
- (void)deswizzlePushMethods;
- (void)setPushNotificationsDeviceToken:(NSData *)newDeviceToken;
- (BOOL)didReceiveRemoteNotification:(NSDictionary *)userInfo withBackgroundCompletionHandler:(void (^)(UIBackgroundFetchResult, NSDictionary *))completionHandler API_AVAILABLE(ios(7.0));
- (void)processInfluenceData;
- (void)saveConfigForPushDelivery;

@end
#endif //!defined(SWRVE_NO_PUSH)

@interface Swrve () <SwrveCommonDelegate> {
    BOOL initialised;
    BOOL sdkStarted;
    BOOL lifecycleCallbacksRegistered;
    SwrveEventsManager *eventsManager;
    UInt64 appInstallTimeSeconds;
    UInt64 userJoinedTimeSeconds;
    NSDate *lastSessionDate;
    SwrveEventQueuedCallback event_queued_callback;
    long instanceID; // The unique id associated with this instance of Swrve
    enum SwrveTrackingState trackingState;
    id <SwrveSessionDelegate> sessionDelegate;
}

@property(atomic) SwrveDeeplinkManager *swrveDeeplinkManager;
@property(nonatomic) SwrveReceiptProvider *receiptProvider;

- (int)eventInternal:(NSString *)eventName payload:(NSDictionary *)eventPayload triggerCallback:(bool)triggerCallback;
- (void)setupConfig:(SwrveConfig *)config;
- (void)maybeFlushToDisk;
- (int)queueEvent:(NSString *)eventType data:(NSMutableDictionary *)eventData triggerCallback:(bool)triggerCallback;
- (void)appDidBecomeActive:(NSNotification *)notification;
- (void)appWillResignActive:(NSNotification *)notification;
- (void)appWillTerminate:(NSNotification *)notification;
- (void)queueUserUpdates;
- (NSString *)createJSON:(NSString *)sessionToken events:(NSString *)rawEvents;
- (NSString *)copyBufferToJson:(NSArray *)buffer;
- (void)sendCrashlyticsMetadata;
- (BOOL)isValidJson:(NSData *)json;
- (void)initResources;
- (void)sendEventfile;
- (NSOutputStream *)createEventfile:(int)mode;
- (void)initBuffer;
- (void)checkForCampaignAndResourcesUpdates:(NSTimer *)timer;

@property(atomic) BOOL initialised;
@property(atomic) BOOL sdkStarted;

@property(atomic) SwrveProfileManager *profileManager;

// Used to store the merged user updates
@property(atomic, strong) NSMutableDictionary *userUpdates;

// Used to store the merged device info
@property(atomic, strong) NSMutableDictionary *deviceInfoDic;

// Device UUID, used for tracking event streams from different devices
@property(atomic) NSString *deviceUUID;

// HTTP Request metrics that haven't been sent yet
@property(atomic) NSMutableArray *httpPerformanceMetrics;

// Flush values and timer for campaigns and resources update request
@property(atomic) double campaignsAndResourcesFlushFrequency;
@property(atomic) double campaignsAndResourcesFlushRefreshDelay;
@property(atomic) NSTimer *campaignsAndResourcesTimer;
@property(atomic) int campaignsAndResourcesTimerSeconds;
@property(atomic) NSDate *campaignsAndResourcesLastRefreshed;
@property(atomic) BOOL campaignsAndResourcesInitialized; // Set to true after first call to API returns

// Resource cache files
@property(atomic) SwrveSignatureProtectedFile *resourcesFile;
@property(atomic) SwrveSignatureProtectedFile *resourcesDiffFile;

// Real Time User Properties cache file
@property(atomic) SwrveSignatureProtectedFile *realTimeUserPropertiesFile;

// Store current real time user properties
@property(atomic, strong) NSMutableDictionary *realTimeUserProperties;

// An in-memory buffer of messages that are ready to be sent to the Swrve
// server the next time sendQueuedEvents is called.
@property(atomic) NSMutableArray *eventBuffer;
// Count the number of UTF-16 code points stored in buffer
@property(atomic) int eventBufferBytes;

@property(atomic) NSOutputStream *eventStream;
@property(atomic) NSURL *eventFilename;

// keep track of whether any events were sent so we know whether to check for resources / campaign updates
@property(atomic) bool eventsWereSent;

// URLs
@property(atomic) NSURL *batchURL;
@property(atomic) NSURL *baseCampaignsAndResourcesURL;

@property(atomic) int locationSegmentVersion;

@property(atomic) SwrveRESTClient *restClient;

@property(atomic) NSMutableArray *pausedEventsArray;

// Push
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
@property(atomic, readonly) SwrvePush *push;                         /*!< Push Notification Handler Service */
#endif //!defined(SWRVE_NO_PUSH)

@end

// Manages unique ids for each instance of Swrve
// This allows low-level c callbacks to know if it is safe to execute their callback functions.
// It is not safe to execute a callback function after a Swrve instance has been deallocated or shutdown.
@implementation SwrveInstanceIDRecorder

+ (SwrveInstanceIDRecorder *)sharedInstance {
    static dispatch_once_t pred;
    static SwrveInstanceIDRecorder *shared = nil;
    dispatch_once(&pred, ^{
        shared = [SwrveInstanceIDRecorder alloc];
    });
    return shared;
}

- (id)init {
    if (self = [super init]) {
        nextInstanceID = 1;
    }
    return self;
}

- (BOOL)hasSwrveInstanceID:(long)instanceID {
    @synchronized (self) {
        if (!swrveInstanceIDs) {
            return NO;
        }
        return [swrveInstanceIDs containsObject:[NSNumber numberWithLong:instanceID]];
    }
}

- (long)addSwrveInstanceID {
    @synchronized (self) {
        if (!swrveInstanceIDs) {
            swrveInstanceIDs = [[NSMutableSet alloc] init];
        }
        long result = nextInstanceID++;
        [swrveInstanceIDs addObject:[NSNumber numberWithLong:result]];
        return result;
    }
}

- (void)removeSwrveInstanceID:(long)instanceID {
    @synchronized (self) {
        if (swrveInstanceIDs) {
            [swrveInstanceIDs removeObject:[NSNumber numberWithLong:instanceID]];
        }
    }
}

@end

@implementation Swrve

@synthesize eventsServer;
@synthesize contentServer;
@synthesize identityServer;
@synthesize joined;
@synthesize language;
@synthesize httpTimeout;
@synthesize config;
@synthesize appID;
@synthesize apiKey;
@synthesize messaging;
@synthesize resourceManager;
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
@synthesize push;
#endif
@synthesize initialised;
@synthesize sdkStarted;
@synthesize profileManager;
@synthesize userUpdates;
@synthesize deviceInfoDic;
@synthesize deviceToken = _deviceToken;
@synthesize deviceUUID;
@synthesize httpPerformanceMetrics;
@synthesize campaignsAndResourcesFlushFrequency;
@synthesize campaignsAndResourcesFlushRefreshDelay;
@synthesize campaignsAndResourcesTimer;
@synthesize campaignsAndResourcesTimerSeconds;
@synthesize campaignsAndResourcesLastRefreshed;
@synthesize campaignsAndResourcesInitialized;
@synthesize resourcesFile;
@synthesize resourcesDiffFile;
@synthesize realTimeUserPropertiesFile;
@synthesize realTimeUserProperties;
@synthesize eventBuffer;
@synthesize eventBufferBytes;
@synthesize eventStream;
@synthesize eventFilename;
@synthesize eventsWereSent;
@synthesize batchURL;
@synthesize baseCampaignsAndResourcesURL;
@synthesize locationSegmentVersion;
@synthesize restClient;
@synthesize pausedEventsArray;
@synthesize receiptProvider;
@synthesize swrveDeeplinkManager;

// Non shared instance initialization methods
- (id)initWithAppID:(int)swrveAppID apiKey:(NSString *)swrveAPIKey {
    SwrveConfig *newConfig = [[SwrveConfig alloc] init];
    return [self initWithAppID:swrveAppID apiKey:swrveAPIKey config:newConfig];
}

- (id)initWithAppID:(int)swrveAppID apiKey:(NSString *)swrveAPIKey config:(SwrveConfig *)swrveConfig {
    NSCAssert(self.config == nil, @"Do not initialize Swrve instance more than once!", nil);
    if (self = [super init]) {
        if (self.config) {
            DebugLog(@"Swrve may not be initialized more than once.", nil);
            return self;
        }

        // Do migrations first before anything else is done.
        SwrveMigrationsManager *migrationsManager = [[SwrveMigrationsManager alloc] initWithConfig:[[ImmutableSwrveConfig alloc] initWithMutableConfig:swrveConfig]];
        [migrationsManager checkMigrations];

        [SwrveCommon addSharedInstance:self];

        NSCAssert(swrveAppID > 0, @"Invalid app ID given (%d)", swrveAppID);
        appID = swrveAppID;

        NSCAssert(swrveAPIKey.length > 1, @"API Key is invalid (too short): %@", swrveAPIKey);
        apiKey = swrveAPIKey;

        NSCAssert(swrveConfig, @"Null config object given to Swrve", nil);
        [self setupConfig:swrveConfig];
        eventsServer = [swrveConfig eventsServer];
        contentServer = [swrveConfig contentServer];
        identityServer = [swrveConfig identityServer];
        config = [[ImmutableSwrveConfig alloc] initWithMutableConfig:swrveConfig];

        language = [config language];
        httpTimeout = [config httpTimeoutSeconds];

        eventsManager = [[SwrveEventsManager alloc] initWithDelegate:self];

        instanceID = [[SwrveInstanceIDRecorder sharedInstance] addSwrveInstanceID];
        [self sendCrashlyticsMetadata];
        [self setHttpPerformanceMetrics:[[NSMutableArray alloc] init]];
        locationSegmentVersion = 0; // init to zero
        [self initSwrveRestClient:config.httpTimeoutSeconds];
        [self initBuffer];
        [self setPausedEventsArray:[NSMutableArray array]];

        [SwrveLocalStorage resetDirectoryCreation];
        _deviceToken = [SwrveLocalStorage deviceToken];

        receiptProvider = [[SwrveReceiptProvider alloc] init];

        NSURL *base_events_url = [NSURL URLWithString:swrveConfig.eventsServer];
        [self setBatchURL:[NSURL URLWithString:@"1/batch" relativeToURL:base_events_url]];

        NSURL *base_content_url = [NSURL URLWithString:self.config.contentServer];
        [self setBaseCampaignsAndResourcesURL:[NSURL URLWithString:@"api/1/user_content" relativeToURL:base_content_url]];

        self.deviceUUID = [SwrveLocalStorage deviceUUID];
        if ((self.deviceUUID == nil) || [self.deviceUUID isEqualToString:@""]) {
            self.deviceUUID = [[NSUUID UUID] UUIDString];
            [SwrveLocalStorage saveDeviceUUID:self.deviceUUID];
        }

        self.profileManager = [[SwrveProfileManager alloc] initWithIdentityUrl:config.identityServer
                                                                    deviceUUID:self.deviceUUID
                                                                    restClient:self.restClient
                                                                         appId:self.appID
                                                                        apiKey:self.apiKey];

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
        if (swrveConfig.pushEnabled) {
            push = [SwrvePush sharedInstanceWithPushDelegate:self andCommonDelegate:self];

            if (@available(iOS 10.0, *)) {
                UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
                center.delegate = push;
            } else {
                DebugLog(@"UNUserNotificationCenter delegate not set, not supported (should not reach this code)");
            }

            if (swrveConfig.autoCollectDeviceToken) {
                [self.push observeSwizzling];
            }

            id <SwrvePushResponseDelegate> pushDelegate = swrveConfig.pushResponseDelegate;
            if (pushDelegate != nil) {
                [self.push setResponseDelegate:pushDelegate];
            }
        }
#else
        DebugLog(@"\nWARNING: \nWe have deprecated the SWRVE_NO_PUSH flag as of release 4.9.1. \nIf you still need to exclude Push, please contact CSM with regards to future releases.\n", nil);
#endif //!defined(SWRVE_NO_PUSH)

        self.campaignsAndResourcesFlushFrequency = [SwrveLocalStorage flushFrequency];
        if (self.campaignsAndResourcesFlushFrequency <= 0) {
            self.campaignsAndResourcesFlushFrequency = SWRVE_DEFAULT_CAMPAIGN_RESOURCES_FLUSH_FREQUENCY / 1000;
        }

        self.campaignsAndResourcesFlushRefreshDelay = [self flushRefreshDelay];

        [self initAppInstallTime];

        self.sdkStarted = [self shouldAutoStart];
        if (self.sdkStarted) {
            [profileManager persistUser];
            [self registerLifecycleCallbacks];
            [self initWithUserId:[profileManager userId]];
        }
    }

    return self;
}


- (void)initWithUserId:(NSString *)swrveUserId {

    trackingState = ON;

    NSCAssert(swrveUserId != nil, @"UserId cannot be nil. Something has gone wrong.", nil);
    NSCAssert([swrveUserId length] > 0, @"UserId cannot be blank.", nil);

    event_queued_callback = nil;

    [self initUserJoinedTimeAndIsNewUserForUser:swrveUserId];
    if (config.abTestDetailsEnabled) {
        [self initABTestDetails];
    }
    [self initResources];
    [self initResourcesDiff];
    [self initRealTimeUserProperties];

    NSString *eventCacheFile = [SwrveLocalStorage eventsFilePathForUserId:swrveUserId];
    [self setEventFilename:[NSURL fileURLWithPath:eventCacheFile]];
    [self setEventStream:[self createEventfile:SWRVE_TRUNCATE_IF_TOO_LARGE]];

    // Set up empty user attributes store
    self.userUpdates = [[NSMutableDictionary alloc] init];
    [self.userUpdates setValue:@"user" forKey:@"type"];
    [self.userUpdates setValue:[[NSMutableDictionary alloc] init] forKey:@"attributes"];

    // Set up empty user attributes store
    self.deviceInfoDic = [[NSMutableDictionary alloc] init];
    [self.deviceInfoDic setValue:@"device_update" forKey:@"type"];
    [self.deviceInfoDic setValue:[[NSMutableDictionary alloc] init] forKey:@"attributes"];

    [self setCampaignsAndResourcesInitialized:NO];

#if TARGET_OS_IOS /** exclude tvOS **/
    [SwrvePermissions compareStatusAndQueueEventsWithSDK:self];
#endif

    messaging = [[SwrveMessageController alloc] initWithSwrve:self];
}

- (void)initUserJoinedTimeAndIsNewUserForUser:(NSString *)userId {
    // save the first time a user gets initialised for signature key and setting isNewUser in profile manager
    UInt64 userJoinedTimeSecondsFromFile = [SwrveLocalStorage userJoinedTimeSeconds:userId];
    if (userJoinedTimeSecondsFromFile == 0) {
        [profileManager setIsNewUser:true];
        userJoinedTimeSeconds = [self secondsSinceEpoch];
        [SwrveLocalStorage saveUserJoinedTime:userJoinedTimeSeconds forUserId:userId];
    } else {
        [profileManager setIsNewUser:false];
        userJoinedTimeSeconds = userJoinedTimeSecondsFromFile;
    }
}

- (void)initAppInstallTime {
    UInt64 appInstallTimeSecondsFromFile = [SwrveLocalStorage appInstallTimeSeconds];
    if (appInstallTimeSecondsFromFile == 0) {
        appInstallTimeSeconds = [self secondsSinceEpoch];
        [SwrveLocalStorage saveAppInstallTime:appInstallTimeSeconds];
    } else {
        appInstallTimeSeconds = appInstallTimeSecondsFromFile;
    }
}

- (void)beginSession {
    [self beginSession:nil];
}

- (void)beginSession:(dispatch_group_t)sendEventsCallbackForBeginSessionGroup {

    sdkStarted = true;

    // The app has started and thus our session
    lastSessionDate = [self getNow];
#if TARGET_OS_IOS /** exclude tvOS **/
    [SwrvePermissions compareStatusAndQueueEventsWithSDK:self];
#endif

    [self disableAutoShowAfterDelay];

    [self queueSessionStart];

    NSDictionary *deviceInfo = [self deviceInfo];
    [self mergeWithCurrentDeviceInfo:deviceInfo];
    [self logDeviceInfo:deviceInfo];

    // If this is the first time this user has been seen send install analytics
    if ([profileManager isNewUser]) {
        [self eventInternal:@"Swrve.first_session" payload:nil triggerCallback:false];
        [profileManager setIsNewUser:false];
    }

    [self startCampaignsAndResourcesTimer];

    if (sendEventsCallbackForBeginSessionGroup != nil) {
        dispatch_group_enter(sendEventsCallbackForBeginSessionGroup);
        dispatch_group_enter(sendEventsCallbackForBeginSessionGroup);
    }
    [self sendQueuedEventsWithCallback:^(NSURLResponse *response, NSData *data, NSError *error) {
#pragma unused(response, data, error)
        if (sendEventsCallbackForBeginSessionGroup != nil) {
            dispatch_group_leave(sendEventsCallbackForBeginSessionGroup);
        }
    }                eventFileCallback:^(NSURLResponse *response, NSData *data, NSError *error) {
#pragma unused(response, data, error)
        if (sendEventsCallbackForBeginSessionGroup != nil) {
            dispatch_group_leave(sendEventsCallbackForBeginSessionGroup);
        }
    }];

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    if (self.config.pushEnabled) {
        [self.push saveConfigForPushDelivery];
    }
#endif
}

- (void)initSwrveRestClient:(NSTimeInterval)timeOut {
    [self setRestClient:[[SwrveRESTClient alloc] initWithTimeoutInterval:timeOut]];
}

- (BOOL)shouldAutoStart {
    if ([config initMode] == SWRVE_INIT_MODE_AUTO) {
        return true;
    } else if ([config initMode] == SWRVE_INIT_MODE_MANAGED &&
            [config managedModeAutoStartLastUser] &&
            [[SwrveLocalStorage swrveUserId] length] > 0) {
        return true;
    } else {
        return false;
    }
}

- (void)queueSessionStart {
    [self maybeFlushToDisk];
    NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
    [self queueEvent:@"session_start" data:json triggerCallback:true];
}

- (int)sessionStart {
    [self queueSessionStart];
    [self sendQueuedEvents];
    return SWRVE_SUCCESS;
}

- (int)purchaseItem:(NSString *)itemName currency:(NSString *)itemCurrency cost:(int)itemCost quantity:(int)itemQuantity {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    [self maybeFlushToDisk];
    NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
    [json setValue:NullableNSString(itemName) forKey:@"item"];
    [json setValue:NullableNSString(itemCurrency) forKey:@"currency"];
    [json setValue:[NSNumber numberWithInt:itemCost] forKey:@"cost"];
    [json setValue:[NSNumber numberWithInt:itemQuantity] forKey:@"quantity"];
    return [self queueEvent:@"purchase" data:json triggerCallback:true];
}

- (int)event:(NSString *)eventName {
    if ([eventsManager isValidEventName:eventName] && [self sdkReady]) {
        return [self eventInternal:eventName payload:nil triggerCallback:true];
    } else {
        return SWRVE_FAILURE;
    }
}

- (int)event:(NSString *)eventName payload:(NSDictionary *)eventPayload {
    if ([eventsManager isValidEventName:eventName] && [self sdkReady]) {
        return [self eventInternal:eventName payload:eventPayload triggerCallback:true];
    } else {
        return SWRVE_FAILURE;
    }
}

- (int)eventWithNoCallback:(NSString *)eventName payload:(NSDictionary *)eventPayload {
    if ([eventsManager isValidEventName:eventName] && [self sdkReady]) {
        return [self eventInternal:eventName payload:eventPayload triggerCallback:false notifyMessageController:true];
    } else {
        return SWRVE_FAILURE;
    }
}

- (int)iap:(SKPaymentTransaction *)transaction product:(SKProduct *)product {
    return [self iap:transaction product:product rewards:nil];
}

- (int)iap:(SKPaymentTransaction *)transaction product:(SKProduct *)product rewards:(SwrveIAPRewards *)rewards {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    NSString *product_id = @"unknown";
    int queuedStatus = SWRVE_SUCCESS;
    switch (transaction.transactionState) {
        case SKPaymentTransactionStatePurchased: {
            if (transaction.payment != nil && transaction.payment.productIdentifier != nil) {
                product_id = transaction.payment.productIdentifier;
            }

            NSString *transactionId = [transaction transactionIdentifier];
#pragma unused(transactionId)

            SwrveReceiptProviderResult *receipt = [self.receiptProvider receiptForTransaction:transaction];
            if (!receipt || !receipt.encodedReceipt) {
                DebugLog(@"No transaction receipt could be obtained for %@", transactionId);
                return SWRVE_FAILURE;
            }
            DebugLog(@"Swrve building IAP event for transaction %@ (product %@)", transactionId, product_id);
            NSString *encodedReceipt = receipt.encodedReceipt;
            NSString *localCurrency = [product.priceLocale objectForKey:NSLocaleCurrencyCode];
            double localCost = [[product price] doubleValue];

            // Construct the IAP event
            NSString *store = @"apple";
            if (encodedReceipt == nil) {
                store = @"unknown";
            }
            if (rewards == nil) {
                rewards = [[SwrveIAPRewards alloc] init];
            }

            [self maybeFlushToDisk];
            NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
            [json setValue:store forKey:@"app_store"];
            [json setValue:localCurrency forKey:@"local_currency"];
            [json setValue:[NSNumber numberWithDouble:localCost] forKey:@"cost"];
            [json setValue:[rewards rewards] forKey:@"rewards"];
            [json setValue:encodedReceipt forKey:@"receipt"];
            // Payload data
            NSMutableDictionary *eventPayload = [[NSMutableDictionary alloc] init];
            [eventPayload setValue:product_id forKey:@"product_id"];
            [json setValue:eventPayload forKey:@"payload"];
            if (receipt.transactionId) {
                // Send transactionId only for iOS7+. This is how the server knows it is an iOS7 receipt!
                [json setValue:receipt.transactionId forKey:@"transaction_id"];
            }
            queuedStatus = [self queueEvent:@"iap" data:json triggerCallback:true];

            // After IAP event we want to immediately flush the event buffer and update campaigns and resources if necessary
            if ([self.config autoDownloadCampaignsAndResources]) {
                [self checkForCampaignAndResourcesUpdates:nil];
            }
        }
            break;
        case SKPaymentTransactionStateFailed: {
            if (transaction.payment != nil && transaction.payment.productIdentifier != nil) {
                product_id = transaction.payment.productIdentifier;
            }
            NSString *error = @"unknown";
            if (transaction.error != nil && transaction.error.description != nil) {
                error = transaction.error.description;
            }
            NSDictionary *payload = @{@"product_id": product_id, @"error": error};
            queuedStatus = [self eventInternal:@"Swrve.iap.transaction_failed_on_client" payload:payload triggerCallback:false];
        }
            break;
        case SKPaymentTransactionStateRestored: {
            if (transaction.originalTransaction != nil && transaction.originalTransaction.payment != nil && transaction.originalTransaction.payment.productIdentifier != nil) {
                product_id = transaction.originalTransaction.payment.productIdentifier;
            }
            NSDictionary *payload = @{@"product_id": product_id};
            queuedStatus = [self eventInternal:@"Swrve.iap.restored_on_client" payload:payload triggerCallback:false];
        }
            break;
        default:
            break;
    }

    return queuedStatus;
}

- (int)unvalidatedIap:(SwrveIAPRewards *)rewards localCost:(double)localCost localCurrency:(NSString *)localCurrency productId:(NSString *)productId productIdQuantity:(int)productIdQuantity {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    [self maybeFlushToDisk];
    NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
    [json setValue:@"unknown" forKey:@"app_store"];
    [json setValue:localCurrency forKey:@"local_currency"];
    [json setValue:[NSNumber numberWithDouble:localCost] forKey:@"cost"];
    [json setValue:productId forKey:@"product_id"];
    [json setValue:[NSNumber numberWithInteger:productIdQuantity] forKey:@"quantity"];
    [json setValue:[rewards rewards] forKey:@"rewards"];
    int queued_status = [self queueEvent:@"iap" data:json triggerCallback:true];
    // After IAP event we want to immediately flush the event buffer and update campaigns and resources if necessary
    if ([self.config autoDownloadCampaignsAndResources]) {
        [self checkForCampaignAndResourcesUpdates:nil];
    }
    return queued_status;
}

- (int)currencyGiven:(NSString *)givenCurrency givenAmount:(double)givenAmount {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    [self maybeFlushToDisk];
    NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
    [json setValue:NullableNSString(givenCurrency) forKey:@"given_currency"];
    [json setValue:[NSNumber numberWithDouble:givenAmount] forKey:@"given_amount"];
    return [self queueEvent:@"currency_given" data:json triggerCallback:true];
}

- (void)mergeWithCurrentDeviceInfo:(NSDictionary *)attributes {
    [self maybeFlushToDisk];

    // Merge attributes with current set of attributes
    if (attributes) {
        @synchronized (self.deviceInfoDic) {
            NSMutableDictionary *currentAttributes = (NSMutableDictionary *) [self.deviceInfoDic objectForKey:@"attributes"];
            [self.deviceInfoDic setValue:[NSNumber numberWithUnsignedLongLong:[SwrveUtils getTimeEpoch]] forKey:@"time"];
            for (id attributeKey in attributes) {
                id attribute = [attributes objectForKey:attributeKey];
                [currentAttributes setObject:attribute forKey:attributeKey];
            }
        }
    }
}

- (int)userUpdate:(NSDictionary *)attributes {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    [self maybeFlushToDisk];

    // Merge attributes with current set of attributes
    if (attributes) {
        @synchronized (self.userUpdates) {
            NSMutableDictionary *currentAttributes = (NSMutableDictionary *) [self.userUpdates objectForKey:@"attributes"];
            [self.userUpdates setValue:[NSNumber numberWithUnsignedLongLong:[SwrveUtils getTimeEpoch]] forKey:@"time"];
            for (id attributeKey in attributes) {
                id attribute = [attributes objectForKey:attributeKey];
                [currentAttributes setObject:attribute forKey:attributeKey];
            }
        }
    }

    return SWRVE_SUCCESS;
}

- (int)userUpdate:(NSString *)name withDate:(NSDate *)date {
    if (![self sdkReady]) {
        return SWRVE_FAILURE;
    }
    if (name && date) {
        @synchronized (self.userUpdates) {
            NSMutableDictionary *currentAttributes = (NSMutableDictionary *) [self.userUpdates objectForKey:@"attributes"];
            [self.userUpdates setValue:[NSNumber numberWithUnsignedLongLong:[SwrveUtils getTimeEpoch]] forKey:@"time"];
            [currentAttributes setObject:[self convertDateToString:date] forKey:name];
        }

    } else {
        DebugLog(@"nil object passed into userUpdate:withDate");
        return SWRVE_FAILURE;
    }

    return SWRVE_SUCCESS;
}

- (NSString *)convertDateToString:(NSDate *)date {

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];

    return [dateFormatter stringFromDate:date];
}

- (void)refreshCampaignsAndResources:(NSTimer *)timer {
#pragma unused(timer)
    [self refreshCampaignsAndResources];
}

- (void)refreshCampaignsAndResources {
    if (![self sdkReady]) {
        return;
    }
    // When campaigns need to be downloaded manually, enforce max. flush frequency
    if (!self.config.autoDownloadCampaignsAndResources) {
        NSDate *now = [self getNow];

        if (self.campaignsAndResourcesLastRefreshed != nil) {
            NSDate *nextAllowedTime = [NSDate dateWithTimeInterval:self.campaignsAndResourcesFlushFrequency sinceDate:self.campaignsAndResourcesLastRefreshed];
            if ([now compare:nextAllowedTime] == NSOrderedAscending) {
                // Too soon to call refresh again
                DebugLog(@"Request to retrieve campaign and user resource data was rate-limited.", nil);
                return;
            }
        }

        self.campaignsAndResourcesLastRefreshed = [self getNow];
    }

    NSURL *url = [self campaignsAndResourcesURL];
    DebugLog(@"Refreshing campaigns from URL %@", url);
    [restClient sendHttpGETRequest:url completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (!error) {
            NSInteger statusCode = 200;
            enum HttpStatus status = HTTP_SUCCESS;

            NSDictionary *headers = [[NSDictionary alloc] init];
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                statusCode = [httpResponse statusCode];
                status = [self httpStatusFromResponse:httpResponse];
                headers = [httpResponse allHeaderFields];
            }

            if (status == SWRVE_SUCCESS) {
                if ([self isValidJson:data]) {
                    NSString *etagHeader = [headers objectForKey:@"ETag"];
                    if (etagHeader != nil) {
                        [SwrveLocalStorage saveETag:etagHeader forUserId:self.userID];
                    }

                    NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

                    NSNumber *flushFrequency = [responseDict objectForKey:@"flush_frequency"];
                    if (flushFrequency != nil) {
                        self.campaignsAndResourcesFlushFrequency = [flushFrequency integerValue] / 1000;
                        [SwrveLocalStorage saveFlushFrequency:self.campaignsAndResourcesFlushFrequency];
                    }

                    NSNumber *flushDelay = [responseDict objectForKey:@"flush_refresh_delay"];
                    if (flushDelay != nil) {
                        self.campaignsAndResourcesFlushRefreshDelay = [flushDelay integerValue] / 1000;
                        [SwrveLocalStorage saveflushDelay:self.campaignsAndResourcesFlushRefreshDelay];
                    }

                    if (self.messaging) {
                        NSDictionary *campaignJson = [responseDict objectForKey:@"campaigns"];
                        if (campaignJson != nil) {
                            [self.messaging updateCampaigns:campaignJson];

                            NSData *campaignData = [NSJSONSerialization dataWithJSONObject:campaignJson options:0 error:nil];
                            [self.messaging writeToCampaignCache:campaignData];
                            [self.messaging autoShowMessages];

                            // Notify campaigns have been downloaded
                            NSMutableArray *campaignIds = [[NSMutableArray alloc] init];
                            for (SwrveCampaign *campaign in self.messaging.campaigns) {
                                [campaignIds addObject:[NSNumber numberWithUnsignedInteger:campaign.ID]];
                            }

                            NSDictionary *payload = @{@"ids": [campaignIds componentsJoinedByString:@","],
                                    @"count": [NSString stringWithFormat:@"%lu", (unsigned long) [self.messaging.campaigns count]]};

                            [self eventInternal:@"Swrve.Messages.campaigns_downloaded" payload:payload triggerCallback:false];
                        }
                    }

                    // In Version 7 QA is at the root
                    NSDictionary *jsonQa = [responseDict objectForKey:@"qa"];
                    if (jsonQa) {
                        //Location QA setup
                        [SwrveQA updateQAUser:jsonQa];
                    }

                    if (self.config.abTestDetailsEnabled) {
                        NSDictionary *campaignJson = [responseDict objectForKey:@"campaigns"];
                        if (campaignJson != nil) {
                            id abTestDetailsJson = [campaignJson objectForKey:@"ab_test_details"];
                            if (abTestDetailsJson != nil && [abTestDetailsJson isKindOfClass:[NSDictionary class]]) {
                                [self updateABTestDetails:abTestDetailsJson];
                            }
                        }
                    }

                    NSArray *resourceJson = [responseDict objectForKey:@"user_resources"];
                    if (resourceJson != nil) {
                        [self updateResources:resourceJson writeToCache:YES];
                    }
                    
                    NSDictionary *realTimeUserPropertiesJson = [responseDict objectForKey:@"real_time_user_properties"];
                    if(realTimeUserPropertiesJson != nil) {
                        [self updateRealTimeUserProperties:realTimeUserPropertiesJson writeToCache:YES];
                    }
                    
                } else {
                    DebugLog(@"Invalid JSON received for user resources and campaigns", nil);
                }
            } else if (statusCode == 429) {
                DebugLog(@"Request to retrieve campaign and user resource data was rate-limited.", nil);
            } else {
                DebugLog(@"Request to retrieve campaign and user resource data failed", nil);
            }
        }

        if (![self campaignsAndResourcesInitialized]) {
            [self setCampaignsAndResourcesInitialized:YES];

            // Only called first time API call returns - whether failed or successful, whether new campaigns were returned or not;
            // this ensures that if API call fails or there are no changes, we call autoShowMessages with cached campaigns
            if (self.messaging) {
                [self.messaging autoShowMessages];
            }

            // Invoke listeners once to denote that the first attempt at downloading has finished
            // independent of whether the resources or campaigns have changed from cached values
            if ([self.config resourcesUpdatedCallback]) {
                [[self.config resourcesUpdatedCallback] invoke];
            }
        }
    }];
}

- (UInt64)joinedDateMilliSeconds {
    return 1000 * self->userJoinedTimeSeconds;
}

- (NSURL *)campaignsAndResourcesURL {
    UInt64 joinedDateMilliSeconds = [self joinedDateMilliSeconds];
    NSMutableString *queryString = [NSMutableString stringWithFormat:@"?user=%@&api_key=%@&app_version=%@&joined=%llu",
                                                                     self.userID, self.apiKey, self.appVersion, joinedDateMilliSeconds];
    if (self.messaging) {
        NSString *campaignQueryString = [self.messaging campaignQueryString];
        [queryString appendFormat:@"&%@", campaignQueryString];
    }

    if (self.config.abTestDetailsEnabled) {
        [queryString appendString:@"&ab_test_details=1"];
    }

    NSString *etagValue = [SwrveLocalStorage eTagForUserId:self.userID];
    if (etagValue != nil) {
        [queryString appendFormat:@"&etag=%@", etagValue];
    }

    return [NSURL URLWithString:queryString relativeToURL:self.baseCampaignsAndResourcesURL];
}

- (void)checkForCampaignAndResourcesUpdates:(NSTimer *)timer {
    // If this wasn't called from the timer then reset the timer
    if (timer == nil) {
        NSDate *now = [self getNow];
        NSDate *nextInterval = [now dateByAddingTimeInterval:self.campaignsAndResourcesFlushFrequency];
        @synchronized ([self campaignsAndResourcesTimer]) {
            [self.campaignsAndResourcesTimer setFireDate:nextInterval];
        }
    }

    // Check if there are events in the buffer or in the cache
    BOOL eventsToSend;
    @synchronized (self.eventBuffer) {
        eventsToSend = ([self eventFileHasData] || [self.eventBuffer count] > 0 || [self eventsWereSent]);
    }
    if (eventsToSend) {
        [self sendQueuedEvents];
        [self setEventsWereSent:NO];

        [NSTimer scheduledTimerWithTimeInterval:self.campaignsAndResourcesFlushRefreshDelay target:self selector:@selector(refreshCampaignsAndResources:) userInfo:nil repeats:NO];
    }
}

- (BOOL)processPermissionRequest:(NSString *)action {
#if TARGET_OS_IOS /** exclude tvOS **/
    return [SwrvePermissions processPermissionRequest:action withSDK:self];
#else
    return NO;
#endif
}

- (void)sendQueuedEvents {
    if (![self sdkReady]) {
        return;
    }
    if (trackingState == EVENT_SENDING_PAUSED) {
        DebugLog(@"Swrve event sending paused so attempt to send queued events has failed.", nil);
        return;
    }
    [self sendQueuedEventsWithCallback:nil eventFileCallback:nil];
}

- (void)sendQueuedEventsWithCallback:(void (^)(NSURLResponse *response, NSData *data, NSError *error))eventBufferCallback
                   eventFileCallback:(void (^)(NSURLResponse *response, NSData *data, NSError *error))eventFileCallback {

    [self sendQueuedEventsWithCallback:eventBufferCallback eventFileCallback:eventFileCallback forceFlush:false];
}

- (void)sendQueuedEventsWithCallback:(void (^)(NSURLResponse *response, NSData *data, NSError *error))eventBufferCallback
                   eventFileCallback:(void (^)(NSURLResponse *response, NSData *data, NSError *error))eventFileCallback
                          forceFlush:(BOOL) isForceFlush {

    if (trackingState == EVENT_SENDING_PAUSED && !isForceFlush) {
        DebugLog(@"Swrve event sending paused.", nil);
        if (eventBufferCallback != nil) {
            eventBufferCallback(nil, nil, nil);
        }
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }
    if (!self.userID) {
        DebugLog(@"Swrve user_id is null. Not sending data.", nil);
        if (eventBufferCallback != nil) {
            eventBufferCallback(nil, nil, nil);
        }
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }

    DebugLog(@"Sending queued events", nil);
    if ([self eventFileHasData]) {
        if (eventFileCallback == nil) {
            [self sendEventfile:nil];
        } else {
            [self sendEventfile:^(NSURLResponse *response, NSData *data, NSError *error) {
                eventFileCallback(response, data, error);
            }];
        }
    } else {
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
    }

    [self queueUserUpdates];
    [self queueDeviceInfo];

    // Early out if length is zero.
    NSArray *buffer = self.eventBuffer;
    int bytes = self.eventBufferBytes;

    @synchronized (buffer) {
        if ([buffer count] == 0) {
            if (eventBufferCallback != nil) {
                eventBufferCallback(nil, nil, nil);
            }
            return;
        }

        // Swap buffers
        [self initBuffer];
    }

    NSString *array_body = [self copyBufferToJson:buffer];
    NSString *json_string = [self createJSON:[self sessionToken] events:array_body];

    NSData *json_data = [json_string dataUsingEncoding:NSUTF8StringEncoding];
    [self setEventsWereSent:YES];

    // track this in case identity call finished first and the swrve user id changes before this call completes
    __block NSString *swrveUserIdForEventSending = [self.userID copy];
    [restClient sendHttpPOSTRequest:[self batchURL]
                           jsonData:json_data
                  completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                      // Schedule the stream on the current run loop, then open the stream (which
                      // automatically sends the request).  Wait for at least one byte of data to
                      // be returned by the server.  As soon as at least one byte is available,
                      // the full HTTP response header is available. If no data is returned
                      // within the timeout period, give up.
                      SwrveSendContext *sendContext = [[SwrveSendContext alloc] init];
                      [sendContext setSwrveReference:self];
                      [sendContext setSwrveInstanceID:self->instanceID];
                      @synchronized (buffer) {
                          [sendContext setBuffer:buffer];
                          [sendContext setBufferLength:bytes];
                      }

                      if (error) {
                          DebugLog(@"Error opening HTTP stream: %@ %@", [error localizedDescription], [error localizedFailureReason]);
                          [self eventsSentCallback:HTTP_SERVER_ERROR withData:data andContext:sendContext withSwrveUserId:swrveUserIdForEventSending]; //503 network error
                          if (eventBufferCallback != nil) {
                              eventBufferCallback(response, data, error);
                          }
                          return;
                      }

                      enum HttpStatus status = HTTP_SUCCESS;
                      if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                          NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                          status = [self httpStatusFromResponse:httpResponse];
                      }
                      [self eventsSentCallback:status withData:data andContext:sendContext withSwrveUserId:swrveUserIdForEventSending];
                      if (eventBufferCallback != nil) {
                          eventBufferCallback(response, data, error);
                      }
                  }];
}

- (void)saveEventsToDisk {
    if (![self sdkReady]) {
        return;
    }
    DebugLog(@"Writing unsent event data to file", nil);

    [self queueUserUpdates];
    [self queueDeviceInfo];

    NSArray *buffer = self.eventBuffer;
    @synchronized (buffer) {
        if ([self eventStream] && [buffer count] > 0) {
            NSString *json = [self copyBufferToJson:buffer];
            json = [json stringByAppendingString:@",\n"];
            NSData *bufferJson = [json dataUsingEncoding:NSUTF8StringEncoding];
            long bytes = [[self eventStream] write:(const uint8_t *) [bufferJson bytes] maxLength:[bufferJson length]];
            if (bytes == 0) {
                DebugLog(@"Nothing was written to the event file");
            } else if (bytes < 0) {
                DebugLog(@"Error, could not write events to disk");
            } else {
                DebugLog(@"Written to the event file");
                [self initBuffer];
            }
        }
    }
}

- (void)setEventQueuedCallback:(SwrveEventQueuedCallback)callbackBlock {
    if (![self sdkReady]) {
        return;
    }
    event_queued_callback = callbackBlock;
}

- (void)shutdown {
    DebugLog(@"shutting down swrveInstance..", nil);
    if ([[SwrveInstanceIDRecorder sharedInstance] hasSwrveInstanceID:instanceID] == NO) {
        DebugLog(@"Swrve shutdown: called on invalid instance.", nil);
        return;
    }

    [self stopCampaignsAndResourcesTimer];

    //ensure UI isn't displaying during shutdown
    [self.messaging cleanupConversationUI];
    [self.messaging dismissMessageWindow];
    messaging = nil;

    resourceManager = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [[SwrveInstanceIDRecorder sharedInstance] removeSwrveInstanceID:instanceID];

    if ([self eventStream]) {
        [[self eventStream] close];
        [self setEventStream:nil];
    }

    [self setEventBuffer:nil];

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    [self.push deswizzlePushMethods];
    [SwrvePush resetSharedInstance];
    push = nil;
#endif
}

#pragma mark -
#pragma mark Private methods

- (int)eventInternal:(NSString *)eventName payload:(NSDictionary *)eventPayload triggerCallback:(bool)triggerCallback  {
    //triggerCallback and notifyMessageController bools are the same unless we are using eventWithNoCallBack which will set notifyMessageController to true
    //we want to call eventRaised when going through eventWithNoCallBack below
    bool notifyMessageController = triggerCallback;
    return [self eventInternal:eventName payload:eventPayload triggerCallback:triggerCallback notifyMessageController:notifyMessageController];
}

- (int)eventInternal:(NSString *)eventName payload:(NSDictionary *)eventPayload triggerCallback:(bool)triggerCallback notifyMessageController:(bool)notifyMessageController {
    if (!eventPayload) {
        eventPayload = [[NSDictionary alloc] init];
    }

    [self maybeFlushToDisk];
    NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
    [json setValue:NullableNSString(eventName) forKey:@"name"];
    [json setValue:eventPayload forKey:@"payload"];
    return [self queueEvent:@"event" data:json triggerCallback:triggerCallback notifyMessageController:notifyMessageController];
}

- (void)dealloc {
    if ([[SwrveInstanceIDRecorder sharedInstance] hasSwrveInstanceID:instanceID] == YES) {
        [self shutdown];
    }
}

- (void)registerLifecycleCallbacks {

    if (!lifecycleCallbacksRegistered) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appWillTerminate:)
                                                     name:UIApplicationWillTerminateNotification object:nil];
        lifecycleCallbacksRegistered = true;
    }
}

- (BOOL)lifecycleCallbacksRegistered {
    return lifecycleCallbacksRegistered;
}

- (void)appDidBecomeActive:(NSNotification *)notification {
#pragma unused(notification)

    trackingState = ON;

    if (!initialised) {
        initialised = YES;
        [self beginSession]; // App started the first time
        [self executeSessionStartedDelegate];
        return;
    }

    // App became active after a pause
    NSDate *now = [self getNow];
    NSTimeInterval secondsPassed = [now timeIntervalSinceDate:lastSessionDate];
    if (secondsPassed >= self.config.newSessionInterval) {
        [self sessionStart]; // We consider this a new session as more than newSessionInterval seconds have passed.
        if (self.messaging) {
            [self.messaging setAutoShowMessagesEnabled:YES]; // Re-enable auto show messages at session start
            [self disableAutoShowAfterDelay];
        }
        [self executeSessionStartedDelegate];
    }

    NSDictionary *deviceInfo = [self deviceInfo];
    [self mergeWithCurrentDeviceInfo:deviceInfo];
    [self logDeviceInfo:deviceInfo];
    if (self.config.autoSendEventsOnResume) {
        [self sendQueuedEvents];
    }

    if (self.messaging != nil) {
        [self.messaging appDidBecomeActive];
    }

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    if (self.config.pushEnabled) {
        [self.push processInfluenceData];
        if (_deviceToken == nil) {
            [SwrvePermissions refreshDeviceToken:self];
        }
    }
#endif //!defined(SWRVE_NO_PUSH)

    [self resumeCampaignsAndResourcesTimer];
    lastSessionDate = [self getNow];
}

- (void)appWillResignActive:(NSNotification *)notification {
#pragma unused(notification)
    lastSessionDate = [self getNow];
    [self suspend:NO];
}

- (void)appWillTerminate:(NSNotification *)notification {
#pragma unused(notification)
    [self suspend:YES];
}

- (void)suspend:(BOOL)terminating {
    if (terminating) {
        if (self.config.autoSaveEventsOnResign) {
            [self saveEventsToDisk];
        }
    } else {
        [self sendQueuedEvents];
    }

    [self stopCampaignsAndResourcesTimer];
}

- (void)startCampaignsAndResourcesTimer {
    if (!self.config.autoDownloadCampaignsAndResources) {
        return;
    }

    [self refreshCampaignsAndResources];
    // Start repeating timer
    [self setCampaignsAndResourcesTimer:[NSTimer scheduledTimerWithTimeInterval:1
                                                                         target:self
                                                                       selector:@selector(campaignsAndResourcesTimerTick:)
                                                                       userInfo:nil
                                                                        repeats:YES]];

    // Call refresh once after refresh delay to ensure campaigns are reloaded after initial events have been sent
    [NSTimer scheduledTimerWithTimeInterval:[self campaignsAndResourcesFlushRefreshDelay]
                                     target:self
                                   selector:@selector(refreshCampaignsAndResources:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)campaignsAndResourcesTimerTick:(NSTimer *)timer {
    self.campaignsAndResourcesTimerSeconds++;
    if (self.campaignsAndResourcesTimerSeconds >= self.campaignsAndResourcesFlushFrequency) {
        self.campaignsAndResourcesTimerSeconds = 0;
        [self checkForCampaignAndResourcesUpdates:timer];
    }
}

- (void)resumeCampaignsAndResourcesTimer {
    if (!self.config.autoDownloadCampaignsAndResources) {
        return;
    }

    @synchronized (self.campaignsAndResourcesTimer) {
        [self stopCampaignsAndResourcesTimer];
        [self setCampaignsAndResourcesTimer:[NSTimer scheduledTimerWithTimeInterval:1
                                                                             target:self
                                                                           selector:@selector(campaignsAndResourcesTimerTick:)
                                                                           userInfo:nil
                                                                            repeats:YES]];
    }
}

- (void)stopCampaignsAndResourcesTimer {
    @synchronized (self.campaignsAndResourcesTimer) {
        if (self.campaignsAndResourcesTimer && [self.campaignsAndResourcesTimer isValid]) {
            [self.campaignsAndResourcesTimer invalidate];
        }
    }
}

//If talk enabled ensure that after SWRVE_DEFAULT_AUTOSHOW_MESSAGES_MAX_DELAY autoshow is disabled
- (void)disableAutoShowAfterDelay {
    if (self.messaging) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
        SEL autoShowSelector = @selector(setAutoShowMessagesEnabled:);
#pragma clang diagnostic pop

        NSInvocation *disableAutoshowInvocation = [NSInvocation invocationWithMethodSignature:
                [self.messaging methodSignatureForSelector:autoShowSelector]];

        bool arg = NO;
        [disableAutoshowInvocation setSelector:autoShowSelector];
        [disableAutoshowInvocation setTarget:self.messaging];
        [disableAutoshowInvocation setArgument:&arg atIndex:2];
        [NSTimer scheduledTimerWithTimeInterval:(self.config.autoShowMessagesMaxDelay / 1000) invocation:disableAutoshowInvocation repeats:NO];
    }
}


- (void)queueUserUpdates {
    @synchronized (self.userUpdates) {
        NSMutableDictionary *currentAttributes = (NSMutableDictionary *) [self.userUpdates objectForKey:@"attributes"];
        if (currentAttributes.count > 0) {
            [self queueEvent:@"user" data:[self.userUpdates mutableCopy] triggerCallback:false];
            [currentAttributes removeAllObjects];
        }
    }
}

- (void)queueDeviceInfo {
    @synchronized (self.deviceInfoDic) {
        NSMutableDictionary *currentAttributes = (NSMutableDictionary *) [self.deviceInfoDic objectForKey:@"attributes"];
        if (currentAttributes.count > 0) {
            [self queueEvent:@"device_update" data:[self.deviceInfoDic mutableCopy] triggerCallback:false];
            [currentAttributes removeAllObjects];
        }
    }
}

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS

- (void)deviceTokenIncoming:(NSData *)newDeviceToken {
    [self setDeviceToken:newDeviceToken];
}

- (void)deviceTokenUpdated:(NSString *)newDeviceToken {
    if (![_deviceToken isEqualToString:newDeviceToken]) {
        _deviceToken = newDeviceToken;
        [SwrveLocalStorage saveDeviceToken:newDeviceToken];
        NSDictionary *deviceInfo = [self deviceInfo];
        [self mergeWithCurrentDeviceInfo:deviceInfo];
        [self mergeWithCurrentDeviceInfo:[SwrvePermissions currentStatusWithSDK:self]];

        [self logDeviceInfo:deviceInfo];
        [self queueDeviceInfo];
        [self sendQueuedEvents];
    }
}

- (void)setDeviceToken:(NSData *)deviceToken {
    if (![self sdkReady]) {
        return;
    }
    if (self.config.pushEnabled && deviceToken) {
        [self.push setPushNotificationsDeviceToken:deviceToken];

        if (self.messaging) {
            [self.messaging deviceTokenUpdated];
        }
    }
}

- (NSString *)deviceToken {
    if (![self sdkReady]) {
        return @"";
    }
    return self->_deviceToken;
}

- (BOOL)didReceiveRemoteNotification:(NSDictionary *)userInfo withBackgroundCompletionHandler:(void (^)(UIBackgroundFetchResult, NSDictionary *))completionHandler  API_AVAILABLE(ios(7.0)){
    if (self.config.pushEnabled) {
        return [self.push didReceiveRemoteNotification:userInfo withBackgroundCompletionHandler:completionHandler];
    } else {
        // When we return NO, we don't trigger our completionHandler. Customers will need to call the fetchCompletionHandler regarding the UIBackgroundFetchResult.
        return NO;
    }
}

- (void)processNotificationResponseWithIdentifier:(NSString *)identifier andUserInfo:(NSDictionary *)userInfo {
    DebugLog(@"Processing Push Notification Response: %@", identifier);
    NSURL *deeplinkUrl = [SwrveNotificationManager notificationResponseReceived:identifier withUserInfo:userInfo];
    if (deeplinkUrl) {
        [self deeplinkReceived:deeplinkUrl];
    }
}

- (void)processNotificationResponse:(UNNotificationResponse *)response __IOS_AVAILABLE(10.0) __TVOS_AVAILABLE(10.0) {
    [self processNotificationResponseWithIdentifier:response.actionIdentifier andUserInfo:response.notification.request.content.userInfo];
}

- (void)deeplinkReceived:(NSURL *)url {
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            DebugLog(@"Opening url [%@] successfully: %d", url, success);
        }];
    } else {
        DebugLog(@"Deeplink not processed, not supported (should not reach this code)");
    }
}

#endif //!defined(SWRVE_NO_PUSH)
#pragma mark -

- (void)setupConfig:(SwrveConfig *)newConfig {
    NSString *prefix = [self stackHostPrefixFromConfig:newConfig];

    // Set up default server locations
    if (nil == newConfig.eventsServer) {
        newConfig.eventsServer = [NSString stringWithFormat:@"%@://%ld.%@api.swrve.com", @"https", self.appID, prefix];
    }

    if (nil == newConfig.contentServer) {
        newConfig.contentServer = [NSString stringWithFormat:@"%@://%ld.%@content.swrve.com", @"https", self.appID, prefix];
    }

    if (nil == newConfig.identityServer) {
        newConfig.identityServer = [NSString stringWithFormat:@"%@://%ld.%@identity.swrve.com", @"https", self.appID, prefix];
    }

    // Validate other values
    NSCAssert(newConfig.httpTimeoutSeconds > 0, @"httpTimeoutSeconds must be greater than zero or requests will fail immediately.", nil);
}

- (NSString *)stackHostPrefixFromConfig:(SwrveConfig *)newConfig {
    if (newConfig.stack == SWRVE_STACK_EU) {
        return @"eu-";
    } else {
        return @""; // default to US which has no prefix
    }
}

- (void)maybeFlushToDisk {
    if (trackingState == EVENT_SENDING_PAUSED) {
        DebugLog(@"Swrve event sending paused so attempt to flush disk has failed.", nil);
        return;
    }
    if (self.eventBufferBytes > SWRVE_MEMORY_QUEUE_MAX_BYTES) {
        [self saveEventsToDisk];
    }
}

- (int)queueEvent:(NSString *)eventType data:(NSMutableDictionary *)eventData triggerCallback:(bool)triggerCallback {
    //triggerCallback and notifyMessageController bools are the same unless we are using eventWithNoCallBack which will set notifyMessageController to true
    //we want to call eventRaised when going through eventWithNoCallBack below
    bool notifyMessageController = triggerCallback;
    return [self queueEvent:eventType data:eventData triggerCallback:triggerCallback notifyMessageController:notifyMessageController];
}

- (int)queueEvent:(NSString *)eventType data:(NSMutableDictionary *)eventData triggerCallback:(bool)triggerCallback notifyMessageController:(bool)notifyMessageController {
    if (trackingState == EVENT_SENDING_PAUSED) {
        DebugLog(@"Swrve event sending paused so attempt to queue events has failed. Will auto retry when event sending resumes.", nil);

        SwrveEventQueueItem *queueItem = [[SwrveEventQueueItem alloc] initWithEventType:eventType
                                                                              eventData:eventData
                                                                        triggerCallback:triggerCallback
                                                                notifyMessageController:notifyMessageController];
        [self.pausedEventsArray addObject:queueItem];
        return SWRVE_FAILURE;
    };
    NSMutableArray *buffer = self.eventBuffer;
    if (buffer) {
        // Add common attributes (if not already present)
        if (![eventData objectForKey:@"type"]) {
            [eventData setValue:eventType forKey:@"type"];
        }
        if (![eventData objectForKey:@"time"]) {
            [eventData setValue:[NSNumber numberWithUnsignedLongLong:[SwrveUtils getTimeEpoch]] forKey:@"time"];
        }
        if (![eventData objectForKey:@"seqnum"]) {
            [eventData setValue:[NSNumber numberWithInteger:[self nextEventSequenceNumber]] forKey:@"seqnum"];
        }

        // Convert to string
        NSData *json_data = [NSJSONSerialization dataWithJSONObject:eventData options:0 error:nil];
        if (json_data) {
            NSString *json_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
            @synchronized (buffer) {
                [self setEventBufferBytes:self.eventBufferBytes + (int) [json_string length]];
                [buffer addObject:json_string];
            }

            if (triggerCallback && event_queued_callback != NULL) {
                event_queued_callback(eventData, json_string);
            }

            if (self.messaging && notifyMessageController) {
                [self.messaging eventRaised:eventData];
            }
        }
    }
    return SWRVE_SUCCESS;
}

- (NSString *)swrveSDKVersion {
    return @SWRVE_SDK_VERSION;
}

- (NSString *)appVersion {
    NSString *appVersion = self.config.appVersion;
    if (appVersion == nil) {
        @try {
            appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
        }
        @catch (NSException *e) {
            DebugLog(@"Could not obtian version: %@", e);
        }
    }
    return appVersion;
}

- (NSSet *)notificationCategories {
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    return self.config.notificationCategories;
#else
    return nil;
#endif
}

- (NSString *)appGroupIdentifier {
    return self.config.appGroupIdentifier;
}

- (void)sendPushNotificationEngagedEvent:(NSString *)pushId {
    NSString *eventName = [NSString stringWithFormat:@"Swrve.Messages.Push-%@.engaged", pushId];
    [self eventInternal:eventName payload:nil triggerCallback:false];
    [self sendQueuedEventsWithCallback:nil eventFileCallback:nil];
}

- (void)sendCrashlyticsMetadata {

    // Check if Crashlytics is used in this project
    Class crashlyticsClass = NSClassFromString(@"Crashlytics");
    if (crashlyticsClass != nil) {
        SEL setObjectValueSelector = NSSelectorFromString(@"setObjectValue:forKey:");
        if ([crashlyticsClass respondsToSelector:setObjectValueSelector]) {
            IMP imp = [crashlyticsClass methodForSelector:setObjectValueSelector];
            void (*func)(__strong id, SEL, id, NSString *) = (void (*)(__strong id, SEL, id, NSString *)) imp;
            func(crashlyticsClass, setObjectValueSelector, @SWRVE_SDK_VERSION, @"Swrve_version");
        }
    }
}

- (NSDictionary *)deviceInfo {
    NSDictionary *permissionStatus = [SwrvePermissions currentStatusWithSDK:self];
    SwrveDeviceProperties *swrveDeviceProperties = nil;

#if TARGET_OS_IOS /** tvOS has no support for telephony or push **/
    CTCarrier *carrierInfo = [SwrveUtils carrierInfo];
    swrveDeviceProperties = [[SwrveDeviceProperties alloc] initWithVersion:@SWRVE_SDK_VERSION
                                                     appInstallTimeSeconds:appInstallTimeSeconds
                                                       conversationVersion:CONVERSATION_VERSION
                                                               deviceToken:self.deviceToken
                                                          permissionStatus:permissionStatus
                                                              sdk_language:self.config.language
                                                               carrierInfo:carrierInfo
                                                             swrveInitMode:[self swrveInitModeString]];

#elif TARGET_OS_TV
    swrveDeviceProperties = [[SwrveDeviceProperties alloc] initWithVersion:@SWRVE_SDK_VERSION
                                                     appInstallTimeSeconds:appInstallTimeSeconds
                                                          permissionStatus:permissionStatus
                                                              sdk_language:self.config.language
                                                             swrveInitMode:[self swrveInitModeString]];


#endif

    NSDictionary *deviceProperties = [swrveDeviceProperties deviceProperties];
    return deviceProperties;
}

- (NSString *)swrveInitModeString {
    NSString *initMode = @"unknown";
    if (self.config.initMode == SWRVE_INIT_MODE_AUTO) {
        initMode = @"auto";
    } else if (self.config.initMode == SWRVE_INIT_MODE_MANAGED && self.config.managedModeAutoStartLastUser) {
        initMode = @"managed_auto";
    } else if (self.config.initMode == SWRVE_INIT_MODE_MANAGED && !self.config.managedModeAutoStartLastUser) {
        initMode = @"managed";
    }
    return initMode;
}

- (void)logDeviceInfo:(NSDictionary *)deviceProperties {
    NSMutableString *formattedDeviceData = [[NSMutableString alloc] initWithFormat:
            @"                      User: %@\n"
            "                   API Key: %@\n"
            "                    App ID: %ld\n"
            "               App Version: %@\n"
            "                  Language: %@\n"
            "              Event Server: %@\n"
            "            Content Server: %@\n"
            "           Identity Server: %@\n",
            self.userID,
            self.apiKey,
            self.appID,
            self.appVersion,
            self.config.language,
            self.config.eventsServer,
            self.config.contentServer,
            self.config.identityServer];

    for (NSString *key in deviceProperties) {
        [formattedDeviceData appendFormat:@"  %24s: %@\n", [key UTF8String], [deviceProperties objectForKey:key]];
    }

    if (!getenv("RUNNING_UNIT_TESTS")) {
        DebugLog(@"Swrve config:\n%@", formattedDeviceData);
    }
}

- (UInt64)secondsSinceEpoch {
    return (unsigned long long) ([[NSDate date] timeIntervalSince1970]);
}

/*
 * Invalidates the currently stored ETag
 * Should be called when a refresh of campaigns and resources needs to be forced (eg. when cached data cannot be read)
 */
- (void)invalidateETag {
    [SwrveLocalStorage removeETagForUserId:self.userID];
}

- (void)initResources {
    SwrveSignatureProtectedFile *file = [self signatureFileWithType:SWRVE_RESOURCE_FILE errorDelegate:self];

    [self setResourcesFile:file];

    // Initialize resource manager
    if (resourceManager == nil) {
        resourceManager = [[SwrveResourceManager alloc] init];
    }

    // Read content of resources file and update resource manager if signature valid
    NSData *content = [self.resourcesFile readWithRespectToPlatform];

    if (content != nil) {
        NSError *error = nil;
        NSArray *resourcesArray = [NSJSONSerialization JSONObjectWithData:content options:NSJSONReadingMutableContainers error:&error];
        if (!error) {
            [self updateResources:resourcesArray writeToCache:NO];
        }
    } else {
        [self invalidateETag];
    }
}

- (void)initABTestDetails {
    SwrveSignatureProtectedFile *campaignFile = [self signatureFileWithType:SWRVE_CAMPAIGN_FILE errorDelegate:nil];

    // Initialize resource manager
    if (resourceManager == nil) {
        resourceManager = [[SwrveResourceManager alloc] init];
    }

    // Read content of campaigns file and update ab test details
    NSData *content = [campaignFile readWithRespectToPlatform];

    if (content != nil) {
        NSError *jsonError;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:content options:0 error:&jsonError];
        if (jsonError) {
            DebugLog(@"Error parsing AB Test details.\nError: %@ %@", [jsonError localizedDescription], [jsonError localizedFailureReason]);
        } else {
            id abTestDetailsJson = [jsonDict objectForKey:@"ab_test_details"];
            if (abTestDetailsJson != nil && [abTestDetailsJson isKindOfClass:[NSDictionary class]]) {
                [self updateABTestDetails:abTestDetailsJson];
            }
        }
    }
}

- (void)updateABTestDetails:(NSDictionary *)abTestDetailsJson {
    [self.resourceManager setABTestDetailsFromDictionary:abTestDetailsJson];
}

- (void)updateResources:(NSArray *)resourceJson writeToCache:(BOOL)writeToCache {
    [self.resourceManager setResourcesFromArray:resourceJson];

    if (writeToCache) {
        NSData *resourceData = [NSJSONSerialization dataWithJSONObject:resourceJson options:0 error:nil];
        [self.resourcesFile writeWithRespectToPlatform:resourceData];
    }

    if (self.config.resourcesUpdatedCallback != nil) {
        [self.config.resourcesUpdatedCallback invoke];
    }
}

- (void)initRealTimeUserProperties {
    SwrveSignatureProtectedFile *file = [self signatureFileWithType:SWRVE_REAL_TIME_USER_PROPERTIES_FILE errorDelegate:self];

    [self setRealTimeUserPropertiesFile:file];

    // Initialize real time user properties NSDictionary
    if (self.realTimeUserProperties == nil) {
        self.realTimeUserProperties = [NSMutableDictionary dictionary];
    }

    // Read content of properties file and update real time user properties if signature valid
    NSData *content = [self.realTimeUserPropertiesFile readWithRespectToPlatform];

    if (content != nil) {
        NSError *error = nil;
        NSDictionary *realtimeUserProperties = [NSJSONSerialization JSONObjectWithData:content options:NSJSONReadingMutableContainers error:&error];
        if (!error) {
            self.realTimeUserProperties = [realtimeUserProperties mutableCopy];
        }
    } else {
        [self invalidateETag];
    }
}

- (void)updateRealTimeUserProperties:(NSDictionary *)realTimeUserPropertiesJson writeToCache:(BOOL)writeToCache {
    self.realTimeUserProperties = [realTimeUserPropertiesJson mutableCopy];
    
    if (writeToCache) {
        NSData *propertiesData = [NSJSONSerialization dataWithJSONObject:realTimeUserPropertiesJson options:0 error:nil];
        [self.realTimeUserPropertiesFile writeWithRespectToPlatform:propertiesData];
    }
}

enum HttpStatus {
    HTTP_SUCCESS,
    HTTP_REDIRECTION,
    HTTP_CLIENT_ERROR,
    HTTP_SERVER_ERROR
};

- (enum HttpStatus)httpStatusFromResponse:(NSHTTPURLResponse *)httpResponse {
    long code = [httpResponse statusCode];

    if (code < 300) {
        return HTTP_SUCCESS;
    }

    if (code < 400) {
        return HTTP_REDIRECTION;
    }

    if (code < 500) {
        return HTTP_CLIENT_ERROR;
    }

    // 500+
    return HTTP_SERVER_ERROR;
}

- (NSOutputStream *)createEventfile:(int)mode {
    // If the file already exists, close it.
    if ([self eventStream]) {
        [[self eventStream] close];
    }

    NSOutputStream *newFile = NULL;
    NSURL *filePath = [self eventFilename];
    switch (mode) {
        case SWRVE_TRUNCATE_FILE:
            newFile = [NSOutputStream outputStreamWithURL:filePath append:NO];
            break;

        case SWRVE_APPEND_TO_FILE:
            newFile = [NSOutputStream outputStreamWithURL:filePath append:YES];
            break;

        case SWRVE_TRUNCATE_IF_TOO_LARGE: {
            NSData *cacheContent = [NSData dataWithContentsOfURL:filePath];

            if (cacheContent == nil) {
                newFile = [NSOutputStream outputStreamWithURL:filePath append:NO];
            } else {
                NSUInteger cacheLength = [cacheContent length];
                if (cacheLength < SWRVE_DISK_MAX_BYTES) {
                    newFile = [NSOutputStream outputStreamWithURL:filePath append:YES];
                } else {
                    newFile = [NSOutputStream outputStreamWithURL:filePath append:NO];
                    DebugLog(@"Swrve log file too large (%lu)... truncating", (unsigned long) cacheLength);
                }
            }

            break;
        }
    }

    [newFile open];

    return newFile;
}

- (void)eventsSentCallback:(enum HttpStatus)status withData:(NSData *)data andContext:(SwrveSendContext *)client_info withSwrveUserId:(NSString *)swrveUserIdForEventsSent {
#pragma unused(data)
    Swrve *swrve = [client_info swrveReference];
    if ([[SwrveInstanceIDRecorder sharedInstance] hasSwrveInstanceID:[client_info swrveInstanceID]] == YES) {

        switch (status) {
            case HTTP_REDIRECTION:
            case HTTP_SUCCESS:
                DebugLog(@"Success sending events to Swrve", nil);
                break;
            case HTTP_CLIENT_ERROR:
                DebugLog(@"HTTP Error - not adding events back into the queue: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                break;
            case HTTP_SERVER_ERROR:
                DebugLog(@"Error sending event data to Swrve (%@) Adding data back onto unsent message buffer", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

                // Edge case check, in case user id changed in identity call before this callback completed
                NSString *currentSwrveUserId = [swrve userID];
                if (![currentSwrveUserId isEqualToString:swrveUserIdForEventsSent]) {
                    // Write the events back to the user cache file
                    NSString *eventCacheFile = [SwrveLocalStorage eventsFilePathForUserId:swrveUserIdForEventsSent];
                    NSURL *file = [NSURL fileURLWithPath:eventCacheFile];
                    NSOutputStream *stream = [NSOutputStream outputStreamWithURL:file append:YES];

                    if (stream != nil && [[client_info buffer] count] > 0) {
                        [stream open];
                        NSString *json = [self copyBufferToJson:[client_info buffer]];
                        json = [json stringByAppendingString:@",\n"];
                        NSData *bufferJson = [json dataUsingEncoding:NSUTF8StringEncoding];
                        long bytes = [stream write:(const uint8_t *) [bufferJson bytes] maxLength:[bufferJson length]];
                        if (bytes == 0) {
                            DebugLog(@"Nothing was written to the event file");
                        } else if (bytes < 0) {
                            DebugLog(@"Error, could not write events to disk");
                        } else {
                            DebugLog(@"Written to the event file");
                        }
                        [stream close];
                    }
                } else {
                    // Add events back to buffer and save to cache file for current swrve user
                    NSMutableArray *buffer = swrve.eventBuffer;
                    @synchronized (buffer) {
                        if (buffer) {
                            [buffer addObjectsFromArray:[client_info buffer]];
                        }
                    }
                    [swrve setEventBufferBytes:swrve.eventBufferBytes + [client_info bufferLength]];
                    [swrve saveEventsToDisk];
                }

                break;
        }
    }
}

// Convert the array of strings into a json array.
// This does not add the square brackets.
- (NSString *)copyBufferToJson:(NSArray *)buffer {
    @synchronized (buffer) {
        return [buffer componentsJoinedByString:@",\n"];
    }
}

- (NSString *)createJSON:(NSString *)sessionToken events:(NSString *)rawEvents {
    NSString *eventArray = [NSString stringWithFormat:@"[%@]", rawEvents];
    NSData *bodyData = [eventArray dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *body = [NSJSONSerialization
            JSONObjectWithData:bodyData
                       options:NSJSONReadingMutableContainers
                         error:nil];

    NSMutableDictionary *jsonPacket = [[NSMutableDictionary alloc] init];
    [jsonPacket setValue:self.userID forKey:@"user"];
    [jsonPacket setValue:self.deviceUUID forKey:@"unique_device_id"];
    [jsonPacket setValue:[NSNumber numberWithInt:SWRVE_VERSION] forKey:@"version"];
    [jsonPacket setValue:NullableNSString(self.appVersion) forKey:@"app_version"];
    [jsonPacket setValue:NullableNSString(sessionToken) forKey:@"session_token"];
    [jsonPacket setValue:body forKey:@"data"];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonPacket options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    return json;
}

- (NSInteger)nextEventSequenceNumber {
    NSInteger seqno;
    @synchronized (self) {
        // Defaults to 0 if this value is not available
        NSString *seqNumKey = [[profileManager userId] stringByAppendingString:@"swrve_event_seqnum"];
        seqno = [SwrveLocalStorage seqNumWithCustomKey:seqNumKey];
        seqno += 1;
        [SwrveLocalStorage saveSeqNum:seqno withCustomKey:seqNumKey];
    }

    return seqno;
}

- (void)eventFileSentCallback:(enum HttpStatus)status withData:(NSData *)data andContext:(SwrveSendEventfileContext *)context {
#pragma unused(data)
    Swrve *swrve = [context swrveReference];
    if ([[SwrveInstanceIDRecorder sharedInstance] hasSwrveInstanceID:[context swrveInstanceID]] == YES) {
        int mode = SWRVE_TRUNCATE_FILE;

        switch (status) {
            case HTTP_SUCCESS:
            case HTTP_CLIENT_ERROR:
            case HTTP_REDIRECTION:
                DebugLog(@"Received a valid HTTP POST response. Truncating event log file", nil);
                break;
            case HTTP_SERVER_ERROR:
                DebugLog(@"Error sending log file - reopening in append mode: status", nil);
                mode = SWRVE_APPEND_TO_FILE;
                break;
        }

        // close, truncate and re-open the file.
        [swrve setEventStream:[swrve createEventfile:mode]];
    }
}

- (bool)eventFileHasData {
    NSData *cacheContent = [NSData dataWithContentsOfURL:[self eventFilename]];
    return [cacheContent length] > 0;
}

- (void)sendEventfile {
    [self sendEventfile:nil];
}

- (void)sendEventfile:(void (^)(NSURLResponse *response, NSData *data, NSError *error))eventFileCallback {

    if (![self eventStream]) {
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }
    if (![self eventFileHasData]) {
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }

    // Close the write stream and set it to null
    // No more appending will happen while it is null
    [[self eventStream] close];
    [self setEventStream:NULL];

    NSMutableData *contents = [[NSMutableData alloc] initWithContentsOfURL:[self eventFilename]];
    if (contents == nil) {
        [self resetEventCache];
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }

    const NSUInteger length = [contents length];
    if (length <= 2) {
        [self resetEventCache];
        if (eventFileCallback != nil) {
            eventFileCallback(nil, nil, nil);
        }
        return;
    }

    // Remove trailing comma
    [contents setLength:[contents length] - 2];
    NSString *file_contents = [[NSString alloc] initWithData:contents encoding:NSUTF8StringEncoding];
    NSString *json_string = [self createJSON:[self sessionToken] events:file_contents];
    NSData *json_data = [json_string dataUsingEncoding:NSUTF8StringEncoding];

    [restClient sendHttpPOSTRequest:[self batchURL]
                           jsonData:json_data
                  completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                      SwrveSendEventfileContext *eventFileContext = [[SwrveSendEventfileContext alloc] init];
                      [eventFileContext setSwrveReference:self];
                      [eventFileContext setSwrveInstanceID:self->instanceID];

                      if (error) {
                          DebugLog(@"Error opening HTTP stream when sending the contents of the log file", nil);
                          [self eventFileSentCallback:HTTP_SERVER_ERROR withData:data andContext:eventFileContext]; //HTTP 503 Error, service not available
                          if (eventFileCallback != nil) {
                              eventFileCallback(response, data, error);
                          }
                          return;
                      }

                      enum HttpStatus status = HTTP_SUCCESS;
                      if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                          status = [self httpStatusFromResponse:(NSHTTPURLResponse *) response];
                      }
                      [self eventFileSentCallback:status withData:data andContext:eventFileContext];
                      if (eventFileCallback != nil) {
                          eventFileCallback(response, data, error);
                      }
                  }];
}

- (void)resetEventCache {
    [self setEventStream:[self createEventfile:SWRVE_TRUNCATE_FILE]];
}

- (void)initBuffer {
    [self setEventBuffer:[[NSMutableArray alloc] initWithCapacity:SWRVE_MEMORY_QUEUE_INITIAL_SIZE]];
    [self setEventBufferBytes:0];
}

- (BOOL)isValidJson:(NSData *)jsonNSData {
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:jsonNSData options:NSJSONReadingMutableContainers error:&err];
    if (err) {
        DebugLog(@"Error with json.\nError:%@", err);
    }
    return obj != nil;
}

- (NSString *)signatureKey {
    return [NSString stringWithFormat:@"%@%llu", self.apiKey, self->appInstallTimeSeconds];
}

- (void)signatureError:(NSURL *)file {
#pragma unused(file)
    DebugLog(@"Signature check failed for file %@", file);
    [self eventInternal:@"Swrve.signature_invalid" payload:nil triggerCallback:false];
}

- (void)initResourcesDiff {

    SwrveSignatureProtectedFile *file = [self signatureFileWithType:SWRVE_RESOURCE_DIFF_FILE errorDelegate:self];
    [self setResourcesDiffFile:file];
}

- (void)userResources:(SwrveUserResourcesCallback)callbackBlock {
    if (![self sdkReady]) {
        return;
    }
    NSCAssert(callbackBlock, @"getUserResources: callbackBlock must not be nil.", nil);
    NSDictionary *resourcesDict = [self resourceManager].resources;
    NSMutableString *jsonString = [[NSMutableString alloc] initWithString:@"["];
    BOOL first = YES;
    for (NSString *resourceName in resourcesDict) {
        if (!first) {
            [jsonString appendString:@","];
        }
        first = NO;

        NSDictionary *resource = [resourcesDict objectForKey:resourceName];
        NSData *resourceData = [NSJSONSerialization dataWithJSONObject:resource options:0 error:nil];
        [jsonString appendString:[[NSString alloc] initWithData:resourceData encoding:NSUTF8StringEncoding]];
    }
    [jsonString appendString:@"]"];

    if (callbackBlock != nil) {
        @try {
            callbackBlock(resourcesDict, jsonString);
        }
        @catch (NSException *e) {
            DebugLog(@"Exception in userResources callback. %@", e);
        }
    }
}

- (void)userResourcesDiff:(SwrveUserResourcesDiffCallback)callbackBlock {
    if (![self sdkReady]) {
        return;
    }
    NSCAssert(callbackBlock, @"getUserResourcesDiff: callbackBlock must not be nil.", nil);
    NSURL *url = [self userResourcesDiffURL];
    [restClient sendHttpGETRequest:url completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSData *resourcesDiffCacheContent = [[self resourcesDiffFile] readWithRespectToPlatform];

        if (!error) {
            enum HttpStatus status = HTTP_SUCCESS;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [self httpStatusFromResponse:(NSHTTPURLResponse *) response];
            }

            if (status == SWRVE_SUCCESS) {
                if ([self isValidJson:data]) {
                    resourcesDiffCacheContent = data;
                    [self.resourcesDiffFile writeWithRespectToPlatform:data];

                } else {
                    DebugLog(@"Invalid JSON received for user resources diff", nil);
                }
            }
        }

        // At this point the cached content has been updated with the http response if a valid response was received
        // So we can call the callbackBlock with the cached content
        @try {
            NSArray *resourcesArray = [NSJSONSerialization JSONObjectWithData:resourcesDiffCacheContent options:NSJSONReadingMutableContainers error:nil];

            NSMutableDictionary *oldResourcesDict = [[NSMutableDictionary alloc] init];
            NSMutableDictionary *newResourcesDict = [[NSMutableDictionary alloc] init];

            for (NSDictionary *resourceObj in resourcesArray) {
                NSString *itemName = [resourceObj objectForKey:@"uid"];
                NSDictionary *itemDiff = [resourceObj objectForKey:@"diff"];

                NSMutableDictionary *oldValues = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *newValues = [[NSMutableDictionary alloc] init];

                for (NSString *propertyKey in itemDiff) {
                    NSDictionary *propertyVals = [itemDiff objectForKey:propertyKey];
                    [oldValues setObject:[propertyVals objectForKey:@"old"] forKey:propertyKey];
                    [newValues setObject:[propertyVals objectForKey:@"new"] forKey:propertyKey];
                }

                [oldResourcesDict setObject:oldValues forKey:itemName];
                [newResourcesDict setObject:newValues forKey:itemName];
            }

            NSString *jsonString = [[NSString alloc] initWithData:resourcesDiffCacheContent encoding:NSUTF8StringEncoding];
            callbackBlock(oldResourcesDict, newResourcesDict, jsonString);
        }
        @catch (NSException *e) {
            DebugLog(@"Exception in userResourcesDiff callback. %@", e);
        }
    }];
}

- (NSURL *)userResourcesDiffURL {
    NSURL *base_content_url = [NSURL URLWithString:self.config.contentServer];
    NSURL *resourcesDiffURL = [NSURL URLWithString:@"api/1/user_resources_diff" relativeToURL:base_content_url];
    UInt64 joinedDateMilliSeconds = [self joinedDateMilliSeconds];
    NSString *queryString = [NSString stringWithFormat:@"user=%@&api_key=%@&app_version=%@&joined=%llu",
                                                       self.userID, self.apiKey, self.appVersion, joinedDateMilliSeconds];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"?%@", queryString] relativeToURL:resourcesDiffURL];
    return url;
}

- (void) realTimeUserProperties:(SwrveRealTimeUserPropertiesCallback)callbackBlock {
    if (![self sdkReady]) {
        return;
    }

    NSCAssert(callbackBlock, @"realTimeUserProperties: callbackBlock must not be nil.", nil);
    if (callbackBlock != nil) {
        @try {
            callbackBlock(self.realTimeUserProperties);
        }
        @catch (NSException *e) {
            DebugLog(@"Exception in realtimeUserProperies callback. %@", e);
        }
    }
}

// Overwritten for unit tests
- (NSDate *)getNow {
    return [NSDate date];
}

- (SwrveSignatureProtectedFile *)signatureFileWithType:(int)type errorDelegate:(id <SwrveSignatureErrorDelegate>)delegate {

    SwrveSignatureProtectedFile *file = [[SwrveSignatureProtectedFile alloc] protectedFileType:type
                                                                                        userID:self.profileManager.userId
                                                                                  signatureKey:[self signatureKey]
                                                                                 errorDelegate:delegate];

    return file;
}

- (SwrveMessageController *)messagingController {

    return self.messaging;
}

- (void)initSwrveDeeplinkManager {
    if (self.swrveDeeplinkManager == nil) {
        self.swrveDeeplinkManager = [[SwrveDeeplinkManager alloc] initWithSwrve:self];
    }
}

- (void)handleDeeplink:(NSURL *)url {
    if (![self sdkReady]) {
        return;
    }
    if (![SwrveDeeplinkManager isSwrveDeeplink:url]) {
        return;
    }
    [self initSwrveDeeplinkManager];
    [self.swrveDeeplinkManager handleDeeplink:url];
}

- (void)handleDeferredDeeplink:(NSURL *)url {
    if (![self sdkReady]) {
        return;
    }
    if (![SwrveDeeplinkManager isSwrveDeeplink:url]) {
        return;
    }
    [self initSwrveDeeplinkManager];
    [self.swrveDeeplinkManager handleDeferredDeeplink:url];
}

- (void)installAction:(NSURL *)url {
    if (![self sdkReady]) {
        return;
    }
    if (![SwrveDeeplinkManager isSwrveDeeplink:url]) {
        return;
    }
    [self initSwrveDeeplinkManager];
    self.swrveDeeplinkManager.actionType = SWRVE_AD_INSTALL;
}

- (void)handleNotificationToCampaign:(NSString *)campaignId {

    if ([config initMode] == SWRVE_INIT_MODE_MANAGED && ![config managedModeAutoStartLastUser]) {
        DebugLog(@"Warning: SwrveSDK Push to IAM/Conv cannot execute in MANAGED mode and managedModeAutoStartLastUser==false.", nil);
        return;
    }
    [self initSwrveDeeplinkManager];
    [self.swrveDeeplinkManager handleNotificationToCampaign:campaignId];
}

- (id <SwrvePermissionsDelegate>)permissionsDelegate {
    return self.config.permissionsDelegate;
}

- (NSString *)userID {
    return self.profileManager.userId;
}

- (NSString *)sessionToken {
    return self.profileManager.sessionToken;
}

#pragma mark  Switch User ID

- (void)switchUser:(NSString *)newUserID isFirstSession:(BOOL)isFirstSession  {

    // dont do anything if the current user is the same as the new one and its already been started
    if ((newUserID == nil) || (sdkStarted == true && [newUserID isEqualToString:self.profileManager.userId])) {
        [self enableEventSending];
        [self queuePausedEventsArray];
        return;
    }

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    [SwrveNotificationManager clearAllAuthenticatedNotifications];
#endif //!defined(SWRVE_NO_PUSH)

    // update SwrveProfileManager
    [self.profileManager switchUser:newUserID];
    [self.profileManager persistUser];

    [self initWithUserId:newUserID];
    [self queuePausedEventsArray];

    if (!isFirstSession) {
        //this will prevent the Swrve.first_session event from been queued in the beginSession call below
        [profileManager setIsNewUser:false];
    }

    [self beginSession];
}

- (void)identify:(NSString *)externalUserId onSuccess:(void (^)(NSString *status, NSString *swrveUserId))onSuccess
         onError:(void (^)(NSInteger httpCode, NSString *errorMessage))onError {

    if (self.config.initMode == SWRVE_INIT_MODE_MANAGED) {
        [self throwIllegalOperationException:@"Cannot call identify api in MANAGED initMode."];
    }

    if (externalUserId == nil || [externalUserId isEqualToString:@""]) {
        DebugLog(@"Swrve identify: External user id cannot be nil or empty", nil);
        if (onError != nil) {
            onError(-1, @"External user id cannot be nil or empty");
        }
        return;
    }

    DebugLog(@"Swrve identify: Pausing event queuing and sending prior to Identity API call...", nil);
    [self pauseEventSending];

    dispatch_group_t sendEventsCallback = dispatch_group_create();

    DebugLog(@"Swrve identify: Flushing event buffer and cache prior to Identity API call...", nil);
    // this will force flush events even though event sending and queuing has been paused above
    [self forceFlushAllEvents:sendEventsCallback];

    // this code should only execute after the 2 callbacks in flushAllEventsBeforeIdentify complete
    dispatch_group_notify(sendEventsCallback, dispatch_get_main_queue(), ^{

        SwrveUser *cachedSwrveUser = [self.profileManager swrveUserWithId:externalUserId];

        if ([self identifyCachedUser:cachedSwrveUser withCallback:onSuccess]) {
            return;
        }

        [self identifyUnknownUserWithExternalId:externalUserId
                                  andCachedUser:cachedSwrveUser
                                      onSuccess:onSuccess
                                        onError:onError];

    });
}

- (void)forceFlushAllEvents:(dispatch_group_t)sendEventsCallbackGroup {

    dispatch_group_enter(sendEventsCallbackGroup);
    dispatch_group_enter(sendEventsCallbackGroup);

    [self sendQueuedEventsWithCallback:^(NSURLResponse *response, NSData *data, NSError *error) {
#pragma unused(response, data, error)
        dispatch_group_leave(sendEventsCallbackGroup);
    }                eventFileCallback:^(NSURLResponse *response, NSData *data, NSError *error) {
#pragma unused(response, data, error)
        dispatch_group_leave(sendEventsCallbackGroup);
    } forceFlush:true];
}

- (BOOL)identifyCachedUser:(SwrveUser *)cachedSwrveUser withCallback:(void (^)(NSString *status, NSString *swrveUserId))onSuccess {
    BOOL isVerified = NO;
    if (cachedSwrveUser != nil && cachedSwrveUser.verified) {
        DebugLog(@"Swrve identify: Identity API call skipped, user loaded from cache. Event sending reenabled.", nil);
        [self switchUser:cachedSwrveUser.swrveId isFirstSession:false];

        if (onSuccess != nil) {
            onSuccess(@"Identity API call skipped, user loaded from cache", cachedSwrveUser.swrveId);
        }
        isVerified = YES;
    }
    return isVerified;
}

- (void)identifyUnknownUserWithExternalId:(NSString *)externalUserId
                            andCachedUser:(SwrveUser *)cachedSwrveUser
                                onSuccess:(void (^)(NSString *status, NSString *swrveUserId))onSuccess
                                  onError:(void (^)(NSInteger httpCode, NSString *errorMessage))onError {

    NSString *unidentifiedSwrveId = [self unidentifiedUserIdFromExternalId:externalUserId andCachedUser:cachedSwrveUser];

    // being cautious here and clearing the buffer in case any events got in there
    [[self eventBuffer] removeAllObjects];

    [self.profileManager identify:externalUserId swrveUserId:unidentifiedSwrveId onSuccess:^(NSString *status, NSString *swrveUserId) {
#pragma unused(status)
        DebugLog(@"Swrve identify: Identity service success: %@", status);

        //update the swrve user in cache
        [self.profileManager updateSwrveUserWithId:swrveUserId externalUserId:externalUserId];

        bool isFirstSession = [unidentifiedSwrveId isEqualToString:swrveUserId];

        [self switchUser:swrveUserId isFirstSession:isFirstSession];

        if (onSuccess != nil) {
            onSuccess(status, swrveUserId);
        }

    }                     onError:^(NSInteger httpCode, NSString *errorMessage) {
#pragma unused(errorMessage)
        DebugLog(@"Swrve identify: Identity service returned %li error message: %@", (long) httpCode, errorMessage);

        [self switchUser:unidentifiedSwrveId isFirstSession:true];

        if (httpCode == 403) {
            [self.profileManager removeSwrveUserWithId:externalUserId];
        }

        if (onError != nil) {
            onError(httpCode, errorMessage);
        }
    }];
}

- (NSString *)unidentifiedUserIdFromExternalId:(NSString *)externalUserId andCachedUser:(SwrveUser *)cachedSwrveUser {
    NSString *swrveId;
    if (cachedSwrveUser == nil) {
        // if the current swrve user id hasn't already been used, we can use it
        SwrveUser *existingUser = [self.profileManager swrveUserWithId:self.userID];
        swrveId = (existingUser == nil) ? self.userID : [[NSUUID UUID] UUIDString];

        // save unverified user
        SwrveUser *unVerifiedUser = [[SwrveUser alloc] initWithExternalId:externalUserId swrveId:swrveId verified:false];
        [self.profileManager saveSwrveUser:unVerifiedUser];

    } else {
        swrveId = cachedSwrveUser.swrveId; // a previous identify call didn't complete so user has been cached and is unverified
    }
    return swrveId;
}

- (void)queuePausedEventsArray {
    for (SwrveEventQueueItem *queueItem in self.pausedEventsArray) {
        [self queueEvent:queueItem.eventType data:queueItem.eventData triggerCallback:queueItem.triggerCallback notifyMessageController:queueItem.notifyMessageController];
    }
    if ([self.pausedEventsArray count] > 0) {
        [self sendQueuedEvents];
    }
    [self.pausedEventsArray removeAllObjects];
}

- (void)enableEventSending {
    DebugLog(@"Swrve: Event sending reenabled", nil);
    trackingState = ON;
    [self resumeCampaignsAndResourcesTimer];
}

- (void)pauseEventSending {
    trackingState = EVENT_SENDING_PAUSED;
    [self stopCampaignsAndResourcesTimer];
}

- (NSString *)externalUserId {
    if (![self sdkReady]) {
        return @"";
    }
    SwrveUser *swrveUser =  [self.profileManager swrveUserWithId:self.userID];
    return (swrveUser == nil) ? @"" : swrveUser.externalId;
}

- (double)flushRefreshDelay {
    double flushRefreshDelay = [SwrveLocalStorage flushDelay];
    if (flushRefreshDelay <= 0) {
        flushRefreshDelay = SWRVE_DEFAULT_CAMPAIGN_RESOURCES_FLUSH_REFRESH_DELAY / 1000;
    }
    return flushRefreshDelay;
}

- (void)fetchNotificationCampaigns:(NSMutableSet *)campaignIds {
    [self initSwrveDeeplinkManager];
    [self.swrveDeeplinkManager fetchNotificationCampaigns:campaignIds];
}

- (void)setSwrveSessionDelegate:(id <SwrveSessionDelegate>)swrveSessionDelegate {
    sessionDelegate = swrveSessionDelegate;
}

- (void)executeSessionStartedDelegate {
    if (sessionDelegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self -> sessionDelegate sessionStarted];
        });
    }
}

- (void)setCustomPayloadForConversationInput:(NSMutableDictionary *)payload {
    if (![self sdkReady]) {
        return;
    }
    [SwrveConversationEvents setCustomPayload:payload];
}

- (void)start {
    [self startWithUserId:self.userID];
}

- (void)startWithUserId:(NSString *)userId {
    if (self.config.initMode == SWRVE_INIT_MODE_AUTO) {
        [self throwIllegalOperationException:@"Cannot call start api in SWRVE_INIT_MODE_AUTO initMode."];
    }

    if (userId == nil) {
        userId = self.profileManager.userId;
    }

    DebugLog(@"Swrve startWithUserId: Pausing event queuing and sending prior to changing user...", nil);
    [self pauseEventSending];

    dispatch_group_t sendEventsCallback = dispatch_group_create();

    // this will force flush events even though event sending and queuing has been paused above
    DebugLog(@"Swrve startWithUserId: Flushing event buffer and cache prior to changing user...", nil);
    [self forceFlushAllEvents:sendEventsCallback];

    // this code should only execute after the 2 callbacks in flushAllEvents complete
    dispatch_group_notify(sendEventsCallback, dispatch_get_main_queue(), ^{

        [self registerLifecycleCallbacks];

        // If join time for the user is zero then its the first time this userId has been on this device so send first session event
        BOOL isFirstSession = [SwrveLocalStorage userJoinedTimeSeconds:userId] == 0;
        [self switchUser:userId isFirstSession:isFirstSession];
    });
}

- (BOOL)started {
    return sdkStarted;
}

- (BOOL)sdkReady {
    if (([config initMode] == SWRVE_INIT_MODE_MANAGED) && [self started] == NO) {
        DebugLog(@"Warning: SwrveSDK needs to be started in MANAGED mode before calling this api.", nil);
        return NO;
    } else {
        return YES;
    }
}

- (SwrveMessageController *)messaging {
    if (![self sdkReady]) {
        messaging = [SwrveMessageController new];
    }
    return messaging;
}

- (SwrveResourceManager *)resourceManager {
    if (![self sdkReady]) {
        resourceManager = [SwrveResourceManager new];
    }
    return resourceManager;
}

- (void)throwIllegalOperationException:(NSString *) reason {
    NSException *e = [NSException
                      exceptionWithName:@"SwrveIllegalOperation"
                      reason:reason
                      userInfo:nil];
    @throw e;
}

@end
