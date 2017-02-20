#import <Foundation/Foundation.h>
#import "Gigya.h"

@interface GSWebBridge (Internal) <GSSocializeDelegate, GSAccountsDelegate>

@property (nonatomic, weak) id webView;
@property (nonatomic, weak) id<GSWebBridgeDelegate> delegate;

- (void)invokeGlobalEvent:(NSString *)eventName parameters:(NSMutableDictionary *)params;

@end
