#import "YCPNative.h"
#import "YCPResponsiveLayout.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Hooks stay within the YouTube process. No SpringBoard or CarPlay service injection.
// Implemented independently of the retired CarTV YouTube experiment.
static const void *YCPConfigurationIMPKey = &YCPConfigurationIMPKey;
static IMP YCPOriginalSetDelegate;
static IMP YCPOriginalSetRoot;
static IMP YCPOriginalBecomeFirstResponder;
static IMP YCPOriginalTextFieldInput;
static IMP YCPOriginalTextViewInput;
static IMP YCPOriginalSetWindowScene;
static IMP YCPOriginalViewDidLayout;

static IMP YCPOriginalPlaybackError;
static void YCPRecordPlaybackError(NSError *error, NSUInteger depth) {
    if (![error isKindOfClass:NSError.class] || depth > 5) return;
    // Record diagnostic identifiers only. Never dump URLs, request headers,
    // account details, response bodies, or arbitrary error userInfo values.
    NSMutableDictionary *status = [NSMutableDictionary new];
    for (NSString *key in @[@"statusCode", @"HTTPStatusCode", @"httpStatusCode", @"reasonCode", @"errorCode", @"NSURLErrorFailingURLPeerTrustErrorKey"])
        if ([error.userInfo[key] isKindOfClass:NSNumber.class]) status[key] = error.userInfo[key];
    YCPLog(@"Playback failure depth=%lu domain=%@ code=%ld status=%@", (unsigned long)depth, error.domain, (long)error.code, status);
    YCPRecordPlaybackError(error.userInfo[NSUnderlyingErrorKey], depth + 1);
    id multiple = error.userInfo[@"NSMultipleUnderlyingErrors"];
    if ([multiple isKindOfClass:NSArray.class])
        for (id nested in multiple) YCPRecordPlaybackError(nested, depth + 1);
}
static void YCPPlaybackError(id controller, SEL selector, NSError *error) {
    YCPRecordPlaybackError(error, 0);
    ((void (*)(id, SEL, id))YCPOriginalPlaybackError)(controller, selector, error);
}

static BOOL YCPAllowNativeCarStartup(id config, SEL selector) { return NO; }

void YCPBootstrapNativeScene(UIWindowScene *scene, UISceneSession *session, UISceneConnectionOptions *options) {
    id delegate = UIApplication.sharedApplication.delegate;
    Ivar mainWindowIvar = class_getInstanceVariable([delegate class], "_mainWindow");
    UIWindow *existing = mainWindowIvar ? object_getIvar(delegate, mainWindowIvar) : nil;
    if (existing.rootViewController) return;
    // Google's 21.42.4 scene router deliberately ignores non-phone roles. Run its
    // own startup against the car's real UIWindowScene, with only that app-local
    // feature check disabled for the duration of this call. No phone activation.
    Ivar configIvar = class_getInstanceVariable([delegate class], "_hotConfig");
    id config = configIvar ? object_getIvar(delegate, configIvar) : nil;
    Class configClass = [config class];
    SEL flag = NSSelectorFromString(@"mainAppCoreClientIos27SceneDelegateIgnoreNonRoleApplicationWindows");
    Method flagMethod = configClass && [config respondsToSelector:flag] ? class_getInstanceMethod(configClass, flag) : NULL;
    IMP original = flagMethod ? method_getImplementation(flagMethod) : NULL;
    if (original) {
        const char *types = method_getTypeEncoding(flagMethod);
        if (!class_addMethod(configClass, flag, (IMP)YCPAllowNativeCarStartup, types))
            class_replaceMethod(configClass, flag, (IMP)YCPAllowNativeCarStartup, types);
    }
    @try {
        SEL connect = @selector(scene:willConnectToSession:options:);
        if ([delegate respondsToSelector:connect]) {
            YCPLog(@"Cold CarPlay launch: starting Google's native scene lifecycle");
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(delegate, connect, scene, session, options);
        }
        UIWindow *initializedWindow = mainWindowIvar ? object_getIvar(delegate, mainWindowIvar) : nil;
        if (!initializedWindow && mainWindowIvar) {
            UIWindow *bootstrapWindow = [[UIWindow alloc] initWithWindowScene:scene];
            [delegate setValue:bootstrapWindow forKey:@"mainWindow"];
            YCPLog(@"Created native startup window on CarPlay");
        }
        SEL foreground = @selector(sceneWillEnterForeground:);
        if ([delegate respondsToSelector:foreground]) ((void (*)(id, SEL, id))objc_msgSend)(delegate, foreground, scene);
        SEL active = @selector(sceneDidBecomeActive:);
        if ([delegate respondsToSelector:active]) ((void (*)(id, SEL, id))objc_msgSend)(delegate, active, scene);
    } @finally {
        if (original) class_replaceMethod(configClass, flag, original, method_getTypeEncoding(flagMethod));
    }
}

