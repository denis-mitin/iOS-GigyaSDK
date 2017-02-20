#import "GSLoginManager.h"
#import "GSProviderSelectionViewController.h"
#import "Gigya+Internal.h"

@interface GSLoginManager () <GSLoginViewControllerDelegate>

@property (nonatomic, strong) NSMutableDictionary *loginProviders;
@property (nonatomic, strong) GSLoginRequest *pendingRequest;
@property (nonatomic, strong) UIPopoverController *popover;
@property (nonatomic, copy) GSUserInfoHandler loginHandler;

@end

@implementation GSLoginManager

#pragma mark - Init methods
+ (GSLoginManager *)sharedInstance
{
    return [GSLoginManager sharedInstanceWithApplication:nil launchOptions:nil];
}


+ (GSLoginManager *)sharedInstanceWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    static dispatch_once_t onceToken;
    static GSLoginManager *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSLoginManager alloc] initWithApplication:application launchOptions:launchOptions];
    });
    
    return instance;
}

- (GSLoginManager *)initWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    self = [super init];
    
    if (self) {
        NSMutableDictionary *providers = [NSMutableDictionary dictionary];
        
        if ([GSGoogleProvider isAppConfiguredForProvider])
            providers[@"googleplus"] = [GSGoogleProvider instance];
        
        if ([GSFacebookProvider isAppConfiguredForProvider])
            providers[@"facebook"] = [GSFacebookProvider instanceWithApplication:application launchOptions:launchOptions];
        
        if ([GSTwitterProvider isAppConfiguredForProvider])
            providers[@"twitter"] = [GSTwitterProvider instance];
        
        self.loginProviders = providers;
    }
    
    return self;
}

- (void)refreshLoginProviders
{
    // This method is used after returning from fast app switch, to handle the possibility the user has logged in to the twitter
    // system account while the app was in the background. Since thw GSTwitterProvider does not leave the app we do not lose the
    // login state so it is safe to re-create it.
    [self.loginProviders removeObjectForKey:@"twitter"];
    
    if ([GSTwitterProvider isAppConfiguredForProvider])
        (self.loginProviders)[@"twitter"] = [GSTwitterProvider instance];
}

#pragma mark - Login methods
- (void)startLoginForMethod:(NSString *)method
                  providers:(NSArray *)providers
                 parameters:(NSMutableDictionary *)parameters
             viewController:(UIViewController *)viewController
                popoverView:(UIView *)view
          completionHandler:(GSUserInfoHandler)handler
{
    self.loginHandler = handler;
    
    [self checkProvidersCompatibility:providers
                               params:parameters];
    
    self.pendingRequest = [GSLoginRequest loginRequestForMethod:method
                                                       provider:nil
                                                     parameters:parameters];
    
    if ([providers count] == 1) {
        self.pendingRequest.provider = providers[0];
        [self.pendingRequest startLoginOverViewController:viewController
                                        completionHandler:^(GSUser *user, NSError *error) {
                                            self.pendingRequest = nil;
                                            
                                            if (self.loginHandler)
                                                self.loginHandler(user, error);
                                        }];
    }
    else {
        if ([providers count] > 0)
            parameters[@"enabledProviders"] = [providers componentsJoinedByString:@","];
        
        GSProviderSelectionViewController *loginViewController = [[GSProviderSelectionViewController alloc] initWitMethod:method
                                                                                                               parameters:parameters];
        loginViewController.loginDelegate = self;
        
        if (viewController)
            [self showLoginViewController:loginViewController modallyOver:viewController];
        else if (view)
            [self showLoginViewController:loginViewController popoverFrom:view];
    }
}

- (void)showLoginViewController:(GSProviderSelectionViewController *)loginViewController modallyOver:(UIViewController *)viewController
{
    loginViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    loginViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    loginViewController.view.backgroundColor = [UIColor whiteColor];
    [viewController presentViewController:loginViewController animated:YES completion:nil];
}

- (void)showLoginViewController:(GSProviderSelectionViewController *)loginViewController popoverFrom:(UIView *)view
{
    _popover = [[UIPopoverController alloc] initWithContentViewController:loginViewController];
    [self.popover presentPopoverFromRect:[view bounds]
                                  inView:view
                permittedArrowDirections:UIPopoverArrowDirectionAny
                                animated:YES];
}

