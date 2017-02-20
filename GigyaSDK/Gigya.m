#import "Gigya.h"
#import "Gigya+Internal.h"

@interface Gigya ()

@property (nonatomic) BOOL sessionLoaded;
@property (nonatomic, strong) GSSession *session;
@property (nonatomic) BOOL touchIDEnabled;
@property (nonatomic, copy) NSString *touchIDMessage;
@property (nonatomic, copy) NSString *APIKey;
@property (nonatomic, copy) NSString *APIDomain;
@property (nonatomic) BOOL useHTTPS;
@property (nonatomic) BOOL dontLeaveApp;
@property (nonatomic) BOOL networkActivityIndicatorEnabled;
@property (nonatomic) NSTimeInterval requestTimeout;

@property (nonatomic) NSTimeInterval serverTimeSkew;
@property (nonatomic, strong) NSArray *errorsToReport;

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
@property (nonatomic, weak) id<GSSessionDelegate> sessionDelegate;
#pragma GCC diagnostic warning "-Wdeprecated-declarations"

@property (nonatomic, weak) id<GSSocializeDelegate> socializeDelegate;
@property (nonatomic, weak) id<GSAccountsDelegate> accountsDelegate;

@property (nonatomic, strong) NSMutableArray *socializeDelegatesArray;
@property (nonatomic, strong) NSMutableArray *accountsDelegatesArray;

@property (nonatomic, strong) NSDictionary *providerPermissions;

@property (nonatomic, copy) NSString *ucid;
@property (nonatomic, copy) NSString *gmid;

@property (nonatomic) BOOL __debugOptionEnableTestNetworks;

@end

@implementation Gigya

#pragma mark - Init methods
+ (void)initWithAPIKey:(NSString *)key application:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions
{
    [Gigya initWithAPIKey:key application:application launchOptions:launchOptions APIDomain:nil];
}

+ (void)initWithAPIKey:(NSString *)key application:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions APIDomain:(NSString *)domain
{
    [Gigya sharedInstance].APIKey = key;

    if ([domain length] == 0)
        domain = GSDefaultAPIDomain;

    [Gigya sharedInstance].APIDomain = domain;
    [GSLoginManager sharedInstanceWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions];
    [GSWebBridgeManager sharedInstance];
    GSLog(@"Initialized with API Key: %@, API Domain: %@", [Gigya sharedInstance].APIKey, [Gigya sharedInstance].APIDomain);

    // All use standardUserDefault. Important to synchronize in the end.
    [[Gigya sharedInstance] loadIDs];
    [[Gigya sharedInstance] getSDKConfig];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Singleton
- (Gigya *)init
{
    self = [super init];

    if (self) {
        self.sessionLoaded = NO;
        self.__debugOptionEnableTestNetworks = NO;
        self.useHTTPS = YES;
        self.networkActivityIndicatorEnabled = YES;
        self.socializeDelegatesArray = [NSMutableArray array];
        self.accountsDelegatesArray = [NSMutableArray array];

        NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];

        if ([infoDict valueForKey:@"GigyaLoginDontLeaveApp"])
            self.dontLeaveApp = [[infoDict valueForKey:@"GigyaLoginDontLeaveApp"] boolValue];
        else
            self.dontLeaveApp = YES;

        if ([infoDict valueForKey:@"GigyaTouchIDEnabled"])
            self.touchIDEnabled = [[infoDict valueForKey:@"GigyaTouchIDEnabled"] boolValue];
        else
            self.touchIDEnabled = NO; // for backward compatible

        if ([infoDict valueForKey:@"GigyaTouchIDMessage"])
            self.touchIDMessage = [infoDict valueForKey:@"GigyaTouchIDMessage"];
        else
            self.touchIDMessage = @"Please authenticate to proceed";
    }

    return self;
}

+ (Gigya *)sharedInstance
{
    static dispatch_once_t onceToken;
    static Gigya *instance = nil;

    dispatch_once(&onceToken, ^{
        instance = [[Gigya alloc] init];
    });

    return instance;
}

#pragma mark - Static "Properties"
+ (void)getSessionWithCompletionHandler:(GSGetSessionCompletionHandler _Nonnull)handler
{
    return [[Gigya sharedInstance] getSessionWithCompletionHandler:handler];
}

+ (BOOL)isSessionValid
{
    return [[Gigya sharedInstance] isSessionValid];
}

