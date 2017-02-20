#import <UIKit/UIKit.h>

@class GSWebViewController;

@protocol GSWebViewControllerDelegate <NSObject>

@optional
- (void)webViewControllerDidCancel:(GSWebViewController *)webViewController;
- (BOOL)webViewController:(GSWebViewController *)webViewController shouldStartLoadWithRequest:(NSURLRequest *)request;
- (void)webViewController:(GSWebViewController *)webViewController didFailLoadWithError:(NSError *)error;
- (void)webViewControllerDidFinishLoad:(GSWebViewController *)webViewController;
- (void)webViewControllerDidStartLoad:(GSWebViewController *)webViewController;
@end

@interface GSWebViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, weak) id<GSWebViewControllerDelegate> delegate;

- (id)initWithURL:(NSURL *)url;
- (void)startWebView;

@end
