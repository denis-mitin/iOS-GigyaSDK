#import "GSWebBridgeManager.h"
#import "Gigya+Internal.h"

@interface GSWebBridgeManager ()

@property (nonatomic, strong) NSMutableArray *bridges;

@end

@implementation GSWebBridgeManager

#pragma mark - Init Methods
+ (GSWebBridgeManager *)sharedInstance
{
    static dispatch_once_t onceToken;
    static GSWebBridgeManager *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSWebBridgeManager alloc] init];
    });
    
    return instance;
}

- (GSWebBridgeManager *)init
{
    self = [super init];
    if (self) {
        self.bridges = [NSMutableArray array];
    }
    return self;
}


#pragma mark - Bridges Array Handling
- (void)addBridge:(GSWebBridge *)bridge
{
    if ([self.bridges indexOfObject:bridge] == NSNotFound) {
        [self.bridges addObject:bridge];
    }
}

- (void)removeBridge:(GSWebBridge *)bridge
{
    [self.bridges removeObject:bridge];
}

- (GSWebBridge *)bridgeForWebView:(id)webView
{
    for (GSWebBridge *bridge in self.bridges) {
        if (bridge.webView == webView) {
            return bridge;
        }
    }
    
    return nil;
}

#pragma mark - GSSessionDelegate Methods


- (void)invokeGlobalEvent:(NSString *)eventName parameters:(NSMutableDictionary *)params
{
    for (GSWebBridge *bridge in self.bridges) {
        [bridge invokeGlobalEvent:eventName parameters:params];
    }
}

#pragma mark - UI Convenience Methods
- (void)showPluginViewDialogOver:(UIViewController *)viewController
                          plugin:(NSString *)plugin
                      parameters:(NSDictionary *)parameters
                        delegate:(id<GSPluginViewDelegate>)delegate
                  dismissHandler:(GSPluginCompletionHandler)handler
{
    GSPluginViewController *pluginViewController = [[GSPluginViewController alloc] initWithPlugin:plugin
                                                                                       parameters:parameters
                                                                                         delegate:delegate
                                                                                   dismissHandler:handler];
    pluginViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    pluginViewController.view.backgroundColor = [UIColor whiteColor];
    
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:pluginViewController];
    [viewController presentViewController:navigation animated:YES completion:nil];
    
}

@end
