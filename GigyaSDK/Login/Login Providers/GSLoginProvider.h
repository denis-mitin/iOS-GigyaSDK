#import <Foundation/Foundation.h>
#import "Gigya.h"

typedef void(^GSLoginResponseHandler)(NSDictionary *sessionData, NSError *error);

@protocol GSLoginProvider <NSObject>

@required
+ (instancetype)instance;
+ (BOOL)isAppConfiguredForProvider;

- (BOOL)isLoggedIn;
- (void)startLoginForMethod:(NSString *)method
                 parameters:(NSDictionary *)parameters
             viewController:(UIViewController *)viewController
          completionHandler:(GSLoginResponseHandler)handler;

@optional
- (BOOL)handleOpenURL:(NSURL *)url
          application:(UIApplication *)application
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation;
- (void)handleDidBecomeActive;
- (void)logout;

@end
