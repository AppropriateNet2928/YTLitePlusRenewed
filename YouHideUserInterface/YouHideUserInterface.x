#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTReelWatchPlaybackOverlayView.h>
#import <YTScript/YTScriptRuntime.h>

// This right here is YTScript logic, and YES I am not joking, this will be actual code upon compilation
YT_PAGE(@"YouHideUserInterface");
YT_TOGGLE(@"YouHideUserInterface", @"This is a feature for hiding the User Interface in both Shorts and Video Overlay. App restart is required", YES);
YT_SLIDER(@"Visibility", 1, 10, 1, @"This is a slider to set the eye to be less or more visible in both Shorts and Video Overlay. App restart is required");

YT_ON(YouHideUserInterface)

@interface YTReelPlayerViewController : UIViewController
@end

static BOOL gHideUserInterface = NO;
static char eyeButtonKey;
static char managedHiddenKey;
static char previousInteractionKey;

static NSString * const YouHideUINotificationName = @"YouHideUserInterfaceToggleNotification";
static NSInteger const YouHideUIEyeButtonTag = 99999;

@interface UIView (YouHideUserInterface)
@property (nonatomic, strong) UIButton *youHideUI_eyeButton;
- (UIButton *)youHideUI_getOrCreateEyeButtonWithTarget:(id)target action:(SEL)action;
@end

@implementation UIView (YouHideUserInterface)
- (UIButton *)youHideUI_eyeButton {
    return objc_getAssociatedObject(self, &eyeButtonKey);
}
- (void)setYouHideUI_eyeButton:(UIButton *)button {
    objc_setAssociatedObject(self, &eyeButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (UIButton *)youHideUI_getOrCreateEyeButtonWithTarget:(id)target action:(SEL)action {
    UIButton *btn = [self viewWithTag:YouHideUIEyeButtonTag];
    if (!btn) {
        btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = YouHideUIEyeButtonTag;
        btn.tintColor = [UIColor whiteColor];
        btn.accessibilityIdentifier = @"YouHideUserInterface.eyeButton";
        btn.accessibilityLabel = @"Hide interface";
        btn.adjustsImageWhenHighlighted = YES;

        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 1);
        btn.layer.shadowOpacity = 0.75;
        btn.layer.shadowRadius = 2.5;
        btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        self.youHideUI_eyeButton = btn;
    }
    return btn;
}
@end

static CGFloat YouHideUI_GetEyeButtonOpacity() {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"Visibility"];
    float opacity = val ? [val floatValue] : 1.0; // 1-10, default is 1 (0.1 opacity)
    return opacity / 10.0;
}

static void YouHideUIUpdateEyeButton(UIButton *button) {
    if (!button) return;

    UIImage *image = nil;
    if (@available(iOS 13.0, *)) {
        image = [UIImage systemImageNamed:gHideUserInterface ? @"eye.slash" : @"eye"];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightBold];
        image = [image imageWithConfiguration:config];
    }
    [button setImage:image forState:UIControlStateNormal];
    button.hidden = NO;
    button.alpha = YouHideUI_GetEyeButtonOpacity();
    button.userInteractionEnabled = YES;
    [button.superview bringSubviewToFront:button];
}

static BOOL YouHideUIIsEyeButton(UIView *view) {
    return view.tag == YouHideUIEyeButtonTag;
}

