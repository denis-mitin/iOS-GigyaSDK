#import "GSFacebookProvider.h"
#import "Gigya+Internal.h"

#define DEFAULT_FACEBOOK_READ_PERMISSIONS @[@"email"]
#define PUBLISH_PERMISSIONS @[ @"ads_management" , @"create_event", @"manage_friendlists", @"manage_notifications", @"publish_actions" , @"publish_stream" ,@"rsvp_event", @"publish_pages", @"manage_pages" ]
#define TEN_YEARS (10 * 365 * 24 * 60)
#define DISTANT_FUTURE 64092211200.0

#define FB_ACCESS_TOKEN_CHANGED_NOTIFICATION_KEY @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification"

@interface GSFacebookProvider ()
{
    BOOL _isLoggedIn;
    FBSDKLoginManager *_fbLoginManager;
}

@property (nonatomic, copy) GSNativeLoginHandler handler;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, strong) NSDictionary *parameters;
@property (nonatomic, copy) GSPermissionRequestResultHandler permissionsHandler;
@property (nonatomic, strong) NSArray *declinedPermissions;

@end

@implementation GSFacebookProvider

#pragma mark - GSLoginProvider methods
+ (GSFacebookProvider *)instance
{
    return [GSFacebookProvider instanceWithApplication:nil launchOptions:nil];
}

+ (GSFacebookProvider *)instanceWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    static dispatch_once_t onceToken;
    static GSFacebookProvider *instance = nil;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSFacebookProvider alloc] initWithApplication:application launchOptions:launchOptions];
    });
    
    return instance;
}

- (GSFacebookProvider *)initWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    self = [super init];
    Class fbLoginManager = NSClassFromString(@"FBSDKLoginManager");
    Class fbApplicationDelegate = NSClassFromString(@"FBSDKApplicationDelegate");
    
    if (self && fbLoginManager) {
        if (application)
            [(FBSDKApplicationDelegate *)[fbApplicationDelegate sharedInstance] application:application didFinishLaunchingWithOptions:launchOptions];
        
        
        _fbLoginManager = [[fbLoginManager alloc] init];
        _isLoggedIn = NO;
        
        if (![Gigya sharedInstance].touchIDEnabled && [self fbAccessToken])
            _isLoggedIn = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(observeTokenChange:) name:FB_ACCESS_TOKEN_CHANGED_NOTIFICATION_KEY object:nil];
    }
    
    return self;
}

- (NSString *)name
{
    return @"facebook";
}

+ (BOOL)isAppConfiguredForProvider
{
    id plistAppId = [[NSBundle mainBundle] infoDictionary][@"FacebookAppID"];
    id plistAppName = [[NSBundle mainBundle] infoDictionary][@"FacebookDisplayName"];
    
    return ([plistAppId length] > 0 &&
            [plistAppName length] > 0 &&
            NSClassFromString(@"FBSDKLoginManager"));
}

+ (BOOL)isProviderAppInstalled
{
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"fb://"]];
}

- (BOOL)isLoggedIn
{
    return _isLoggedIn;
}

- (void)logout
{
    if (_isLoggedIn) {
        [_fbLoginManager logOut];
        _isLoggedIn = NO;
        GSLog(@"Cleared Facebook session");
    }
}

- (BOOL)handleOpenURL:(NSURL *)url
          application:(UIApplication *)application
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
    Class fbApplicationDelegate = NSClassFromString(@"FBSDKApplicationDelegate");
    Class bfURL = NSClassFromString(@"BFURL");
    
    BOOL wasHandled = [(FBSDKApplicationDelegate *)[fbApplicationDelegate sharedInstance] application:application
                                                                                              openURL:url
                                                                                    sourceApplication:sourceApplication
                                                                                           annotation:annotation];
    
    BFURL *parsedURL = [bfURL URLWithInboundURL:url sourceApplication:sourceApplication];
    if ([parsedURL appLinkData]) {
        NSURL *targetURL = [parsedURL targetURL];
        if (targetURL)
            [[Gigya sharedInstance] reportURLReferral:targetURL provider:@"facebook"];
    }
    
    return wasHandled;
}

- (void)handleDidBecomeActive
{
    Class fbAppEvents = NSClassFromString(@"FBSDKAppEvents");
    [fbAppEvents activateApp];
}

