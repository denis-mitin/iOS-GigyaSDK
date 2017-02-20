#import "Gigya+Internal.h"
#import <CommonCrypto/CommonHMAC.h>

@interface GSRequest () <GSLoggerContext>

@property (nonatomic, copy) GSResponseHandler handler;
@property (nonatomic, strong) NSString *requestID;

// Connection properties
@property (nonatomic, strong) NSURLSessionTask *sessionTask;
@property (nonatomic)         NSTimeInterval serverTime;
@property (nonatomic)         BOOL retryOnTimeSkew;
@property (nonatomic)         BOOL retryOnUnauthorizedUser;
@property (nonatomic, strong) NSMutableDictionary * _Nullable originalParameters;

@end

typedef void(^GSPrepareRequestHandler)(NSMutableURLRequest *request);

@implementation GSRequest

#pragma mark - Autoreleased creators
+ (GSRequest *)requestForMethod:(NSString *)method
{
    return [[GSRequest alloc] initWithMethod:method];
}

+ (GSRequest *)requestForMethod:(NSString *)method parameters:(NSDictionary *)params
{
    return [[GSRequest alloc] initWithMethod:method
                                    parameters:params
                                      useHTTPS:[Gigya useHTTPS]
                                    requestTimeout:[Gigya requestTimeout]];
}

#pragma mark - Init methods
- (GSRequest *)initWithMethod:(NSString *)method
                   parameters:(NSDictionary *)params
                     useHTTPS:(BOOL)shouldUseHTTPS
               requestTimeout:(NSTimeInterval)requestTimeout
{
    self = [super init];

    if (self) {
        self.method = method;
        self.useHTTPS = shouldUseHTTPS;
        self.requestTimeout = requestTimeout;
        self.parameters = [NSMutableDictionary dictionary];
        self.retryOnTimeSkew = YES;
        self.retryOnUnauthorizedUser = YES;
        self.includeAuthInfo = YES;
        self.source = @"sdk";
        self.requestID = [NSString GSGUIDString];

        if (params)
            [self.parameters addEntriesFromDictionary:params];
    }

    return self;
}

- (GSRequest *)initWithMethod:(NSString *)method
{
    return [self initWithMethod:method
                      parameters:nil
                        useHTTPS:[Gigya useHTTPS]
                  requestTimeout:[Gigya requestTimeout]];
}

#pragma mark - Property setters
- (void)setMethod:(NSString *)method
{

    // If no method namespace, using socialize
    if ([method rangeOfString:@"."].location == NSNotFound)
        _method = [NSString stringWithFormat:@"socialize.%@", method];
    else
        _method = [method copy];
}

- (void)setParameters:(NSMutableDictionary *)parameters
{

    // It's easy to get confused and send a NSDictionary instead of NSMutableDictionary, so we make sure to use a mutable copy.
    _parameters = [parameters mutableCopy];
}

#pragma mark - Sending the request
- (void)prepareRequest:(GSPrepareRequestHandler _Nonnull)handler
{
    self.originalParameters = [self.parameters copy];
    BOOL forceNoAuth = [(self.parameters)[@"noAuth"] boolValue];

    GSGetSessionCompletionHandler sessionHandler = ^(GSSession *session) {
        self.session = session;

        BOOL forceHTTPS = ([self.parameters objectForKey:@"regToken"] != nil);
        NSMutableURLRequest *request = nil;
        NSString *requestURL;

        [self.parameters addEntriesFromDictionary:@{ @"format": @"json",
                                                     @"httpStatusCodes": @"false",
                                                     @"sdk": GSGigyaSDKVersion,
                                                     @"targetEnv": @"mobile",
                                                     @"apikey": [Gigya APIKey]}];
        if ([[Gigya sharedInstance] ucid])
            (self.parameters)[@"ucid"] = [[Gigya sharedInstance] ucid];

        if (forceNoAuth) {
            [self.parameters removeObjectForKey:@"noAuth"];
            NSString *includeParamValue = [self.parameters valueForKey:@"include"];
            forceHTTPS = (includeParamValue && [includeParamValue rangeOfString:@",ids"].location != NSNotFound);
        }
        else {
            if (self.useHTTPS || forceHTTPS) {
                if (!(self.parameters)[@"gmidTicket"])
                    (self.parameters)[@"gmid"] = [[Gigya sharedInstance] gmid];
            }
    
            // Sign if secret is present
            if (self.includeAuthInfo && self.session && [self.session isValid]) {
                // Add oauth1 params
                NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] + [[Gigya sharedInstance] serverTimeSkew];
                (self.parameters)[@"timestamp"] = [NSString stringWithFormat:@"%.0f", timestamp];
                (self.parameters)[@"nonce"] = @(timestamp);
                (self.parameters)[@"oauth_token"] = [self.session token];
                
                // Calculate oAuth signature
                [self.parameters removeObjectForKey:@"sig"];
                requestURL = [self buildRequestURLWithScheme:(self.useHTTPS || forceHTTPS ? @"https" : @"http")];
                (self.parameters)[@"sig"] = [self oauth1Signature:requestURL];
            }
        }

        if (!requestURL)
            requestURL = [self buildRequestURLWithScheme:(self.useHTTPS || forceHTTPS ? @"https" : @"http")];

        // Create the request
        request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:requestURL]];
        request.timeoutInterval = self.requestTimeout;
        request.HTTPMethod = @"POST";
        [request setHTTPBody:[[self.parameters GSURLQueryString] dataUsingEncoding:NSUTF8StringEncoding]];

        handler(request);
    };

    if (forceNoAuth)
        sessionHandler([Gigya sharedInstance].session); // use currently loaded session as is without attepting to load one
    else
        [Gigya getSessionWithCompletionHandler:sessionHandler];
}

