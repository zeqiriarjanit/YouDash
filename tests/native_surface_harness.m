#import "YCPNative.h"
#import "YCPResponsiveLayout.h"

// An initialized app root with real navigation content, without Google's binary.
@interface YTAppViewControllerImpl : UIViewController
@property(nonatomic, strong) UINavigationController *appNavigationController;
@end
@implementation YTAppViewControllerImpl
- (instancetype)init {
    if ((self = [super init])) {
        UIViewController *feed = [UIViewController new];
        feed.title = @"Loaded feed";
        self.appNavigationController = [[UINavigationController alloc] initWithRootViewController:feed];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self addChildViewController:self.appNavigationController];
    self.appNavigationController.view.frame = self.view.bounds;
    self.appNavigationController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.appNavigationController.view];
    [self.appNavigationController didMoveToParentViewController:self];
}
@end

void YCPBootstrapNativeScene(UIWindowScene *scene, UISceneSession *session, UISceneConnectionOptions *options) {}

// iOS 27 terminates apps that do not adopt the UIScene lifecycle. The checks
// below drive windows directly, so the declared scene only satisfies UIKit.
@interface HarnessSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation HarnessSceneDelegate @end

@interface HarnessDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *mainWindow;
@end
@implementation HarnessDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.mainWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    dispatch_async(dispatch_get_main_queue(), ^{
        YCPSurface *surface = YCPSurface.shared;
        UIWindow *first = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1000, 570)];
        [surface connectWindow:first];
        YTAppViewControllerImpl *native = [YTAppViewControllerImpl new];
        self.mainWindow.rootViewController = native;
        [self.mainWindow makeKeyAndVisible];
        BOOL originalLayout = native.view.translatesAutoresizingMaskIntoConstraints;
        UIViewController *feed = native.appNavigationController.topViewController;
        [surface reconcile];
        NSCAssert([surface ownsNativeController:native], @"Must transfer initialized root, not build another");
        NSCAssert(self.mainWindow.rootViewController != native, @"Phone must have placeholder");
        NSCAssert(native.view.window == first, @"Loaded interface must be in car window");
        NSCAssert(native.appNavigationController.topViewController == feed, @"Navigation content must survive");
        NSCAssert(native.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad, @"Car host supplies the native tablet layout trait");
        NSArray *sizes = @[[NSValue valueWithCGSize:CGSizeMake(480, 240)], [NSValue valueWithCGSize:CGSizeMake(640, 360)], [NSValue valueWithCGSize:CGSizeMake(800, 480)], [NSValue valueWithCGSize:CGSizeMake(1024, 600)], [NSValue valueWithCGSize:CGSizeMake(1280, 480)], [NSValue valueWithCGSize:CGSizeMake(1920, 720)], [NSValue valueWithCGSize:CGSizeMake(768, 1024)]];
        for (NSValue *value in sizes) {
            YCPScaledContentView *viewport = [[YCPScaledContentView alloc] initWithFrame:(CGRect){CGPointZero, value.CGSizeValue}];
            [first.rootViewController.view addSubview:viewport];
            [viewport setNeedsLayout]; [viewport layoutIfNeeded];
            CGFloat scale = viewport.contentScale;
            CGRect visible = [viewport.canvas convertRect:viewport.canvas.bounds toView:viewport];
            NSCAssert(fabs(visible.size.width - viewport.bounds.size.width) < 0.01 && fabs(visible.size.height - viewport.bounds.size.height) < 0.01, @"Scaled canvas must fill both axes without cropping or letterboxing");
            NSCAssert(scale > 0 && scale <= 1, @"Density must stay bounded");
            UIButton *target = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 44, 44)];
            [viewport.canvas addSubview:target];
            CGPoint physicalPoint = [target convertPoint:CGPointMake(22, 22) toView:viewport];
            NSCAssert([viewport hitTest:physicalPoint withEvent:nil] == target, @"Scaled buttons must receive touches at their visible position");
            if (value.CGSizeValue.width >= 480 && value.CGSizeValue.width < 960 && value.CGSizeValue.width > value.CGSizeValue.height)
                NSCAssert(YCPShouldUseWideWatch(viewport.canvas.bounds.size), @"Small landscape screens must retain the side-by-side watch layout after density adjustment");
            [viewport removeFromSuperview];
        }
        first.frame = CGRectMake(0, 0, 480, 240);
        first.rootViewController.view.frame = first.bounds;
        [first.rootViewController.view setNeedsLayout]; [first.rootViewController.view layoutIfNeeded];
        [native.view.superview.superview setNeedsLayout]; [native.view.superview.superview layoutIfNeeded];
        [native.view.superview setNeedsLayout]; [native.view.superview layoutIfNeeded];
        NSCAssert(surface.contentBounds.size.width >= 820, @"The actual hosted native tree must use logical canvas dimensions on a small car");
        UIWindow *replacement = [[UIWindow alloc] initWithFrame:first.frame];
        [surface connectWindow:replacement];
        NSCAssert(first.rootViewController == nil, @"Old car window must release host");
        NSCAssert(native.view.window == replacement, @"One native tree must move to replacement");
        [surface disconnectWindow:first];
        NSCAssert([surface ownsNativeController:native], @"Stale disconnect must not release active root");
        [surface disconnectWindow:replacement];
        NSCAssert(self.mainWindow.rootViewController == native, @"Disconnect must restore exact phone root");
        NSCAssert(native.parentViewController == nil, @"Restored root must leave host containment");
        NSCAssert(native.view.translatesAutoresizingMaskIntoConstraints == originalLayout, @"Restore root layout behavior");
        [surface connectWindow:replacement];
        NSCAssert([surface ownsNativeController:native], @"Reconnect must reuse initialized root");
        [surface disconnectWindow:replacement];
        NSCAssert(self.mainWindow.rootViewController == native, @"Repeated disconnect must restore root");
        NSLog(@"NATIVE_SURFACE_TESTS_PASSED");
        exit(0);
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessDelegate.class)); }
}
