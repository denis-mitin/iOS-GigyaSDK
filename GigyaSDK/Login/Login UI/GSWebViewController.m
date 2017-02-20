#import "GSWebViewController.h"
#import "Gigya+Internal.h"

@interface GSWebViewController ()
{
    NSURL *_url;
    BOOL _didAlreadyAppear;
}

@end

@implementation GSWebViewController

#pragma mark - Init methods
- (id)initWithURL:(NSURL *)url
{
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        _url = [url copy];
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.preferredContentSize = CGSizeMake(320, 480);
    self.modalInPopover = YES;

    // Create the web view
    _webView = [[UIWebView alloc] initWithFrame:[self.view bounds]];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    [self.view addSubview:self.webView];
    
    // Navigation
    self.navigationItem.title = self.title;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(cancelPressed:)];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!_didAlreadyAppear) {
        [self startWebView];
        _didAlreadyAppear = YES;
    }
}

- (void)startWebView
{
    // For non-visible mode (native login)
    if (!_webView) {
        _webView = [[UIWebView alloc] init];
        self.webView.delegate = self;
    }
    
    if (_url)
        [self.webView loadRequest:[NSURLRequest requestWithURL:_url]];
}

- (void)viewWillUnload:(BOOL)animated
{
    [self.webView loadHTMLString:@"" baseURL:nil];
}

#pragma mark - User events
- (void)cancelPressed:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(webViewControllerDidCancel:)])
        [self.delegate webViewControllerDidCancel:self];
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    if ([self.delegate respondsToSelector:@selector(webViewControllerDidStartLoad:)])
        [self.delegate webViewControllerDidStartLoad:self];
    
    [[Gigya sharedInstance] showNetworkActivityIndicator];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self.webView stringByEvaluatingJavaScriptFromString:
     [NSString stringWithFormat:@"document.querySelector('meta[name=viewport]').setAttribute('content', 'width=%d;', false);",
      (int)webView.frame.size.width]];
    
    if ([self.delegate respondsToSelector:@selector(webViewControllerDidFinishLoad:)])
        [self.delegate webViewControllerDidFinishLoad:self];
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    // -999 == "Operation could not be completed" - happens on first load of Facebook web login:
    // http://stackoverflow.com/questions/8002260/first-dialog-after-authenticating-fails-immediately-and-closes-dialog/8016055#comment9863824_8016055
    // This is the same solution as used in the Facebook SDK.
    if (!(error.code == -999 && [error.domain isEqualToString:@"NSURLErrorDomain"]) &&
        [self.delegate respondsToSelector:@selector(webViewController:didFailLoadWithError:)]) {
        [self.delegate webViewController:self didFailLoadWithError:error];
    }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ([self.delegate respondsToSelector:@selector(webViewController:shouldStartLoadWithRequest:)])
        return [self.delegate webViewController:self shouldStartLoadWithRequest:request];
    
    return YES;
}

#pragma mark - Memory management
- (void)dealloc
{
    [_webView stopLoading];
    [_webView setDelegate:nil];
}

@end