static void YCPInspectNativeRoot(UIViewController *root) {
    static BOOL inspected = NO;
    if (inspected || ![NSStringFromClass(root.class) isEqualToString:@"YTAppViewControllerImpl"]) return;
    inspected = YES;
    for (NSString *property in @[@"services", @"navigationProtocol", @"appEventHandler", @"parentResponder", @"eventGroupHandlers"]) {
        SEL getter = NSSelectorFromString(property);
        if (![root respondsToSelector:getter]) continue;
        id value = [root valueForKey:property];
        NSArray *objects = [value isKindOfClass:NSArray.class] ? value : (value ? @[value] : @[]);
        YCPLog(@"Startup dependency %@ class=%@ count=%lu", property, NSStringFromClass([value class]), (unsigned long)objects.count);
        for (id object in objects) {
            NSMutableArray *selectors = [NSMutableArray new];
            unsigned int count = 0;
            Method *methods = class_copyMethodList([object class], &count);
            for (unsigned int index = 0; index < count; index++) {
                NSString *name = NSStringFromSelector(method_getName(methods[index]));
                if ([name hasPrefix:@"init"] || [name hasPrefix:@"set"] || [name containsString:@"ViewController"])
                    [selectors addObject:name];
            }
            free(methods);
            YCPLog(@"Startup component %@: %@", NSStringFromClass([object class]), [selectors componentsJoinedByString:@", "]);
        }
    }
}

static UISceneConfiguration *YCPSceneConfiguration(id object, SEL selector, UIApplication *application,
                                                  UISceneSession *session, UISceneConnectionOptions *options) {
    YCPLog(@"Diagnostics: scene requested role=%@ car=%d", session.role, YCPIsCarRole(session.role));
    if (YCPIsCarRole(session.role)) {
        UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"YouTube CarPlay" sessionRole:session.role];
        BOOL isTemplate = [session.role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication];
        configuration.sceneClass = isTemplate ? CPTemplateApplicationScene.class : UIWindowScene.class;
        configuration.delegateClass = isTemplate ? YCPTemplateDelegate.class : YCPWindowDelegate.class;
        YCPLog(@"Route scene: %@ delegate=%@", session.role, NSStringFromClass(configuration.delegateClass));
        return configuration;
    }
    // Each delegate class owns its original implementation. A new delegate cannot
    // accidentally overwrite the original for another class.
    IMP original = NULL;
    for (Class cls = object_getClass(object); cls && !original; cls = class_getSuperclass(cls))
        original = [objc_getAssociatedObject(cls, YCPConfigurationIMPKey) pointerValue];
    if (original) return ((id (*)(id, SEL, id, id, id))original)(object, selector, application, session, options);
    // YouTube 21.42.4's original scene manifest is kept intact when packaging.
    NSArray *configurations = NSBundle.mainBundle.infoDictionary[@"UIApplicationSceneManifest"][@"UISceneConfigurations"][session.role];
    NSDictionary *entry = configurations.firstObject;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:entry[@"UISceneConfigurationName"] sessionRole:session.role];
    configuration.sceneClass = NSClassFromString(entry[@"UISceneClassName"] ?: @"UIWindowScene");
    configuration.delegateClass = NSClassFromString(entry[@"UISceneDelegateClassName"] ?: @"YTSceneDelegate");
    return configuration;
}