+ (void)setSession:(GSSession *)session
{
    [Gigya setSession:session completionHandler:nil];
}

+ (NSString*)APIKey
{
    return [Gigya sharedInstance].APIKey;
}

+ (NSString*)APIDomain
{
    return [Gigya sharedInstance].APIDomain;
}

+ (BOOL)useHTTPS
{
    return [Gigya sharedInstance].useHTTPS;
}

+ (void)setUseHTTPS:(BOOL)useHTTPS
{
    [Gigya sharedInstance].useHTTPS = useHTTPS;
}

+ (BOOL)networkActivityIndicatorEnabled
{
    return [Gigya sharedInstance].networkActivityIndicatorEnabled;
}

+ (void)setNetworkActivityIndicatorEnabled:(BOOL)networkActivityIndicatorEnabled
{
    [Gigya sharedInstance].networkActivityIndicatorEnabled = networkActivityIndicatorEnabled;
}

+ (NSTimeInterval)requestTimeout
{
    return [Gigya sharedInstance].requestTimeout;
}

+ (void)setRequestTimeout:(NSTimeInterval)requestTimeout
{
    [Gigya sharedInstance].requestTimeout = requestTimeout;
}

+ (BOOL)dontLeaveApp
{
    return [Gigya sharedInstance].dontLeaveApp;
}

+ (void)setDontLeaveApp:(BOOL)dontLeaveApp
{
    [Gigya sharedInstance].dontLeaveApp = dontLeaveApp;
}

+ (BOOL)__debugOptionEnableTestNetworks
{
    return [Gigya sharedInstance].__debugOptionEnableTestNetworks;
}

+ (void)__setDebugOptionEnableTestNetworks:(BOOL)debugOptionEnableTestNetworks
{
     [Gigya sharedInstance].__debugOptionEnableTestNetworks = debugOptionEnableTestNetworks;
}

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
+ (id<GSSessionDelegate>)sessionDelegate
{
    return [Gigya sharedInstance].sessionDelegate;
}

+ (void)setSessionDelegate:(id<GSSessionDelegate>)delegate
{
    [Gigya sharedInstance].sessionDelegate = delegate;
}
#pragma GCC diagnostic warning "-Wdeprecated-declarations"

+ (id<GSSocializeDelegate>)socializeDelegate
{
    return [Gigya sharedInstance].socializeDelegate;
}

+ (void)setSocializeDelegate:(id<GSSocializeDelegate>)delegate
{
    [[Gigya sharedInstance].socializeDelegatesArray removeObject:[Gigya sharedInstance].socializeDelegate];

    if (delegate) {
        [[Gigya sharedInstance] addSocializeDelegate:delegate];
        [Gigya sharedInstance].socializeDelegate = delegate;
    }
}

+ (id<GSAccountsDelegate>)accountsDelegate
{
    return [Gigya sharedInstance].accountsDelegate;
}

+ (void)setAccountsDelegate:(id<GSAccountsDelegate>)delegate
{
    [[Gigya sharedInstance].accountsDelegatesArray removeObject:[Gigya sharedInstance].accountsDelegate];

    if (delegate) {
        [[Gigya sharedInstance] addAccountsDelegate:delegate];
        [Gigya sharedInstance].accountsDelegate = delegate;
    }
}

- (void)addSocializeDelegate:(id<GSSocializeDelegate>)delegate
{
    if (![self.socializeDelegatesArray containsObject:delegate])
        [self.socializeDelegatesArray addObject:delegate];
}

- (void)addAccountsDelegate:(id<GSAccountsDelegate>)delegate
{
    if (![self.accountsDelegatesArray containsObject:delegate])
        [self.accountsDelegatesArray addObject:delegate];
}

- (void)removeDelegate:(id)delegate
{
    [self.socializeDelegatesArray removeObject:delegate];
    [self.accountsDelegatesArray removeObject:delegate];
}

