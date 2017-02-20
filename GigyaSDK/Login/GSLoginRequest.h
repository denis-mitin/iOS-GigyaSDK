#import <Foundation/Foundation.h>
#import "Gigya.h"

@interface GSLoginRequest : NSObject

@property (nonatomic, copy) NSMutableDictionary *parameters;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *provider;
@property (nonatomic, copy) NSString *source;
@property (nonatomic) BOOL returnUserInfoResponse;

+ (GSLoginRequest *)loginRequestForMethod:(NSString *)method
                                 provider:(NSString *)provider
                               parameters:(NSDictionary *)parameters;
- (void)startLoginWithCompletionHandler:(GSUserInfoHandler)handler;
- (void)startLoginOverViewController:(UIViewController *)viewController
                   completionHandler:(GSUserInfoHandler)handler;
@end