static void YCPSetDelegate(UIApplication *application, SEL selector, id delegate) {
    if (delegate) {
        Class cls = object_getClass(delegate);
        SEL route = @selector(application:configurationForConnectingSceneSession:options:);
        Method method = class_getInstanceMethod(cls, route);
        IMP current = method ? method_getImplementation(method) : NULL;
        if (current != (IMP)YCPSceneConfiguration) {
            if (current) objc_setAssociatedObject(cls, YCPConfigurationIMPKey, [NSValue valueWithPointer:current], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            const char *types = method ? method_getTypeEncoding(method) : "@@:@@@";
            if (!class_addMethod(cls, route, (IMP)YCPSceneConfiguration, types))
                class_replaceMethod(cls, route, (IMP)YCPSceneConfiguration, types);
            YCPLog(@"Installed scene routing on %@", NSStringFromClass(cls));
        }
    }
    ((void (*)(id, SEL, id))YCPOriginalSetDelegate)(application, selector, delegate);
}

static void YCPSetRoot(UIWindow *window, SEL selector, UIViewController *controller) {
    if ([YCPSurface.shared ownsNativeController:controller] && window != YCPSurface.shared.activeWindow) {
        // Google's -load can target its global phone window. The car controller
        // is already hosted in its own window; never replace the phone interface.
        YCPLog(@"Kept car controller out of Google's phone window");
        return;
    }
    ((void (*)(id, SEL, id))YCPOriginalSetRoot)(window, selector, controller);
    // YouTube constructs its root asynchronously. Observe completion rather than
    // assuming a root exists at CarPlay connection time.
    if (controller && [controller isKindOfClass:NSClassFromString(@"YTAppViewControllerImpl")]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [YCPSurface.shared reconcile]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ YCPInspectNativeRoot(controller); });
    }
}

static void YCPSetWindowScene(UIWindow *window, SEL selector, UIWindowScene *scene) {
    ((void (*)(id, SEL, id))YCPOriginalSetWindowScene)(window, selector, scene);
    if ([scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
        [YCPSurface.shared sourceWindowMovedToPhone:window];
    }
}

static void YCPViewDidLayout(UIViewController *controller, SEL selector) {
    ((void (*)(id, SEL))YCPOriginalViewDidLayout)(controller, selector);
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (!car || controller.viewIfLoaded.window != car) return;
    YCPRefreshHeaderScrollObservers();
    if (!controller.presentingViewController) return;
    // YouTube's search header uses frame-based positions and ignores extra
    // safe-area insets. Move the presented viewport, not just its safe area.
    UIView *presentedView = controller.viewIfLoaded;
    BOOL search = [NSStringFromClass(controller.class) containsString:@"Search"];
    for (UIViewController *child in controller.childViewControllers)
        if ([NSStringFromClass(child.class) containsString:@"Search"]) search = YES;
    // Playback presentations own their geometry. Applying search's viewport
    // correction to them fights the native player's layout on every update.
    if (search && !controller.parentViewController && presentedView.superview) {
        CGFloat left = car.safeAreaInsets.left + 8;
        CGRect viewport = UIEdgeInsetsInsetRect(car.bounds, UIEdgeInsetsMake(0, left, 0, MAX(8, car.safeAreaInsets.right)));
        CGRect frame = [car convertRect:viewport toView:presentedView.superview];
        CGFloat scale = YCPContentScaleForSize(viewport.size);
        CGRect bounds = CGRectMake(0, 0, frame.size.width / scale, frame.size.height / scale);
        CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
        if (!CGRectEqualToRect(presentedView.bounds, bounds) || !CGAffineTransformEqualToTransform(presentedView.transform, transform) || !CGPointEqualToPoint(presentedView.center, center)) {
            presentedView.bounds = bounds;
            presentedView.center = center;
            presentedView.transform = transform;
            [presentedView setNeedsLayout];
        }
        UIEdgeInsets extra = controller.additionalSafeAreaInsets;
        if (extra.left != 0) { extra.left = 0; controller.additionalSafeAreaInsets = extra; }
    }
    // Input activation is handled by becomeFirstResponder below; avoid walking
    // the entire playback hierarchy on every controller layout update.
}

static BOOL YCPBecomeFirstResponder(UIResponder *responder, SEL selector) {
    BOOL accepted = ((BOOL (*)(id, SEL))YCPOriginalBecomeFirstResponder)(responder, selector);
    if (accepted && [responder isKindOfClass:UIView.class]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [YCPSurface.shared textInputBecameActive:(UIView *)responder]; });
    }
    return accepted;
}

