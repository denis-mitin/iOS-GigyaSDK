#import "NSDictionary+GSDictionary.h"
#import "NSString+GSString.h"

@implementation NSDictionary (GSDictionary)

- (NSString *)GSJSONString
{
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self
                                                       options:0
                                                         error:nil];
    NSString *result = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    return result;
}

- (NSString *)GSURLQueryString
{
    NSMutableString *result = [@"" mutableCopy];
    
    // Sorting the keys
    NSArray *sortedKeys = [[self allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    // Going over the parameters and adding them
    for (NSString *key in sortedKeys) {
        id value = self[key];
        
        if ([value respondsToSelector:@selector(GSJSONString)]) {
            value = [value GSJSONString];
        }
        
        NSString *valueString = [NSString stringWithFormat:@"%@", value];
        [result appendFormat:@"&%@=%@", key, [valueString GSURLEncodedString]];
    }
    
    if ([result length] > 0)
        [result deleteCharactersInRange:NSMakeRange(0, 1)];
    
    return result;
}

+ (NSMutableDictionary *)GSDictionaryWithURLQueryString:(NSString *)queryString
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // Getting the seperate key-value strings
    NSArray *params = [queryString componentsSeparatedByString:@"&"];
    
    // Adding each key-value to the dictionary
    for (NSString *param in params) {
        if ([param length] > 0) {
            NSArray *keyValue = [param componentsSeparatedByString:@"="];
            NSString *key = keyValue[0];
            NSString *value = [keyValue[1] GSURLDecodedString];
            result[key] = value;
        }
    }
    
    return result;
}

@end