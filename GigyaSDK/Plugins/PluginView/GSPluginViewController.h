#import <UIKit/UIKit.h>
#import "Gigya.h"

@interface GSPluginViewController : UIViewController

- (id)initWithPlugin:(NSString *)plugin
          parameters:(NSDictionary *)parameters
            delegate:(id<GSPluginViewDelegate>)delegate
      dismissHandler:(GSPluginCompletionHandler)handler;

@end
