#import "YCPNative.h"
#import "YCPResponsiveLayout.h"
#import <objc/message.h>
#import <objc/runtime.h>

void YCPLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[YouTubeCarPlay] %@", message);
    // No account information, searches, cookies or video URLs are recorded.
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/YouTubeCarPlay.log"];
    @synchronized (YCPSurface.class) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path])
            [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        @try {
            [file seekToEndOfFile];
            [file writeData:[[NSString stringWithFormat:@"%@ %@\n", NSDate.date, message] dataUsingEncoding:NSUTF8StringEncoding]];
            [file closeFile];
        } @catch (NSException *exception) { NSLog(@"[YouTubeCarPlay] Log file unavailable"); }
    }
}

BOOL YCPIsCarRole(UISceneSessionRole role) {
    return [role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication]
        || [role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]
        || [role isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive];
}

static id YCPReadObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

@interface YCPHost : UIViewController
@property(nonatomic, strong) UIViewController *nativeController;
@property(nonatomic, strong) YCPScaledContentView *content;
@property(nonatomic, strong) UIStackView *keyboard;
@property(nonatomic, weak) UIView<UIKeyInput> *inputTarget;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic) BOOL originalTranslatesAutoresizingMask;
@property(nonatomic, strong) UIWindow *keyboardWindow;
@property(nonatomic, strong) NSLayoutConstraint *leftInset;
- (void)embed:(UIViewController *)controller;
- (void)releaseNative;
- (void)showKeyboardFor:(UIView<UIKeyInput> *)target;
@end