#pragma mark - SDK Configuration
- (void)getSDKConfig
{
    // Load the config from the server
    GSRequest *request = [GSRequest requestForMethod:@"getSDKConfig"];
    request.includeAuthInfo = NO;
    request.useHTTPS = YES;

    NSString *include = @"permissions";
    if (!self.gmid || !self.ucid)
        include = [NSString stringWithFormat:@"%@,ids", include];

    (request.parameters)[@"include"] = include;
    (request.parameters)[@"apikey"] = [Gigya sharedInstance].APIKey;
    (request.parameters)[@"noAuth"] = @YES;

    [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
        // Set the error codes that should be reported back to the server
        if (!error) {
            id errorReportRules = response[@"errorReportRules"];

            if ([errorReportRules isKindOfClass:[NSArray class]]) {
                self.errorsToReport = errorReportRules;
            }

            [self saveIDs:response[@"ids"]];
            self.providerPermissions = response[@"permissions"];
        }
    }];
}

- (void)loadIDs
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.ucid = [defaults objectForKey:GSUCIDDefaultsKey];
    self.gmid = [defaults objectForKey:GSGMIDDefaultsKey];
}

- (void)saveIDs:(NSDictionary *)ids
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if (!self.ucid && ids[@"ucid"]) {
        self.ucid = ids[@"ucid"];
        [defaults setObject:self.ucid forKey:GSUCIDDefaultsKey];
    }

    if (!self.gmid && ids[@"gmid"]) {
        self.gmid = ids[@"gmid"] ? ids[@"gmid"] : ids[@"gcid"];
        [defaults setObject:self.gmid forKey:GSGMIDDefaultsKey];
    }

    [defaults synchronize];
}

// Migrates UCID from cookie store (from versions <3.0)
- (void)migrateUCID
{
    __block NSString *ucidCookie = nil;

    // Remove all cookies except for ucid
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    [[cookieStorage cookies] enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger idx, BOOL *stop) {
        if ([[cookie name] isEqualToString:@"ucid"]) {
            ucidCookie = [cookie.value copy];
            [cookieStorage deleteCookie:cookie];
        }
        else if ([[cookie name] isEqualToString:@"gmid"]) {
            [cookieStorage deleteCookie:cookie];
        }
    }];

    if ([ucidCookie length] > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:ucidCookie forKey:GSUCIDDefaultsKey];
    }
}

- (void)checkSDKInit
{
    if ([self.APIKey length] == 0) {
        [NSException raise:GSInvalidOperationException
                    format:@"GigyaSDK was not initialized, please make sure you call [Gigya initWithAPIKey:] in your AppDelegate's didFinishLaunchingWithOptions"];
    }
}

#pragma mark - Session handling
- (void)setSession:(GSSession *)session completionHandler:(GSSetSessionCompletionHandler _Nullable)handler
{
    if (![session isEqual:self.session]) {
        self.session = session;
        self.sessionLoaded = YES;

        [self saveSessionWithCompletionHandler:handler];
    }
    else if (handler) {
        handler(nil);
    }
}

- (void)getSessionWithCompletionHandler:(GSGetSessionCompletionHandler _Nonnull)handler
{
    if (self.sessionLoaded)
        handler(self.session);
    else
        [self loadSessionWithCompletionHandler:handler];
}

- (void)invokeSelectorOnSocializeDelegates:(SEL)selector withObject:(GSObject *)object
{
    if ([self.sessionDelegate respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.sessionDelegate performSelector:selector withObject:object];
#pragma clang diagnostic pop
    }

    NSArray *socializeDelegatesArray = [self.socializeDelegatesArray copy];

    for (id<GSSocializeDelegate> delegate in socializeDelegatesArray) {
        if ([delegate respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [delegate performSelector:selector withObject:object];
#pragma clang diagnostic pop
        }
    }
}

- (void)invokeSelectorOnAccountsDelegates:(SEL)selector withObject:(GSObject *)object
{
    NSArray *accountsDelegatesArray = [self.accountsDelegatesArray copy];

    for (id<GSAccountsDelegate> delegate in accountsDelegatesArray) {
        if ([delegate respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [delegate performSelector:selector withObject:object];
#pragma clang diagnostic pop
        }
    }
}

+ (void)updateUserInfo
{
    [Gigya updateUserInfoWithSessionChanged:NO completionHandler:nil];
}

+ (void)updateUserInfoWithSessionChanged:(BOOL)sessionChanged
                       completionHandler:(GSUserInfoHandler _Nullable)handler
{
    // update user info cached in the SDK
    if (handler || [[Gigya sharedInstance].socializeDelegatesArray count] > 0) {
        NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
        if ([Gigya __debugOptionEnableTestNetworks])
            params[@"enabledProviders"] = @"*,testnetwork3,testnetwork4";

        GSRequest *request = [GSRequest requestForMethod:@"socialize.getUserInfo" parameters:params];
        [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
            // If a real getUserInfo response (without error) was received, returning the user
            GSUser *user = nil;
            if (!error)
                user = (GSUser *)response;

            if (handler)
                handler(user, error);

            if (user) {
                // Global delegate method for user login
                if (sessionChanged)
                    [[Gigya sharedInstance] invokeSelectorOnSocializeDelegates:@selector(userDidLogin:) withObject:user];

                // Global delegate method for user change
                [[Gigya sharedInstance] invokeSelectorOnSocializeDelegates:@selector(userInfoDidChange:) withObject:user];
            }
        }];
    }

    if ([[Gigya sharedInstance].accountsDelegatesArray count] > 0) {
        NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
        if ([Gigya __debugOptionEnableTestNetworks])
            params[@"enabledProviders"] = @"*,testnetwork3,testnetwork4";

        GSRequest *request = [GSRequest requestForMethod:@"accounts.getAccountInfo" parameters:params];
        [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
            if (!error) {
                GSAccount *account = (GSAccount *)response;

                // Global delegate method for user login
                if (sessionChanged)
                    [[Gigya sharedInstance] invokeSelectorOnAccountsDelegates:@selector(accountDidLogin:) withObject:account];
            }
        }];
    }
}

