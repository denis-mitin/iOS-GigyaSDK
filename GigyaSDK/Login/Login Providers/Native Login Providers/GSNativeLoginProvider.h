#import <Foundation/Foundation.h>
#import "Gigya.h"
#import "GSLoginProvider.h"

typedef void(^GSNativeLoginHandler)(NSDictionary *providerSessionData, NSError *error);

@interface GSNativeLoginProvider : NSObject <GSLoginProvider>

@property (weak, nonatomic, readonly) NSString *name;

+ (instancetype)instanceWithApplication:(UIApplication *)application launchOptions:(NSDictionary *)launchOptions;

- (NSMutableArray *)mergePermissions:(NSArray *)defaultPermissions extraPermissions:(NSArray *)extraPermissions;

@end
