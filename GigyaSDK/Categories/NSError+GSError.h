#import <Foundation/Foundation.h>
#import "Gigya.h"

@interface NSError (GSError)

+ (NSError *)errorWithGigyaResponse:(GSResponse *)response;
+ (NSError *)errorWithGigyaLoginResponse:(NSDictionary *)errorQueryParams;
+ (NSError *)errorWithGigyaPluginEvent:(NSDictionary *)event;
- (NSMutableDictionary *)GSDictionaryRepresentation;

@end
