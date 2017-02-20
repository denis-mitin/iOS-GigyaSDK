#import "GSNativeLoginProvider.h"
#import "Gigya+Internal.h"
#import "GSMBProgressHUD.h"

@interface GSNativeLoginProvider () <GSWebViewControllerDelegate>

@property (nonatomic, copy) GSLoginResponseHandler loginHandler;
@property (nonatomic, copy) GSLoginResponseHandler innerHandler;
@property (nonatomic, strong) GSWebViewController *backgroundWebView;

@end

@implementation GSNativeLoginProvider

#pragma mark - Init methods
+ (instancetype)instance
{
    return [GSNativeLoginProvider instanceWithApplication:nil launchOptions:nil];
}

+ (instancetype)instanceWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)dealloc
{
    [_backgroundWebView setDelegate:nil];
}

#pragma mark - Properties
- (NSString *)name
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (BOOL)shouldFallbackToWebLoginOnProviderError
{
    return NO;
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
        GSMBProgressHUD *progress = [GSMBProgressHUD showHUDAddedTo:viewController.view animated:YES];
        progress.labelText = GSDefaultLoginText;
    }

    [self startLoginForMethod:method
                   parameters:parameters
               viewController:viewController
            completionHandler:handler
           shouldRetryOnError:YES];
}

- (void)startLoginForMethod:(NSString *)method
                 parameters:(NSDictionary *)parameters
             viewController:(UIViewController *)viewController
          completionHandler:(GSLoginResponseHandler)handler
         shouldRetryOnError:(BOOL)shouldRetry
{
    self.loginHandler = handler;
    
    [self startNativeLoginForMethod:method
                         parameters:parameters
                     viewController:viewController
                  completionHandler:^(NSDictionary *providerSessionData, NSError *error) {
                      if (error) {
                          [GSMBProgressHUD hideHUDForView:viewController.view animated:YES];
                          
                          if (error.code == GSErrorProviderError && [self shouldFallbackToWebLoginOnProviderError]) {
                              // This currently works only for twitter - if there's an issue with the system account we want to fall back to web view / safari login
                              [[[GSLoginManager sharedInstance] webLoginProvider] startLoginForMethod:method
                                                                                           parameters:parameters
                                                                                       viewController:viewController
                                                                                    completionHandler:handler];
                          }
                          else if (self.loginHandler) {
                              self.loginHandler(nil, error);
                          }
                      }
                      else {
                          NSMutableDictionary *loginParams = [parameters mutableCopy];
                          [loginParams addEntriesFromDictionary:providerSessionData];
                          [self completeLoginMethod:method parameters:loginParams responseHandler:^(NSDictionary *sessionData, NSError *error) {
                              if (self.loginHandler)
                                  self.loginHandler(sessionData, error);
                              
                              [GSMBProgressHUD hideHUDForView:viewController.view animated:YES];
                          }];
                      }
                  }];
}

- (BOOL)isLoggedIn
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

#pragma mark - Login flow
- (void)startNativeLoginForMethod:(NSString *)method
                       parameters:(NSDictionary *)parameters
                   viewController:(UIViewController *)viewController
                completionHandler:(GSNativeLoginHandler)handler
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)completeLoginMethod:(NSString *)method
                 parameters:(NSMutableDictionary *)params
            responseHandler:(GSLoginResponseHandler)handler
{
    self.innerHandler = handler;

    [Gigya getSessionWithCompletionHandler:^(GSSession *session) {
        params[@"provider"] = self.name;
        if (params[@"loginMode"] && [params[@"loginMode"] isEqualToString:@"reAuth"])
            [params removeObjectForKey:@"loginMode"];
        
        NSURL *url = [NSURL URLForGigyaLoginMethod:method
                                        parameters:params
                                 redirectURLScheme:GSRedirectURLScheme
                                           session:session];
        
        // Push a new WebViewController with provider login page
        GSWebViewController *webViewController = [[GSWebViewController alloc] initWithURL:url];
        webViewController.delegate = self;
        _backgroundWebView = webViewController;
        [webViewController startWebView];
    }];
}

- (BOOL)webViewController:(GSWebViewController *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
{
    NSURL *url = [request URL];
    
    if ([[url scheme] isEqualToString:GSRedirectURLScheme] && [[url host] isEqualToString:GSRedirectURLLoginResult] && self.loginHandler) {
        NSDictionary *responseData = [NSDictionary GSDictionaryWithURLQueryString:[url fragment]];
        
        if (responseData[@"error"]) {
            NSError *error = [NSError errorWithGigyaLoginResponse:responseData];
            
            if ([error code] == GSErrorAccountPendingRegistration && responseData[@"x_regToken"]) {
                GSRequest *accountRequest = [GSRequest requestForMethod:@"accounts.getAccountInfo"
                                                             parameters:@{ @"regToken" : responseData[@"x_regToken"] }];
            
                [accountRequest sendWithResponseHandler:^(GSResponse *accountResponse, NSError *accountError) {
                    NSMutableDictionary *mutableResponseData = [responseData mutableCopy];
                    
                    if (!accountError) {
                        mutableResponseData[@"profile"] = accountResponse[@"profile"] ? accountResponse[@"profile"] : @{};
                        if (accountResponse[@"UID"])
                            mutableResponseData[@"profile"][@"UID"] = accountResponse[@"UID"];
                        if (accountResponse[@"data"])
                            mutableResponseData[@"data"] = accountResponse[@"data"];
                        if (accountResponse[@"samlData"])
                            mutableResponseData[@"samlData"] = accountResponse[@"samlData"];
                    }
                    
                    self.innerHandler(mutableResponseData, error);
                }];
            }
            else {
                self.innerHandler(nil, error);
            }
        }
        else {
            self.innerHandler(responseData, nil);
        }

        return NO;
    }
    
    return YES;
}

- (NSMutableArray *)mergePermissions:(NSArray *)defaultPermissions extraPermissions:(NSArray *)extraPermissions
{
    NSMutableArray *result = [defaultPermissions mutableCopy];
    
    if ([extraPermissions count] > 0) {
        for (NSString *perm in extraPermissions) {
            if ([result indexOfObject:perm] == NSNotFound) {
                [result addObject:perm];
            }
        }
    }
    
    return result;
}

@end
