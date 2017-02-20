#import "NSError+GSError.h"

@implementation NSError (GSError)

+ (NSError *)errorWithGigyaResponse:(GSResponse *)response
{
    NSError *result = nil;

    if (response.errorCode != 0)
    {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        
        if (response[@"errorMessage"])
            dict[NSLocalizedDescriptionKey] = response[@"errorMessage"];

        if ([response callId])
            dict[@"callId"] = [response callId];
        
        if (response[@"errorDetails"])
            dict[@"details"] = response[@"errorDetails"];
        
        result = [NSError errorWithDomain:GSGigyaSDKDomain
                                     code:response.errorCode
                                 userInfo:dict];
    }
    
    return result;
}

+ (NSError *)errorWithGigyaLoginResponse:(NSDictionary *)errorQueryParams
{
    NSError *error = nil;
    NSString *description = [errorQueryParams[@"error_description"] stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    NSMutableDictionary *errorInfo = [NSMutableDictionary dictionary];
    
    for (NSString *key in errorQueryParams.allKeys) {
        if (![key isEqual:@"error_description"]) {
            NSString *destKey = key;
            
            if ([key rangeOfString:@"x_"].location == 0) {
                destKey = [key substringWithRange:NSMakeRange(2, [key length] - 2)];
            }
            
            errorInfo[destKey] = errorQueryParams[key];
        }
    }
    
    if (description) {
        NSArray *errorComponents = [description componentsSeparatedByString:@" - "];
        errorInfo[NSLocalizedDescriptionKey] = errorComponents[1];
        
        if ([errorComponents count] > 1) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:[errorComponents[0] intValue]
                                    userInfo:errorInfo];
        }
    }
    
    if (!error) {
        errorInfo[NSLocalizedDescriptionKey] = @"Login has failed";
        error = [NSError errorWithDomain:GSGigyaSDKDomain
                                    code:GSErrorServerLoginFailure
                                userInfo:errorInfo];
    }
    
    return error;
}

+ (NSError *)errorWithGigyaPluginEvent:(NSDictionary *)event
{
    NSError *result = nil;
    
    if (event[@"errorCode"])
    {
        
        NSMutableDictionary *dict = [@{ NSLocalizedDescriptionKey: event[@"errorMessage"] } mutableCopy];
        
        NSMutableDictionary *mutableEvent = [event mutableCopy];
        [mutableEvent removeObjectsForKeys:@[ @"errorMessage", @"errorCode" ]];
        [dict addEntriesFromDictionary:mutableEvent];
        
        result = [NSError errorWithDomain:GSGigyaSDKDomain
                                     code:[event[@"errorCode"] intValue]
                                 userInfo:dict];
    }
    
    return result;

}

// For serializing NSError to JSON
- (NSMutableDictionary *)GSDictionaryRepresentation
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"errorCode"] = @(self.code);
    dict[@"errorMessage"] = (self.userInfo)[NSLocalizedDescriptionKey];
    
    NSMutableDictionary *details = [self.userInfo mutableCopy];
    NSError *underlyingError = details[NSUnderlyingErrorKey];

    if (underlyingError)
        details[NSUnderlyingErrorKey] = [underlyingError description];
    
    dict[@"errorDetails"] = [details description];
    
    NSString *regToken = [self userInfo][@"regToken"];
    if (regToken)
        dict[@"regToken"] = regToken;
    
    return dict;
}

@end