- (void)sendWithResponseHandler:(GSResponseHandler)handler
{
    [[Gigya sharedInstance] checkSDKInit];

    [self cancel];
    self.handler = handler;

    [self requestPermissionsIfNeeded:^(BOOL granted, NSError *error, NSArray *declinedPermissions) {
        if (granted && ![declinedPermissions containsObject:@"publish_actions"]) {
            [self sendValidatedRequest];
        }
        else {
            [self finishWithResponse:nil error:error];
        }
    }];
}

- (void)sendValidatedRequest
{
    [self prepareRequest:^(NSMutableURLRequest *request) {
        GSLogContext(@"Sending request: %@", self);

        // Start the request
        if (request) {
            self.sessionTask = [GSRequest getURLSessionTaskForRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;

                if (error) {
                    [self finishWithResponse:nil error:[NSError errorWithDomain:GSGigyaSDKDomain
                                                                           code:GSErrorNetworkFailure
                                                                       userInfo:@{ NSLocalizedDescriptionKey: @"Failed connecting to server",
                                                                                   NSUnderlyingErrorKey: error }]];
                } else {
                    if ([httpResponse statusCode] == 200) {
                        GSLogContext(@"Web server: %@\n", [httpResponse allHeaderFields][@"X-Server"]);

                        self.serverTime = [self timeIntervalFromServerDate:httpResponse];

                        // Create Gigya response
                        [GSResponse responseForMethod:self.method data:data completionHandler:^(GSResponse *gigyaResponse, NSError *gigyaError){
                            gigyaResponse.source = self.source;

                            // If the response is an error
                            if (gigyaResponse.errorCode != 0) {
                                gigyaError = [NSError errorWithGigyaResponse:gigyaResponse];
                            }

                            // failed because of time synchronization issue, try again with time skew
                            if ((gigyaResponse.errorCode == GSErrorInvalidTime) && self.retryOnTimeSkew) {
                                [self retryAfterTimeSync:gigyaResponse];
                            }
                            else if (gigyaResponse.errorCode == GSErrorUnauthorizedUser && self.retryOnUnauthorizedUser) {
                                self.retryOnUnauthorizedUser = NO;
                                [[GSLoginManager sharedInstance] clearSessionAfterLogout];
                                [self invokeLogoutEventsWithObject:gigyaResponse];
                                
                                NSDictionary *retryParameters = self.originalParameters ? [self.originalParameters copy] : @{};
                                GSRequest *retryRequest = [GSRequest requestForMethod:self.method parameters:retryParameters];
                                retryRequest.retryOnUnauthorizedUser = NO;
                                retryRequest.includeAuthInfo = NO;
                                
                                [retryRequest sendWithResponseHandler:^(GSResponse * _Nullable retryResponse, NSError * _Nullable retryError) {
                                    if (retryError && (retryError.code == GSErrorMissingRequiredParameter || retryError.code == GSErrorPermissionDenied))
                                        [self finishWithResponse:gigyaResponse error:gigyaError];
                                    else
                                        [self finishWithResponse:retryResponse error:retryError];
                                }];
                            }
                            else {
                                [self finishWithResponse:gigyaResponse error:gigyaError];
                            }
                        }];
                    }
                    else {
                        [self finishWithResponse:nil error:[NSError errorWithDomain:GSGigyaSDKDomain
                                                                               code:GSErrorNetworkFailure
                                                                           userInfo:@{ NSLocalizedDescriptionKey: @"Failed connecting to server" }]];
                    }
                }
            }];

            [[Gigya sharedInstance] showNetworkActivityIndicator];
        }
    }];
}

