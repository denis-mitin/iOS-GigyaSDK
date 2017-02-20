#import "GSWebBridge.h"
#import "Gigya+Internal.h"

@interface GSWebBridge ()

@property (nonatomic, weak) id webView;
@property (nonatomic, weak) id<GSWebBridgeDelegate> delegate;
@property (nonatomic, copy) NSString *bridgeID;
@property (nonatomic, copy) NSDictionary *settings;

@end

@implementation GSWebBridge

#pragma mark - Init Methods
- (instancetype) initWithWebView:(id)webView delegate:(id<GSWebBridgeDelegate>)delegate settings:(NSDictionary *)settings
{
    self = [super init];
    
    if (self) {
        self.webView = webView;
        self.delegate = delegate;
        self.bridgeID = [NSString stringWithFormat:@"js_%@", [NSString GSGUIDString]];
        self.settings = settings ? settings : @{};
    }
    
    return self;
}


#pragma mark - External Class Methods
+ (void)webViewDidStartLoad:(UIWebView *)webView
{
    GSWebBridge *bridge = [[GSWebBridgeManager sharedInstance] bridgeForWebView:webView];
    [webView stringByEvaluatingJavaScriptFromString:[GSWebBridge adapterSettingsJS:bridge]];
}

+ (BOOL)handleRequest:(NSURLRequest *)request webView:(id)webView
{
    NSURL *url = [request URL];
    
    if ([[url absoluteString] hasPrefix:GSRedirectURLScheme]) {
        GSWebBridge *bridge = [[GSWebBridgeManager sharedInstance] bridgeForWebView:webView];
        return [bridge handleURL:url];
    }
    
    return NO;
}

+ (void)registerWebView:(id)webView delegate:(id<GSWebBridgeDelegate>)delegate
{
    [self registerWebView:webView delegate:delegate settings:nil];
}

+ (void)registerWebView:(id)webView delegate:(id<GSWebBridgeDelegate>)delegate settings:(NSDictionary *)settings
{
    GSWebBridge *bridge = [[GSWebBridgeManager sharedInstance] bridgeForWebView:webView];
    if (!bridge) {
        bridge = [[GSWebBridge alloc] initWithWebView:webView delegate:delegate settings:settings];
        [[GSWebBridgeManager sharedInstance] addBridge:bridge];
    }
    
    if ([webView isKindOfClass:[UIWebView class]])
        return;
    
    Class wkUserScript = NSClassFromString(@"WKUserScript");
    WKUserScript *beforeLoadScript = [[wkUserScript alloc] initWithSource:[GSWebBridge adapterSettingsJS:bridge]
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:NO];
    
    [[[(WKWebView *)webView configuration] userContentController] addUserScript:beforeLoadScript];
}

+ (void)unregisterWebView:(id)webView
{
    GSWebBridge *bridge = [[GSWebBridgeManager sharedInstance] bridgeForWebView:webView];
    bridge.webView = nil;
    bridge.delegate = nil;
    [[Gigya sharedInstance] removeDelegate:bridge];
    [[GSWebBridgeManager sharedInstance] removeBridge:bridge];
}

+ (NSString *)adapterSettingsJS:(GSWebBridge *)bridge {
    return [NSString stringWithFormat:
            @"window.__gigAPIAdapterSettings = { "
                "getAdapterName: function() { return 'mobile'; },"
                "getAPIKey: function() { return '%@'; },"
                "getFeatures: function() { return '%@'; },"
                "getSettings: function() { return '%@'; }"
            " };",
            [Gigya APIKey],
            [GS_WEB_BRIDGE_SUPPORTED_FEATURES GSJSONString],
            [bridge.settings GSJSONString]];
}

