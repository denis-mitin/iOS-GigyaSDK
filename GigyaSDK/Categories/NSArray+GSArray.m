#import "NSArray+GSArray.h"

@implementation NSArray (GSArray)

- (NSString *)GSJSONString
{
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self
                                                       options:0
                                                         error:nil];
    NSString *result = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    return result;
}

@end
