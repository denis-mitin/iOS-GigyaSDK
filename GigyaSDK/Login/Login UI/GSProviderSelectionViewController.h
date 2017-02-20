#import <UIKit/UIKit.h>
#import "Gigya.h"

@class GSProviderSelectionViewController;

@protocol GSLoginViewControllerDelegate <NSObject>

@optional
- (void)loginViewController:(GSProviderSelectionViewController *)loginViewController
           didFailWithError:(NSError *)error;
- (void)loginViewController:(GSProviderSelectionViewController *)loginViewController
           selectedProvider:(NSString *)provider
                displayName:(NSString *)displayName;
- (void)loginViewControllerDidCancel:(GSProviderSelectionViewController *)loginViewController;

@end

@interface GSProviderSelectionViewController : UINavigationController

@property (nonatomic, weak) id<GSLoginViewControllerDelegate> loginDelegate;
@property (nonatomic, copy) NSString *navigationTitle;

- (id)initWitMethod:(NSString *)method
         parameters:(NSDictionary *)params;
- (void)startWebViewWithSession:(GSSession *)session;

@end
