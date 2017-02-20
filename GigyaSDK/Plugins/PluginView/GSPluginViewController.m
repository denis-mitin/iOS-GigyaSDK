#import "GSPluginViewController.h"
#import "Gigya+Internal.h"

@interface GSPluginViewController () <GSPluginViewDelegate>
{
    BOOL _wasLoaded;
}

@property (nonatomic, copy) NSString *plugin;
@property (nonatomic, strong) NSMutableDictionary *parameters;
@property (nonatomic, strong) GSPluginView *pluginView;
@property (nonatomic, copy) GSPluginCompletionHandler handler;
@property (nonatomic, weak) id<GSPluginViewDelegate> delegate;

@end

@implementation GSPluginViewController

#pragma mark - Init Methods
- (id)initWithPlugin:(NSString *)plugin
          parameters:(NSDictionary *)parameters
            delegate:(id<GSPluginViewDelegate>)delegate
      dismissHandler:(GSPluginCompletionHandler)handler
{
    self = [super init];

    if (self) {
        self.plugin = plugin;
        self.handler = handler;
        self.delegate = delegate;
        _parameters = [parameters mutableCopy];
        _pluginView = [[GSPluginView alloc] init];
        _pluginView.delegate = self;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = (self.parameters)[@"captionText"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(cancelPressed:)];

    self.pluginView.frame = self.view.bounds;
    self.pluginView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [self.view addSubview:self.pluginView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!_wasLoaded) {
        [self.pluginView loadPlugin:self.plugin parameters:self.parameters];
        _wasLoaded = YES;
    }
}

- (void)dealloc
{
    [_pluginView setDelegate:nil];
}

#pragma mark - GSPluginView delegate methods
- (void)pluginView:(GSPluginView *)pluginView finishedLoadingPluginWithEvent:(NSDictionary *)event
{
    if ([self.delegate respondsToSelector:@selector(pluginView:finishedLoadingPluginWithEvent:)])
        [self.delegate pluginView:pluginView finishedLoadingPluginWithEvent:event];
}

- (void)pluginView:(GSPluginView *)pluginView firedEvent:(NSDictionary *)event
{
    NSString *eventName = event[@"eventName"];
    if ([eventName isEqualToString:@"hide"] || [eventName isEqualToString:@"close"]) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
            if (self.handler)
                self.handler(NO, nil);
        }];
    }
    
    if ([self.delegate respondsToSelector:@selector(pluginView:firedEvent:)])
        [self.delegate pluginView:pluginView firedEvent:event];
}

- (void)pluginView:(GSPluginView *)pluginView didFailWithError:(NSError *)error
{
    // FFU - currently we do not know if the plugin event was fatal or not.
//    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
//        if (self.handler)
//            self.handler(NO, error);
//    }];
    
    if ([self.delegate respondsToSelector:@selector(pluginView:didFailWithError:)])
        [self.delegate pluginView:pluginView didFailWithError:error];
}

#pragma mark - User Interaction
- (void)cancelPressed:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (self.handler)
            self.handler(YES, nil);
    }];
}

// fix for UIWebView crashing when quickly clicking on HTML SELECT element multiple times
// http://openradar.appspot.com/19469574#aglvcGVucmFkYXJyFAsSB0NvbW1lbnQYgICAoOugswoM
// http://stackoverflow.com/questions/25908729/ios8-ipad-uiwebview-crashes-while-displaying-popover-when-user-taps-drop-down-li/26692948#26692948
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_USEC), dispatch_get_main_queue(),
                   ^{
                       if ([viewControllerToPresent respondsToSelector:@selector(popoverPresentationController)] &&
                           viewControllerToPresent.popoverPresentationController &&
                           !viewControllerToPresent.popoverPresentationController.sourceView)
                       {
                           return;
                       }
                       
                       [super presentViewController:viewControllerToPresent animated:flag completion:completion];
                   });
}

@end