+ (void)setSession:(GSSession *)session completionHandler:(GSUserInfoHandler _Nullable)handler
{
    GSSession *currentSession = [Gigya sharedInstance].session; // access session directly to prevent two touchID popups
    BOOL sessionChanged = YES;

    if (currentSession && session && [currentSession isEqual:session])
        sessionChanged = NO;

    [[Gigya sharedInstance] setSession:session completionHandler:^(NSError * _Nullable error) {
        [Gigya updateUserInfoWithSessionChanged:sessionChanged completionHandler:handler];
    }];
}

- (void)saveSessionWithCompletionHandler:(GSSetSessionCompletionHandler _Nullable)handler
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    [self deleteSessionFromUserDefaults:userDefaults];
    [userDefaults removeObjectForKey:GSSessionInfoUserDefaultsKey];
    [userDefaults synchronize];

    [KeychainStorage removeDataForAttributeName:GSSessionKeychainKey
                                    serviceName:GSGigyaSDKDomain
                              completionHandler:^(NSError *deleteError){
                                  if (!deleteError) {
                                      GSLog(@"Saved session delete failed: %@", deleteError);
                                  }

                                  if (self.session) {
                                      KeychainPasscodeOptions passcodeOption = keychainPreferPasscode;
                                      if (!self.touchIDEnabled)
                                          passcodeOption = keychainIgnorePasscode;

                                      NSData *encodedSession = [NSKeyedArchiver archivedDataWithRootObject:self.session];
                                      [KeychainStorage addDataWithAuthenticationUI:encodedSession
                                                                         dummyData:[NSKeyedArchiver archivedDataWithRootObject:[GSSession alloc]]
                                                                     attributeName:GSSessionKeychainKey
                                                                       serviceName:GSGigyaSDKDomain
                                                                    passcodeOption:passcodeOption
                                                              authenticationPrompt:self.touchIDMessage
                                                                 completionHandler:^(NSError *setError) {
                                                                     if (setError) {
                                                                         [[GSLoginManager sharedInstance] clearSessionAfterLogout];
                                                                         
                                                                         if (handler)
                                                                             handler(setError);
                                                                         
                                                                         return;
                                                                     }
                                                                     
                                                                     NSData *encodedSessionInfo = [NSKeyedArchiver archivedDataWithRootObject:self.session.info];
                                                                     [userDefaults setObject:encodedSessionInfo forKey:GSSessionInfoUserDefaultsKey];
                                                                     [userDefaults synchronize];
                                                                     GSLog(@"Saved session in storage: %@", self.session);
                                                                     
                                                                     if (handler)
                                                                         handler(nil);
                                                                 }];
                                  }
                                  else {
                                      GSLog(@"Removed saved session from storage");
                                      
                                      if (handler)
                                          handler(nil);
                                  }
                              }];
}

