#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SwrveInAppMessageDelegate.h"
#if TARGET_OS_TV
#import "SwrveInAppMessageFocusDelegate.h"
#endif

#if __has_include(<SwrveSDKCommon/SwrveInAppCapabilitiesDelegate.h>)
#import <SwrveSDKCommon/SwrveInAppCapabilitiesDelegate.h>
#else
#import "SwrveInAppCapabilitiesDelegate.h"
#endif

/*! A block that will be called when an event triggers an in-app message with personalization
 * \param eventPayload the payload associated with the message
 * \returns NSDictionary of key / value strings used for personalising the IAM
 */
typedef NSDictionary *(^SwrveMessagePersonalizationCallback)(NSDictionary *eventPayload);

@interface SwrveInAppMessageConfig : NSObject

/*! in-app background color used for the area behind the message */
@property (nonatomic, retain) UIColor *backgroundColor;

/*! By default Swrve will choose the status bar appearance
 * when presenting any In-app view Incontrollers.
 * You can disable this functionality by setting
 * prefersIAMStatusBarHidden to false.
 */
@property (nonatomic) BOOL prefersStatusBarHidden;

/*! in-app background color used for all personalized text, can be overridden by server value */
@property (nonatomic, retain) UIColor *personalizationBackgroundColor;

/*! in-app text color used for all personalized text, can be overridden by server value */
@property (nonatomic, retain) UIColor *personalizationForegroundColor;

/*! in-app text font used for all personalized text, can be overridden by server value */
@property (nonatomic, retain) UIFont *personalizationFont;

/*!< Implement this delegate to intercept IAM calls with personalization . */
@property(nonatomic, copy) SwrveMessagePersonalizationCallback personalizationCallback;

/*! in-app capabilities delegate used by client to notify swrve of capability request and status*/
@property (nonatomic, weak) id <SwrveInAppCapabilitiesDelegate> inAppCapabilitiesDelegate;

/*! in-app message delegate to process certain message actions.*/
@property (nonatomic, weak) id <SwrveInAppMessageDelegate> inAppMessageDelegate;

#if TARGET_OS_TV
/*! in-app message focus delegate to process focus view changes.*/
@property (nonatomic, weak) id <SwrveInAppMessageFocusDelegate> inAppMessageFocusDelegate;
#endif

/*! Custom dismiss button image to use in in-app story campaigns */
@property (nonatomic, retain) UIImage *storyDismissButton;

/*! Custom dismiss button image for highlighted state to use in in-app story campaigns */
@property (nonatomic, retain) UIImage *storyDismissButtonHighlighted;

@end
