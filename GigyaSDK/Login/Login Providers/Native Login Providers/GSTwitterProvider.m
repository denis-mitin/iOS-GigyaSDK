#import "GSTwitterProvider.h"
#import "Gigya+Internal.h"

@interface GSTwitterProvider ()

@property (nonatomic, copy) GSNativeLoginHandler handler;
@property (nonatomic, strong) UIViewController *viewController;
@property (nonatomic, strong) ACAccountStore *accountStore;
@property (nonatomic, strong) NSString *reverseAuthParam;
@property (nonatomic, strong) NSString *consumerKey;
@property (nonatomic, strong) ACAccountType *accountType;
@property (nonatomic, strong) NSArray *accounts;

@end

@implementation GSTwitterProvider

#pragma mark - Init methods
+ (GSTwitterProvider *)instance
{
    static dispatch_once_t onceToken;
    static GSTwitterProvider *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSTwitterProvider alloc] init];
    });
    
    return instance;
}

#pragma mark - GSLoginProvider methods
+ (BOOL)isAppConfiguredForProvider
{
    BOOL shouldDisableNative = [[[NSBundle mainBundle] infoDictionary][@"DisableTwitterNativeLogin"] boolValue];
    
    return (!shouldDisableNative &&
            NSClassFromString(@"SLRequest") &&
            NSClassFromString(@"ACAccountStore") &&
            NSClassFromString(@"IDTwitterAccountChooserViewController"));
}

- (BOOL)isLoggedIn
{
    return NO;
}

- (BOOL)shouldFallbackToWebLoginOnProviderError
{
    return YES;
}

- (NSString *)name
{
    return @"twitter";
}

#pragma mark - Login flow
- (void)startNativeLoginForMethod:(NSString *)method
                       parameters:(NSDictionary *)parameters
                   viewController:(UIViewController *)viewController
                completionHandler:(GSNativeLoginHandler)handler
{
    self.handler = handler;
    self.viewController = viewController;
    
    // Step 1 - start the reverse auth process as described here: https://dev.twitter.com/docs/ios/using-reverse-auth
    GSRequest *reverseTokenRequest = [GSRequest requestForMethod:@"socialize.getTwitterReverseAuthToken"];
    [reverseTokenRequest sendWithResponseHandler:^(GSResponse *response, NSError *error) {
        if (error) {
            [self finishWithAuthData:nil error:error];
        }
        else {
            NSString *reverseAuthParamString = response[@"data"];
            NSDictionary *reverseAuthParams = [self parseReverseAuthParams:reverseAuthParamString];
            NSString *consumerKey = reverseAuthParams[@"oauth_consumer_key"];
            
            if ([reverseAuthParamString length] == 0 || [consumerKey length] == 0) {
                error = [NSError errorWithDomain:GSGigyaSDKDomain
                                            code:GSErrorServerLoginFailure
                                        userInfo: @{ NSLocalizedDescriptionKey: @"Invalid Twitter reverse auth data received" }];
                [self finishWithAuthData:nil error:error];
            }
            else {
                Class acAccountStore = NSClassFromString(@"ACAccountStore");
                if (!self.accountStore)
                    _accountStore = [[acAccountStore alloc] init];
                
                self.accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:@"com.apple.twitter"];
                self.reverseAuthParam = reverseAuthParamString;
                self.consumerKey = consumerKey;
                
                [self getAccounts:^(NSArray *accounts) {
                    self.accounts = accounts;
                    [self chooseAccount];
                }];
            }
        }
    }];
}

- (void)getAccounts:(void (^)(NSArray *))completionHandler
{
    [self.accountStore requestAccessToAccountsWithType:self.accountType options:nil completion:^(BOOL granted, NSError *storeError) {
        if (!granted) {
            NSError *error = nil;
            
            if (!storeError) {
                error = [NSError errorWithDomain:GSGigyaSDKDomain
                                            code:GSErrorCanceledByUser
                                        userInfo:@{ NSLocalizedDescriptionKey: @"User did not allow access to Twitter Accounts" }];
            }
            else {
                error = [NSError errorWithDomain:GSGigyaSDKDomain
                                            code:GSErrorProviderError
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                                    @"providerError": storeError }];
            }
            
            [self finishWithAuthData:nil error:error];
        }
        else {
            completionHandler([self.accountStore accountsWithAccountType:self.accountType]);
        }
    }];
}