static UIView *YCPInputView(id object, SEL selector, IMP original) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (car && ((UIView *)object).window == car) {
        static UIView *empty;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ empty = [[UIView alloc] initWithFrame:CGRectZero]; });
        return empty;
    }
    return ((id (*)(id, SEL))original)(object, selector);
}
static UIView *YCPTextFieldInput(id object, SEL selector) { return YCPInputView(object, selector, YCPOriginalTextFieldInput); }
static UIView *YCPTextViewInput(id object, SEL selector) { return YCPInputView(object, selector, YCPOriginalTextViewInput); }

static IMP YCPReplace(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method_getImplementation(method);
    // Never mutate a superclass's method when the target merely inherits it.
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    return original;
}

// Add CarPlay integration attribution without replacing YouMod's own credits.
static IMP YCPOriginalSettingsItems, YCPOriginalSettingsItemsWithIcon;
static NSArray *YCPYouModCredits(NSArray *items, NSUInteger category, NSString *title) {
    if (category != 0x79746d6f || ![title isEqualToString:@"YouMod"]) return items;
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL factory = NSSelectorFromString(@"itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (![itemClass respondsToSelector:factory]) return items;
    // Some app versions forward the icon overload to the older overload.
    for (id item in items) {
        SEL identifier = NSSelectorFromString(@"accessibilityIdentifier");
        if ([item respondsToSelector:identifier] &&
            [((id (*)(id, SEL))objc_msgSend)(item, identifier) isEqual:@"ycp.creator"])
            return items;
    }
    id (*make)(id, SEL, id, id, id, id, id) = (void *)objc_msgSend;
    id credit = make(itemClass, factory, @"YouDash · Sehind Hemzani",
        @"CarPlay integration · github.com/sa4hnd", @"ycp.creator", nil,
        ^BOOL(id cell, NSUInteger index) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/sa4hnd"]
                options:@{} completionHandler:nil];
            return YES;
        });
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *reported = info[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *actual = info[@"YCPActualYouTubeVersion"] ?: reported;
    NSString *detail = [actual isEqualToString:reported] ? @"Native YouTube app version"
        : [NSString stringWithFormat:@"Reports %@ for playback compatibility", reported];
    id version = make(itemClass, factory, [@"YouTube " stringByAppendingString:actual],
        detail, @"ycp.youtube-version", nil, ^BOOL(id cell, NSUInteger index) { return NO; });
    if (!credit || !version) return items;
    NSMutableArray *result = [NSMutableArray arrayWithObjects:credit, version, nil];
    [result addObjectsFromArray:items ?: @[]];
    return result;
}
static void YCPSettingsItems(id controller, SEL selector, NSArray *items, NSUInteger category,
                             NSString *title, NSString *description, BOOL hidden) {
    ((void (*)(id, SEL, id, NSUInteger, id, id, BOOL))YCPOriginalSettingsItems)
        (controller, selector, YCPYouModCredits(items, category, title), category, title, description, hidden);
}
static void YCPSettingsItemsWithIcon(id controller, SEL selector, NSArray *items, NSUInteger category,
                                     NSString *title, id icon, NSString *description, BOOL hidden) {
    ((void (*)(id, SEL, id, NSUInteger, id, id, id, BOOL))YCPOriginalSettingsItemsWithIcon)
        (controller, selector, YCPYouModCredits(items, category, title), category, title, icon, description, hidden);
}
static void YCPInstallSettingsCredits(void) {
    Class settings = NSClassFromString(@"YTSettingsViewController");
    SEL plain = NSSelectorFromString(@"setSectionItems:forCategory:title:titleDescription:headerHidden:");
    SEL icon = NSSelectorFromString(@"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:");
    if (settings && class_getInstanceMethod(settings, plain))
        YCPOriginalSettingsItems = YCPReplace(settings, plain, (IMP)YCPSettingsItems);
    if (settings && class_getInstanceMethod(settings, icon))
        YCPOriginalSettingsItemsWithIcon = YCPReplace(settings, icon, (IMP)YCPSettingsItemsWithIcon);
}

