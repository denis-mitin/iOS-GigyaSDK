#import "GSGigyaSafariProvider.h"
#import "Gigya+Internal.h"
#import "GSMBProgressHUD.h"

@interface GSGigyaSafariProvider ()

@property (nonatomic, copy) GSLoginResponseHandler handler;
@property (nonatomic, copy) NSString *currentProvider;
@property (nonatomic, weak) GSMBProgressHUD *progress;

@end

@implementation GSGigyaSafariProvider

#pragma mark - Init methods
+ (instancetype)instance
{
    static dispatch_once_t onceToken;
    static GSGigyaSafariProvider *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSGigyaSafariProvider alloc] init];
    });
    
    return instance;
}

#pragma mark - GSLoginProvider methods
+ (BOOL)isAppConfiguredForProvider
{
    return YES;
}

- (void)startLoginForMethod:(NSString *)method
                 parameters:(NSDictionary *)parameters
             viewController:(UIViewController *)viewController
          completionHandler:(GSLoginResponseHandler)handler
{
    if ([viewController isKindOfClass:[GSProviderSelectionViewController class]]) {
        self.progress = [GSMBProgressHUD showHUDAddedTo:viewController.view animated:YES];
        self.progress.labelText = GSDefaultLoginText;
    }
    
    self.handler = handler;
    
    NSString *gmid = [[Gigya sharedInstance] gmid];
    if (gmid) {
        // Removing the gmid and getting a gmidTicket from the server - in order to not pass the gmid to the browser
        NSMutableDictionary *mutableParams = [parameters mutableCopy];
        [mutableParams removeObjectForKey:@"gmid"];
        GSRequest *request = [GSRequest requestForMethod:@"getGmidTicket" parameters:@{@"gmid" : gmid}];
        request.useHTTPS = YES;
        [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
            if (!error && response.errorCode == 0) {
                mutableParams[@"gmidTicket"] = response[@"gmidTicket"];
            }
            
            [self openLoginURLForMethod:method parameters:parameters];
        }];
    } else{
        [self openLoginURLForMethod:method parameters:parameters];
    }
}

- (void)openLoginURLForMethod:(NSString *)method parameters:(NSDictionary *)parameters
{
    [self testURLScheme];
    [Gigya getSessionWithCompletionHandler:^(GSSession *session) {
        NSURL *loginURL = [NSURL URLForGigyaLoginMethod:method
                                             parameters:parameters
                                      redirectURLScheme:[self URLScheme]
                                                session:session];
        
        [[UIApplication sharedApplication] openURL:loginURL];
    }];
}

- (BOOL)isLoggedIn
{
    return false;
}

- (BOOL)handleOpenURL:(NSURL *)url
          application:(UIApplication *)application
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
    if (([[url scheme] caseInsensitiveCompare:[self URLScheme]] == NSOrderedSame) && [[url host] isEqualToString:GSRedirectURLLoginResult] && self.handler) {
        NSDictionary *responseData = [NSDictionary GSDictionaryWithURLQueryString:[url fragment]];
        
        if (responseData[@"error"]) {
            self.handler(nil, [NSError errorWithGigyaLoginResponse:responseData]);
        }
        else {
            self.handler(responseData, nil);
        }
        
        [self.progress hide:YES];
        self.handler = nil;
        return YES;
    }
    
    return NO;
}

- (void)handleDidBecomeActive
{
    // There was a pending login that wasn't completed
    if (self.handler) {
        NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                             code:GSErrorCanceledByUser
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Login process did not complete" }];
        self.handler(nil, error);
        [self.progress hide:YES];
        self.handler = nil;
    }
}

#pragma mark - URL Scheme
- (void)testURLScheme
{
    NSURL *testURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://test", [self URLScheme]]];
    
    if (![[UIApplication sharedApplication] canOpenURL:testURL]) {
        [NSException raise:GSGigyaSDKDomain
                    format:@"Could not login. URL Scheme %@:// is not configured", [self URLScheme]];
    }
}

- (NSString *)URLScheme
{
    return [[NSBundle mainBundle] bundleIdentifier];
}

@end
