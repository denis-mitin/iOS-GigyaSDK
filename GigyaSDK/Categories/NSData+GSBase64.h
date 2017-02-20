#import <Foundation/Foundation.h>

@interface NSData (GSBase64)

+ (NSData *)GSDataFromBase64String:(NSString *)base64String;
- (NSString *)GSBase64SEncodedString;

@end