#pragma mark - JS -> Mobile
- (BOOL)handleURL:(NSURL *)url
{
    NSString *action = [url host];
    NSDictionary *query = [NSDictionary GSDictionaryWithURLQueryString:[url query]];
    NSString *method = [[url path] stringByReplacingOccurrencesOfString:@"/" withString:@""];
    
    NSString *callbackID = query[@"callbackID"];
    NSDictionary *params = [NSDictionary GSDictionaryWithURLQueryString:query[@"params"]];
    NSDictionary *settings = [NSDictionary GSDictionaryWithURLQueryString:query[@"settings"]];
    
    if ([action isEqualToString:GSWebBridgeActionIsSessionValid]) {
        BOOL isSessionValid = [Gigya isSessionValid];
        [self invokeCallback:callbackID result:@(isSessionValid)];
    }
    else if ([action isEqualToString:GSWebBridgeActionSendRequest]) {
        [self sendRequest:method
                   params:params
                 settings:settings
               callbackID:callbackID];
    }
    else if ([action isEqualToString:GSWebBridgeActionSendOAuthRequest]) {
        [self sendOAuthRequest:method
                        params:params
                      settings:settings
                    callbackID:callbackID];
    }
    else if ([action isEqualToString:GSWebBridgeActionOnPluginEvent]) {
        [self handlePluginEvent:params];
    }
    else if ([action isEqualToString:GSWebBridgeActionGetIDs]) {
        [self getIDs:callbackID];
    }
    else if ([action isEqualToString:GSWebBridgeActionRegisterForNamespaceEvents]) {
        [self registerForNamespaceEvents:params];
    }
    else if ([action isEqualToString:GSWebBridgeActionOnJSLog]) {
        [self handleJsLog:params];
    }
    else if ([action isEqualToString:GSWebBridgeActionClearSession]) {
        [self handleClearSession];
    }
    else {
        return NO;
    }
    
    return YES;
}

- (void)sendRequest:(NSString *)method params:(NSDictionary *)params settings:(NSDictionary *)settings callbackID:(NSString *)callbackID
{
    GSRequest *request = [GSRequest requestForMethod:method parameters:params];
    (request.parameters)[@"ctag"] = @"webbridge";
    request.source = self.bridgeID;
    
    if ([settings[@"forceHttps"] boolValue])
        request.useHTTPS = YES;
    
    [request sendWithResponseHandler:^(GSResponse *response, NSError *error) {
        if (response) {
            [self invokeCallback:callbackID result:response];
        }
        else if (error) {
            [self invokeCallback:callbackID error:error];
        }
    }];
}

- (void)sendOAuthRequest:(NSString *)method params:(NSDictionary *)params settings:(NSDictionary *)settings callbackID:(NSString *)callbackID
{
    NSString *provider = params[@"provider"];
    
    if ([provider length] == 0) {
        [self invokeCallback:callbackID error:[NSError errorWithDomain:GSGigyaSDKDomain
                                                                  code:GSErrorMissingRequiredParameter
                                                              userInfo:@{ NSLocalizedDescriptionKey: @"Missing parameter: provider" }]];
    }
    else {
        if ([self.delegate respondsToSelector:@selector(webView:startedLoginForMethod:parameters:)])
            [self.delegate webView:self.webView startedLoginForMethod:method parameters:params];
        
        GSLoginRequest *request = [GSLoginRequest loginRequestForMethod:method
                                                               provider:provider
                                                             parameters:params];
        request.source = self.bridgeID;
        request.returnUserInfoResponse = NO;
        
        [request startLoginOverViewController:[self.webView GSFindViewController] completionHandler:^(GSUser *response, NSError *error) {
            // if error exists, return it to JS, even if response is not empty
            if (error) {
                [self invokeCallback:callbackID error:error];
            }
            else if (response) {
                [self invokeCallback:callbackID result:response];
            }
            
            if ([self.delegate respondsToSelector:@selector(webView:finishedLoginWithResponse:)])
                [self.delegate webView:self.webView finishedLoginWithResponse:response];
        }];
    }
}

- (void)getIDs:(NSString *)callbackID
{
    NSDictionary *ids = @{ @"ucid": [[Gigya sharedInstance] ucid],
                           @"gcid": [[Gigya sharedInstance] gmid] };
    
    [self invokeCallback:callbackID result:ids];
}

- (void)handlePluginEvent:(NSDictionary *)event
{
    if ([self.delegate respondsToSelector:@selector(webView:receivedPluginEvent:fromPluginInContainer:)]) {
        NSString *containerID = event[@"sourceContainerID"];
        [self.delegate webView:self.webView receivedPluginEvent:event fromPluginInContainer:containerID];
    }
}

