#import <XCTest/XCTest.h>
#import "SwrveSDK.h"
#import "SwrveNotificationManager.h"
#import <OCMock/OCMock.h>

@interface SwrveNotificationManager()
+ (void)downloadAttachment:(NSString *)mediaUrl withCompletedContentCallback:(void (^)(UNNotificationAttachment *attachment, NSError *error))callback;
@end

@interface SwrvePush()
+ (SwrvePush *)sharedInstance;
- (BOOL)handleAuthenticatedPushNotification:(NSDictionary *)userInfo withCompletionHandler:(void (^)(UIBackgroundFetchResult, NSDictionary *)) completionHandler;
@end

@interface SwrveTestAuthPush : XCTestCase

@end

@implementation SwrveTestAuthPush

- (void)testAuthPushMediaDownloadSucceeds {
    id currentMockCenter = OCMClassMock([UNUserNotificationCenter class]);
    OCMStub([currentMockCenter currentNotificationCenter]).andReturn(currentMockCenter);
    
    id mediaHelperMock = OCMClassMock([SwrveNotificationManager class]);
    OCMStub([mediaHelperMock downloadAttachment:OCMOCK_ANY withCompletedContentCallback:OCMOCK_ANY]).andDo(^(NSInvocation *invoke) {
   
        void (^withCompletedContentCallback)(UNNotificationAttachment *attachment, NSError *error);
        
        NSURL *attachmentURL = [[NSBundle mainBundle] URLForResource:@"logo" withExtension:@"gif"];
        UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:attachmentURL options:nil error:nil];
        
        NSError *mockedError = nil;
        [invoke getArgument:&withCompletedContentCallback atIndex:3];
        withCompletedContentCallback(attachment, mockedError);
    });
    
    id swrvePushMock = OCMPartialMock([SwrvePush sharedInstance]);
    
    [SwrveLocalStorage saveSwrveUserId:@"1234"];
    
    NSDictionary *userInfo = @{
                               @"_p":@"1",
                               @"_aui": @"1234",
                               @"_sw":@{
                                       @"media": @{
                                               @"title": @"rich_title",
                                               @"body":  @"rich_body",
                                               @"subtitle": @"rich_subtitle",
                                               @"url": @"media download will succeed"
                                               }
                                       },
                               @"version": @1
                               };
    
    XCTestExpectation *addNotificationRequest = [self expectationWithDescription:@"addNotificationRequest"];

    void (^addNotificationRequestObserver)(NSInvocation *) = ^(NSInvocation *invoke) {
        __unsafe_unretained UNNotificationRequest * request = nil;
        [invoke getArgument:&request atIndex:2];

        XCTAssertEqualObjects(request.content.userInfo[@"_sw"][@"media"][@"title"],@"rich_title");
        [addNotificationRequest fulfill];
    };
    
    OCMStub([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]).andDo(addNotificationRequestObserver);

    XCTAssertTrue([swrvePushMock handleAuthenticatedPushNotification:userInfo withCompletionHandler:nil]);
    [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
        if (error) {
            XCTFail(@"addNotificationRequest not called");
        }
    }];
    OCMVerify([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]);
    OCMVerifyAll(currentMockCenter);
    [currentMockCenter stopMocking];
}

- (void)testAuthPushCompletionHandlerCallback {
    id currentMockCenter = OCMClassMock([UNUserNotificationCenter class]);
    OCMStub([currentMockCenter currentNotificationCenter]).andReturn(currentMockCenter);
    
    id swrvePushMock = OCMPartialMock([SwrvePush sharedInstance]);
    id mediaHelperMock = OCMClassMock([SwrveNotificationManager class]);
    OCMStub([mediaHelperMock downloadAttachment:OCMOCK_ANY withCompletedContentCallback:OCMOCK_ANY]).andDo(^(NSInvocation *invoke) {

        void (^withCompletedContentCallback)(UNNotificationAttachment *attachment, NSError *error);

        NSURL *attachmentURL = [[NSBundle mainBundle] URLForResource:@"logo" withExtension:@"gif"];
        UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:attachmentURL options:nil error:nil];

        NSError *mockedError = nil;
        [invoke getArgument:&withCompletedContentCallback atIndex:3];
        withCompletedContentCallback(attachment, mockedError);
    });

    [SwrveLocalStorage saveSwrveUserId:@"1234"];
    NSDictionary *userInfo = @{
                               @"_p":@"1",
                               @"_aui": @"1234",
                               @"_sw":@{
                                       @"media": @{
                                               @"title": @"rich_title",
                                               @"body":  @"rich_body",
                                               @"subtitle": @"rich_subtitle",
                                               @"url": @"media download will succeed"
                                               }
                                       },
                               @"version": @1
                               };

    void (^addNotificationRequestObserver)(NSInvocation *) = ^(NSInvocation *invoke) {
        void (^completionHandlerIntercepted)(UIBackgroundFetchResult fetch, NSDictionary *dic);
        [invoke getArgument:&completionHandlerIntercepted atIndex:3];
        
        // Mimic what the inside block of SwrvePush
        completionHandlerIntercepted(UIBackgroundFetchResultNewData, nil);
    };
    
    OCMStub([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]).andDo(addNotificationRequestObserver);
    
    XCTestExpectation *completionHandler = [self expectationWithDescription:@"completionHandler"];
    BOOL isPushHandledBySwrve = [swrvePushMock handleAuthenticatedPushNotification:userInfo withCompletionHandler:^(UIBackgroundFetchResult fetch, NSDictionary *dic) {
        XCTAssertTrue(fetch == UIBackgroundFetchResultNewData);
        XCTAssertEqualObjects(dic, nil);
        [completionHandler fulfill];
    }];

    XCTAssertTrue(isPushHandledBySwrve);
    [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
        if (error) {
            XCTFail(@"completionHandler not called");
        }
    }];

    OCMReject([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]);
    OCMVerifyAll(currentMockCenter);
    [currentMockCenter stopMocking];
}