- (void)checkProvidersCompatibility:(NSArray *)providers params:(NSMutableDictionary *)params
{
    // Facebook is supported only with Facebook SDK (their policy)
    if (!(self.loginProviders)[@"facebook"]) {
        if ([providers count] == 1 && [providers[0] isEqualToString:@"facebook"]) {
            [NSException raise:GSInvalidOperationException
                        format:@"Logging in with Facebook is supported only using Facebook SDK native login."];
        }
        
        NSString *disabledProviders = params[@"disabledProviders"];
        NSMutableString *newDisabledProviders = [NSMutableString stringWithString:@"facebook"];
        
        if ([disabledProviders length] > 0)
            [newDisabledProviders appendFormat:@",%@", disabledProviders];
        params[@"disabledProviders"] = newDisabledProviders;
    }
    
    // Googleplus is supported only with Google SDK (their policy)
    if (!(self.loginProviders)[@"googleplus"]) {
        if ([providers count] == 1 && [providers[0] isEqualToString:@"googleplus"]) {
            [NSException raise:GSInvalidOperationException
                        format:@"Logging in with Google Plus is supported only using Google Plus native login."];
        }
        
        NSString *disabledProviders = params[@"disabledProviders"];
        NSMutableString *newDisabledProviders = [NSMutableString stringWithString:@"googleplus"];
        
        if ([disabledProviders length] > 0)
            [newDisabledProviders appendFormat:@",%@", disabledProviders];
        params[@"disabledProviders"] = newDisabledProviders;
    }
}

- (void)cancelPendingWithError:(NSError *)error
{
    if (self.loginHandler)
        self.loginHandler(nil, error);
    
    self.pendingRequest = nil;
}

#pragma mark - GSLoginViewControllerDelegate methods
- (void)loginViewControllerDidCancel:(GSProviderSelectionViewController *)loginViewController
{
    NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                         code:GSErrorCanceledByUser
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Login was canceled by user" }];
    
    [self loginViewController:loginViewController
             didFailWithError:error];
}

- (void)loginViewController:(GSProviderSelectionViewController *)loginViewController didFailWithError:(NSError *)error
{
    if (self.popover) {
        [self.popover dismissPopoverAnimated:YES];
        [self cancelPendingWithError:error];
        self.popover = nil;
    }
    else {
        [[loginViewController presentingViewController] dismissViewControllerAnimated:YES completion:^{
            [self cancelPendingWithError:error];
        }];
    }
}

- (void)loginViewController:(GSProviderSelectionViewController *)loginViewController
           selectedProvider:(NSString *)provider
                displayName:(NSString *)displayName
{
    self.pendingRequest.provider = provider;
    (self.pendingRequest.parameters)[@"captionText"] = displayName;
    
    // If displayed in a popover, we want the web dialog to display modally
    if (self.popover)
        (self.pendingRequest.parameters)[@"forceModal"] = @YES;
    
    [self.pendingRequest startLoginOverViewController:loginViewController completionHandler:^(GSUser *user, NSError *error) {
        void (^completion)(void) = ^{
            self.pendingRequest = nil;
            
            if (self.loginHandler)
                self.loginHandler(user, error);
        };
        
        if (error.code != GSErrorCanceledByUser && self.popover) {
            [self.popover dismissPopoverAnimated:YES];
            completion();
            self.popover = nil;
        }
        else {
            [[loginViewController presentingViewController] dismissViewControllerAnimated:YES completion:completion];
        }
    }];
}


#pragma mark - Logout methods
- (void)logoutWithCompletionHandler:(GSResponseHandler)handler
{
    if ([Gigya isSessionValid]) {
        GSRequest *request = [GSRequest requestForMethod:@"socialize.logout"];
        [request sendWithResponseHandler:handler];
    }
    else if (handler) {
        [self clearSessionAfterLogout];
        
        NSDictionary *responseDict = @{ @"errorCode": @0,
                                        @"status": @"OK" };
        
        [GSResponse responseForMethod:@"socialize.logout"
                                 data:[[responseDict GSJSONString] dataUsingEncoding:NSUTF8StringEncoding]
                    completionHandler:handler];
    }
}

