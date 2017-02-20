#import "UIView+GSView.h"

@implementation UIView (GSView)

- (UIViewController *)GSFindViewController
{
    id nextResponder = self.nextResponder;
    
    if ([nextResponder isKindOfClass:[UIViewController class]])
        return (UIViewController *)nextResponder;
    else if ([nextResponder isKindOfClass:[UIView class]])
        return [nextResponder GSFindViewController];
    else
        return nil;
}

@end
