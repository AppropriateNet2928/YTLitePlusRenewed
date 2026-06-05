// YouCast.x - Implementation of YouCast tweak
#import "YouCast.h"
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char youCastButtonKey;
static char youCastNativeButtonKey;

@interface YouCastCloseTarget : NSObject
@property (nonatomic, weak) UIViewController *vc;
- (void)close;
@end

@implementation YouCastCloseTarget
- (void)close {
    [self.vc dismissViewControllerAnimated:YES completion:nil];
}
@end

static UIWindow *YouCastActiveWindow() {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }

    NSArray *windows = [[UIApplication sharedApplication] valueForKey:@"windows"];
    for (UIWindow *window in windows) {
        if (window.isKeyWindow) {
            return window;
        }
    }

    return windows.firstObject;
}

static UIViewController *getTopViewController() {
    UIViewController *root = YouCastActiveWindow().rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    if ([root isKindOfClass:[UINavigationController class]]) {
        root = ((UINavigationController *)root).visibleViewController;
    } else if ([root isKindOfClass:[UITabBarController class]]) {
        root = ((UITabBarController *)root).selectedViewController;
    }
    return root;
}

static UIImage *getCastIconImage() {
    Class iconClass = objc_getClass("YTIIcon");
    if (iconClass) {
        id icon = [[iconClass alloc] init];
        if ([icon respondsToSelector:@selector(setIconType:)]) {
            [icon setValue:@(886) forKey:@"iconType"]; // 886 is cast outline
        }
        if ([icon respondsToSelector:@selector(iconImageWithColor:)]) {
            UIImage *image = [icon performSelector:@selector(iconImageWithColor:) withObject:[UIColor whiteColor]];
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }
    // Fallback icon
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"tv.and.mediabox"];
    }
    return nil;
}

static UIImage *YouCastSnapshotImageForView(UIView *view) {
    if (!view || CGRectIsEmpty(view.bounds)) return nil;

    BOOL wasHidden = view.hidden;
    CGFloat oldAlpha = view.alpha;
    view.hidden = NO;
    view.alpha = MAX(oldAlpha, 1.0);
    [view layoutIfNeeded];

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        if (![view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO]) {
            [view.layer renderInContext:context.CGContext];
        }
    }];

    view.hidden = wasHidden;
    view.alpha = oldAlpha;
    return image;
}

static BOOL YouCastTriggerControlInView(UIView *view) {
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return YES;
    }

    for (UIView *subview in view.subviews) {
        if (YouCastTriggerControlInView(subview)) {
            return YES;
        }
    }

    return NO;
}

static void YouCastTriggerNativeRouteButton(UIButton *customButton) {
    UIView *nativeButton = objc_getAssociatedObject(customButton, &youCastNativeButtonKey);
    if (!nativeButton) return;

    BOOL wasHidden = nativeButton.hidden;
    nativeButton.hidden = NO;
    [nativeButton layoutIfNeeded];
    YouCastTriggerControlInView(nativeButton);
    nativeButton.hidden = wasHidden;
}

static void YouCastPresentPicker(id sender) {
    UIViewController *topVC = getTopViewController();
    if (!topVC) return;

    BOOL isActiveSession = NO;
    Class sessionManagerClass = objc_getClass("MDXSessionManager");
    if (sessionManagerClass) {
        id manager = [sessionManagerClass sharedInstance];
        if ([manager respondsToSelector:@selector(hasActiveMDXOrAirPlaySession)]) {
            isActiveSession = [manager hasActiveMDXOrAirPlaySession];
        }
    }

    NSString *title = isActiveSession ? NSLocalizedString(@"Select different device", nil) : NSLocalizedString(@"Select a device", nil);
    
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:title
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    if (isActiveSession) {
        UIAlertAction *disconnectAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"This device", nil)
                                                                   style:UIAlertActionStyleDestructive
                                                                 handler:^(UIAlertAction *action) {
            Class mdxSessionClass = objc_getClass("MDXSessionManager");
            if (mdxSessionClass) {
                id manager = [mdxSessionClass sharedInstance];
                if ([manager respondsToSelector:@selector(disconnectFromScreen)]) {
                    [manager performSelector:@selector(disconnectFromScreen)];
                }
            }
        }];
        [actionSheet addAction:disconnectAction];
    }

    UIAlertAction *airplayAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"AirPlay & Bluetooth devices", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AVRoutePickerView *picker = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
            picker.hidden = YES;

            UIWindow *window = [sender isKindOfClass:[UIView class]] ? ((UIView *)sender).window : nil;
            if (!window) {
                window = YouCastActiveWindow();
            }
            [window addSubview:picker];
            [picker layoutIfNeeded];

            for (UIView *subview in picker.subviews) {
                if ([subview isKindOfClass:[UIButton class]]) {
                    [(UIButton *)subview sendActionsForControlEvents:UIControlEventTouchUpInside];
                    break;
                }
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [picker removeFromSuperview];
            });
        });
    }];
    [actionSheet addAction:airplayAction];

    UIAlertAction *tvCodeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Link with TV code", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *tvCodeVC = nil;
            Class tvCodeVCClass = objc_getClass("MDXSmartPairingTVCodeViewController");
            if (tvCodeVCClass) {
                tvCodeVC = [[tvCodeVCClass alloc] init];
            }
            if (!tvCodeVC) {
                Class mainVCClass = objc_getClass("MDXSmartPairingMainViewController");
                if (mainVCClass) {
                    tvCodeVC = [[mainVCClass alloc] init];
                }
            }

            if (tvCodeVC) {
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:tvCodeVC];
                YouCastCloseTarget *target = [[YouCastCloseTarget alloc] init];
                target.vc = nav;
                objc_setAssociatedObject(nav, "youCastCloseTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:target
                                                                                          action:@selector(close)];
                tvCodeVC.navigationItem.leftBarButtonItem = closeBtn;
                [topVC presentViewController:nav animated:YES completion:nil];
            }
        });
    }];
    [actionSheet addAction:tvCodeAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [actionSheet addAction:cancelAction];

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad && [sender isKindOfClass:[UIView class]]) {
        actionSheet.popoverPresentationController.sourceView = sender;
        actionSheet.popoverPresentationController.sourceRect = ((UIView *)sender).bounds;
    }

    [topVC presentViewController:actionSheet animated:YES completion:nil];
}

