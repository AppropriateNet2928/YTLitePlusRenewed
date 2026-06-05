// YouCast.h - Header for YouCast tweak
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTMainAppVideoPlayerOverlayView : UIView
@property (nonatomic, strong) UIView *playbackRouteButton;
@end

@interface YTPlayerViewController : UIViewController
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@property (nonatomic, assign) YTPlayerViewController *parentViewController;
@end

@interface MDXSessionManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)hasActiveMDXOrAirPlaySession;
- (void)disconnectFromScreen;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title
                    titleDescription:(NSString *)description
             accessibilityIdentifier:(NSString *)identifier
                            switchOn:(BOOL)on
                         switchBlock:(BOOL (^)(id cell, BOOL enabled))block
                       settingItemId:(NSInteger)itemId;
@end

@interface YTSettingsCell : UITableViewCell
- (void)setSwitchOn:(BOOL)on animated:(BOOL)animated;
@end

@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle
              pickerSectionTitle:(id)title
                            rows:(NSArray *)rows
               selectedItemIndex:(NSInteger)index
                 parentResponder:(id)responder;
@end