// The feed's actual grid controls; trait changes alone leave phone responses
// at one column. Keep each ABI from YouTube 21.42.4's property declarations.
static IMP YCPOriginalFeedColumns, YCPOriginalGridOverride, YCPOriginalGridPrepare;
static IMP YCPOriginalSectionColumns, YCPOriginalLayoutColumns, YCPOriginalLayoutEnabled;
static BOOL YCPBrowseGrid(id object) {
    return YCPShouldOverrideBrowseGrid(object, YCPSurface.shared.activeWindow);
}
static NSUInteger YCPCarColumnCount(void) {
    CGFloat width = YCPSurface.shared.contentBounds.size.width;
    return width >= 780 ? 3 : width >= 500 ? 2 : 1;
}
static double YCPFeedColumns(id object, SEL selector) {
    if (YCPBrowseGrid(object)) return (double)YCPCarColumnCount();
    return ((double (*)(id, SEL))YCPOriginalFeedColumns)(object, selector);
}
static NSUInteger YCPGridOverride(id object, SEL selector) {
    if (YCPBrowseGrid(object)) return YCPCarColumnCount();
    return ((NSUInteger (*)(id, SEL))YCPOriginalGridOverride)(object, selector);
}
static NSUInteger YCPSectionColumns(id object, SEL selector) {
    if (YCPBrowseGrid(object)) return YCPCarColumnCount();
    return ((NSUInteger (*)(id, SEL))YCPOriginalSectionColumns)(object, selector);
}
static NSUInteger YCPLayoutColumns(UICollectionViewLayout *layout, SEL selector) {
    if (YCPBrowseGrid(layout) && layout.collectionView.window == YCPSurface.shared.activeWindow) return YCPCarColumnCount();
    return ((NSUInteger (*)(id, SEL))YCPOriginalLayoutColumns)(layout, selector);
}
static BOOL YCPLayoutEnabled(UICollectionViewLayout *layout, SEL selector) {
    if (YCPBrowseGrid(layout) && layout.collectionView.window == YCPSurface.shared.activeWindow) return YES;
    return ((BOOL (*)(id, SEL))YCPOriginalLayoutEnabled)(layout, selector);
}
static void YCPGridPrepare(UICollectionViewLayout *layout, SEL selector) {
    if (YCPBrowseGrid(layout) && layout.collectionView.window == YCPSurface.shared.activeWindow) {
        SEL enabled = NSSelectorFromString(@"setEnableGridLayout:");
        SEL columns = NSSelectorFromString(@"setNumberOfColumns:");
        if ([layout respondsToSelector:enabled]) ((void (*)(id, SEL, BOOL))objc_msgSend)(layout, enabled, YES);
        if ([layout respondsToSelector:columns]) ((void (*)(id, SEL, NSUInteger))objc_msgSend)(layout, columns, YCPCarColumnCount());
    }
    ((void (*)(id, SEL))YCPOriginalGridPrepare)(layout, selector);
}
static void YCPInstallFeedGrid(void) {
    YCPInstallWatchLayoutHooks();
    YCPInstallHeaderLayoutHooks();
    Class feed = NSClassFromString(@"YTFeedSectionController");
    Class section = NSClassFromString(@"YTSectionController");
    Class layout = NSClassFromString(@"YTGridCollectionViewFlowLayout");
    SEL count = NSSelectorFromString(@"numberOfColumns");
    SEL override = NSSelectorFromString(@"numberOfColumnsOverrideForGrid");
    if (feed && class_getInstanceMethod(feed, count)) YCPOriginalFeedColumns = YCPReplace(feed, count, (IMP)YCPFeedColumns);
    if (section && class_getInstanceMethod(section, count)) YCPOriginalSectionColumns = YCPReplace(section, count, (IMP)YCPSectionColumns);
    if (layout && class_getInstanceMethod(layout, count)) YCPOriginalLayoutColumns = YCPReplace(layout, count, (IMP)YCPLayoutColumns);
    SEL enabled = NSSelectorFromString(@"enableGridLayout");
    if (layout && class_getInstanceMethod(layout, enabled)) YCPOriginalLayoutEnabled = YCPReplace(layout, enabled, (IMP)YCPLayoutEnabled);
    if (section && class_getInstanceMethod(section, override)) YCPOriginalGridOverride = YCPReplace(section, override, (IMP)YCPGridOverride);
    if (layout && class_getInstanceMethod(layout, @selector(prepareLayout))) YCPOriginalGridPrepare = YCPReplace(layout, @selector(prepareLayout), (IMP)YCPGridPrepare);
}

