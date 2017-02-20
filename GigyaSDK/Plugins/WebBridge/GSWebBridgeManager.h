#import <Foundation/Foundation.h>
#import "Gigya.h"

@interface GSWebBridgeManager : NSObject

+ (GSWebBridgeManager *)sharedInstance;
- (void)showPluginViewDialogOver:(UIViewController *)viewController
                          plugin:(NSString *)plugin
                      parameters:(NSDictionary *)parameters
                        delegate:(id<GSPluginViewDelegate>)delegate
                  dismissHandler:(GSPluginCompletionHandler)handler;

- (void)addBridge:(GSWebBridge *)bridge;
- (void)removeBridge:(GSWebBridge *)bridge;
- (GSWebBridge *)bridgeForWebView:(id)webView;

@end