- (BOOL)isSessionValid
{
    if (!self.sessionLoaded) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

        NSData *sessionInfoData = [userDefaults objectForKey:GSSessionInfoUserDefaultsKey];

        if (sessionInfoData) {
            GSSessionInfo *sessionInfo = (GSSessionInfo *)[NSKeyedUnarchiver unarchiveObjectWithData:sessionInfoData];

            if ([sessionInfo isValid]) {
                return YES;
            }
            else {
                self.sessionLoaded = YES; // no need to perform this check again

                [self deleteSessionFromKeychain:userDefaults];
                [userDefaults synchronize];

                return NO;
            }
        }

        self.sessionLoaded = YES;
        [self loadSessionFromUserDefaults:userDefaults];
    }

    if (!self.session)
        return NO;

    return [self.session isValid];

}

- (void)deleteSessionFromUserDefaults:(NSUserDefaults *)userDefaults
{
    [userDefaults removeObjectForKey:GSSessionUserDefaultsKey];
    [userDefaults removeObjectForKey:GSSessionAPIKeyUserDefaultsKey];
}

- (void)deleteSessionFromKeychain:(NSUserDefaults *)userDefaults
{
    [userDefaults removeObjectForKey:GSSessionInfoUserDefaultsKey];
    [KeychainStorage removeDataForAttributeName:GSSessionKeychainKey
                                    serviceName:GSGigyaSDKDomain
                              completionHandler:nil];
}

- (void)loadSessionFromUserDefaults:(NSUserDefaults *)userDefaults
{
    GSLog(@"Attempt to load saved session from user defaults");
    NSString *encodedAPIKey = [userDefaults objectForKey:GSSessionAPIKeyUserDefaultsKey];

    // If this is the same API key as last SDK init, loading the session
    if (!encodedAPIKey || [encodedAPIKey isEqual:self.APIKey]) {

        NSData *encodedSession = [userDefaults objectForKey:GSSessionUserDefaultsKey];
        if (encodedSession) {
            _session = (GSSession *)[NSKeyedUnarchiver unarchiveObjectWithData:encodedSession];

            if (_session && [_session isValid]) {
                GSLog(@"Loaded saved session from user defaults: %@", _session);
            }
            else {
                _session = nil;
            }
        }
    }
}

- (void)loadSessionWithCompletionHandler:(GSGetSessionCompletionHandler)handler
{
    _session = nil; // prevent triggering of saveSession from setSession
    self.sessionLoaded = YES; // prevent multiple loads
    BOOL waitingForKeychain = NO;
    __block BOOL clearKeychainSession = NO;

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    // Load session from the key chain

    KeychainStorageGetDataHandler completionHandler = ^(NSData *keychainSessionData, NSError *keychainError) {
        BOOL clearUserDefaultsSession = NO;

        if (keychainSessionData) {
            _session = (GSSession *)[NSKeyedUnarchiver unarchiveObjectWithData:keychainSessionData];

            if (_session && [_session isValid]) {
                GSLog(@"Loaded saved session from keychain: %@", _session);
                clearUserDefaultsSession = YES;
            }
            else {
                _session = nil;
                clearKeychainSession = YES;
            }
        }
        else {
            clearKeychainSession = YES;
        }

        if (!_session) {
            [self loadSessionFromUserDefaults:userDefaults];

            if (!_session)
                clearUserDefaultsSession = YES;
        }
        
        if (clearUserDefaultsSession && clearKeychainSession) {
            [[GSLoginManager sharedInstance] clearSessionAfterLogout];
        }
        else if (clearUserDefaultsSession) {
            [self deleteSessionFromUserDefaults:userDefaults];
        }
        else if (clearKeychainSession) {
            [self deleteSessionFromKeychain:userDefaults];
        }

        [userDefaults synchronize];

        dispatch_async(dispatch_get_main_queue(), ^{
            handler(_session);
        });
    };

    NSData *sessionInfoData = [userDefaults objectForKey:GSSessionInfoUserDefaultsKey];

    if (sessionInfoData) {
        GSSessionInfo *sessionInfo = (GSSessionInfo *)[NSKeyedUnarchiver unarchiveObjectWithData:sessionInfoData];

        if ([sessionInfo isValid]) {
            GSLog(@"Attempt to load saved session from keychain");
            waitingForKeychain = YES;
            [KeychainStorage getDataForAttributeName:GSSessionKeychainKey
                                         serviceName:GSGigyaSDKDomain
                                authenticationPrompt:self.touchIDMessage
                                   completionHandler:completionHandler];
        }
        else {
            clearKeychainSession = YES;
        }
    }
    else {
        clearKeychainSession = YES;
    }

    if (!waitingForKeychain)
        completionHandler(nil, nil);
}

