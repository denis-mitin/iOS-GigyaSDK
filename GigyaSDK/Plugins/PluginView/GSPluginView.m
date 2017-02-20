#import "GSPluginView.h"
#import "Gigya+Internal.h"
#import "GSMBProgressHUD.h"

@interface GSPluginView () <GSWebBridgeDelegate, UIWebViewDelegate>

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, copy) NSString *containerID;
@property (nonatomic, strong) NSMutableDictionary *parameters;

@end

@implementation GSPluginView

#pragma mark - Init methods
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initProperties];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self ) {
        [self initProperties];
    }
    return self;
}

- (void)initProperties
{
    self.javascriptLoadingTimeout = 10000;
    self.loginProgressText = GSDefaultLoginText;
    self.loadingProgressText = GSDefaultLoadingText;
    self.showLoadingProgress = YES;
    self.showLoginProgress = YES;
}

- (void)initWebView
{
    if (_webView)
        [self releaseWebView];
    
    NSDictionary *settings = @{ @"logLevel": @"error" };
    _webView = [[UIWebView alloc] initWithFrame:[self bounds]];
    self.webView.autoresizingMask =  UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.webView.delegate = self;
    [self addSubview:self.webView];
    
    [GSWebBridge registerWebView:self.webView delegate:self settings:settings];
}

- (void)releaseWebView
{
    [GSMBProgressHUD hideAllHUDsForView:self animated:NO];
    [_webView removeFromSuperview];
    _webView.delegate = nil;
    [GSWebBridge unregisterWebView:_webView];
    [_webView loadHTMLString:@"" baseURL:nil];
    _webView = nil;
}

- (void)dealloc
{
    [self releaseWebView];
}

#pragma mark - Showing plugin
- (void)loadPlugin:(NSString *)pluginName
{
    [self loadPlugin:pluginName parameters:nil];
}

- (void)loadPlugin:(NSString *)plugin parameters:(NSDictionary *)parameters
{
    [self initWebView];
    
    _plugin = [plugin copy];
    self.containerID = @"pluginContainer";

    self.parameters = [parameters mutableCopy];
    if (!self.parameters)
        self.parameters = [NSMutableDictionary dictionary];
    
    (self.parameters)[@"containerID"] = self.containerID;
    
    [self.webView loadHTMLString:[self buildPluginHTML] baseURL:nil];
    
    if (self.showLoadingProgress) {
        GSMBProgressHUD *progress = [GSMBProgressHUD showHUDAddedTo:self animated:YES];
        progress.labelText = self.loadingProgressText;
    }
}

- (void)failWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(pluginView:didFailWithError:)])
        [self.delegate pluginView:self didFailWithError:error];
}

- (NSString *)buildPluginHTML
{
    NSString *enableTestNetworksScript = @"";
    if ([Gigya __debugOptionEnableTestNetworks]) {
        enableTestNetworksScript = @"gigya._.providers.arProviders.push(new gigya._.providers.Provider(6016, 'testnetwork3', 650, 400, "
        "'login,friends,actions,status,photos,places,checkins', true));"
        "gigya._.providers.arProviders.push(new gigya._.providers.Provider(6017, 'testnetwork4', 650, 400, 'login,friends,actions,status,photos,places,checkins', true));";
    }
    
    if (!(self.parameters)[@"deviceType"])
        (self.parameters)[@"deviceType"] = @"mobile";
    
    if ([self.plugin rangeOfString:@"commentsUI"].location != NSNotFound &&
        !(self.parameters)[@"version"]) {
        (self.parameters)[@"version"] = @2;
    }
    
    NSString *disabledProviders = (self.parameters)[@"disabledProviders"];
    
    if (![GSFacebookProvider isAppConfiguredForProvider]) {
        
        
        if ([disabledProviders length] > 0)
            disabledProviders = [NSString stringWithFormat:@"facebook,%@", disabledProviders];
        else
            disabledProviders = @"facebook";
        
        (self.parameters)[@"disabledProviders"] = disabledProviders;
    }
    
    if (![GSGoogleProvider isAppConfiguredForProvider]) {
        
        if ([disabledProviders length] > 0)
            disabledProviders = [NSString stringWithFormat:@"googleplus,%@", disabledProviders];
        else
            disabledProviders = @"googleplus";
        
        (self.parameters)[@"disabledProviders"] = disabledProviders;
    }
    
        
    
    NSString *template =
        @"<head>"
            "<meta name='viewport' content='initial-scale=1,maximum-scale=1,user-scalable=no' />"
            "<script>"
                "function onJSException(ex) {"
                    "document.location.href = '%@://%@?ex=' + encodeURIComponent(ex);"
                "}"
                "function onJSLoad() {"
                    "if (gigya && gigya.isGigya)"
                        "window.__wasSocializeLoaded = true;"
                "}"
                "setTimeout(function() {"
                    "if (!window.__wasSocializeLoaded)"
                        "document.location.href = '%@://%@';"
                "}, %i);"
            "</script>"
            "<script src='http://cdn.gigya.com/JS/gigya.js?apikey=%@' type='text/javascript' onLoad='onJSLoad();'>"
            "{"
                "deviceType: 'mobile'" // "consoleLogLevel: 'error'"
            "}"
            "</script>"
        "</head>"
        "<body>"
            "<div id='%@'></div>"
            "<script>"
                "%@"
                "try {"
                    "gigya._.apiAdapters.mobile.showPlugin('%@', %@);"
                "} catch (ex) { onJSException(ex); }"
            "</script>"
        "</body>";
    
    NSString *html = [NSString stringWithFormat:template,
                        GSRedirectURLScheme,
                        GSPluginViewOnJSException,
                        GSRedirectURLScheme,
                        GSPluginViewOnJSLoadError,
                        self.javascriptLoadingTimeout,
                        [Gigya APIKey],
                        self.containerID,
                        enableTestNetworksScript,
                        self.plugin,
                        [self.parameters GSJSONString]];
    return html;
}