@implementation YCPHost
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    button.accessibilityLabel = title;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    // Draw YouTube's surface edge to edge; only interactive content is inset
    // by the CarPlay safe-area guide below.
    UIColor *surface = [UIColor colorWithWhite:15.0 / 255.0 alpha:1];
    self.view.backgroundColor = surface;
    self.content = [YCPScaledContentView new];
    self.content.backgroundColor = surface;
    self.keyboard = [UIStackView new];
    self.keyboard.axis = UILayoutConstraintAxisVertical;
    self.keyboard.spacing = 4;
    self.keyboard.hidden = YES;
    self.keyboard.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    for (NSString *row in @[@"1234567890", @"qwertyuiop", @"asdfghjkl", @"zxcvbnm"]) {
        UIStackView *keys = [UIStackView new];
        keys.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger index = 0; index < row.length; index++) {
            UIButton *key = [self button:[row substringWithRange:NSMakeRange(index, 1)] action:@selector(typeKey:)];
            [keys addArrangedSubview:key];
        }
        [keys.heightAnchor constraintEqualToConstant:38].active = YES;
        [self.keyboard addArrangedSubview:keys];
    }
    UIStackView *controls = [UIStackView new];
    controls.distribution = UIStackViewDistributionFillEqually;
    [controls addArrangedSubview:[self button:@"Space" action:@selector(typeSpace)]];
    [controls addArrangedSubview:[self button:@"Delete" action:@selector(deleteKey)]];
    [controls addArrangedSubview:[self button:@"Search" action:@selector(submitSearch)]];
    [controls addArrangedSubview:[self button:@"Done" action:@selector(hideKeyboard)]];
    [controls.heightAnchor constraintEqualToConstant:42].active = YES;
    [self.keyboard addArrangedSubview:controls];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.content, self.keyboard]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.leftInset = [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.leftInset,
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
    self.status = [UILabel new];
    self.status.text = @"Opening YouTube…";
    self.status.numberOfLines = 0;
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.textColor = UIColor.whiteColor;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.centerYAnchor constraintEqualToAnchor:self.content.centerYAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:20],
        [self.status.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-20]
    ]];
}
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    self.leftInset.constant = 0;
}
- (void)embed:(UIViewController *)controller {
    [self loadViewIfNeeded];
    if (self.nativeController == controller) return;
    [self releaseNative];
    self.nativeController = controller;
    self.originalTranslatesAutoresizingMask = controller.view.translatesAutoresizingMaskIntoConstraints;
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addChildViewController:controller];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content.canvas addSubview:controller.view];
    [NSLayoutConstraint activateConstraints:@[
        [controller.view.leadingAnchor constraintEqualToAnchor:self.content.canvas.leadingAnchor],
        [controller.view.trailingAnchor constraintEqualToAnchor:self.content.canvas.trailingAnchor],
        [controller.view.topAnchor constraintEqualToAnchor:self.content.canvas.topAnchor],
        [controller.view.bottomAnchor constraintEqualToAnchor:self.content.canvas.bottomAnchor]
    ]];
    [self.content setNeedsLayout];
    [self.content layoutIfNeeded];
    [controller didMoveToParentViewController:self];
    self.status.hidden = YES;
}
- (void)releaseNative {
    if (!self.nativeController) return;
    [self.nativeController willMoveToParentViewController:nil];
    [self.nativeController.view removeFromSuperview];
    [self.nativeController removeFromParentViewController];
    self.nativeController.view.translatesAutoresizingMaskIntoConstraints = self.originalTranslatesAutoresizingMask;
    self.nativeController = nil;
    self.status.hidden = NO;
    [self hideKeyboard];
}
- (void)showKeyboardFor:(UIView<UIKeyInput> *)target {
    if (self.inputTarget == target && self.keyboardWindow) return;
    self.inputTarget = target;
    UIWindowScene *scene = target.window.windowScene;
    if (!scene) return;
    Class factory = NSClassFromString(@"YCPKeyboardFactory");
    SEL make = NSSelectorFromString(@"makeWithText:secure:onChange:onGo:onDone:");
    if (![factory respondsToSelector:make]) return;
    self.keyboardWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.keyboardWindow.windowLevel = UIWindowLevelAlert + 1;
    NSString *text = [target respondsToSelector:@selector(text)] ? [(id)target text] : @"";
    BOOL secure = [target respondsToSelector:@selector(isSecureTextEntry)] && [(id)target isSecureTextEntry];
    __weak typeof(self) weakSelf = self;
    void (^changed)(NSString *) = ^(NSString *value) {
        UIView<UIKeyInput> *input = weakSelf.inputTarget;
        if ([input conformsToProtocol:@protocol(UITextInput)]) {
            id<UITextInput> editor = (id)input;
            UITextRange *all = [editor textRangeFromPosition:editor.beginningOfDocument toPosition:editor.endOfDocument];
            [editor replaceRange:all withText:value];
        }
    };
    void (^go)(void) = ^{ [weakSelf submitSearch]; };
    void (^done)(void) = ^{ [weakSelf hideKeyboard]; };
    UIViewController *keys = ((id (*)(id, SEL, id, BOOL, id, id, id))objc_msgSend)(factory, make, text ?: @"", secure, changed, go, done);
    self.keyboardWindow.rootViewController = keys;
    self.keyboardWindow.hidden = NO;
}
- (void)hideKeyboard {
    self.keyboardWindow.hidden = YES;
    self.keyboardWindow = nil;
    self.keyboard.hidden = YES;
    [self.inputTarget resignFirstResponder];
    self.inputTarget = nil;
}
- (void)typeKey:(UIButton *)sender { [self.inputTarget insertText:sender.currentTitle]; }
- (void)typeSpace { [self.inputTarget insertText:@" "]; }
- (void)deleteKey { [self.inputTarget deleteBackward]; }
- (void)submitSearch {
    id target = self.inputTarget;
    if ([target isKindOfClass:UITextField.class]) {
        UITextField *field = target;
        if ([field.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) [field.delegate textFieldShouldReturn:field];
        else [field sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
    } else [target insertText:@"\n"];
    [self hideKeyboard];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface YCPSurface ()
@property(nonatomic, strong) CPInterfaceController *interfaceController;
@property(nonatomic, weak) UIWindow *templateWindow;
@property(nonatomic, weak) UIWindow *sceneWindow;
@property(nonatomic, strong) UIWindow *phoneWindow;
@property(nonatomic, strong) UIViewController *nativeController;
@property(nonatomic, strong) YCPHost *host;
@property(nonatomic, strong) UIViewController *phonePlaceholder;
@property(nonatomic, strong) NSTimer *retryTimer;
@property(nonatomic) NSUInteger attempts;
@property(nonatomic) BOOL reconciling;
@property(nonatomic) BOOL requestedPhoneScene;
@end

@implementation YCPSurface
+ (instancetype)shared {
    static YCPSurface *surface;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ surface = [YCPSurface new]; });
    return surface;
}
- (UIWindow *)activeWindow { return self.sceneWindow ?: self.templateWindow; }
- (CGRect)contentBounds {
    UIView *view = self.nativeController.viewIfLoaded ?: self.activeWindow.rootViewController.viewIfLoaded;
    return view ? view.bounds : self.activeWindow.bounds;
}
- (UIEdgeInsets)miniPlayerSafeInsets {
    UIEdgeInsets insets = self.nativeController.viewIfLoaded ? self.nativeController.viewIfLoaded.safeAreaInsets : UIEdgeInsetsZero;
    id pivot = YCPReadObject(self.nativeController, @"pivotBarViewController");
    UIView *bar = [pivot isKindOfClass:UIViewController.class] ? ((UIViewController *)pivot).viewIfLoaded : nil;
    if (bar && !bar.hidden && bar.window == self.activeWindow) {
        CGFloat height = bar.bounds.size.height;
        insets.bottom = MAX(insets.bottom, height > 0 && height < 100 ? height + 8 : 64);
    }
    return insets;
}
- (BOOL)ownsNativeController:(UIViewController *)controller { return controller && controller == self.nativeController; }
- (void)sourceWindowMovedToPhone:(UIWindow *)window {
    if (window != self.phoneWindow) return;
    window.hidden = NO;
    [window makeKeyAndVisible];
    YCPLog(@"Native phone window activated alongside CarPlay");
}
- (void)connectTemplate:(CPInterfaceController *)controller window:(CPWindow *)window {
    YCPLog(@"Template connected: window=%@", window ? NSStringFromCGRect(window.bounds) : @"none");
    self.interfaceController = controller;
    self.templateWindow = window;
    if (self.activeWindow) {
        [controller setRootTemplate:[[CPListTemplate alloc] initWithTitle:@"YouTube" sections:@[]] animated:NO completion:nil];
    } else {
        CPListItem *item = [[CPListItem alloc] initWithText:@"Waiting for a CarPlay window" detailText:@"Native YouTube needs a drawable car display. Open YouDash on your iPhone to finish setup."];
        [controller setRootTemplate:[[CPListTemplate alloc] initWithTitle:@"YouTube" sections:@[[[CPListSection alloc] initWithItems:@[item]]]] animated:NO completion:nil];
    }
    [self reconcile];
}
- (void)disconnectTemplate {
    YCPLog(@"Template disconnected");
    UIWindow *old = self.templateWindow;
    self.templateWindow = nil;
    self.interfaceController = nil;
    if (old.rootViewController == self.host) old.rootViewController = nil;
    [self reconcile];
}
- (void)connectWindow:(UIWindow *)window {
    YCPLog(@"Window connected: role=%@ bounds=%@", window.windowScene.session.role, NSStringFromCGRect(window.bounds));
    if (self.sceneWindow != window && self.sceneWindow.rootViewController == self.host)
        self.sceneWindow.rootViewController = nil;
    self.sceneWindow = window;
    [self reconcile];
}
- (void)disconnectWindow:(UIWindow *)window {
    YCPLog(@"Window disconnected");
    if (self.sceneWindow != window) return;
    self.sceneWindow = nil;
    if (window.rootViewController == self.host) window.rootViewController = nil;
    [self reconcile];
}
- (UIWindow *)findPhoneWindow {
    UIWindow *best = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || ![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root = window.rootViewController;
            if (!root || [root isKindOfClass:YCPHost.class] || window.windowLevel != UIWindowLevelNormal) continue;
            if (!best || window.isKeyWindow) best = window;
        }
    }
    if (!best) {
        id delegate = UIApplication.sharedApplication.delegate;
        Ivar ivar = class_getInstanceVariable([delegate class], "_mainWindow");
        UIWindow *nativeWindow = ivar ? object_getIvar(delegate, ivar) : nil;
        if ([nativeWindow.rootViewController isKindOfClass:NSClassFromString(@"YTAppViewControllerImpl")]) best = nativeWindow;
    }
    return best;
}
- (void)restorePhone {
    [self.retryTimer invalidate]; self.retryTimer = nil;
    UIViewController *native = self.nativeController;
    [self.host releaseNative];
    // Clear ownership before assigning the root: the window hook otherwise
    // correctly prevents an owned car controller from moving back to the phone.
    self.nativeController = nil;
    if (native && self.phoneWindow.rootViewController == self.phonePlaceholder) {
        self.phoneWindow.rootViewController = native;
        [self.phoneWindow makeKeyAndVisible];
        YCPLog(@"Restored initialized YouTube interface to source window");
    }
    self.phonePlaceholder = nil;
    self.phoneWindow = nil;
    self.host = nil;
    self.requestedPhoneScene = NO;
    self.attempts = 0;
}
- (void)scheduleRetry {
    if (self.retryTimer || self.attempts >= 90) return;
    __weak typeof(self) weakSelf = self;
    self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        YCPSurface *owner = weakSelf;
        if (!owner || ++owner.attempts >= 90) {
            [timer invalidate]; owner.retryTimer = nil;
            owner.host.status.text = @"Open YouDash on your phone, then reconnect CarPlay.";
            YCPLog(@"Native scene initialization timed out");
            return;
        }
        [owner reconcile];
    }];
}
- (void)reconcile {
    NSAssert(NSThread.isMainThread, @"CarPlay UI must run on main thread");
    if (self.reconciling) return;
    self.reconciling = YES;
    @try {
        UIWindow *destination = self.activeWindow;
        if (!destination) { [self restorePhone]; return; }
        if (!self.host) self.host = [YCPHost new];
        destination.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        if (destination.rootViewController != self.host) {
            // A CPWindow and a window scene can arrive in either order. One host owns
            // the native controller; moving surfaces must never duplicate the player.
            for (UIWindow *other in @[self.templateWindow ?: destination, self.sceneWindow ?: destination])
                if (other != destination && other.rootViewController == self.host) other.rootViewController = nil;
            destination.rootViewController = self.host;
            [destination makeKeyAndVisible];
        }
        if (self.nativeController) return;
        UIWindow *phone = [self findPhoneWindow];
        if (phone) {
            UIViewController *phoneRoot = phone.rootViewController;
            Class nativeClass = NSClassFromString(@"YTAppViewControllerImpl");
            if (!nativeClass || ![phoneRoot isKindOfClass:nativeClass]) {
                YCPLog(@"Waiting for Google's initialized native root, current=%@", NSStringFromClass(phoneRoot.class));
                [self scheduleRetry];
                return;
            }
            // The independent root rendered the pivot bar but had an empty
            // navigation stack. Reuse Google's initialized tree and its existing
            // account, navigation, event handlers and playback services instead.
            id navigation = YCPReadObject(phoneRoot, @"appNavigationController");
            NSArray *stack = YCPReadObject(navigation, @"viewControllers");
            if (stack.count == 0) {
                self.host.status.text = @"Waiting for YouTube to finish loading on the phone…";
                [self scheduleRetry];
                return;
            }
            self.phoneWindow = phone;
            self.nativeController = phoneRoot;
            UIViewController *placeholder = [UIViewController new];
            placeholder.view.backgroundColor = UIColor.blackColor;
            UILabel *label = [UILabel new];
            label.text = @"YouTube is on the car display.\nDisconnect CarPlay to restore it here.";
            label.numberOfLines = 0;
            label.textColor = UIColor.whiteColor;
            label.textAlignment = NSTextAlignmentCenter;
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [placeholder.view addSubview:label];
            [NSLayoutConstraint activateConstraints:@[
                [label.centerYAnchor constraintEqualToAnchor:placeholder.view.centerYAnchor],
                [label.leadingAnchor constraintEqualToAnchor:placeholder.view.leadingAnchor constant:24],
                [label.trailingAnchor constraintEqualToAnchor:placeholder.view.trailingAnchor constant:-24]
            ]];
            self.phonePlaceholder = placeholder;
            // Preserve phone UI idiom and size classes inside the car host.
            self.host.traitOverrides.userInterfaceIdiom = UIUserInterfaceIdiomPad;
            self.host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
            self.host.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassRegular;
            phone.rootViewController = placeholder;
            [self.host embed:phoneRoot];
            [destination makeKeyAndVisible];
            if (YCPIsCarRole(phone.windowScene.session.role) && phone != destination) phone.hidden = YES;
            [self.retryTimer invalidate]; self.retryTimer = nil;
            YCPLog(@"Transferred initialized native root: %@ navigationDepth=%lu car=%@", NSStringFromClass(phoneRoot.class), (unsigned long)stack.count, NSStringFromCGRect(destination.bounds));
        } else {
            if (!self.requestedPhoneScene) {
                self.requestedPhoneScene = YES;
                YCPLog(@"Waiting for native startup services from the car scene");
            }
            [self scheduleRetry];
        }
    } @finally { self.reconciling = NO; }
}
- (void)textInputBecameActive:(UIView *)view {
    if (view.window != self.activeWindow || ![view conformsToProtocol:@protocol(UIKeyInput)]) return;
    [self.host showKeyboardFor:(id)view];
}
@end

