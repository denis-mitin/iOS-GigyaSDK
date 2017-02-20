#import "Gigya+Internal.h"
#import "GSProviderSelectionViewController.h"
#import "GSWebViewController.h"
#import "GSMBProgressHUD.h"

@interface GSProviderSelectionViewController () <GSWebViewControllerDelegate>

@property (nonatomic) BOOL wasPresented;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, strong) NSMutableDictionary *parameters;
@property (nonatomic, strong) GSMBProgressHUD *progress;

@end

@implementation GSProviderSelectionViewController

#pragma mark - Initialization methods
- (id)initWitMethod:(NSString *)method
         parameters:(NSDictionary *)params
{
    self = [super init];
    
    if (self) {
        self.method = method;
        _parameters = [params mutableCopy];
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.wasPresented = NO;
    self.preferredContentSize = CGSizeMake(320, 480);
    
    if ((self.parameters)[@"captionText"]) {
        self.navigationTitle = (self.parameters)[@"captionText"];
    }
    else if ([self.method isEqualToString:@"socialize.login"]) {
        self.navigationTitle = @"Login";
    }
    else if ([self.method isEqualToString:@"socialize.addConnection"]) {
        self.navigationTitle = @"Add Connection";
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!self.wasPresented) {
        self.wasPresented = YES;
        [self startWebViewWithSession:[Gigya sharedInstance].session];
    }
}

- (void)startWebViewWithSession:(GSSession *)session
{
    NSURL *loginURL = nil;
    
    // Create the navigation and webview
    (self.parameters)[@"width"] = @(self.view.bounds.size.width);
    loginURL = [NSURL URLForGigyaProviderSelection:self.parameters session:session];
    
    GSWebViewController *webViewController = [[GSWebViewController alloc] initWithURL:loginURL];
    webViewController.title = self.navigationTitle;
    webViewController.delegate = self;
    [self pushViewController:webViewController animated:YES];
    
    self.progress = [GSMBProgressHUD showHUDAddedTo:webViewController.view animated:YES];
    self.progress.labelText = GSDefaultLoadingText;
    
    // Add gesture recognizer for debug mode
    UILongPressGestureRecognizer *recognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(debugLongPressRecognized:)];
    recognizer.minimumPressDuration = 5;
    recognizer.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:recognizer];
}

- (void)debugLongPressRecognized:(UIGestureRecognizer *)recognizer
{
    // Enabled debug logging
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [[GSLogger sharedInstance] setEnabled:YES];
    }
    
    GSLog(@"*** GIGYA LOGGER ACTIVATED ***");
}

#pragma mark - Login flow
- (BOOL)webViewController:(GSWebViewController *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
{
    // Extract information from URL
    NSURL *url = [request URL];
    
    // If this is a gigya redirect - working according to login workflow
    if ([[url scheme] isEqualToString:GSRedirectURLScheme] &&  [[url host] isEqualToString:GSRedirectURLNetworkSelected])
    {
        NSDictionary *responseData = [NSDictionary GSDictionaryWithURLQueryString:[url query]];
        
        if (responseData[@"provider"]) {
            if ([self.loginDelegate respondsToSelector:@selector(loginViewController:selectedProvider:displayName:)])
                [self.loginDelegate loginViewController:self
                                       selectedProvider:responseData[@"provider"]
                                            displayName:responseData[@"displayName"]];
        }
        else {
            if ([self.loginDelegate respondsToSelector:@selector(loginViewController:didFailWithError:)]) {
                NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                     code:GSErrorServerLoginFailure
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"Internal server error." }];
                [self.loginDelegate loginViewController:self didFailWithError:error];
            }
        }
        
        return NO;
    }
    
    return YES;
}

#pragma mark - GSWebViewDelegate methods
- (void)webViewControllerDidCancel:(GSWebViewController *)webViewController
{
    if ([self.loginDelegate respondsToSelector:@selector(loginViewControllerDidCancel:)])
        [self.loginDelegate loginViewControllerDidCancel:self];
}

- (void)webViewController:webViewController didFailLoadWithError:(NSError *)error
{
    if ([self.loginDelegate respondsToSelector:@selector(loginViewController:didFailWithError:)])
        [self.loginDelegate loginViewController:self didFailWithError:error];
}

- (void)webViewControllerDidFinishLoad:(GSWebViewController *)webViewController
{
    [self.progress hide:YES];
}

#pragma mark - Memory handling

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
