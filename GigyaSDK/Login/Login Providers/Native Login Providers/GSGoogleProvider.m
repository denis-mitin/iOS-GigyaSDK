#import "GSGoogleProvider.h"
#import "Gigya+Internal.h"

#define DEFAULT_GOOGLE_PERMISSIONS @[ @"https://www.googleapis.com/auth/plus.login", @"email" ] // For failover if getSDKConfig fails

typedef void(^GSGoogleLoginHandler)(GIDGoogleUser *auth, NSError *error);

@interface GSGoogleProvider ()
{
}

@property (nonatomic) BOOL isLoggedIn;
@property (nonatomic, copy) GSGoogleLoginHandler gidLoginHandler;

@end

@implementation GSGoogleProvider

#pragma mark - Init methods
+ (GSGoogleProvider *)instance
{
    static dispatch_once_t onceToken;
    static GSGoogleProvider *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSGoogleProvider alloc] init];
    });
    
    return instance;
}

- (GSGoogleProvider *)init {
    GSLog(@"init");
    self = [super init];
    
    if (self && [GSGoogleProvider isAppConfiguredForProvider] && ![Gigya sharedInstance].touchIDEnabled) {
        [self autologin];
    }
    
    return self;
}

#pragma mark - automatic login to provider

- (void)autologin {
    GSLog(@"Auto signIn started");

    NSArray *permissions = DEFAULT_GOOGLE_PERMISSIONS;
    
    // If we have stored the permissions (logged in with those permissions already)
    NSArray *storedPermissions = [self fetchStoredPermissions];
    if (storedPermissions)
        permissions = [self mergePermissions:permissions extraPermissions:storedPermissions];

    __weak typeof(self) weakSelf = self;
    self.gidLoginHandler = ^(GIDGoogleUser *auth, NSError *error) {
        if (error) {
            GSLog(@"Auto signIn failed: %@", error);
            weakSelf.isLoggedIn = NO;
            [weakSelf clearStoredPermissions];
        } else {
            GSLog(@"Auto signIn succeded");
            weakSelf.isLoggedIn = YES;
            [weakSelf reportExtendedToken:auth];
        }
    };
    
    GIDSignIn *signIn = [self getGIDSignInInstance];

    signIn.delegate = self;
    signIn.scopes = permissions;
    signIn.clientID = [GSGoogleProvider clientID];
    
    [signIn signInSilently];
}

- (void)reportExtendedToken:(GIDGoogleUser *)auth {
    // Prepare the request data
    NSDictionary* parameters = [self providerSessionFromGIDGoogleUser:auth forRefresh:YES];
    
    GSRequest *request = [GSRequest requestForMethod:@"refreshProviderSession" parameters:parameters];
    request.useHTTPS = YES;
    [request sendWithResponseHandler:nil];
}

- (void)storePermissions:(NSArray *)permissions
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setValue:permissions forKey:GSGooglePermissionsDefaultsKey];
    [defaults synchronize];
}

- (void)clearStoredPermissions
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:GSGooglePermissionsDefaultsKey];
    [defaults synchronize];
}

- (NSArray *)fetchStoredPermissions
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:GSGooglePermissionsDefaultsKey];
}

#pragma mark - app identifications

+ (NSString *)clientID {
    return [[NSBundle mainBundle] infoDictionary][@"GoogleClientID"];
}

- (NSString *)name {
    return @"googleplus"; // this is the gigya provider name - and should remain matching the server provider name
}

#pragma mark - GSLoginProvider methods

+ (BOOL)isAppConfiguredForProvider
{
    return ([[GSGoogleProvider clientID] length] > 0 &&
            NSClassFromString(@"GIDSignIn"));
}

- (void)logout
{
    GIDSignIn *signIn = [self getGIDSignInInstance];
    
    [signIn signOut];
    signIn.scopes = DEFAULT_GOOGLE_PERMISSIONS; // reset scopes for future login attempts
    
    self.isLoggedIn = NO;
}

