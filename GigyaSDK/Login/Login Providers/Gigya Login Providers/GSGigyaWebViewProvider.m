#import "GSGigyaWebViewProvider.h"
#import "Gigya+Internal.h"
#import "GSMBProgressHUD.h"

@interface GSGigyaWebViewProvider () <GSWebViewControllerDelegate>

@property (nonatomic, copy) GSLoginResponseHandler handler;
@property (nonatomic, strong) UINavigationController *dialogNavigationController;

@end

@implementation GSGigyaWebViewProvider

#pragma mark - Init methods
+ (instancetype)instance
{
    static dispatch_once_t onceToken;
    static GSGigyaWebViewProvider *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSGigyaWebViewProvider alloc] init];
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
    self.handler = handler;
    
    [Gigya getSessionWithCompletionHandler:^(GSSession *session) {
        NSURL *loginURL = [NSURL URLForGigyaLoginMethod:method
                                             parameters:parameters
                                      redirectURLScheme:GSRedirectURLScheme
                                                session:session];
        BOOL forceModal = [parameters[@"forceModal"] boolValue];
        
        GSWebViewController *webViewController = [[GSWebViewController alloc] initWithURL:loginURL];
        webViewController.delegate = self;
        
        if ([viewController isKindOfClass:[GSProviderSelectionViewController class]] && !forceModal) {
            // If this comes from a provider selection screen, we should push to its navigation controller
            GSProviderSelectionViewController *providersViewController = (GSProviderSelectionViewController *)viewController;
            webViewController.title = parameters[@"captionText"] ?: providersViewController.navigationTitle;
            [providersViewController pushViewController:webViewController animated:YES];
        }
        else {
            // If a different view controller, we display the webview as dialog
            _dialogNavigationController = [[UINavigationController alloc] initWithRootViewController:webViewController];
            _dialogNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
            _dialogNavigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
            _dialogNavigationController.view.backgroundColor = [UIColor whiteColor];
            webViewController.webView.scalesPageToFit = YES;
            
            if (parameters[@"captionText"]) {
                webViewController.title = parameters[@"captionText"];
            }
            else if ([method isEqualToString:@"socialize.addConnection"]) {
                webViewController.title = @"Add Connection";
            }
            else {
                webViewController.title = @"Login";
            }
            
            [viewController presentViewController:_dialogNavigationController
                                         animated:YES
                                       completion:nil];
        }
    }];
}

- (BOOL)isLoggedIn
{
    return false;
}

#pragma mark - GSWebViewControllerDelegate methods

- (BOOL)webViewController:(GSWebViewController *)webViewController shouldStartLoadWithRequest:(NSURLRequest *)request
{
    NSURL *url = [request URL];
    
    if ([[url scheme] isEqualToString:GSRedirectURLScheme] && [[url host] isEqualToString:GSRedirectURLLoginResult]) {
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
                    
                    [self finishWithSessionData:mutableResponseData error:error];
                }];
            }
            else {
                [self finishWithSessionData:nil error:error];
            }
        }
        else {
            [self finishWithSessionData:responseData error:nil];
        }

        return NO;
    }
    
    return YES;
}


- (void)webViewControllerDidStartLoad:(GSWebViewController *)webViewController
{
    GSMBProgressHUD *progress = [GSMBProgressHUD showHUDAddedTo:webViewController.webView animated:YES];
    progress.labelText = GSDefaultLoadingText;
}

- (void)webViewControllerDidFinishLoad:(GSWebViewController *)webViewController
{
    [GSMBProgressHUD hideAllHUDsForView:webViewController.webView animated:YES];
}

- (void)webViewControllerDidCancel:(GSWebViewController *)webViewController
{
    NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                         code:GSErrorCanceledByUser
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Login was canceled by user" }];
    
    [self finishWithSessionData:nil error:error];
}

- (void)webViewController:(GSWebViewController *)webViewController didFailLoadWithError:(NSError *)error
{
    [self finishWithSessionData:nil error:error];
}

- (void)finishWithSessionData:(NSDictionary *)sessionData error:(NSError *)error
{
    if (self.dialogNavigationController) {
        if ([self.dialogNavigationController presentingViewController]) {
            [[self.dialogNavigationController presentingViewController] dismissViewControllerAnimated:YES completion:^{
                [self invokeHandlerWithSessionData:sessionData error:error];
                self.dialogNavigationController = nil;
            }];
        }
    }
    else {
        [self invokeHandlerWithSessionData:sessionData error:error];
    }
}

- (void)invokeHandlerWithSessionData:(NSDictionary *)sessionData error:(NSError *)error
{
    if (self.handler) {
        self.handler(sessionData, error);
        self.handler = nil;
    }
}

@end
