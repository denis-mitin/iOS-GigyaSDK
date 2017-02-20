#import <Foundation/Foundation.h>
#import "GSJSONCollection.h"

@interface NSDictionary (GSDictionary) <GSJSONCollection>

- (NSString *)GSURLQueryString;
+ (NSMutableDictionary *)GSDictionaryWithURLQueryString:(NSString *)queryString;

@end