// Diagnostics only (issue #3): records which path, if any, delivers a drawable
// car window. Nothing here changes routing or window ownership.
static NSString *YCPDescribeWindow(UIWindow *window) {
    if (!window) return @"nil";
    return [NSString stringWithFormat:@"%@ bounds=%@ screen=%@ hidden=%d root=%@", NSStringFromClass(window.class),
            NSStringFromCGRect(window.bounds), window.screen ? NSStringFromCGRect(window.screen.bounds) : @"nil",
            window.hidden, NSStringFromClass(window.rootViewController.class)];
}

static void YCPLogCarDiagnostics(NSString *path, CPTemplateApplicationScene *scene, CPWindow *window) {
    YCPLog(@"Diagnostics: path=%@ OS=%@ callbackWindow=%@", path, UIDevice.currentDevice.systemVersion, YCPDescribeWindow(window));
    YCPLog(@"Diagnostics: scene.carWindow=%@", YCPDescribeWindow(scene.carWindow));
    if (@available(iOS 26.4, *)) {
        static CPSessionConfiguration *session;
        static id<CPSessionConfigurationDelegate> sessionDelegate;
        if (!session) {
            sessionDelegate = (id<CPSessionConfigurationDelegate>)[NSObject new];
            session = [[CPSessionConfiguration alloc] initWithDelegate:sessionDelegate];
        }
        YCPLog(@"Diagnostics: supportsVideoPlayback=%d limitedUI=%lu", session.supportsVideoPlayback, (unsigned long)session.limitedUserInterfaces);
    }
    for (UIScene *connected in UIApplication.sharedApplication.connectedScenes)
        YCPLog(@"Diagnostics: connected scene role=%@ class=%@ state=%ld", connected.session.role,
               NSStringFromClass(connected.class), (long)connected.activationState);
}