- (void)registerForNamespaceEvents:(NSDictionary *)params
{
    NSString *namespace = params[@"namespace"];

    if ([namespace isEqualToString:@"socialize"])
        [[Gigya sharedInstance] addSocializeDelegate:self];
    else if ([namespace isEqualToString:@"accounts"])
        [[Gigya sharedInstance] addAccountsDelegate:self];
}

- (void)handleJsLog:(NSDictionary *)logEntry
{
//    GSLog(@"%@", logEntry);
    
    NSString *logType = logEntry[@"logType"];
    NSDictionary *logInfo = logEntry[@"logInfo"];

    if ([self.delegate respondsToSelector:@selector(webView:receivedJsLog:logInfo:)])
        [self.delegate webView:self.webView receivedJsLog:logType logInfo:logInfo];
}

- (void)handleClearSession {
    [[GSLoginManager sharedInstance] clearSessionAfterLogout];
}

#pragma mark - Mobile -> JS
- (void)invokeCallback:(NSString *)callbackID error:(NSError *)error
{
    GSResponse *errorResponse = [GSResponse responseWithError:error];
    [self invokeCallback:callbackID result:errorResponse];
}

- (void)invokeCallback:(NSString *)callbackID result:(NSObject *)result
{
    NSString *resString = nil;
    
    if ([result respondsToSelector:@selector(GSJSONString)]) {
        resString = [(id<GSJSONCollection>)result GSJSONString];
    }
    else if ([result isKindOfClass:[GSObject class]]) {
        resString = [(GSObject *)result JSONString];
    }
    else if ([result isKindOfClass:[NSString class]]) {
        resString = [NSString stringWithFormat:@"'%@'", [result description]];
    }
    else {
        resString = [NSString stringWithFormat:@"%@", [result description]];
    }
    
    NSString *callbackPath = [NSString stringWithFormat:@"%@['%@'](%@);", GSWebBridgeCallbackJSPath, callbackID, resString];
    [self invokeJavaScript:callbackPath withTimeout:0];
}

- (void)invokeGlobalEvent:(NSString *)eventName parameters:(NSMutableDictionary *)params
{
    if (!params)
        params = [NSMutableDictionary dictionary];
    
    params[@"eventName"] = eventName;
    NSString *invokeCommand = [NSString stringWithFormat:@"%@(%@);", GSWebBridgeGlobalEventsJSPath, [params GSJSONString]];
    [self invokeJavaScript:invokeCommand withTimeout:0];
}

- (void)invokeJavaScript:(NSString *)code withTimeout:(NSTimeInterval)timeout
{
    NSString *finalJs = [NSString stringWithFormat:@"setTimeout(function() { %@ }, %f);", code, timeout];
    if ([self.webView isKindOfClass:[UIWebView class]]) {
        [self.webView stringByEvaluatingJavaScriptFromString:finalJs];
    }
    else {
        [self.webView evaluateJavaScript:finalJs completionHandler:nil];
    }
}

#pragma mark - Session delegates
- (void)userDidLogin:(GSUser *)user
{
    if (![[user source] isEqualToString:self.bridgeID]) {
        NSMutableDictionary *params = [@{ @"user": [user dictionary] } mutableCopy];
        [self invokeGlobalEvent:@"socialize.login" parameters:params];
    }
}

- (void)userDidLogout
{
    [self invokeGlobalEvent:@"socialize.logout" parameters:nil];
}

- (void)userInfoDidChange:(GSUser *)user
{
    if (![[user source] isEqualToString:self.bridgeID]) {
        NSMutableDictionary *params = [@{ @"user": [user dictionary] } mutableCopy];
        [self invokeGlobalEvent:@"socialize.connectionAdded" parameters:params];
    }
}

- (void)accountDidLogin:(GSAccount *)account
{
    if (![[account source] isEqualToString:self.bridgeID]) {
        NSMutableDictionary *params = [[account dictionary] mutableCopy];
        [self invokeGlobalEvent:@"accounts.login" parameters:params];
    }
}

- (void)accountDidLogout
{
    [self invokeGlobalEvent:@"accounts.logout" parameters:nil];
}

@end
