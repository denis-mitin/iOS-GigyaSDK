#import <Foundation/Foundation.h>


@interface NSString (GSString)

- (NSString *)GSURLEncodedString;
- (NSString *)GSURLDecodedString;
+ (NSString *)GSGUIDString;

@end