#pragma mark - Login Methods

+ (void)loginToProvider:(NSString * _Nonnull)provider
{
    [self loginToProvider:provider
               parameters:nil
        completionHandler:nil];
}

+ (void)loginToProvider:(NSString * _Nonnull)provider
             parameters:(NSDictionary * _Nullable)params
      completionHandler:(GSUserInfoHandler _Nullable)handler
{
    [self loginToProvider:provider
               parameters:params
                     over:nil
        completionHandler:handler];
}

+ (void)loginToProvider:(NSString * _Nonnull)provider
             parameters:(NSDictionary * _Nullable)params
                   over:(UIViewController * _Nullable)viewController
      completionHandler:(GSUserInfoHandler _Nullable)handler
{
    [self showDialogForMethod:@"socialize.login"
               viewController:viewController
                  popoverView:nil
                    providers:@[ provider ]
                   parameters:params
            completionHandler:handler];
}

+ (void)addConnectionToProvider:(NSString *)provider
{
    [self addConnectionToProvider:provider
                       parameters:nil
                completionHandler:nil];
}

+ (void)addConnectionToProvider:(NSString *)provider
                     parameters:(NSDictionary *)params
              completionHandler:(GSUserInfoHandler)handler
{
    [self addConnectionToProvider:provider
                       parameters:params
                             over:nil
                completionHandler:handler];
}

+ (void)addConnectionToProvider:(NSString *)provider
                     parameters:(NSDictionary *)params
                           over:(UIViewController *)viewController
              completionHandler:(GSUserInfoHandler)handler
{
    [self showDialogForMethod:@"socialize.addConnection"
               viewController:viewController
                  popoverView:nil
                    providers:@[ provider ]
                   parameters:params
            completionHandler:handler];
}

+ (void)showLoginProvidersDialogOver:(UIViewController *)viewController
{
    [self showProvidersDialogOver:viewController
                        providers:nil
                   providerAction:GSProviderActionLogin
                       parameters:nil
                completionHandler:nil];
}

+ (void)showLoginProvidersDialogOver:(UIViewController *)viewController
                           providers:(NSArray *)providers
                          parameters:(NSDictionary *)params
                   completionHandler:(GSUserInfoHandler)handler
{
    [self showProvidersDialogOver:viewController
                        providers:providers
                   providerAction:GSProviderActionLogin
                       parameters:params
                completionHandler:handler];
}

+ (void)showLoginProvidersPopoverFrom:(UIView *)view
{
    [self showProvidersPopoverFrom:view
                         providers:nil
                    providerAction:GSProviderActionLogin
                        parameters:nil
                 completionHandler:nil];
}

+ (void)showLoginProvidersPopoverFrom:(UIView *)view
                            providers:(NSArray *)providers
                           parameters:(NSDictionary *)params
                    completionHandler:(GSUserInfoHandler)handler
{
    [self showProvidersPopoverFrom:view
                         providers:providers
                    providerAction:GSProviderActionLogin
                        parameters:params
                 completionHandler:handler];
}

+ (void)showAddConnectionProvidersDialogOver:(UIViewController *)viewController
{
    [self showProvidersDialogOver:viewController
                        providers:nil
                   providerAction:GSProviderActionAddConnection
                       parameters:nil
                completionHandler:nil];
}

+ (void)showAddConnectionProvidersDialogOver:(UIViewController *)viewController
                                   providers:(NSArray *)providers
                                  parameters:(NSDictionary *)params
                           completionHandler:(GSUserInfoHandler)handler
{
    [self showProvidersDialogOver:viewController
                        providers:providers
                   providerAction:GSProviderActionAddConnection
                       parameters:params
                completionHandler:handler];
}

+ (void)showAddConnectionProvidersPopoverFrom:(UIView *)view
{
    [self showProvidersPopoverFrom:view
                        providers:nil
                   providerAction:GSProviderActionAddConnection
                       parameters:nil
                completionHandler:nil];
 }