- (void)cancel
{
    if (self.sessionTask) {
        [self.sessionTask cancel];
        self.sessionTask = nil;
        self.handler = nil;
    }
}

- (NSString *)buildRequestURLWithScheme:(NSString *)scheme
{
    // Domain prefix and method
    NSArray *methodParts = [self.method componentsSeparatedByString:@"."];

    // Build URL
    return [NSString stringWithFormat:@"%@://%@.%@/%@", scheme, methodParts[0], Gigya.APIDomain, self.method];
}

- (void)requestPermissionsIfNeeded:(GSPermissionRequestResultHandler)handler
{
    NSError *error = nil;
    BOOL doesNeedPermissions = NO;

    // If connected to Facebook via native login
    GSFacebookProvider *facebookProvider = [[GSLoginManager sharedInstance] loginProvider:@"facebook"];
    NSString *enabledProviders = (self.parameters)[@"enabledProviders"];

    if ([facebookProvider isLoggedIn]) {
        // If the method requires publish_action, and enabled providers has facebook/unspecified
        if (([self.method rangeOfString:@"publishUserAction"].location != NSNotFound ||
             [self.method rangeOfString:@"setStatus"].location != NSNotFound ||
             [self.method rangeOfString:@"checkin"].location != NSNotFound) &&
            (!enabledProviders || [enabledProviders isEqualToString:@"*"] || [enabledProviders rangeOfString:@"facebook"].location != NSNotFound))
        {
            doesNeedPermissions = YES;

            [facebookProvider requestNewPublishPermissions:@"publish_actions"
                                            viewController:nil
                                           responseHandler:handler];
        }
    }

    if (!doesNeedPermissions && handler) {
        handler(YES, error, nil);
    }
}

- (void)finishWithResponse:(GSResponse *)response error:(NSError *)error
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [self checkForSessionChanges:response error:error];

    if (response && !error) {
        GSLogContext(@"Received response: %@", response);
        [self checkRevokedProviders:response];
    }

    if (self.handler)
        self.handler(response, error);

    [self reportErrorIfNeeded:response];
}

- (void)checkForSessionChanges:(GSResponse *)response error:(NSError *)error
{
    NSDictionary *sessionInfo = response[@"sessionInfo"];
    NSString *token;
    NSString *secret;
    NSString *expiresIn;

    if (!error && (sessionInfo || response[@"sessionToken"])) {
        if (sessionInfo) {
            token = sessionInfo[@"sessionToken"];
            secret = sessionInfo[@"sessionSecret"];
            expiresIn = sessionInfo[@"expires_in"];
        } else {
            token = response[@"sessionToken"];
            secret = response[@"sessionSecret"];
            expiresIn = response[@"expires_in"];
        }

        if (token && secret) {
            // Create a new session
            GSSession *newSession = [[GSSession alloc] initWithSessionToken:token
                                                                     secret:secret
                                                                  expiresIn:expiresIn];
            [Gigya setSession:newSession];
        }
    }
    else if (!error && [self.method rangeOfString:@".logout"].location != NSNotFound) {
        // This was a logout method, session needs to be cleared
        [[GSLoginManager sharedInstance] clearSessionAfterLogout];
        [self invokeLogoutEventsWithObject:response];
    }
    else if (!error && [self.method rangeOfString:@".removeConnection"].location != NSNotFound) {
        // Re-set session to invoke relevant events
        [Gigya updateUserInfo];

        NSString *provider = (self.parameters)[@"provider"];
        id<GSLoginProvider> nativeLoginProvider = [[GSLoginManager sharedInstance] loginProvider:provider];
        if ([nativeLoginProvider respondsToSelector:@selector(logout)])
            [nativeLoginProvider logout];
    }
}

- (void)checkRevokedProviders:(GSResponse *)response
{
    NSArray *providerErrorArray = response[@"providerErrorCodes"];

    for (NSDictionary *providerError in providerErrorArray) {
        if ([providerError[@"errorCode"] intValue] == GSErrorCode_ProviderSessionExpired) {
            NSString *providerName = providerError[@"provider"];
            id<GSLoginProvider> nativeLoginProvider = [[GSLoginManager sharedInstance] loginProvider:providerName];

            if ([nativeLoginProvider respondsToSelector:@selector(logout)])
                [nativeLoginProvider logout];
        }
    }
}