- (void)clearSessionAfterLogout
{
    for (id<GSLoginProvider> provider in [[self allLoginProviders] allValues]) {
        if ([provider respondsToSelector:@selector(logout)])
            [provider logout];
    }
    
    [Gigya sharedInstance].session = nil;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [[Gigya sharedInstance] deleteSessionFromUserDefaults:userDefaults];
    [[Gigya sharedInstance] deleteSessionFromKeychain:userDefaults];
    
    [userDefaults synchronize];
}

- (void)removeConnectionToProvider:(NSString *)provider
                 completionHandler:(GSUserInfoHandler)handler
{
    if (![Gigya isSessionValid]) {
        [NSException raise:GSInvalidOperationException
                    format:@"RemoveConnection cannot be called when not logged in"];
    }
    
    NSDictionary *params = nil;
    
    if (provider)
        params = @{ @"provider": provider };
    
    GSRequest *request = [GSRequest requestForMethod:@"socialize.removeConnection" parameters:params];
    [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
        
        if (!error) {
            [Gigya updateUserInfo];
        }
        else if (handler) {
            handler(nil, error);
        }
    }];
}

#pragma mark - Login providers methods
- (NSDictionary *)allLoginProviders
{
    NSMutableDictionary *loginProviders = [self.loginProviders mutableCopy];
    loginProviders[@"default"] = [self getDefaultProvider];
    return loginProviders;
}

- (id<GSLoginProvider>)loginProvider:(NSString *)providerName
{
    id<GSLoginProvider> provider = (self.loginProviders)[[providerName lowercaseString]];
    
    if (!provider)
        provider = [self getDefaultProvider];
    
    return (provider);
}

- (id<GSLoginProvider>)webLoginProvider
{
    return [self getDefaultProvider];
}

- (id<GSLoginProvider>)getDefaultProvider
{
    if ([Gigya sharedInstance].dontLeaveApp)
        return [GSGigyaWebViewProvider instance];
    else
        return [GSGigyaSafariProvider instance];
}

- (GSFacebookProvider *)getFacebookProvider
{
    GSFacebookProvider *facebookProvider = [self loginProvider:@"facebook"];
    
    if (!facebookProvider) {
        [NSException raise:GSInvalidOperationException
                    format:@"App isn't configured for Facebook native login"];
    }
    
    self.currentProvider = facebookProvider;
    return facebookProvider;
}

- (void)requestNewFacebookPublishPermissions:(NSString *)permissions
                              viewController:(UIViewController * _Nullable)viewController
                             responseHandler:(GSPermissionRequestResultHandler)handler
{
    GSFacebookProvider *facebookProvider = [self getFacebookProvider];
    [facebookProvider requestNewPublishPermissions:permissions
                                    viewController:viewController
                                   responseHandler:handler];
}

- (void)requestNewFacebookReadPermissions:(NSString *)permissions
                           viewController:(UIViewController * _Nullable)viewController
                          responseHandler:(GSPermissionRequestResultHandler)handler
{
    GSFacebookProvider *facebookProvider = [self getFacebookProvider];
    [facebookProvider requestNewReadPermissions:permissions
                                 viewController:viewController
                                responseHandler:handler];
}

- (BOOL)handleOpenURL:(NSURL *)url
          application:(UIApplication *)application
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation
{
    for (id<GSLoginProvider> provider in [[self allLoginProviders] allValues]) {
        if ([provider respondsToSelector:@selector(handleOpenURL:application:sourceApplication:annotation:)] &&
            [provider handleOpenURL:url application:application sourceApplication:sourceApplication annotation:annotation]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)handleDidBecomeActive
{
    for (id<GSLoginProvider> provider in [[self allLoginProviders] allValues]) {
        if ([provider respondsToSelector:@selector(handleDidBecomeActive)])
            [provider handleDidBecomeActive];
    }

    [self refreshLoginProviders];
}

#pragma mark - Teardown

@end