+ (void)showAddConnectionProvidersPopoverFrom:(UIView *)view
                                    providers:(NSArray *)providers
                                   parameters:(NSDictionary *)params
                            completionHandler:(GSUserInfoHandler)handler
{
    [self showProvidersPopoverFrom:view
                        providers:providers
                   providerAction:GSProviderActionAddConnection
                       parameters:params
                completionHandler:handler];
}

+ (void)showProvidersDialogOver:(UIViewController *)viewController
                      providers:(NSArray *)providers
                 providerAction:(GSProviderAction)action
                     parameters:(NSDictionary *)params
              completionHandler:(GSUserInfoHandler)handler
{
    NSString *method = @"socialize.login";

    if (action == GSProviderActionAddConnection)
        method = @"socialize.addConnection";

    [self showDialogForMethod:method
               viewController:viewController
                  popoverView:nil
                    providers:providers
                   parameters:params
            completionHandler:handler];
}

+ (void)showProvidersPopoverFrom:(UIView *)view
                       providers:(NSArray *)providers
                  providerAction:(GSProviderAction)action
                      parameters:(NSDictionary *)params
               completionHandler:(GSUserInfoHandler)handler
{
    NSString *method = @"socialize.login";

    if (action == GSProviderActionAddConnection)
        method = @"socialize.addConnection";

    [self showDialogForMethod:method
               viewController:nil
                  popoverView:view
                    providers:providers
                   parameters:params
            completionHandler:handler];
}

+ (void)showDialogForMethod:(NSString *)method
             viewController:(UIViewController *)viewController
                popoverView:(UIView *)view
                  providers:(NSArray *)providers
                 parameters:(NSDictionary *)params
          completionHandler:(GSUserInfoHandler)handler
{
    [[Gigya sharedInstance] checkSDKInit];

    // If this is add connection, we must pass the oauth token too
    if ([method isEqualToString:@"socialize.login"]) {
        if ([Gigya sharedInstance].dontLeaveApp && !viewController && !view) {
            [NSException raise:GSInvalidOperationException
                        format:@"A view controller must be provided if the GigyaLoginDontLeaveApp setting is enabled. Use the [Gigya loginToProvider:parameters:over:completionHandler:] method."];
        }
        else if ([Gigya isSessionValid] && (!params[@"loginMode"] || ![params[@"loginMode"] isEqualToString:@"reAuth"])) {
            [NSException raise:GSInvalidOperationException
                        format:@"Already logged in, log out before attempting to login again"];
        }
    }
    else if ([method isEqualToString:@"socialize.addConnection"]) {
        if ([Gigya sharedInstance].dontLeaveApp && !viewController && !view) {
            [NSException raise:GSInvalidOperationException
                        format:@"A view controller must be provided if the GigyaLoginDontLeaveApp setting is enabled. Use the [Gigya addConnectionToProvider:parameters:over:completionHandler:] method."];
        }
        else if (![Gigya isSessionValid]) {
            [NSException raise:GSInvalidOperationException
                        format:@"AddConnection cannot be called when not logged in"];
        }
    }

    if (params)
        params = [params mutableCopy];
    else
        params = [NSMutableDictionary dictionary];

    [[GSLoginManager sharedInstance] startLoginForMethod:method
                                               providers:providers
                                              parameters:(NSMutableDictionary *)params
                                          viewController:viewController
                                             popoverView:view
                                       completionHandler:handler];
}

#pragma mark - Logout Methods
+ (void)logoutWithCompletionHandler:(GSResponseHandler)handler
{
    [[Gigya sharedInstance] checkSDKInit];

    [[GSLoginManager sharedInstance] logoutWithCompletionHandler:handler];
}

+ (void)logout
{
    [self logoutWithCompletionHandler:nil];
}

+ (void)removeConnectionToProvider:(NSString *)provider
                 completionHandler:(GSUserInfoHandler)handler
{
    [[Gigya sharedInstance] checkSDKInit];

    [[GSLoginManager sharedInstance] removeConnectionToProvider:provider
                                              completionHandler:handler];
}

+ (void)removeConnectionToProvider:(NSString *)provider
{
    [self removeConnectionToProvider:provider
                   completionHandler:nil];
}

#pragma mark - Plugins UI Methods
+ (void)showPluginDialogOver:(UIViewController *)viewController
                      plugin:(NSString *)plugin
                  parameters:(NSDictionary *)parameters
{
    [Gigya showPluginDialogOver:viewController
                     plugin:plugin
                     parameters:parameters
              completionHandler:nil
                       delegate:nil];
}