static void YouHideUISetManagedHidden(UIView *view, BOOL hidden) {
    if (!view || YouHideUIIsEyeButton(view)) return;

    NSNumber *managed = objc_getAssociatedObject(view, &managedHiddenKey);
    if (hidden) {
        if (!view.hidden && !managed.boolValue) {
            objc_setAssociatedObject(view, &managedHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &previousInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.hidden = YES;
            view.userInteractionEnabled = NO;
        }
    } else if (managed.boolValue) {
        NSNumber *previousInteraction = objc_getAssociatedObject(view, &previousInteractionKey);
        view.hidden = NO;
        view.userInteractionEnabled = previousInteraction ? previousInteraction.boolValue : YES;
        objc_setAssociatedObject(view, &managedHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &previousInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL YouHideUIIsStructuralView(UIView *view) {
    NSString *className = NSStringFromClass([view class]);
    NSArray *structuralNames = @[
        @"PlayerView",
        @"ContentView",
        @"Video",
        @"OverlayView",
        @"ControlsOverlayView",
        @"CollectionView",
        @"ScrollView",
        @"Gesture",
        @"Transition",
        @"Container",
        @"Cell"
    ];
    for (NSString *name in structuralNames) {
        if ([className containsString:name]) return YES;
    }

    return [view isKindOfClass:[UICollectionView class]] ||
           [view isKindOfClass:[UITableView class]] ||
           [view isKindOfClass:[UIScrollView class]];
}

static BOOL YouHideUIShouldHideControl(UIView *view) {
    if (!view || YouHideUIIsEyeButton(view) || YouHideUIIsStructuralView(view)) return NO;

    NSString *className = NSStringFromClass([view class]);
    NSArray *controlNames = @[
        @"Button",
        @"Action",
        @"Menu",
        @"Overflow",
        @"Scrubber",
        @"PlayerBar",
        @"FullscreenActions",
        @"Engagement",
        @"Chip",
        @"Search",
        @"Like",
        @"Dislike",
        @"Share",
        @"Comment"
    ];
    for (NSString *name in controlNames) {
        if ([className containsString:name]) return YES;
    }

    return [view isKindOfClass:[UIButton class]];
}

static void YouHideUIApplyControlHiding(UIView *root, BOOL hidden) {
    if (!root) return;

    for (UIView *subview in root.subviews) {
        if (YouHideUIIsEyeButton(subview)) {
            subview.hidden = NO;
            subview.alpha = YouHideUI_GetEyeButtonOpacity();
            subview.userInteractionEnabled = YES;
            continue;
        }

        BOOL shouldHide = YouHideUIShouldHideControl(subview);
        YouHideUISetManagedHidden(subview, hidden && shouldHide);
        if (!shouldHide || !hidden) {
            YouHideUIApplyControlHiding(subview, hidden);
        }
    }
}

// Finds the correct anchor, working flawlessly even when the interface is hidden
static UIView *FindTopRightAnchor(UIView *overlay) {
    UIView *anchor = nil;
    for (UIView *subview in overlay.subviews) {
        if (YouHideUIIsEyeButton(subview)) continue;
        
        NSNumber *managed = objc_getAssociatedObject(subview, &managedHiddenKey);
        BOOL hiddenByUs = managed ? managed.boolValue : NO;
        
        // If it is hidden natively by YT (not by us), or has alpha < 0.1, skip it
        if ((subview.hidden && !hiddenByUs) || subview.alpha < 0.1) continue;
        
        CGRect frame = subview.frame;
        if (frame.origin.x > overlay.bounds.size.width * 0.7 && 
            frame.origin.y > 10 && 
            frame.origin.y < 200 && 
            frame.size.width > 20 && 
            frame.size.height > 20) {
            if (!anchor || frame.origin.y > anchor.frame.origin.y) {
                anchor = subview;
            }
        }
    }
    return anchor;
}

static UIView *YouHideUIFirstUsableButton(NSArray *buttons) {
    UIView *candidate = nil;
    for (UIView *button in buttons) {
        if (![button isKindOfClass:[UIView class]] || YouHideUIIsEyeButton(button)) continue;
        CGRect frame = button.frame;
        if (CGRectIsEmpty(frame) || frame.size.width < 20 || frame.size.height < 20) continue;
        if (!candidate || frame.origin.y < candidate.frame.origin.y) {
            candidate = button;
        }
    }
    return candidate;
}

static void YouHideUIPositionEyeButton(UIButton *button, UIView *overlay, UIView *anchor, CGFloat fallbackY) {
    CGFloat size = 44.0;
    CGFloat rightPadding = 12.0;
    if (@available(iOS 11.0, *)) {
        rightPadding += overlay.safeAreaInsets.right;
    }

    CGFloat x = overlay.bounds.size.width - rightPadding - size;
    CGFloat y = fallbackY;
    if (anchor) {
        CGRect convertedFrame = [anchor.superview convertRect:anchor.frame toView:overlay];
        x = CGRectGetMidX(convertedFrame) - (size / 2.0);
        y = CGRectGetMaxY(convertedFrame) + 10.0;
    }

    // Find existing top-right button to anchor under
    CGFloat maxY = MAX(0, overlay.bounds.size.height - size - 18.0);
    button.frame = CGRectMake(MAX(8.0, x), MIN(MAX(24.0, y), maxY), size, size);
    YouHideUIUpdateEyeButton(button);
}

static void YouHideUIPostToggleNotification(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:YouHideUINotificationName
                                                        object:nil
                                                      userInfo:@{@"hidden": @(gHideUserInterface)}];
}

// Hooks for the YouTube Shorts overlay screen
%hook YTReelWatchPlaybackOverlayView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:YouHideUINotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(youHideUI_handleNotification:) 
                                                     name:YouHideUINotificationName
                                                   object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%new
- (void)youHideUI_handleNotification:(NSNotification *)notification {
    BOOL isHidden = [notification.userInfo[@"hidden"] boolValue];
    gHideUserInterface = isHidden;
    
    YouHideUIUpdateEyeButton((UIButton *)[self viewWithTag:YouHideUIEyeButtonTag]);
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    %orig;
    
    UIButton *btn = [self youHideUI_getOrCreateEyeButtonWithTarget:self action:@selector(youHideUI_toggleUI)];
    
    UIView *anchor = FindTopRightAnchor(self);
    YouHideUIPositionEyeButton(btn, self, anchor, 210.0);

    // Smart filtering: Hide visual elements, but protect gesture/structural layers
    for (UIView *subview in self.subviews) {
        if (YouHideUIIsEyeButton(subview)) {
            subview.hidden = NO;
            subview.alpha = YouHideUI_GetEyeButtonOpacity();
            subview.userInteractionEnabled = YES;
            continue;
        }
        
        if (YouHideUIIsStructuralView(subview)) {
            // If the element is structural (e.g., swipe layers), do not hide it directly,
            // but clean up sub-buttons inside it if they exist.
            YouHideUIApplyControlHiding(subview, gHideUserInterface);
        } else {
            // If it's a pure UI element (button containers, text labels), hide it completely.
            YouHideUISetManagedHidden(subview, gHideUserInterface);
        }
    }
}

%new
- (void)youHideUI_toggleUI {
    gHideUserInterface = !gHideUserInterface;
    YouHideUIPostToggleNotification();
}

%end

// Shorts Controller (Reset state when leaving the screen)
%hook YTReelPlayerViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(youHideUI_handleNotification:) 
                                                 name:YouHideUINotificationName
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%new
- (void)youHideUI_handleNotification:(NSNotification *)notification {
    BOOL isHidden = [notification.userInfo[@"hidden"] boolValue];
    gHideUserInterface = isHidden;
    
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)viewDidLayoutSubviews {
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gHideUserInterface) {
        gHideUserInterface = NO;
        YouHideUIPostToggleNotification();
    }
}

%end

// Hooks for the Standard Video Player (Normal YouTube Video)
%hook YTMainAppVideoPlayerOverlayView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:YouHideUINotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(youHideUI_handleNotification:) 
                                                     name:YouHideUINotificationName
                                                   object:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%new
- (void)youHideUI_handleNotification:(NSNotification *)notification {
    BOOL isHidden = [notification.userInfo[@"hidden"] boolValue];
    gHideUserInterface = isHidden;
    
    YouHideUIUpdateEyeButton((UIButton *)[self viewWithTag:YouHideUIEyeButtonTag]);
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    %orig;
    
    UIButton *btn = [self youHideUI_getOrCreateEyeButtonWithTarget:self action:@selector(youHideUI_toggleUI)];

    UIView *anchor = FindTopRightAnchor(self);
    YouHideUIPositionEyeButton(btn, self, anchor, 70.0);

    UIView *controls = nil;
    if ([self respondsToSelector:@selector(controlsOverlayView)]) {
        controls = [(id)self controlsOverlayView];
    }
    YouHideUIApplyControlHiding(controls ?: (UIView *)self, gHideUserInterface);
}

%new
- (void)youHideUI_toggleUI {
    gHideUserInterface = !gHideUserInterface;
    YouHideUIPostToggleNotification();
}

%end

// Standard Video Controller (Reset state when leaving the video)
%hook YTPlayerViewController

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gHideUserInterface) {
        gHideUserInterface = NO;
        YouHideUIPostToggleNotification();
    }
}

%end

YT_END
