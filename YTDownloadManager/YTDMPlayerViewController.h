#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "YTDMDownloadsManager.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const YTDMPlaybackStateChangedNotification;

@interface YTDMPlaybackSession : NSObject

+ (instancetype)sharedSession;

@property (nonatomic, strong, readonly) AVPlayer *player;
@property (nonatomic, strong, nullable, readonly) YTDMDownloadItem *currentItem;
@property (nonatomic, copy, readonly) NSArray<YTDMDownloadItem *> *playlist;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, assign) float playbackRate;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL repeatEnabled;

- (void)playItem:(YTDMDownloadItem *)item inPlaylist:(NSArray<YTDMDownloadItem *> *)playlist index:(NSInteger)index;
- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)seekTo:(NSTimeInterval)time;
- (void)skipSeconds:(NSTimeInterval)seconds;
- (void)playNext;
- (void)playPrevious;
- (void)stop;

// Replaces the playlist while preserving the currently playing item.
// Used by the playback queue when the user reorders upcoming videos, so
// playNext / playPrevious advance through the new order.
- (void)setPlaylist:(NSArray<YTDMDownloadItem *> *)playlist;

@end

@interface YTDMPlayerViewController : UIViewController

@property (nonatomic, copy, nullable) void (^onDismiss)(void);

- (instancetype)initWithItem:(YTDMDownloadItem *)item inPlaylist:(NSArray<YTDMDownloadItem *> *)playlist index:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