- (void)reportErrorIfNeeded:(GSResponse *)response
{
    if ([response.method isEqualToString:@"socialize.reportSDKError"])
        return;

    NSArray *errorsToReport = [Gigya sharedInstance].errorsToReport;

    // Checking if the error code for the method is specified in the config
    if (errorsToReport) {
        for (NSDictionary *errorType in errorsToReport) {
            if (([errorType[@"method"] isEqualToString:@"*"] ||
                [errorType[@"method"] isEqualToString:response.method]) &&
                ([errorType[@"error"] isEqualToString:@"*"] ||
                 [errorType[@"error"] intValue] == response.errorCode))
            {
                [self reportError:response];
                break;
            }
        }
    }
}

- (void)reportError:(GSResponse *)response
{
    GSRequest *request = [GSRequest requestForMethod:@"reportSDKError"];
    [request.parameters addEntriesFromDictionary:@{ @"info":    @(response.errorCode),
                                                    @"log":     [GSLogger logForContext:self] }];
    request.useHTTPS = YES;
    request.includeAuthInfo = NO;
    [request sendWithResponseHandler:nil];
}

- (void)retryAfterTimeSync:(GSResponse *)response
{
    NSTimeInterval requestTime = [(self.parameters)[@"timestamp"] doubleValue];

    // Calculate the time skew
    [[Gigya sharedInstance] setServerTimeSkew:(self.serverTime - requestTime)];

    // Resend the request, this time without retrying on time skew error
    GSRequest *retry = [GSRequest requestForMethod:self.method parameters:self.parameters];
    retry.retryOnTimeSkew = NO;
    [retry sendWithResponseHandler:self.handler];
}

#pragma mark - OAuth1 Signature
- (NSString *)oauth1Signature:(NSString*)requestURL
{
    // Sign the base string with the secret - http://oauth.net/core/1.0 - section 9.2
    NSData *baseStringData = [[self oauth1SignatureBaseString:requestURL] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *secretData = [NSData GSDataFromBase64String:self.session.secret];
    unsigned char result[20];
    CCHmac(kCCHmacAlgSHA1, [secretData bytes], [secretData length], [baseStringData bytes], [baseStringData length], result);

    // Return the signature string
    NSData *data = [NSData dataWithBytes:result length:20];
    return [data GSBase64SEncodedString];
}

- (NSString *)oauth1SignatureBaseString:(NSString *)requestURL
{
    // http://oauth.net/core/1.0 - 9.1 Signature Base String
    // Base string components
    NSString *method = @"POST";
    NSURL *url = [NSURL URLWithString:requestURL];
    NSString *params = [self.parameters GSURLQueryString];

    NSString *baseString = [NSString stringWithFormat:@"%@&%@&%@", method, [url.description GSURLEncodedString], [params GSURLEncodedString]];
    GSLogContext(@"Calculating signature with base string:\n%@", baseString);

    return baseString;
}

#pragma mark - Utility methods
- (void)invokeLogoutEventsWithObject:(GSObject *)object
{
    [[Gigya sharedInstance] invokeSelectorOnSocializeDelegates:@selector(userDidLogout) withObject:object];
    [[Gigya sharedInstance] invokeSelectorOnAccountsDelegates:@selector(accountDidLogout) withObject:object];
}

- (NSTimeInterval)timeIntervalFromServerDate:(NSHTTPURLResponse *)response
{
    NSTimeInterval result = 0;
    NSString *serverDate = [response allHeaderFields][@"Date"];

    if ([serverDate length] > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
        [formatter setLocale:locale];
        result = [[formatter dateFromString:serverDate] timeIntervalSince1970];
    }

    return result;
}

+ (NSURLSessionTask *)getURLSessionTaskForRequest:(NSURLRequest * _Nonnull)request
                                completionHandler:(void (^)(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error))handler
{
    static dispatch_once_t onceToken;
    static NSURLSession *session = nil;

    dispatch_once(&onceToken, ^{
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                delegate:nil
                                           delegateQueue:[NSOperationQueue mainQueue]];
    });

    NSURLSessionTask *task = [session dataTaskWithRequest:request
                                        completionHandler:handler];

    [task resume];

    return task;
}

#pragma mark - Overrides
- (NSString *)description {
    NSDictionary *dictToPrint = @{ @"method": self.method,
                                   @"parameters": self.parameters };
    return [NSString stringWithFormat:@"GSRequest = %@", dictToPrint];
}

- (NSString *)contextID {
    return self.requestID;
}


- (void)dealloc
{
    [GSLogger clear:self];
}

@end