#pragma mark - GSWebBridgeDelegate methods
- (void)webView:(UIWebView *)webView receivedPluginEvent:(NSDictionary *)event fromPluginInContainer:(NSString *)containerID
{
    if ([containerID isEqualToString:self.containerID]) {
        NSString *eventName = event[@"eventName"];
        
        if ([eventName isEqualToString:@"load"]) {
            if ([self.delegate respondsToSelector:@selector(pluginView:finishedLoadingPluginWithEvent:)])
                [self.delegate pluginView:self finishedLoadingPluginWithEvent:event];
            
            [GSMBProgressHUD hideHUDForView:self animated:YES];
        }
        else if ([eventName isEqualToString:@"error"]) {
            [self failWithError:[NSError errorWithGigyaPluginEvent:event]];
        }
        else if ([self.delegate respondsToSelector:@selector(pluginView:firedEvent:)]) {
            [self.delegate pluginView:self firedEvent:event];
        }
    }
}

- (void)webView:(UIWebView *)webView startedLoginForMethod:(NSString *)method parameters:(NSDictionary *)parameters
{
    if (self.showLoginProgress) {
        GSMBProgressHUD *progress = [GSMBProgressHUD showHUDAddedTo:self animated:YES];
        progress.labelText = self.loginProgressText;
    }
}

- (void)webView:(UIWebView *)webView finishedLoginWithResponse:(GSResponse *)response
{
    [GSMBProgressHUD hideHUDForView:self animated:YES];
}

- (void)webView:(UIWebView *)webView receivedJsLog:(NSString *)logType logInfo:(NSDictionary *)logInfo {
    GSLog(@"JS %@", logInfo);
}

#pragma mark - UIWebViewDelegate methods
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL shouldLoad = NO;

    if (![GSWebBridge handleRequest:request webView:webView])
    {
        if ([[[request URL] scheme] isEqualToString:GSRedirectURLScheme]) {
            if ([[[request URL] host] isEqualToString:GSPluginViewOnJSLoadError]) {
                NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                     code:GSErrorLoadFailed
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: @"Failed loading gigya.js",
                                                            @"eventName": @"error"
                                                            }];
                [self failWithError:error];
            }
            else if ([[[request URL] host] isEqualToString:GSPluginViewOnJSException]) {
                NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                     code:GSErrorJSException
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: @"Javascript error while loading plugin",
                                                            @"eventName": @"error"
                                                            }];
                [self failWithError:error];

            }
        }
        // Checking that this is main document and navigation (not iframe)
        else if ([[[request URL] absoluteString] isEqualToString:[[request mainDocumentURL] absoluteString]] &&
                 ![[[request URL] scheme] isEqualToString:@"about"]) {
            [[UIApplication sharedApplication] openURL:[request URL]];
        }
        else {
            shouldLoad = YES;
        }
    }
    
    return shouldLoad;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [GSWebBridge webViewDidStartLoad:webView];
    [[Gigya sharedInstance] showNetworkActivityIndicator];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self failWithError:error];
}

@end
