#import "YCPNative.h"
#import "YCPResponsiveLayout.h"

@interface UIView (FixtureWindowInsets)
- (UIEdgeInsets)yt_safeAreaInsetsForWindow;
- (UIEdgeInsets)yt_safeAreaInsetsForBrowse;
@end
@implementation UIView (FixtureWindowInsets)
- (UIEdgeInsets)yt_safeAreaInsetsForWindow { return UIEdgeInsetsMake(60, 7, 9, 11); }
- (UIEdgeInsets)yt_safeAreaInsetsForBrowse { return UIEdgeInsetsMake(60, 0, 0, 0); }
@end

@protocol YTWatchLayoutController <NSObject>
@end
@interface FixtureCarWindow : UIWindow @end
@implementation FixtureCarWindow
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsMake(0, 48, 0, 0); }
@end
static UIWindow *TestCarWindow;
@implementation YCPSurface
+ (instancetype)shared { static YCPSurface *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [self new]; }); return s; }
- (UIWindow *)activeWindow { return TestCarWindow; }
- (CGRect)contentBounds { return TestCarWindow.bounds; }
- (UIEdgeInsets)miniPlayerSafeInsets { return UIEdgeInsetsMake(0, 0, 64, 0); }
@end

@interface FixtureWatchLayoutController : NSObject <YTWatchLayoutController>
@property(nonatomic, weak) UIView *watchLayerView;
- (BOOL)isLargeLayout;
- (BOOL)isLargeWideLayout;
- (BOOL)isLandscape;
- (NSInteger)interfaceOrientation;
@end
@implementation FixtureWatchLayoutController
- (BOOL)isLargeLayout { return NO; }
- (BOOL)isLargeWideLayout { return NO; }
- (BOOL)isLandscape { return NO; }
- (NSInteger)interfaceOrientation { return UIInterfaceOrientationPortrait; }
@end

@interface YTWatchViewController : UIViewController
- (BOOL)isWideLayoutForWatchView:(UIView *)view;
@end
@implementation YTWatchViewController
- (BOOL)isWideLayoutForWatchView:(UIView *)view { return NO; }
@end

@interface YTWatchNextResultsViewController : UIViewController
- (UIEdgeInsets)collectionView:(UICollectionView *)collection layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section;
@end
@implementation YTWatchNextResultsViewController
- (UIEdgeInsets)collectionView:(UICollectionView *)collection layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(-6, 10, 4, 10);
}
@end

@interface YTWatchLayerViewController : UIViewController
- (CGFloat)statusBarHeight;
- (CGFloat)headerHeight;
@end
@implementation YTWatchLayerViewController
- (CGFloat)statusBarHeight { return 60; }
- (CGFloat)headerHeight { return 60; }
@end

@interface YTWatchMiniplayerLayoutOutput : NSObject
- (CGRect)miniplayerFrame;
@end
@implementation YTWatchMiniplayerLayoutOutput
- (CGRect)miniplayerFrame { return CGRectMake(900, 800, 500, 300); }
@end
@interface FixtureNativeConfig : NSObject
- (BOOL)enableIosSplitMetadataViewFix;
@end
@implementation FixtureNativeConfig
- (BOOL)enableIosSplitMetadataViewFix { return NO; }
@end

@interface YTHomeViewController : UIViewController @end
@implementation YTHomeViewController @end
@interface YTSearchResultsViewController : UIViewController @end
@implementation YTSearchResultsViewController @end
@interface YTWatchMetadataViewController : UIViewController @end
@implementation YTWatchMetadataViewController @end
@interface FixtureGridSection : NSObject
@property(nonatomic, strong) id feedController;
@end
@implementation FixtureGridSection @end

@interface FixtureNavigationBar : UIView
@property(nonatomic, strong) UIColor *barTintColor;
@end
@implementation FixtureNavigationBar @end
@interface YTHeaderView : FixtureNavigationBar
@property(nonatomic) BOOL headerScrollEnabled;
@property(nonatomic) BOOL stickyNavHeaderEnabled;
@property(nonatomic) CGFloat maximumHeaderHeight;
@property(nonatomic) CGFloat currentHeaderHeight;
- (void)updateBackgroundColor;
- (void)resetHeaderParamsForStatusBarUpdate;
- (void)scrollNavHeaderViewWithOffset:(CGFloat)offset;
@end
@implementation YTHeaderView
- (void)updateBackgroundColor {
    self.barTintColor = UIColor.darkGrayColor;
    self.backgroundColor = UIColor.darkGrayColor;
}
- (void)resetHeaderParamsForStatusBarUpdate {
    self.maximumHeaderHeight = 44 + [self yt_safeAreaInsetsForBrowse].top;
    self.currentHeaderHeight = self.maximumHeaderHeight;
}
- (void)scrollNavHeaderViewWithOffset:(CGFloat)offset {
    if (!self.headerScrollEnabled || self.stickyNavHeaderEnabled) return;
    self.currentHeaderHeight = MIN(self.maximumHeaderHeight, MAX(0, self.currentHeaderHeight - offset));
}
@end