@interface YCPBootstrap : NSObject @end
@implementation YCPBootstrap
+ (void)load {
    // Use YouMod's supported iPad mode before Google's first feed request. A
    // trait override after startup cannot replace a phone-rendered response.
    [NSUserDefaults.standardUserDefaults setInteger:1 forKey:@"YouModDeviceUIIndex"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:@"YCPCarNativePlaybackMigration1"]) {
        // This option retries error 14 indefinitely; it does not repair the
        // failing TV-spoofed request. Restore native playback without the loop.
        [defaults setBool:NO forKey:@"YouModFixPlaybackIssues"];
        [defaults setBool:YES forKey:@"YCPCarNativePlaybackMigration1"];
    }
    YCPOriginalViewDidLayout = YCPReplace(UIViewController.class, @selector(viewDidLayoutSubviews), (IMP)YCPViewDidLayout);
    YCPOriginalSetDelegate = YCPReplace(UIApplication.class, @selector(setDelegate:), (IMP)YCPSetDelegate);
    YCPOriginalSetRoot = YCPReplace(UIWindow.class, @selector(setRootViewController:), (IMP)YCPSetRoot);
    YCPOriginalSetWindowScene = YCPReplace(UIWindow.class, @selector(setWindowScene:), (IMP)YCPSetWindowScene);
    YCPOriginalBecomeFirstResponder = YCPReplace(UIResponder.class, @selector(becomeFirstResponder), (IMP)YCPBecomeFirstResponder);
    YCPOriginalTextFieldInput = YCPReplace(UITextField.class, @selector(inputView), (IMP)YCPTextFieldInput);
    YCPOriginalTextViewInput = YCPReplace(UITextView.class, @selector(inputView), (IMP)YCPTextViewInput);
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        YCPInstallFeedGrid();
        YCPInstallSettingsCredits();
        Class overlay = NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController");
        SEL errorSelector = NSSelectorFromString(@"handleError:");
        if (overlay && class_getInstanceMethod(overlay, errorSelector) && !YCPOriginalPlaybackError)
            YCPOriginalPlaybackError = YCPReplace(overlay, errorSelector, (IMP)YCPPlaybackError);
        YCPLog(@"Native integration loaded; YouTube=%@ OS=%@", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], UIDevice.currentDevice.systemVersion);
        [YCPSurface.shared reconcile];
    }];
    for (NSNotificationName name in @[UITextFieldTextDidBeginEditingNotification, UITextViewTextDidBeginEditingNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIView.class]) [YCPSurface.shared textInputBecameActive:note.object];
        }];
    }
}
@end