@implementation YCPTemplateDelegate
- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene didConnectInterfaceController:(CPInterfaceController *)controller toWindow:(CPWindow *)window {
    YCPLogCarDiagnostics(@"toWindow", scene, window);
    [YCPSurface.shared connectTemplate:controller window:window];
}
- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene didConnectInterfaceController:(CPInterfaceController *)controller {
    YCPLogCarDiagnostics(@"noWindow", scene, nil);
    [YCPSurface.shared connectTemplate:controller window:nil];
}
- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene didDisconnectInterfaceController:(CPInterfaceController *)controller fromWindow:(CPWindow *)window {
    [YCPSurface.shared disconnectTemplate];
}
- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene didDisconnectInterfaceController:(CPInterfaceController *)controller {
    [YCPSurface.shared disconnectTemplate];
}
- (void)sceneDidBecomeActive:(UIScene *)scene { [YCPSurface.shared reconcile]; }
- (void)sceneDidDisconnect:(UIScene *)scene { [YCPSurface.shared disconnectTemplate]; }
@end

@implementation YCPWindowDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    YCPBootstrapNativeScene((UIWindowScene *)scene, session, options);
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [YCPSurface.shared connectWindow:self.window];
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    [YCPSurface.shared disconnectWindow:self.window];
    self.window = nil;
}
- (void)sceneDidBecomeActive:(UIScene *)scene { [YCPSurface.shared reconcile]; }
@end