// ============================================================
// Group: Cast button overlay
// ============================================================
%group YouCastOverlay

%hook YTMainAppVideoPlayerOverlayView

- (void)layoutSubviews {
    %orig;

    UIView *nativeBtn = self.playbackRouteButton;
    if (!nativeBtn) return;

    // --- 1. Don't show in miniplayer (small player views) ---
    BOOL isMiniplayer = CGRectGetWidth(self.bounds) < 300.0 || CGRectGetHeight(self.bounds) < 180.0;
    UIButton *customBtn = objc_getAssociatedObject(self, &youCastButtonKey);

    if (isMiniplayer) {
        if (customBtn) customBtn.hidden = YES;
        return;
    }

    // --- 2. Create the custom button if it doesn't exist yet ---
    if (!customBtn) {
        customBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [customBtn addTarget:self action:@selector(didPressYouCast:) forControlEvents:UIControlEventTouchUpInside];
        customBtn.adjustsImageWhenHighlighted = NO;
        customBtn.adjustsImageWhenDisabled = NO;
        customBtn.backgroundColor = UIColor.clearColor;
        customBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;

        UIImage *icon = getCastIconImage();
        [customBtn setImage:icon forState:UIControlStateNormal];
        customBtn.tintColor = [UIColor whiteColor];
        customBtn.imageEdgeInsets = UIEdgeInsetsMake(1.0, 1.0, 1.0, 1.0);

        objc_setAssociatedObject(self, &youCastButtonKey, customBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(customBtn, &youCastNativeButtonKey, nativeBtn, OBJC_ASSOCIATION_ASSIGN);

    // --- 3. Add to native button's parent so it auto-hides with controls ---
    UIView *controlsContainer = nativeBtn.superview ?: self;
    if (customBtn.superview != controlsContainer) {
        [customBtn removeFromSuperview];
        [controlsContainer addSubview:customBtn];
    }

// --- 4. Position exactly over the native cast button ---
CGRect nativeFrame = nativeBtn.frame;

if (CGRectGetWidth(nativeFrame) > 0.0 &&
    CGRectGetHeight(nativeFrame) > 0.0) {

    customBtn.frame = nativeFrame;
}

nativeBtn.hidden = NO;
    nativeBtn.alpha = 1.0;
    [controlsContainer bringSubviewToFront:nativeBtn];
    
    // --- 5. Crucial part for custom button to properly show up ---
    customBtn.hidden = NO;
    customBtn.alpha = 1.0;
    [controlsContainer bringSubviewToFront:customBtn];
}

%new
- (void)didPressYouCast:(id)sender {
    if ([sender isKindOfClass:[UIButton class]]) {
        YouCastTriggerNativeRouteButton((UIButton *)sender);
    } else {
        YouCastPresentPicker(sender);
    }
}

%end

%hook YTMainAppControlsOverlayView

%new
- (void)didPressYouCast:(id)sender {
    YouCastPresentPicker(sender);
}

%end

%hook YTInlinePlayerBarContainerView

%new
- (void)didPressYouCast:(id)sender {
    YouCastPresentPicker(sender);
}

%end

%end // YouCastOverlay

%ctor {
    %init(YouCastOverlay);
    NSLog(@"[YouCast] Always enabled and initialized at startup.");
}