- (void)startNativeLoginForMethod:(NSString *)method
                       parameters:(NSDictionary *)parameters
                   viewController:(UIViewController *)viewController
                completionHandler:(GSNativeLoginHandler)handler
{
    self.parameters = parameters;
    self.method = method;
    self.handler = handler;
    
    // Use the permissions returned from getSDKConfig, and add any permissions the partner has passed in facebookReadPermissions
    NSArray *permissions = [self mergeReadPermissions:DEFAULT_FACEBOOK_READ_PERMISSIONS
                                     extraPermissions:[[Gigya sharedInstance] providerPermissions][@"facebook"]];
    permissions = [self mergeReadPermissions:permissions
                            extraPermissions:[parameters[@"facebookReadPermissions"] componentsSeparatedByString:@","]];
    
    if ([self doesSessionHavePermissions:permissions]) {
        [self finishWithSession:[self fbAccessToken]];
    }
    else {
        if (parameters[@"facebookLoginBehavior"]) {
            _fbLoginManager.loginBehavior = (FBSDKLoginBehavior)[parameters[@"facebookLoginBehavior"] intValue];
        }
        else if (![Gigya sharedInstance].dontLeaveApp || [GSFacebookProvider isProviderAppInstalled]) {
            _fbLoginManager.loginBehavior = FBSDKLoginBehaviorNative;
        }
        else {
            _fbLoginManager.loginBehavior = FBSDKLoginBehaviorWeb;
        }
        
        FBSDKAccessToken *fbAccessTokenBeforeLogin = [self fbAccessToken];
        
        [_fbLoginManager logInWithReadPermissions:permissions fromViewController:viewController handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            FBSDKAccessToken *fbAccessToken = [self fbAccessToken];
            
            if (error) {
                [self finishWithError:error];
            }
            else if (result.isCancelled) {
                error = [NSError errorWithDomain:GSGigyaSDKDomain
                                            code:GSErrorCanceledByUser
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Facebook login canceled" }];
                
                [self finishWithError:error];
            }
            else if (!fbAccessTokenBeforeLogin || ![fbAccessToken.appID isEqualToString:fbAccessTokenBeforeLogin.appID] || ![fbAccessToken.userID isEqualToString:fbAccessTokenBeforeLogin.userID] || ![Gigya isSessionValid]) {
                _isLoggedIn = YES;
                [self finishWithSession:[self fbAccessToken]];
            }
            else {
                [self reportExtendedToken:[self fbAccessToken]];
            }
        }];
    }
}

#pragma mark - Facebook login
// Used when the token is extended and needs to be reported, e.g. getting publish permissions / expiration extended
- (void)reportExtendedToken:(id)session
{
    // Prepare the request data
    NSDictionary* parameters = @{ @"providerSession": [self authDataFromSession:session forRefresh:YES] };
    
    GSRequest *request = [GSRequest requestForMethod:@"refreshProviderSession" parameters:parameters];
    request.useHTTPS = YES;
    [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
        if (!error) {
            GSLog(@"Facebook session was extended, reported successfully to Gigya");
            
            if (self.permissionsHandler) {
                self.permissionsHandler(YES, nil, self.declinedPermissions);
            }
        }
        else {
            GSLog(@"Facebook session was extended, reporting to Gigya failed");
            
            if (self.permissionsHandler) {
                self.permissionsHandler(NO, error, self.declinedPermissions);
            }
        }
        
        self.permissionsHandler = nil;
    }];
}

- (void)finishWithSession:(id)session
{
    if (self.handler) {
        NSDictionary *authData = [self authDataFromSession:session forRefresh:NO];
        self.handler(authData, nil);
    }
}

- (void)finishWithError:(NSError *)facebookError
{
    NSError *error = nil;
    
    if (facebookError.code == GSErrorCanceledByUser)
        error = facebookError;
    else
        error = [self errorFromFacebookError:facebookError];
    
    if (self.handler)
        self.handler(nil, error);
}

#pragma mark - Facebook extra permissions
- (void)requestNewPublishPermissions:(NSString *)permissions
                      viewController:(UIViewController * _Nullable)viewController
                     responseHandler:(GSPermissionRequestResultHandler)handler
{
    [self requestNewPermissions:@"publish"
                    permissions:permissions
                 viewController:viewController
                responseHandler:handler];
}

- (void)requestNewReadPermissions:(NSString *)permissions
                   viewController:(UIViewController * _Nullable)viewController
                  responseHandler:(GSPermissionRequestResultHandler)handler
{
    [self requestNewPermissions:@"read"
                    permissions:permissions
                 viewController:viewController
                responseHandler:handler];
}

