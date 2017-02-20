#import <Foundation/Foundation.h>
#import "Gigya.h"
#import "GSNativeLoginProvider.h"

@interface GSFacebookProvider : GSNativeLoginProvider

- (void)requestNewPublishPermissions:(NSString *)permissions
                      viewController:(UIViewController * _Nullable)viewController
                     responseHandler:(GSPermissionRequestResultHandler)handler;

- (void)requestNewReadPermissions:(NSString *)permissions
                   viewController:(UIViewController * _Nullable)viewController
                  responseHandler:(GSPermissionRequestResultHandler)handler;


@end