- (void)startNativeLoginForMethod:(NSString *)method
                       parameters:(NSDictionary *)parameters
                   viewController:(UIViewController *)viewController
                completionHandler:(GSNativeLoginHandler)handler
{
    GSLog(@"start native login");
    GIDSignIn *signIn = [self getGIDSignInInstance];
    
    // Use the permissions returned from getSDKConfig, and add any permissions the partner has passed in googlePlusExtraPermissions
    NSArray *permissions = [self mergePermissions:[signIn scopes] // scopes from last login attempt to allow addition of scopes
                                 extraPermissions:[[Gigya sharedInstance] providerPermissions][@"googleplus"]]; // the provider name that getSDKConfig returns, changing this will break existing mobile apps
    
    permissions = [self mergePermissions:permissions
                        extraPermissions:[parameters[@"googlePlusExtraPermissions"] componentsSeparatedByString:@","]];
    
    __weak typeof(self) weakSelf = self;
    self.gidLoginHandler = ^(GIDGoogleUser *auth, NSError *error) {
        GSLog(@"finish native login handler");
        NSDictionary *parameters = nil;
        
/*** TODO: for working with serverAuthCode
        if (!error && !auth.serverAuthCode) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:GSErrorProviderError
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, no server auth code",
                                                @"googleUser": auth }];

            [weakSelf logout]; // reset the session with google
        }
        else if (auth) {
*/
        
        if (error) {
            GSLog(@"native login failed: %@", error);
            [weakSelf logout]; // reset the session with google
        } else {
            GSLog(@"native login succeded");
            parameters = [self providerSessionFromGIDGoogleUser:auth forRefresh:NO];
            
            weakSelf.isLoggedIn = YES;
            [weakSelf storePermissions:signIn.scopes];
        }

        if (handler) {
            handler(parameters, error);
        }
    };

    // set all the parameters on each login to avoid conflicts with direct work with the google SDK
    signIn.scopes = permissions;
    signIn.clientID = [GSGoogleProvider clientID];

/*** TODO: for working with serverAuthCode
    signIn.shouldFetchBasicProfile = NO;
    signIn.serverClientID = [GSGoogleProvider serverClientID];
*/
    
    signIn.delegate = self;
    signIn.uiDelegate = (id)viewController;
    
    [signIn signIn];
}

- (NSDictionary *)providerSessionFromGIDGoogleUser:(GIDGoogleUser *)auth forRefresh:(BOOL)refresh {
    NSTimeInterval expiration = [auth.authentication.accessTokenExpirationDate timeIntervalSince1970];
    
    if (refresh) {
        return @{
                 @"providerSession": @{
                 @"googleplus": @{
                         @"authToken": auth.authentication.accessToken,
                         @"tokenExpiration":@(expiration)
                         } } };
    }
    
    return @{
             @"x_providerToken": auth.authentication.accessToken,
             @"x_providerTokenExpiration":@(expiration)
             };
}

#pragma mark - GIDSignIn methods

- (GIDSignIn *)getGIDSignInInstance {
    Class gidSignIn = NSClassFromString(@"GIDSignIn");
    return [gidSignIn sharedInstance];
}

- (BOOL)handleOpenURL:(NSURL *)url
          application:(UIApplication *)application
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation
{
    GIDSignIn *signIn = [self getGIDSignInInstance];

    return [signIn handleURL:url sourceApplication:sourceApplication annotation:annotation];
}

#pragma mark - GIDSignInDelegate methods: https://developers.google.com/identity/sign-in/ios/api/protocol_g_i_d_sign_in_delegate-p

- (void)signIn:(GIDSignIn *)signIn didSignInForUser:(GIDGoogleUser *)auth withError:(NSError *)providerError
{
    if (self.gidLoginHandler) {
        GIDGoogleUser *nativeResponse = auth;
        NSError *reportedError = nil;
        
        if ((providerError && [providerError code] != 0) || !auth) {
            nativeResponse = nil;
            
            if ([providerError code] == -5) {
                reportedError = [NSError errorWithDomain:GSGigyaSDKDomain
                                                    code:GSErrorCanceledByUser
                                                userInfo:@{ NSLocalizedDescriptionKey: @"Operation was canceled by user, see provider error",
                                                            @"providerError": providerError  }];
            }
            else if (providerError) {
                reportedError = [NSError errorWithDomain:GSGigyaSDKDomain
                                                    code:GSErrorCanceledByUser
                                                userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                                            @"providerError": providerError }];
            }
        }
        
        self.gidLoginHandler(nativeResponse, reportedError);
    }
}

@end