// iOS 27 terminates apps that do not adopt the UIScene lifecycle. The checks
// below drive windows directly, so the declared scene only satisfies UIKit.
@interface HarnessSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation HarnessSceneDelegate @end

@interface TestApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation TestApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    YTWatchViewController *phone = [YTWatchViewController new];
    self.window.rootViewController = phone;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        FixtureWatchLayoutController *layout = [FixtureWatchLayoutController new];
        layout.watchLayerView = phone.view;
        YCPInstallWatchLayoutHooks();
        FixtureNativeConfig *config = [FixtureNativeConfig new];
        YTWatchMiniplayerLayoutOutput *mini = [YTWatchMiniplayerLayoutOutput new];
        NSCAssert(!config.enableIosSplitMetadataViewFix, @"Native metadata setting must remain unchanged outside CarPlay");
        NSCAssert(CGRectEqualToRect(mini.miniplayerFrame, CGRectMake(900, 800, 500, 300)), @"Phone mini-player geometry must remain untouched");
        NSArray *sizes = @[[NSValue valueWithCGSize:CGSizeMake(480, 240)], [NSValue valueWithCGSize:CGSizeMake(640, 360)],
            [NSValue valueWithCGSize:CGSizeMake(800, 480)], [NSValue valueWithCGSize:CGSizeMake(1024, 600)],
            [NSValue valueWithCGSize:CGSizeMake(1280, 480)], [NSValue valueWithCGSize:CGSizeMake(1920, 720)],
            [NSValue valueWithCGSize:CGSizeMake(768, 1024)]];
        for (NSValue *value in sizes) {
            CGSize size = value.CGSizeValue;
            CGRect bounds = (CGRect){CGPointZero, size};
            UIEdgeInsets safe = UIEdgeInsetsMake(0, 48, 64, 0);
            for (NSValue *origin in @[[NSValue valueWithCGPoint:CGPointMake(-999, -999)], [NSValue valueWithCGPoint:CGPointMake(9999, 9999)]]) {
                CGRect requested = (CGRect){origin.CGPointValue, CGSizeMake(500, 300)};
                CGRect fitted = YCPFitMiniPlayer(requested, bounds, safe);
                NSCAssert(CGRectContainsRect(UIEdgeInsetsInsetRect(bounds, safe), fitted), @"Mini-player must stay inside the usable area at every supported test size");
                NSCAssert(fabs(fitted.size.width / fitted.size.height - 16.0/9.0) < 0.001, @"Mini-player must preserve the video aspect ratio");
            }
        }
        NSCAssert(!YCPShouldUseWideWatch(CGSizeMake(800, 480)), @"Short narrow screens must not squeeze two columns");
        NSCAssert(YCPShouldUseWideWatch(CGSizeMake(1024, 600)), @"Wide screens must keep video and queue side by side");
        NSCAssert(!YCPShouldUseWideWatch(CGSizeMake(768, 1024)), @"Tall displays must use the native stacked layout");
        NSCAssert(!layout.isLargeWideLayout && !layout.isLandscape, @"Phone flags must remain original");
        NSCAssert(layout.interfaceOrientation == UIInterfaceOrientationPortrait, @"Phone orientation must remain original");
        TestCarWindow = [[FixtureCarWindow alloc] initWithFrame:CGRectMake(0, 0, 1020, 573)];
        YTWatchViewController *car = [YTWatchViewController new];
        YTWatchLayerViewController *layer = [YTWatchLayerViewController new];
        TestCarWindow.rootViewController = layer;
        [layer addChildViewController:car];
        [layer.view addSubview:car.view];
        [car didMoveToParentViewController:layer];
        TestCarWindow.hidden = NO;
        layout.watchLayerView = car.view;
        UIEdgeInsets nativeInsets = [car.view yt_safeAreaInsetsForWindow];
        NSCAssert(nativeInsets.top == TestCarWindow.safeAreaInsets.top, @"Native window-inset category must discard the phone status-bar height");
        NSCAssert(nativeInsets.left == 7 && nativeInsets.bottom == 9, @"Unrelated native insets must be preserved");
        NSCAssert([phone.view yt_safeAreaInsetsForWindow].top == 60, @"Phone safe-area category must remain unchanged");
        NSCAssert(config.enableIosSplitMetadataViewFix, @"CarPlay must enable the native split-metadata measurement fix");
        NSCAssert(CGRectContainsRect(TestCarWindow.bounds, mini.miniplayerFrame), @"Actual mini-player hook must fit car dimensions");
        NSCAssert(layer.statusBarHeight == TestCarWindow.safeAreaInsets.top, @"Car status inset must use its own window, not the phone's cached height");
        NSCAssert(layer.headerHeight == TestCarWindow.safeAreaInsets.top, @"Car header must not reserve phone navigation space");
        YTWatchLayerViewController *phoneLayer = [YTWatchLayerViewController new];
        NSCAssert(phoneLayer.statusBarHeight == 60 && phoneLayer.headerHeight == 60, @"Other controllers must retain native phone insets");
        NSCAssert(layout.isLargeLayout && layout.isLargeWideLayout && layout.isLandscape, @"Native iPad wide branch must be selected in car");
        NSCAssert(layout.interfaceOrientation == UIInterfaceOrientationLandscapeLeft, @"Watch orientation must follow car geometry");
        NSCAssert([car isWideLayoutForWatchView:car.view], @"Native watch delegate must select the wide renderer");
        NSCAssert(![phone isWideLayoutForWatchView:phone.view], @"Phone delegate must stay unchanged while car connected");
        YTWatchNextResultsViewController *metadataInsets = [YTWatchNextResultsViewController new];
        [car addChildViewController:metadataInsets];
        metadataInsets.view.frame = car.view.bounds;
        [car.view addSubview:metadataInsets.view];
        [metadataInsets didMoveToParentViewController:car];
        UICollectionViewFlowLayout *metadataFlow = [UICollectionViewFlowLayout new];
        UICollectionView *metadataCollection = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 310, 680, 220) collectionViewLayout:metadataFlow];
        [metadataInsets.view addSubview:metadataCollection];
        UIEdgeInsets titleInset = [metadataInsets collectionView:metadataCollection layout:metadataFlow insetForSectionAtIndex:0];
        NSCAssert(titleInset.top == 12 && titleInset.left == 10 && titleInset.bottom == 4, @"First metadata section must clear the player without altering horizontal/bottom spacing");
        metadataCollection.contentOffset = CGPointMake(0, 90);
        (void)[metadataInsets collectionView:metadataCollection layout:metadataFlow insetForSectionAtIndex:0];
        NSCAssert(metadataCollection.contentOffset.y == 90, @"Metadata spacing must never reset the user's scroll position");
        NSCAssert([metadataInsets collectionView:metadataCollection layout:metadataFlow insetForSectionAtIndex:1].top == -6, @"Later metadata sections retain native spacing");
        metadataCollection.frame = CGRectMake(700, 0, 320, 530);
        NSCAssert([metadataInsets collectionView:metadataCollection layout:metadataFlow insetForSectionAtIndex:0].top == -6, @"Right video queue retains native spacing");
        [phone.view addSubview:metadataCollection];
        NSCAssert([metadataInsets collectionView:metadataCollection layout:metadataFlow insetForSectionAtIndex:0].top == -6, @"Phone collection spacing is unchanged");
        layout.watchLayerView = phone.view;
        NSCAssert(!layout.isLargeWideLayout, @"Another window must not inherit car flags");
        UIWindow *gridWindow = [[FixtureCarWindow alloc] initWithFrame:CGRectMake(0, 0, 1020, 573)];
        YTHomeViewController *home = [YTHomeViewController new];
        gridWindow.rootViewController = home; gridWindow.hidden = NO;
        FixtureGridSection *section = [FixtureGridSection new]; section.feedController = home;
        NSCAssert(YCPShouldOverrideBrowseGrid(section, gridWindow), @"Recognized Home sections may use the car grid");
        NSCAssert(!YCPShouldOverrideBrowseGrid([FixtureGridSection new], gridWindow), @"Unknown sections must preserve native layout");
        YTSearchResultsViewController *search = [YTSearchResultsViewController new];
        gridWindow.rootViewController = search;
        section.feedController = search;
        NSCAssert(!YCPShouldOverrideBrowseGrid(section, gridWindow), @"Search rows must never inherit Home columns");
        [search addChildViewController:home]; [search.view addSubview:home.view]; [home didMoveToParentViewController:search];
        section.feedController = home;
        NSCAssert(!YCPShouldOverrideBrowseGrid(section, gridWindow), @"Search ancestors must override a Home-like child name");
        YTWatchMetadataViewController *metadata = [YTWatchMetadataViewController new];
        gridWindow.rootViewController = metadata; section.feedController = metadata;
        NSCAssert(!YCPShouldOverrideBrowseGrid(section, gridWindow), @"Watch metadata must retain its native column measurements");
        NSCAssert(!YCPShouldOverrideBrowseGrid(phone.view, gridWindow), @"Other windows must not receive car grid changes");
        UIWindow *watchCar = TestCarWindow;
        TestCarWindow = gridWindow;
        YCPInstallHeaderLayoutHooks();
        YCPInstallHeaderLayoutHooks();
        YTHomeViewController *headerHome = [YTHomeViewController new];
        gridWindow.rootViewController = headerHome;
        UIScrollView *feedScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 44, 1020, 520)];
        feedScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        feedScroll.alwaysBounceVertical = YES;
        feedScroll.contentSize = CGSizeMake(1020, 2400);
        [headerHome.view addSubview:feedScroll];
        YTHeaderView *header = [[YTHeaderView alloc] initWithFrame:CGRectMake(0, 0, 900, 56)];
        header.headerScrollEnabled = NO; header.stickyNavHeaderEnabled = YES;
        [headerHome.view addSubview:header];
        NSCAssert(header.headerScrollEnabled && !header.stickyNavHeaderEnabled, @"Car browse header must allow native hide/reveal scrolling");
        UIColor *carHeaderColor = [UIColor colorWithWhite:15.0 / 255.0 alpha:1];
        NSCAssert([header.barTintColor isEqual:carHeaderColor], @"Cold-attach header must immediately use YouTube's dark background");
        [header updateBackgroundColor]; header.barTintColor = UIColor.grayColor;
        NSCAssert([header.barTintColor isEqual:carHeaderColor] && [header.backgroundColor isEqual:carHeaderColor], @"Late theme updates must not reintroduce the gray header");
        NSCAssert(header.maximumHeaderHeight == 44, @"Browse header must discard the cached 60-point phone inset");
        YCPRefreshHeaderScrollObservers();
        feedScroll.contentOffset = CGPointMake(0, 80);
        NSCAssert(header.currentHeaderHeight == 0, @"Actual feed scrolling down must collapse the header");
        feedScroll.contentOffset = CGPointMake(0, 55);
        NSCAssert(header.currentHeaderHeight > 0, @"Reversing scroll direction must reveal the header before reaching the top");
        feedScroll.contentOffset = CGPointZero;
        NSCAssert(header.currentHeaderHeight == 44, @"Returning to the top must fully reveal the compact header");
        header.headerScrollEnabled = NO; header.stickyNavHeaderEnabled = YES;
        NSCAssert(header.headerScrollEnabled && !header.stickyNavHeaderEnabled, @"Native configuration updates must not pin the car header");
        [phone.view addSubview:header];
        NSCAssert([header.barTintColor isEqual:UIColor.darkGrayColor], @"Returning to the phone must restore native background updates");
        NSCAssert(!header.headerScrollEnabled && header.stickyNavHeaderEnabled, @"Phone must regain its original header settings");
        YTSearchResultsViewController *headerSearch = [YTSearchResultsViewController new];
        gridWindow.rootViewController = headerSearch;
        YTHeaderView *searchHeader = [YTHeaderView new];
        searchHeader.headerScrollEnabled = NO; searchHeader.stickyNavHeaderEnabled = YES;
        [headerSearch.view addSubview:searchHeader];
        NSCAssert(!searchHeader.headerScrollEnabled && searchHeader.stickyNavHeaderEnabled, @"Search toolbar must not inherit browse-header behavior");
        TestCarWindow = watchCar;
        gridWindow.hidden = YES;
        TestCarWindow.frame = CGRectMake(0, 0, 500, 700);
        layout.watchLayerView = car.view;
        NSCAssert(!layout.isLargeWideLayout, @"Narrow portrait surfaces must retain native layout");
        NSCAssert(layer.statusBarHeight == 60, @"Portrait fallback must restore original status-bar height");
        TestCarWindow = nil;
        NSCAssert(!layout.isLargeWideLayout, @"Disconnect must restore native decisions");
        YCPInstallWatchLayoutHooks();
        NSCAssert(!layout.isLandscape, @"Installing twice must not recurse or replace original");
        NSLog(@"WATCH_LAYOUT_TESTS_PASSED");
        exit(0);
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(TestApp.class)); }
}