- (void)requestNewPermissions:(NSString *)type
                  permissions:(NSString *)permissions
               viewController:(UIViewController * _Nullable)viewController
              responseHandler:(GSPermissionRequestResultHandler)handler
{
    NSArray *permissionsArray = [permissions componentsSeparatedByString:@","];
    self.permissionsHandler = handler;
    BOOL granted = NO;
    NSError *error = nil;
    
    if (![self fbAccessToken]) {
        error = [NSError errorWithDomain:GSGigyaSDKDomain
                                    code:GSErrorNoValidSession
                                userInfo:@{ NSLocalizedDescriptionKey: @"Facebook session is closed, you must login first" }];
    } else {
        granted = [self doesSessionHavePermissions:permissionsArray];
    }
    
    if (granted || error) {
        if (handler)
            handler(granted, error, nil);
    }
    else {
        void (^permissionResponseHandler)(id session, NSError *facebookError) = ^(id session, NSError *facebookError) {
            self.declinedPermissions = [self getDeclinedPermissionsFromArray:permissionsArray];
            
            if (handler && facebookError)
                handler(NO, [self errorFromFacebookError:facebookError], self.declinedPermissions);
        };
        
        Class fbDefaultAudienceFriends = NSClassFromString(@"FBSDKDefaultAudienceFriends");
        ((FBSDKLoginManager *)_fbLoginManager).defaultAudience = (FBSDKDefaultAudience)fbDefaultAudienceFriends;
        
        if ([type isEqualToString:@"publish"])
            [_fbLoginManager logInWithPublishPermissions:permissionsArray fromViewController:viewController handler:permissionResponseHandler];
        else
            [_fbLoginManager logInWithReadPermissions:permissionsArray fromViewController:viewController handler:permissionResponseHandler];
    }
}

#pragma mark - Utility methods
- (NSDictionary *)authDataFromSession:(id)session forRefresh:(BOOL)forRefresh
{
    NSDictionary *result = nil;
    
    if (session) {
        NSDate *expiration = [session expirationDate];
        
        if (forRefresh) {
            result = @{ @"facebook": @{ @"authToken": [session tokenString],
                                        @"tokenExpiration": @([self expirationTimestampForRequest:expiration]) } };
        }
        else {
            result = @{ @"x_providerToken": [session tokenString],
                        @"x_providerTokenExpiration": @([self expirationTimestampForRequest:expiration]) };
        }
    }
    
    return result;
}

- (NSError *)errorFromFacebookError:(NSError *)facebookError
{
    return [NSError errorWithDomain:GSGigyaSDKDomain
                               code:GSErrorProviderError
                           userInfo:@{ NSLocalizedDescriptionKey: @"Operation failed, see provider error",
                                       @"providerError": facebookError }];
}

- (NSTimeInterval)expirationTimestampForRequest:(NSDate *)expiration
{
    // We need to compare the timestamp with the "distant future" constant, because when using FB iOS system account, the token has this default timestamp.
    // Since our server doesn't accept it (conversion from float to double), we replace it with 10 years from now (the server will fetch the real token expiration with a date this far)
    NSTimeInterval expirationTimestamp = [expiration timeIntervalSince1970];
    
    if ((expirationTimestamp == DISTANT_FUTURE) || (expirationTimestamp == 0))
        expirationTimestamp = [[NSDate date] timeIntervalSince1970] + TEN_YEARS;
    
    return expirationTimestamp;
}

- (NSArray *)mergeReadPermissions:(NSArray *)defaultPermissions extraPermissions:(NSArray *)extraPermissions
{
    NSMutableArray *result = [self mergePermissions:defaultPermissions extraPermissions:extraPermissions];
    [result removeObjectsInArray:PUBLISH_PERMISSIONS];
    return result;
}

- (BOOL)doesSessionHavePermissions:(NSArray *)permissions
{
    FBSDKAccessToken *fbAccessToken = [self fbAccessToken];
    if (!fbAccessToken)
        return false;
    
    NSIndexSet* indexes = [permissions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        // Checking if the permission already exists
        return [fbAccessToken hasGranted:obj];
    }];
    
    return ([indexes count] == [permissions count]);
}

- (NSArray *)getDeclinedPermissionsFromArray:(NSArray *)requestedPermissions
{
    NSSet *allDeclinedPermissions = [[self fbAccessToken] declinedPermissions];
    NSArray *declinedPermissions = [requestedPermissions objectsAtIndexes:[requestedPermissions indexesOfObjectsPassingTest:^BOOL(NSString *permission, NSUInteger idx, BOOL *stop) {
        return [allDeclinedPermissions containsObject:permission];
    }]];
    
    return declinedPermissions;
}

- (id)fbAccessToken
{
    Class fbAccessTokenClass = NSClassFromString(@"FBSDKAccessToken");
    return [fbAccessTokenClass currentAccessToken];
}

- (void)observeTokenChange:(NSNotification *)notfication
{
    if (!_isLoggedIn || ![Gigya isSessionValid])
        return;
    
    FBSDKAccessToken *fbAccessToken = [self fbAccessToken];
    if (fbAccessToken)
        [self reportExtendedToken:fbAccessToken];
}

@end