// Auth push does not suppport fallback text for media, when media download fails, the auth push won't show
- (void)testAuthPushMediaDownloadFails {
    id currentMockCenter = OCMClassMock([UNUserNotificationCenter class]);
    OCMStub([currentMockCenter currentNotificationCenter]).andReturn(currentMockCenter);
    
    XCTestExpectation *mediaFailedDownload = [self expectationWithDescription:@"mediaFailedDownload"];
    
    id mediaHelperMock =  OCMPartialMock([SwrveNotificationManager new]);
    OCMExpect([mediaHelperMock downloadAttachment:OCMOCK_ANY withCompletedContentCallback:OCMOCK_ANY]).andDo(^(NSInvocation *invoke) {
        
        void (^withCompletedContentCallback)(UNNotificationAttachment *attachment, NSError *error);
        //deliberately return no attachement indicating a failure.
        UNNotificationAttachment *attachment = nil;
        NSError *mockedError = nil;
        [invoke getArgument:&withCompletedContentCallback atIndex:3];
        withCompletedContentCallback(attachment, mockedError);
        [mediaFailedDownload fulfill];
    });
    
    id swrvePushMock = OCMPartialMock([SwrvePush sharedInstance]);
    
    [SwrveLocalStorage saveSwrveUserId:@"1234"];
    
    NSDictionary *userInfo = @{
                               @"_p":@"1",
                               @"_aui": @"1234",
                               @"_sw":@{
                                       @"media": @{
                                               @"title": @"rich_title",
                                               @"body":  @"rich_body",
                                               @"subtitle": @"rich_subtitle",
                                               @"url": @"media download will fail"
                                               }
                                       },
                               @"version": @1
                               };

    XCTestExpectation *completionHandler = [self expectationWithDescription:@"completionHandler"];
    BOOL isPushHandledBySwrve = [swrvePushMock handleAuthenticatedPushNotification:userInfo withCompletionHandler:^(UIBackgroundFetchResult fetch, NSDictionary *dic) {
        XCTAssertTrue(fetch == UIBackgroundFetchResultFailed);
        XCTAssertEqualObjects(dic, nil);
        [completionHandler fulfill];
    }];

    XCTAssertTrue(isPushHandledBySwrve);
    if (!isPushHandledBySwrve) {
        XCTFail(@"isPushHandledBySwrve should be true");
    }

    [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
        if (error) {
            XCTFail(@"addNotificationRequest not called");
        }
    }];
    
    OCMReject([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]);
    OCMVerifyAll(currentMockCenter);
    [currentMockCenter stopMocking];
}

- (void)testNotHandlePushAuthDifferentUserId {
    id currentMockCenter = OCMClassMock([UNUserNotificationCenter class]);
    OCMStub([currentMockCenter currentNotificationCenter]).andReturn(currentMockCenter);
    
    id swrvePushMock = OCMPartialMock([SwrvePush sharedInstance]);
    // should not handle the push, different user.
    [SwrveLocalStorage saveSwrveUserId:@"4321"];
    NSDictionary *userInfo = @{
                               @"_p":@"1",
                               @"_aui": @"1234",
                               @"_sw":@{
                                       @"media": @{
                                               @"title": @"rich_title",
                                               @"body":  @"rich_body",
                                               @"subtitle": @"rich_subtitle",
                                               @"url": @"media download will fail"
                                               }
                                       },
                               @"version": @1
                               };

    XCTestExpectation *notHandledPushExpectation = [self expectationWithDescription:@"completionHandler"];
    BOOL isPushHandledBySwrve = [swrvePushMock handleAuthenticatedPushNotification:userInfo withCompletionHandler:^(UIBackgroundFetchResult fetch, NSDictionary *dic) {
        XCTFail(@"completionHandler should not called");
    }];

    XCTAssertFalse(isPushHandledBySwrve);
    if (!isPushHandledBySwrve) {
        [notHandledPushExpectation fulfill];
    }

    [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
        if (error) {
            XCTFail(@"addNotificationRequest not called");
        }
    }];

    OCMReject([currentMockCenter addNotificationRequest:OCMOCK_ANY withCompletionHandler:OCMOCK_ANY]);
    OCMVerifyAll(currentMockCenter);
    [currentMockCenter stopMocking];
}

- (void)testNotHandleAuthPushWithoutSwrveKey {
    id swrvePushMock = OCMPartialMock([SwrvePush sharedInstance]);
    // should not handle the push, missing SwrveNotificationIdentifierKey key.
    [SwrveLocalStorage saveSwrveUserId:@"1234"];
    NSDictionary *userInfo = @{
                               @"_aui": @"1234",
                               @"_sw":@{
                                       @"media": @{
                                               @"title": @"rich_title",
                                               @"body":  @"rich_body",
                                               @"subtitle": @"rich_subtitle",
                                               @"url": @"media download will fail"
                                               }
                                       },
                               @"version": @1
                               };

    XCTestExpectation *notHandledPushExpectation = [self expectationWithDescription:@"completionHandler"];
    BOOL isPushHandledBySwrve = [swrvePushMock handleAuthenticatedPushNotification:userInfo withCompletionHandler:^(UIBackgroundFetchResult fetch, NSDictionary *dic) {
        XCTFail(@"completionHandler should not called");
    }];

    XCTAssertFalse(isPushHandledBySwrve);
    if (!isPushHandledBySwrve) {
        [notHandledPushExpectation fulfill];
    }

    [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
        if (error) {
            XCTFail(@"addNotificationRequest not called");
        }
    }];
}

@end
