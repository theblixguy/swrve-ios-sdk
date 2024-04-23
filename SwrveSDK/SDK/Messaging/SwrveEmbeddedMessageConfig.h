#import <Foundation/Foundation.h>
#import "SwrveEmbeddedMessage.h"

@interface SwrveEmbeddedMessageConfig : NSObject

/*! A block that will be called when an event triggers a control embedded message.
 * \param message the SwrveEmbeddedMessage object
 * \param personalizationProperties custom properties which are used for personalization.
 * \param isControl Flag to determine if control or treatment message. If control this message should not be shown to users.
 */
typedef void (^SwrveEmbeddedCallback)(SwrveEmbeddedMessage *message, NSDictionary *personalizationProperties, bool isControl);

@property(nonatomic, copy) SwrveEmbeddedCallback embeddedCallback; /*!< Implement this delegate to implement embedded messages. If control message it should not be shown to user*/
@end
