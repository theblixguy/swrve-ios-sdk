#import "SwrveInAppMessageConfig.h"

@implementation SwrveInAppMessageConfig

@synthesize backgroundColor;
@synthesize prefersStatusBarHidden;
@synthesize personalizationForegroundColor;
@synthesize personalizationBackgroundColor;
@synthesize personalizationFont;
@synthesize personalizationCallback;
@synthesize inAppCapabilitiesDelegate;
@synthesize inAppMessageDelegate;
#if TARGET_OS_TV
@synthesize inAppMessageFocusDelegate;
#endif
@synthesize storyDismissButton;
@synthesize storyDismissButtonHighlighted;

- (id)init {
    if (self = [super init]) {
        prefersStatusBarHidden = YES;
        self.personalizationForegroundColor = [UIColor blackColor];
        self.personalizationBackgroundColor = [UIColor clearColor];
        self.personalizationFont = [UIFont systemFontOfSize:0];
    }
    return self;
}

@end
