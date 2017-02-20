#import "Gigya+Internal.h"

@interface GSResponse ()

@property (weak, nonatomic) NSString *method;

@end

@implementation GSResponse

#pragma mark - Initialization methods
+ (void)responseForMethod:(NSString *)method
                     data:(NSData *)data
        completionHandler:(GSResponseHandler)handler
{
    GSResponse *response;
    
    if ([method isEqualToString:@"socialize.getUserInfo"])
        response = [[GSUser alloc] init];
    else
        response = [[GSResponse alloc] init];
    
    [response addJSONData:data];
    response.method = method;
    
    int errorCode = [response[@"errorCode"] intValue];
    
    if (errorCode == GSErrorAccountPendingRegistration && response[@"regToken"]) {
        GSRequest * accountsRequest = [GSRequest requestForMethod:@"accounts.getAccountInfo"
                                                       parameters:@{ @"regToken" : response[@"regToken"] }];
        
        [accountsRequest sendWithResponseHandler:^(GSResponse *accountResponse, NSError *accountError) {
            if (!accountError) {
                if (accountResponse[@"UID"])
                    response[@"UID"] = accountResponse[@"UID"];
                if (accountResponse[@"profile"])
                    response[@"profile"] = accountResponse[@"profile"];
                if (accountResponse[@"data"])
                    response[@"data"] = accountResponse[@"data"];
                if (accountResponse[@"samlData"])
                    response[@"samlData"] = accountResponse[@"samlData"];
            }
            
            handler(response, nil);
        }];
    }
    else
        handler(response, nil);
}

+ (GSResponse *)responseWithError:(NSError *)error
{
    GSResponse *response = [[GSResponse alloc] init];
    response.dictionary = [error GSDictionaryRepresentation];
    
    return response;
}

#pragma mark - Gigya response properties
- (NSString *)callId
{
    return self[@"callId"];
}

- (int)errorCode
{
    return [self[@"errorCode"] intValue];
}

- (NSString *)description
{
    NSDictionary *dictForPrint = @{ @"method": self.method,
                                    @"response": self.dictionary };
    return [NSString stringWithFormat:@"GSResponse = %@", dictForPrint];
}

#pragma mark - GSObject's wrapper methods
- (id)objectForKeyedSubscript:(NSString *)key
{
    return [super objectForKeyedSubscript:key];
}

- (id)objectForKey:(NSString *)key
{
    return [super objectForKey:key];
}

- (NSArray *)allKeys
{
    return [super allKeys];
}

- (NSString *)JSONString
{
    return [super JSONString];
}

@end
