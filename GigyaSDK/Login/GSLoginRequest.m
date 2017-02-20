#import "GSLoginRequest.h"
#import "Gigya+Internal.h"
#import "GSMBProgressHUD.h"

@interface GSLoginRequest () <GSLoggerContext>

@property (nonatomic, copy) GSUserInfoHandler handler;

@end

@implementation GSLoginRequest

#pragma mark - Init methods
+ (GSLoginRequest *)loginRequestForMethod:(NSString *)method
                                 provider:(NSString *)provider
                               parameters:(NSDictionary *)parameters
{
    GSLoginRequest *instance = [[GSLoginRequest alloc] initWithMethod:method
                                                             provider:provider
                                                           parameters:parameters];
    return instance;
}

- (GSLoginRequest *)initWithMethod:(NSString *)method
                          provider:(NSString *)provider
                        parameters:(NSDictionary *)parameters
{
    self = [super init];

    if (self) {
        self.source = @"sdk";
        self.returnUserInfoResponse = YES;
        self.method = method;
        self.provider = provider;
        _parameters = [parameters mutableCopy];

        if (_parameters[@"loginMode"] && [_parameters[@"loginMode"] isEqualToString:@"reAuth"])
            _parameters[@"forceWebLogin"] = @YES;
    }
    
    return self;
}

#pragma mark - Login flow
- (void)startLoginWithCompletionHandler:(GSUserInfoHandler)handler
{
    [self startLoginOverViewController:nil
                     completionHandler:handler];
}

- (void)startLoginOverViewController:(UIViewController *)viewController
                   completionHandler:(GSUserInfoHandler)handler
{
    self.handler = handler;

    NSMutableDictionary *loginParams = [self.parameters mutableCopy];
    loginParams[@"provider"] = self.provider;
    loginParams[@"loginRequestSource"] = self.source;
    
    id<GSLoginProvider> loginProvider = [[GSLoginManager sharedInstance] loginProvider:self.provider];
    if ([(self.parameters)[@"forceWebLogin"] boolValue])
    {
        loginProvider = [[GSLoginManager sharedInstance] webLoginProvider];
        [self.parameters removeObjectForKey:@"forceWebLogin"];
    }
    
    [loginProvider startLoginForMethod:self.method
                            parameters:loginParams
                        viewController:viewController
                     completionHandler:^(NSDictionary *sessionData, NSError *error) {
                         if (error) {
                             if ([error code] == GSErrorAccountPendingRegistration && sessionData) {
                                 [self finishWithError:error responseData:sessionData];
                             }
                             else {
                                 [self finishWithError:error];
                             }
                         }
                         else {
                             [self finishWithSessionData:sessionData];
                         }
                     }];

    
    GSLogContext(@"Started LoginRequest for method: %@", self.method);
}

#pragma mark - Login flow finished
- (void)finishWithSessionData:(NSDictionary *)responseData
{
    NSString *token = responseData[@"access_token"];
    NSString *secret = responseData[@"x_access_token_secret"];
    NSString *expiresIn = responseData[@"expires_in"];
    
    [Gigya getSessionWithCompletionHandler:^(GSSession *newSession) {
        if (token && secret) {
            newSession = [[GSSession alloc] initWithSessionToken:token
                                                          secret:secret
                                                       expiresIn:expiresIn];
            newSession.lastLoginProvider = self.provider;
        }
        
        [Gigya setSession:newSession completionHandler:^(GSUser *user, NSError *error) {
            user.source = self.source;
            
            if (self.handler) {
                if (self.returnUserInfoResponse || error) {
                    self.handler(user, error);
                }
                else {
                    // This is mostly for web bridge, as the JS SDK expects to receive the response in a single object
                    GSUser *response = [[GSUser alloc] init];
                    response[@"errorCode"] = @0;
                    response[@"userInfo"] = [user dictionary];
                    self.handler(response, nil);
                }
            }
        }];
        
        GSLogContext(@"Finished with token: %@", token);
    }];
}

- (void)finishWithError:(NSError *)error
{
    [self reportErrorIfNeeded:error];

    if (self.handler)
        self.handler(nil, error);
    
    GSLogContext(@"Finished with error: %@", error);
}

- (void)finishWithError:(NSError *)error responseData:(NSDictionary *)responseData {
    [self reportErrorIfNeeded:error];
    
    if (self.handler) {
        GSUser *user = nil;
        
        if (responseData && responseData[@"profile"]) {
            user = [[GSUser alloc] init];
            user.dictionary = responseData[@"profile"];
        }
        
        self.handler(user, error);
    }
    
    GSLogContext(@"Finished with error: %@, data: %@", error, responseData);
}

- (void)reportErrorIfNeeded:(NSError *)error
{
    if ([self.method isEqualToString:@"socialize.reportSDKError"])
        return;
    
    NSArray *errorsToReport = [Gigya sharedInstance].errorsToReport;
    
    // Checking if the error code for the method is specified in the config
    if (errorsToReport) {
        for (NSDictionary *errorType in errorsToReport) {
            if (([errorType[@"method"] isEqualToString:@"*"] ||
                 [errorType[@"method"] isEqualToString:self.method]) &&
                ([errorType[@"error"] isEqualToString:@"*"] ||
                 [errorType[@"error"] intValue] == error.code))
            {
                [self reportError:error];
                break;
            }
        }
    }
}

- (void)reportError:(NSError *)error
{
    GSRequest *request = [GSRequest requestForMethod:@"reportSDKError"];
    [request.parameters addEntriesFromDictionary:@{ @"info": @(error.code),
                                                    @"log": [GSLogger logForContext:self],
                                                    @"apiKey": [Gigya sharedInstance].APIKey }];
    request.useHTTPS = YES;
    request.includeAuthInfo = NO;
    [request sendWithResponseHandler:nil];
}

#pragma mark - Logging
- (NSString *)description {
    return [super description];
}

- (NSString *)contextID {
    return [NSString stringWithFormat:@"%lu", (unsigned long)self.hash];
}


@end