- (void)chooseAccount
{
    if ([self.accounts count] > 1) {
        if (!self.viewController) {
            NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                 code:GSErrorProviderError
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                                         @"providerError": @"UIViewController is missing and required for showing Twitter account chooser" }];
            
            [self finishWithAuthData:nil error:error];
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAccountChooser];
            });
        }
    }
    else if ([self.accounts count] == 1) {
        [self obtainAccessTokenForAccount:(self.accounts)[0]];
    }
    else {
        NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                             code:GSErrorProviderError
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                                     @"providerError": @"No Twitter account was found on the device" }];
        
        [self finishWithAuthData:nil error:error];
    }
}

- (void)showAccountChooser
{
    IDTwitterAccountChooserViewController *chooser = [[IDTwitterAccountChooserViewController alloc] init];
    [chooser setTwitterAccounts:self.accounts];
    [chooser setCompletionHandler:^(ACAccount *account) {
        // if user cancels the chooser then 'account' will be set to nil
        if (!account) {
            NSError *error = nil;
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:GSErrorCanceledByUser
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Login was canceled by user" }];
            
            [self finishWithAuthData:nil error:error];
        }
        else {
            [self obtainAccessTokenForAccount:account];
        }
    }];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        chooser.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    chooser.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    chooser.view.backgroundColor = [UIColor whiteColor];
    [self.viewController presentViewController:chooser animated:YES completion:nil];
}

// Step 2 of the reverse auth process
- (void)obtainAccessTokenForAccount:(ACAccount *)account
{
    Class slRequest = NSClassFromString(@"SLRequest");
    
    // Create the token request
    NSDictionary *requestParams = @{ @"x_reverse_auth_target": self.consumerKey,
                                     @"x_reverse_auth_parameters": self.reverseAuthParam };
    
    NSURL *accessTokenURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
    SLRequest *request = [slRequest requestForServiceType:SLServiceTypeTwitter
                                            requestMethod:SLRequestMethodPOST
                                                      URL:accessTokenURL
                                               parameters:requestParams];
    
    [request setAccount:account];
    [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *twitterError) {
        NSError *error = nil;
        NSDictionary *authData = [self authDataFromResponseData:responseData];
        
        if (twitterError) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:GSErrorProviderError
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                                @"providerError": twitterError }];
        }
        else if (!authData) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:GSErrorProviderError
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed" }];
        }
        
        [self finishWithAuthData:authData error:error];
    }];
}

- (NSDictionary *)authDataFromResponseData:(NSData *)responseData
{
    NSDictionary *result = nil;
    
    NSString *responseString = [[NSString alloc] initWithData:responseData
                                                      encoding:NSUTF8StringEncoding];
    
    if ([responseString containsString:@"oauth_token"] && [responseString containsString:@"oauth_token_secret"]) {
        NSMutableDictionary *response = [NSMutableDictionary GSDictionaryWithURLQueryString:responseString];
        NSString *oauthToken = response[@"oauth_token"];
        NSString *oauthTokenSecret = response[@"oauth_token_secret"];
        
        if ([oauthToken length] > 0 && [oauthTokenSecret length] > 0) {
            result = @{ @"x_providerToken": oauthToken,
                        @"x_providerTokenSecret": oauthTokenSecret };
        }
    }
    
    return result;
}

- (void)finishWithAuthData:(NSDictionary *)authData error:(NSError *)error
{
    if (self.handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.handler(authData, error);
        });
    }
}

#pragma mark - Utility methods

- (NSDictionary *)parseReverseAuthParams:(NSString *)oauthData
{
    oauthData = [oauthData stringByReplacingOccurrencesOfString:@"OAuth " withString:@""];
    oauthData = [oauthData stringByReplacingOccurrencesOfString:@" " withString:@""];
    oauthData = [oauthData stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    oauthData = [oauthData stringByReplacingOccurrencesOfString:@"," withString:@"&"];

    return [NSDictionary GSDictionaryWithURLQueryString:oauthData];
}

#pragma mark -


@end