+ (void)showPluginDialogOver:(UIViewController *)viewController
                      plugin:(NSString *)plugin
                  parameters:(NSDictionary *)parameters
           completionHandler:(GSPluginCompletionHandler)handler
{
    [Gigya showPluginDialogOver:viewController
                         plugin:plugin
                     parameters:parameters
              completionHandler:handler
                       delegate:nil];
}

+ (void)showPluginDialogOver:(UIViewController *)viewController
                      plugin:(NSString *)plugin
                  parameters:(NSDictionary *)parameters
           completionHandler:(GSPluginCompletionHandler)handler
                    delegate:(id<GSPluginViewDelegate>)delegate
{
    [[GSWebBridgeManager sharedInstance] showPluginViewDialogOver:viewController
                                                           plugin:plugin
                                                       parameters:parameters
                                                         delegate:delegate
                                                   dismissHandler:handler];
}

#pragma mark - Deprecated Login Methods
// Deprecated
+ (void)showLoginDialogOver:(UIViewController *)viewController
                   provider:(NSString *)provider
{
    [self loginToProvider:provider];
}

// Deprecated
+ (void)showLoginDialogOver:(UIViewController *)viewController
                   provider:(NSString *)provider
                 parameters:(NSDictionary *)params
          completionHandler:(GSUserInfoHandler)handler
{
    [self loginToProvider:provider
               parameters:params
        completionHandler:handler];
}

// Deprecated
+ (void)showAddConnectionDialogOver:(UIViewController *)viewController
                           provider:(NSString *)provider
{
    [self addConnectionToProvider:provider];
}

// Deprecated
+ (void)showAddConnectionDialogOver:(UIViewController *)viewController
                           provider:(NSString *)provider
                         parameters:(NSDictionary *)params
                  completionHandler:(GSUserInfoHandler)handler
{
    [self addConnectionToProvider:provider
                       parameters:params
                completionHandler:handler];
}

#pragma mark - App lifecycle
+ (BOOL)handleOpenURL:(NSURL *)url
                  app:(UIApplication *)app
              options:(NSDictionary<NSString *, id> *)options
{
    return [self handleOpenURL:url
                   application:app
             sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]
                    annotation:options[UIApplicationOpenURLOptionsAnnotationKey]];
}

+ (BOOL)handleOpenURL:(NSURL *)url application:(UIApplication *)application sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([self.APIKey length] == 0)
        return NO;
    
    return [[GSLoginManager sharedInstance] handleOpenURL:url
                                              application:application
                                        sourceApplication:sourceApplication
                                               annotation:annotation];
}

+ (void)handleDidBecomeActive
{
    [[GSLoginManager sharedInstance] handleDidBecomeActive];
}

#pragma mark - Referrals
- (void)reportURLReferral:(NSURL *)url provider:(NSString *)provider
{
    NSURL *reportURL = [NSURL URLForGigyaReferralReportForURL:url
                                                     provider:provider];

    NSURLRequest *request = [NSURLRequest requestWithURL:reportURL
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:0];

   NSURLSession *session = [NSURLSession sharedSession];
    
   NSURLSessionTask *task = [session dataTaskWithRequest:request
                                       completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error){
                                           // Handler here to eliminate calls to the applicaton delegate on the sharedSession that could be an app delegate
                                       }];

   [task resume];
}

#pragma mark - Misc
- (void)showNetworkActivityIndicator
{
    if (self.networkActivityIndicatorEnabled)
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

+ (void)requestNewFacebookPublishPermissions:(NSString *)permissions
                              viewController:(UIViewController * _Nullable)viewController
                             responseHandler:(GSPermissionRequestResultHandler)handler
{
    [[GSLoginManager sharedInstance] requestNewFacebookPublishPermissions:permissions
                                                           viewController:viewController
                                                          responseHandler:handler];
}

+ (void)requestNewFacebookReadPermissions:(NSString *)permissions
                           viewController:(UIViewController * _Nullable)viewController
                          responseHandler:(GSPermissionRequestResultHandler)handler
{
    [[GSLoginManager sharedInstance] requestNewFacebookReadPermissions:permissions
                                                        viewController:viewController
                                                       responseHandler:handler];
}

#pragma mark - Teardown

@end
