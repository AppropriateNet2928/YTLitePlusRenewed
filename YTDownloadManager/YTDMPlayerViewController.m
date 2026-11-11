#import "YTDMPlayerViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>
#import <objc/runtime.h>

NSNotificationName const YTDMPlaybackStateChangedNotification = @"YTDMPlaybackStateChangedNotification";

// Borderless button with an enlarged, invisible hit area so flat icons stay
// easy to tap without drawing any plate behind them.
@interface YTDMFlatButton : UIButton
@property (nonatomic, assign) CGFloat hitSlop;
@end

@implementation YTDMFlatButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hitSlop <= 0) return [super pointInside:point withEvent:event];
    return CGRectContainsPoint(CGRectInset(self.bounds, -self.hitSlop, -self.hitSlop), point);
}
@end


// ============================================================================
// HOSTING HELPERS
//
// Same logic the project already used successfully for presentation:
//
//   [self ytdm_parentViewController] ?: getTopMostController()
//
// ytdm_parentViewController walks the responder chain to the nearest real
// UIViewController; the top-most lookup walks presentedViewController forward
// from the active key window. Kept local to this file so Tweak.xm stays
// untouched.
// ============================================================================

static UIWindow *YTDMGetKeyWindow(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    return keyWindow;
}

static UIViewController *YTDMGetTopMostController(void) {
    UIWindow *window = YTDMGetKeyWindow();
    if (!window) return nil;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    return root;
}

static UIViewController *YTDMParentViewController(id object) {
    UIResponder *responder = object;
    while ([responder nextResponder]) {
        responder = [responder nextResponder];
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

@interface YTDMPlaybackSession ()
@property (nonatomic, strong, readwrite) AVPlayer *player;
@property (nonatomic, strong, nullable, readwrite) YTDMDownloadItem *currentItem;
@property (nonatomic, copy, readwrite) NSArray<YTDMDownloadItem *> *playlist;
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
@property (nonatomic, strong) id timeObserver;
@end

@implementation YTDMPlaybackSession

+ (instancetype)sharedSession {
    static YTDMPlaybackSession *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [YTDMPlaybackSession new]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _player = [AVPlayer new];
        _playbackRate = 1.0f;
        _playlist = @[];
        _currentIndex = NSNotFound;
        [self setupAudioSession];
        [self setupRemoteCommands];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    }
    return self;
}

- (void)setupAudioSession {
    AVAudioSession *audio = [AVAudioSession sharedInstance];
    [audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:NULL];
    [audio setActive:YES error:NULL];
    if (@available(iOS 15.0, *)) {
        self.player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
    }
    self.player.allowsExternalPlayback = YES;
}

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    [rcc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self play]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self pause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self togglePlayPause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self playNext]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self playPrevious]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rcc.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        MPChangePlaybackPositionCommandEvent *posEvent = (MPChangePlaybackPositionCommandEvent *)e;
        [self seekTo:posEvent.positionTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)updateNowPlayingInfo {
    if (!self.currentItem) {
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.currentItem.title;
    info[MPMediaItemPropertyPlaybackDuration] = @(self.currentItem.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(self.player.currentTime));
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying ? self.playbackRate : 0.0);

    UIImage *thumb = [self.currentItem thumbnailImage];
    if (thumb) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:thumb.size requestHandler:^UIImage *(CGSize size) {
            return thumb;
        }];
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)playItem:(YTDMDownloadItem *)item inPlaylist:(NSArray<YTDMDownloadItem *> *)playlist index:(NSInteger)index {
    if (!item) return;
    self.playlist = playlist ?: @[item];
    self.currentIndex = index;
    self.currentItem = item;

    AVPlayerItem *pItem = [AVPlayerItem playerItemWithURL:item.fileURL];
    [self.player replaceCurrentItemWithPlayerItem:pItem];

    NSTimeInterval resume = [[YTDMDownloadsManager sharedManager] resumePositionForURL:item.fileURL];
    if (resume > 0) {
        [self.player seekToTime:CMTimeMakeWithSeconds(resume, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    [self play];
    [self updateNowPlayingInfo];
}

- (void)play {
    [self.player play];
    self.player.rate = self.playbackRate;
    self.isPlaying = YES;
    [self updateNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMPlaybackStateChangedNotification object:nil];
}

- (void)pause {
    [self.player pause];
    self.isPlaying = NO;
    [self saveCurrentProgress];
    [self updateNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMPlaybackStateChangedNotification object:nil];
}

- (void)togglePlayPause {
    if (self.isPlaying) [self pause]; else [self play];
}

- (void)seekTo:(NSTimeInterval)time {
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self updateNowPlayingInfo];
}

- (void)skipSeconds:(NSTimeInterval)seconds {
    NSTimeInterval cur = CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval target = MAX(0, MIN(cur + seconds, self.currentItem.duration));
    [self seekTo:target];
}

- (void)playNext {
    if (self.playlist.count <= 1) return;
    NSInteger next = self.currentIndex + 1;
    if (next >= self.playlist.count) next = 0;
    [self playItem:self.playlist[next] inPlaylist:self.playlist index:next];
}

- (void)setPlaylist:(NSArray<YTDMDownloadItem *> *)playlist {
    // CRITICAL: assign the IVAR, never the property.
    // The class extension redeclares `playlist` as readwrite, so writing
    // `self.playlist` inside its own setter re-enters this method forever
    // (infinite recursion -> stack exhaustion -> SIGSEGV on first play).
    if (!playlist) {
        _playlist = @[];
        self.currentIndex = NSNotFound;
        return;
    }

    // Re-anchor currentIndex onto the same item after a reorder, otherwise
    // next/previous would advance from the wrong position.
    YTDMDownloadItem *current = self.currentItem;
    NSInteger newIndex = NSNotFound;
    if (current) {
        NSUInteger found = [playlist indexOfObject:current];
        if (found != NSNotFound) newIndex = (NSInteger)found;
    }

    _playlist = [playlist copy];

    if (newIndex != NSNotFound) {
        self.currentIndex = newIndex;
    } else {
        self.currentIndex = playlist.count > 0 ? 0 : NSNotFound;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMPlaybackStateChangedNotification object:nil];
}

- (void)playPrevious {
    if (self.playlist.count <= 1) return;
    NSTimeInterval cur = CMTimeGetSeconds(self.player.currentTime);
    if (cur > 3.0) {
        [self seekTo:0];
        return;
    }
    NSInteger prev = self.currentIndex - 1;
    if (prev < 0) prev = self.playlist.count - 1;
    [self playItem:self.playlist[prev] inPlaylist:self.playlist index:prev];
}

- (void)itemDidFinishPlaying:(NSNotification *)note {
    if (self.repeatEnabled) {
        [self seekTo:0];
        [self play];
        return;
    }
    if (self.currentIndex + 1 < self.playlist.count) {
        [self playNext];
    } else {
        [self pause];
        [self seekTo:0];
    }
}

- (void)saveCurrentProgress {
    if (!self.currentItem) return;
    NSTimeInterval cur = CMTimeGetSeconds(self.player.currentTime);
    [[YTDMDownloadsManager sharedManager] saveResumePosition:cur duration:self.currentItem.duration forURL:self.currentItem.fileURL];
}

- (void)setPlaybackRate:(float)rate {
    _playbackRate = rate;
    if (self.isPlaying) self.player.rate = rate;
    [self updateNowPlayingInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMPlaybackStateChangedNotification object:nil];
}

- (void)stop {
    [self saveCurrentProgress];
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.isPlaying = NO;
    self.currentItem = nil;
    self.playlist = @[];
    self.currentIndex = NSNotFound;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMPlaybackStateChangedNotification object:nil];
}

@end

// ============================================================================
// PLAYER SURFACE VIEW (AVPlayerLayer wrapper)
// ============================================================================

@interface YTDMPlayerSurfaceView : UIView
@property (nonatomic, strong, readonly) AVPlayerLayer *playerLayer;
@end

@implementation YTDMPlayerSurfaceView
+ (Class)layerClass { return [AVPlayerLayer class]; }
- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }
@end

// ============================================================================
// PLAYER VIEW CONTROLLER
// ============================================================================

@interface YTDMQueueViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
@property (nonatomic, copy) void (^onReorder)(NSInteger from, NSInteger to);
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, copy) NSArray<YTDMDownloadItem *> *items;
@end

@implementation YTDMQueueViewController {
    UITableView *_table;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Playback Queue";

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.allowsSelectionDuringEditing = NO;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.editing = YES;              // rows show reorder handles
    _table.tableFooterView = [UIView new];
    [self.view addSubview:_table];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(closeTapped)];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"qcell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];

    YTDMDownloadItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.title ?: @"Untitled";
    cell.textLabel.numberOfLines = 1;

    if (indexPath.row == self.currentIndex) {
        cell.textLabel.text = [@"▶ " stringByAppendingString:cell.textLabel.text];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.detailTextLabel.text = @"Now playing";
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.text = @"Up next";
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.onSelect) self.onSelect(indexPath.row);
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // The currently playing item keeps its position; upcoming items reorder.
    return indexPath.row != self.currentIndex;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.onReorder) self.onReorder(sourceIndexPath.row, destinationIndexPath.row);
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row == self.currentIndex ? UITableViewCellEditingStyleNone
                                              : UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

@end

@interface YTDMPlayerViewController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) YTDMPlaybackSession *session;
@property (nonatomic, strong) YTDMPlayerSurfaceView *surfaceView;
@property (nonatomic, strong) UIView *overlayView;

// Top controls
@property (nonatomic, strong) YTDMFlatButton *dismissButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) AVRoutePickerView *routePicker;

// Center controls
@property (nonatomic, strong) YTDMFlatButton *playPauseButton;
@property (nonatomic, strong) YTDMFlatButton *skipBackButton;
@property (nonatomic, strong) YTDMFlatButton *skipForwardButton;
@property (nonatomic, strong) YTDMFlatButton *prevButton;
@property (nonatomic, strong) YTDMFlatButton *nextButton;

// Bottom controls
@property (nonatomic, strong) UISlider *timeSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) YTDMFlatButton *settingsButton;
@property (nonatomic, strong) YTDMFlatButton *speedButton;
@property (nonatomic, strong) YTDMFlatButton *repeatButton;
@property (nonatomic, strong) YTDMFlatButton *aspectButton;



@property (nonatomic, strong) NSTimer *controlsTimer;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign) BOOL isAspectFill;
@property (nonatomic, strong) id timeObserver;

@end

// Symbol point sizes. These are the icons' optical sizes, NOT the button sizes
// — UIButton centres the image inside the button's bounds, so the symbol is
// never resampled into a plate.
static const CGFloat YTDMPlaySymbolSize = 34.0;
static const CGFloat YTDMSkipSymbolSize = 30.0;
static const CGFloat YTDMStepSymbolSize = 30.0;

@implementation YTDMPlayerViewController

- (instancetype)initWithItem:(YTDMDownloadItem *)item inPlaylist:(NSArray<YTDMDownloadItem *> *)playlist index:(NSInteger)index {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _session = [YTDMPlaybackSession sharedSession];
        // Must cover the whole screen. UIModalPresentationAutomatic resolves to
        // a page sheet on iOS 14+, which shows rounded corners and a backdrop.
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.definesPresentationContext = YES;
        [_session playItem:item inPlaylist:playlist index:index];
    }
    return self;
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self setupSurface];
    [self setupOverlay];
    [self setupGestures];
    [self setupTimeObserver];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncUI)
                                                 name:YTDMPlaybackStateChangedNotification object:nil];
    [self syncUI];
    [self resetControlsTimer];
}

- (void)setupSurface {
    self.surfaceView = [YTDMPlayerSurfaceView new];
    self.surfaceView.frame = self.view.bounds;
    self.surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.surfaceView.playerLayer.player = self.session.player;
    self.surfaceView.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view addSubview:self.surfaceView];
}

- (void)setupOverlay {
    self.overlayView = [UIView new];
    self.overlayView.frame = self.view.bounds;
    self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    [self.view addSubview:self.overlayView];

    // TOP BAR
    self.dismissButton = [YTDMFlatButton new];
    self.dismissButton.hitSlop = 12.0;
    UIImageSymbolConfiguration *topCfg =
        [UIImageSymbolConfiguration configurationWithPointSize:19
                                                         weight:UIImageSymbolWeightSemibold
                                                          scale:UIImageSymbolScaleLarge];
    [self.dismissButton setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:topCfg]
                        forState:UIControlStateNormal];
    self.dismissButton.tintColor = [UIColor whiteColor];
    [self.dismissButton addTarget:self action:@selector(buttonPressedFeedback:) forControlEvents:UIControlEventTouchDown];
    [self.dismissButton addTarget:self action:@selector(buttonReleasedFeedback:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:self.dismissButton];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    [self.overlayView addSubview:self.titleLabel];

    if (@available(iOS 11.0, *)) {
        self.routePicker = [AVRoutePickerView new];
        self.routePicker.tintColor = [UIColor whiteColor];
        [self.overlayView addSubview:self.routePicker];
    }

    // CENTER CONTROLS
    // Native SF Symbols, so the transport row matches the proportions and
    // optical weight of the rest of iOS. The image view is pinned to
    // UIViewContentModeCenter inside the button's own bounds, so the symbol is
    // never resampled. All artwork is solid white.
    self.playPauseButton  = [self makeTransportIconWithSize:YTDMPlaySymbolSize action:@selector(playPauseTapped)];
    self.skipBackButton   = [self makeSkipIconBack:@selector(skipBackTapped)];
    self.skipForwardButton= [self makeSkipIconForward:@selector(skipFwdTapped)];
    self.prevButton       = [self makeSystemButton:@"backward.end.fill" size:YTDMStepSymbolSize action:@selector(prevTapped)];
    self.nextButton       = [self makeSystemButton:@"forward.end.fill"  size:YTDMStepSymbolSize action:@selector(nextTapped)];

    // Stable per-control identities used for layout persistence keys.
    self.prevButton.tag        = 101;
    self.skipBackButton.tag    = 102;
    self.playPauseButton.tag   = 103;
    self.skipForwardButton.tag = 104;
    self.nextButton.tag        = 105;

    [self.overlayView addSubview:self.prevButton];
    [self.overlayView addSubview:self.skipBackButton];
    [self.overlayView addSubview:self.playPauseButton];
    [self.overlayView addSubview:self.skipForwardButton];
    [self.overlayView addSubview:self.nextButton];

    // BOTTOM CONTROLS
    self.timeSlider = [UISlider new];
    self.timeSlider.minimumTrackTintColor = [UIColor whiteColor];
    self.timeSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    [self.timeSlider setThumbImage:[self makeThumbImage] forState:UIControlStateNormal];
    [self.timeSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.timeSlider addTarget:self action:@selector(sliderValueChanged) forControlEvents:UIControlEventValueChanged];
    [self.timeSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.overlayView addSubview:self.timeSlider];

    self.elapsedLabel = [self makeLabel];
    self.durationLabel = [self makeLabel];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    [self.overlayView addSubview:self.elapsedLabel];
    [self.overlayView addSubview:self.durationLabel];

    // Settings lives in the TOP bar (see viewDidLayoutSubviews).
    self.settingsButton = [self makeButton:@"gearshape.fill" size:19 action:@selector(settingsTapped)];

    // Speed: flat text button, no plate.
    self.speedButton = [YTDMFlatButton new];
    self.speedButton.hitSlop = 14.0;
    self.speedButton.tintColor = [UIColor whiteColor];
    self.speedButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.speedButton setTitle:@"1.0x" forState:UIControlStateNormal];
    [self.speedButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.speedButton addTarget:self action:@selector(buttonPressedFeedback:) forControlEvents:UIControlEventTouchDown];
    [self.speedButton addTarget:self action:@selector(buttonReleasedFeedback:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.speedButton addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:self.speedButton];

    self.repeatButton  = [self makeButton:@"repeat" size:19 action:@selector(repeatTapped)];
    self.aspectButton  = [self makeButton:@"arrow.up.left.and.arrow.down.right" size:19 action:@selector(aspectTapped)];

    [self.overlayView addSubview:self.settingsButton];
    [self.overlayView addSubview:self.repeatButton];
    [self.overlayView addSubview:self.aspectButton];
    // Tags for the bottom controls, assigned once they actually exist.
    self.settingsButton.tag = 109;
    self.speedButton.tag    = 107;
    self.repeatButton.tag   = 106;
    self.aspectButton.tag   = 108;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topSafe = self.view.safeAreaInsets.top ?: 20;
    CGFloat btmSafe = self.view.safeAreaInsets.bottom ?: 10;

    // Top: dismiss left, settings right, route picker to its left.
    CGFloat topSize = 40;
    self.dismissButton.frame = CGRectMake(12, topSafe + 4, topSize, topSize);
    self.settingsButton.frame = CGRectMake(w - 12 - topSize, topSafe + 4, topSize, topSize);
    if (self.routePicker) {
        self.routePicker.frame = CGRectMake(CGRectGetMinX(self.settingsButton.frame) - 40,
                                            topSafe + 6, 34, 34);
    }
    CGFloat titleLeft = CGRectGetMaxX(self.dismissButton.frame) + 6;
    CGFloat titleRight = self.routePicker ? CGRectGetMinX(self.routePicker.frame) - 6
                                          : CGRectGetMinX(self.settingsButton.frame) - 6;
    self.titleLabel.frame = CGRectMake(titleLeft, topSafe + 8,
                                       MAX(40, titleRight - titleLeft), 32);

    // Center: large, evenly spaced cluster.
    CGFloat centerY = h * 0.5;
    CGFloat playSize = 78;
    self.playPauseButton.frame = CGRectMake((w - playSize) * 0.5, centerY - playSize * 0.5, playSize, playSize);

    CGFloat skipSize = 58;
    CGFloat gap = 18;
    CGFloat sideWidth = 58;
    self.skipBackButton.frame   = CGRectMake(CGRectGetMinX(self.playPauseButton.frame) - gap - skipSize,
                                             centerY - skipSize * 0.5, skipSize, skipSize);
    self.skipForwardButton.frame = CGRectMake(CGRectGetMaxX(self.playPauseButton.frame) + gap,
                                             centerY - skipSize * 0.5, skipSize, skipSize);
    self.prevButton.frame = CGRectMake(CGRectGetMinX(self.skipBackButton.frame) - gap - sideWidth,
                                       centerY - sideWidth * 0.5, sideWidth, sideWidth);
    self.nextButton.frame = CGRectMake(CGRectGetMaxX(self.skipForwardButton.frame) + gap,
                                       centerY - sideWidth * 0.5, sideWidth, sideWidth);

    // Bottom
    CGFloat btmY = h - btmSafe - 58;
    self.timeSlider.frame = CGRectMake(16, btmY, w - 32, 28);
    self.elapsedLabel.frame  = CGRectMake(16, btmY + 24, 70, 20);
    self.durationLabel.frame = CGRectMake(w - 86, btmY + 24, 70, 20);

    // Bottom cluster, centered horizontally and sitting just under the
    // elapsed/duration row: loop, speed, aspect(fullscreen).
    CGFloat optSize = 38;
    CGFloat optGap = 34;
    CGFloat clusterWidth = optSize * 3 + optGap * 2;
    CGFloat clusterX = (w - clusterWidth) * 0.5;
    CGFloat optY = btmY + 22;

    self.repeatButton.frame = CGRectMake(clusterX, optY, optSize, optSize);
    self.speedButton.frame  = CGRectMake(clusterX + optSize + optGap, optY, optSize, optSize);
    self.aspectButton.frame  = CGRectMake(clusterX + (optSize + optGap) * 2, optY, optSize, optSize);


}

- (void)setupGestures {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(overlayTapped)];
    [self.view addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:pan];
}

// The pan (swipe-to-dismiss) and the overlay tap live on self.view, which also
// contains every control. Without this, a tap on a button is stolen by the pan
// recogniser and the control appears to do nothing.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldReceiveTouch:(UITouch *)touch {
    // While customising, the per-button drag pan MUST receive the touch.
    // Blocking controls here is what previously made dragging do nothing.
    UIView *touched = touch.view;
    while (touched && touched != self.view) {
        if ([touched isKindOfClass:[UIControl class]] ||
            [touched isKindOfClass:[UISlider class]]) {
            return NO;
        }
        touched = touched.superview;
    }
    return YES;
}

- (void)setupTimeObserver {
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.session.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4)
                                                                          queue:dispatch_get_main_queue()
                                                                     usingBlock:^(CMTime time) {
        [weakSelf updatePlaybackProgress];
    }];
}

- (void)updatePlaybackProgress {
    if (self.isScrubbing || !self.session.currentItem) return;
    NSTimeInterval cur = CMTimeGetSeconds(self.session.player.currentTime);
    NSTimeInterval dur = self.session.currentItem.duration;
    if (dur > 0) {
        self.timeSlider.value = cur / dur;
        self.elapsedLabel.text = [self formatTime:cur];
        self.durationLabel.text = [self formatTime:dur];
    }
}

- (void)syncUI {
    self.titleLabel.text = self.session.currentItem.title ?: @"";
    [self setPlayPauseSymbolPlaying:self.session.isPlaying];
    [self.speedButton setTitle:[NSString stringWithFormat:@"%.2gx", self.session.playbackRate] forState:UIControlStateNormal];
    [self refreshSkipBadges];
    // Loop ON/OFF must be visually distinct. ON uses repeat.1 (repeat-one)
    // with a blue tint; OFF uses the plain repeat icon in neutral grey.
    // Deliberately NOT the YTKACE red appearance.
    NSString *repeatSymbol = self.session.repeatEnabled ? @"repeat.1" : @"repeat";
    if (![UIImage systemImageNamed:repeatSymbol]) repeatSymbol = @"repeat";
    UIImageSymbolConfiguration *repeatCfg =
        [UIImageSymbolConfiguration configurationWithPointSize:17
                                                          weight:UIImageSymbolWeightSemibold
                                                           scale:UIImageSymbolScaleMedium];
    [self.repeatButton setImage:[UIImage systemImageNamed:repeatSymbol withConfiguration:repeatCfg]
                        forState:UIControlStateNormal];
    self.repeatButton.tintColor = self.session.repeatEnabled
        ? [UIColor colorWithRed:0.3 green:0.55 blue:0.9 alpha:1.0]
        : [UIColor colorWithWhite:0.8 alpha:1.0];
    // Keep prev/next visible and full-white even when disabled; dim via alpha
    // instead, so they never look like an unmodified stock control.
    BOOL hasQueue = self.session.playlist.count > 1;
    self.prevButton.enabled = hasQueue;
    self.nextButton.enabled = hasQueue;
    self.prevButton.alpha = hasQueue ? 1.0 : 0.45;
    self.nextButton.alpha = hasQueue ? 1.0 : 0.45;
}

- (void)overlayTapped {
    BOOL hidden = self.overlayView.alpha < 0.1;
    [UIView animateWithDuration:0.25 animations:^{
        self.overlayView.alpha = hidden ? 1.0 : 0.0;
    }];
    if (hidden) [self resetControlsTimer];
}

- (void)resetControlsTimer {
    [self.controlsTimer invalidate];
    if (self.session.isPlaying) {
        self.controlsTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 target:self selector:@selector(hideControls) userInfo:nil repeats:NO];
    }
}

- (void)hideControls {
    if (self.isScrubbing) return;
    [UIView animateWithDuration:0.25 animations:^{
        self.overlayView.alpha = 0.0;
    }];
}

- (void)dismissTapped {
    [self.controlsTimer invalidate];
    if (self.timeObserver) {
        [self.session.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    if (self.onDismiss) self.onDismiss();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)playPauseTapped {
    [self.session togglePlayPause];
    [self resetControlsTimer];
}

- (void)skipBackTapped {
    NSTimeInterval interval = [[NSUserDefaults standardUserDefaults] integerForKey:@"YTDMRewindInterval"] ?: 10;
    [self.session skipSeconds:-interval];
    [self resetControlsTimer];
}

- (void)skipFwdTapped {
    NSTimeInterval interval = [[NSUserDefaults standardUserDefaults] integerForKey:@"YTDMForwardInterval"] ?: 10;
    [self.session skipSeconds:interval];
    [self resetControlsTimer];
}

- (void)prevTapped {
    [self.session playPrevious];
    [self resetControlsTimer];
}

- (void)nextTapped {
    [self.session playNext];
    [self resetControlsTimer];
}

- (void)repeatTapped {
    self.session.repeatEnabled = !self.session.repeatEnabled;
    [self syncUI];
    [self resetControlsTimer];
}

- (void)aspectTapped {
    self.isAspectFill = !self.isAspectFill;
    self.surfaceView.playerLayer.videoGravity = self.isAspectFill ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
    self.aspectButton.tintColor = self.isAspectFill ? [UIColor systemRedColor] : [UIColor whiteColor];
    [self resetControlsTimer];
}

- (void)speedTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Playback Speed" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *speeds = @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0];
    for (NSNumber *s in speeds) {
        NSString *title = [NSString stringWithFormat:@"%.2gx", s.floatValue];
        if (fabs(s.floatValue - self.session.playbackRate) < 0.05) {
            title = [@"✓ " stringByAppendingString:title];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.session.playbackRate = s.floatValue;
            [self syncUI];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.speedButton;
        sheet.popoverPresentationController.sourceRect = self.speedButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)sliderTouchDown {
    self.isScrubbing = YES;
    [self.controlsTimer invalidate];
}

- (void)sliderValueChanged {
    NSTimeInterval dur = self.session.currentItem.duration;
    NSTimeInterval cur = self.timeSlider.value * dur;
    self.elapsedLabel.text = [self formatTime:cur];
}

- (void)sliderTouchUp {
    NSTimeInterval dur = self.session.currentItem.duration;
    NSTimeInterval target = self.timeSlider.value * dur;
    [self.session seekTo:target];
    self.isScrubbing = NO;
    [self resetControlsTimer];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.view];
    if (trans.y > 80 && pan.state == UIGestureRecognizerStateEnded) {
        [self dismissTapped];
    }
}

// ============================================================================
// CONTROL ARTWORK
//
// The transport controls use native SF Symbols (play.fill, pause.fill,
// backward.end.fill, forward.end.fill, gobackward.N / goforward.N) instead of
// hand-drawn UIBezierPath/UIGraphicsImageRenderer artwork. Custom glyphs do not
// respect SF's proportions or optical weight, which is what made the controls
// look unnatural. Only the iconography layer changed: layout, hitSlop, press
// feedback, hit areas and behaviour are exactly as before.
// ============================================================================

- (UIImageSymbolConfiguration *)ytdm_transportSymbolConfigurationWithSize:(CGFloat)size {
    return [UIImageSymbolConfiguration configurationWithPointSize:size
                                                           weight:UIImageSymbolWeightSemibold
                                                            scale:UIImageSymbolScaleLarge];
}

// A borderless control showing one native SF Symbol. No background plate, no
// corner radius, no clipping — the system renders the glyph.
- (YTDMFlatButton *)makeSystemButton:(NSString *)symbol
                                size:(CGFloat)size
                              action:(SEL)action {
    YTDMFlatButton *btn = [YTDMFlatButton new];
    btn.hitSlop = 12.0;
    btn.backgroundColor = [UIColor clearColor];
    btn.tintColor = [UIColor whiteColor];
    btn.layer.cornerRadius = 0;
    btn.layer.borderWidth = 0;
    btn.layer.masksToBounds = NO;
    btn.contentEdgeInsets = UIEdgeInsetsZero;
    btn.imageView.contentMode = UIViewContentModeCenter;

    [btn setImage:[UIImage systemImageNamed:symbol
                        withConfiguration:[self ytdm_transportSymbolConfigurationWithSize:size]]
          forState:UIControlStateNormal];

    [btn addTarget:self action:@selector(buttonPressedFeedback:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonReleasedFeedback:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// The centre transport control. Starts on play.fill; syncUI swaps it for
// pause.fill while the session is playing.
- (YTDMFlatButton *)makeTransportIconWithSize:(CGFloat)size action:(SEL)action {
    YTDMFlatButton *btn = [self makeSystemButton:@"play.fill" size:size action:action];
    btn.hitSlop = 14.0;
    return btn;
}

- (void)setPlayPauseSymbolPlaying:(BOOL)playing {
    NSString *symbol = playing ? @"pause.fill" : @"play.fill";
    [self.playPauseButton setImage:[UIImage systemImageNamed:symbol
                                           withConfiguration:[self ytdm_transportSymbolConfigurationWithSize:YTDMPlaySymbolSize]]
                          forState:UIControlStateNormal];
}

// Skip controls. The interval is baked into the symbol name, so 5 / 10 / 15 /
// 20 seconds are readable straight from the button with no custom drawing.
- (YTDMFlatButton *)makeSkipIconBack:(SEL)action  { return [self makeSkipIcon:YES  action:action]; }
- (YTDMFlatButton *)makeSkipIconForward:(SEL)action { return [self makeSkipIcon:NO action:action]; }

- (YTDMFlatButton *)makeSkipIcon:(BOOL)backwards action:(SEL)action {
    YTDMFlatButton *btn = [self makeSystemButton:(backwards ? @"gobackward" : @"goforward")
                                           size:YTDMSkipSymbolSize
                                         action:action];
    // gobackward.20 / goforward.20 do not exist in SF Symbols, so the initial
    // artwork is resolved through the same fallback refreshSkipBadges uses.
    [btn setImage:[self ytdm_skipImageBackwards:backwards
                                       seconds:[self currentSkipSecondsBackwards:backwards]]
          forState:UIControlStateNormal];

    // Remember the direction so refreshSkipBadges can rebuild the symbol when
    // the configured interval changes.
    objc_setAssociatedObject(btn, @selector(currentSkipSecondsBackwards:),
                             @(backwards), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return btn;
}

- (NSString *)ytdm_skipSymbolNameBackwards:(BOOL)backwards seconds:(NSInteger)seconds {
    return [NSString stringWithFormat:@"%@.%ld", backwards ? @"gobackward" : @"goforward", (long)seconds];
}

// gobackward.N / goforward.N only exist for the intervals SF ships. Fall back
// to the bare symbol for anything else so the button is never blank.
- (UIImage *)ytdm_skipImageBackwards:(BOOL)backwards seconds:(NSInteger)seconds {
    UIImageSymbolConfiguration *cfg = [self ytdm_transportSymbolConfigurationWithSize:YTDMSkipSymbolSize];
    UIImage *image = [UIImage systemImageNamed:[self ytdm_skipSymbolNameBackwards:backwards seconds:seconds]
                           withConfiguration:cfg];
    if (!image) {
        image = [UIImage systemImageNamed:(backwards ? @"gobackward" : @"goforward")
                       withConfiguration:cfg];
    }
    return image;
}

- (NSInteger)currentSkipSecondsBackwards:(BOOL)backwards {
    NSString *key = backwards ? @"YTDMRewindInterval" : @"YTDMForwardInterval";
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    return stored > 0 ? stored : 10;
}

- (void)refreshSkipBadges {
    for (UIButton *btn in @[self.skipBackButton, self.skipForwardButton]) {
        NSNumber *direction = objc_getAssociatedObject(btn, @selector(currentSkipSecondsBackwards:));
        if (!direction) continue;
        BOOL backwards = direction.boolValue;
        [btn setImage:[self ytdm_skipImageBackwards:backwards
                                           seconds:[self currentSkipSecondsBackwards:backwards]]
              forState:UIControlStateNormal];
    }
}



// Flat, borderless control. No background plate, no corner radius, no inset
// padding — just a crisp SF Symbol. `prominent` controls are larger.
- (YTDMFlatButton *)makeButton:(NSString *)symbol size:(CGFloat)size action:(SEL)action {
    return [self makeButton:symbol size:size prominent:NO action:action];
}

- (YTDMFlatButton *)makeButton:(NSString *)symbol size:(CGFloat)size prominent:(BOOL)prominent action:(SEL)action {
    YTDMFlatButton *btn = [YTDMFlatButton new];
    btn.hitSlop = 12.0;

    CGFloat pointSize = prominent ? MAX(size, 30.0) : MAX(size, 19.0);
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                         weight:UIImageSymbolWeightSemibold
                                                          scale:UIImageSymbolScaleLarge];

    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    [btn setImage:img forState:UIControlStateNormal];

    // Pressed look is handled by the transform/opacity animation below, not by
    // a red or dark state image.
    btn.tintColor = [UIColor whiteColor];
    btn.backgroundColor = [UIColor clearColor];
    btn.layer.cornerRadius = 0;
    btn.layer.borderWidth = 0;
    btn.layer.masksToBounds = NO;
    btn.contentEdgeInsets = UIEdgeInsetsZero;

    [btn addTarget:self action:@selector(buttonPressedFeedback:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonReleasedFeedback:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)buttonPressedFeedback:(UIButton *)btn {
    btn.layer.masksToBounds = NO;
    [UIView animateWithDuration:0.10 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        btn.transform = CGAffineTransformMakeScale(0.86, 0.86);
        btn.alpha = 0.55;
    } completion:nil];
}

- (void)buttonReleasedFeedback:(UIButton *)btn {
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        btn.transform = CGAffineTransformIdentity;
        btn.alpha = 1.0;
    } completion:nil];
}

- (UILabel *)makeLabel {
    UILabel *lbl = [UILabel new];
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    lbl.text = @"0:00";
    return lbl;
}

- (UIImage *)makeThumbImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(14, 14), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 14, 14)];
    [[UIColor whiteColor] setFill];
    [p fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (NSString *)formatTime:(NSTimeInterval)sec {
    if (!isfinite(sec) || sec < 0) return @"0:00";
    NSInteger s = (NSInteger)sec % 60;
    NSInteger m = ((NSInteger)sec / 60) % 60;
    NSInteger h = (NSInteger)sec / 3600;
    return h > 0 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s]
                 : [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (void)dealloc {
    [self.controlsTimer invalidate];
    if (self.timeObserver) {
        [self.session.player removeTimeObserver:self.timeObserver];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ============================================================================
// PLAYER SETTINGS
// ============================================================================

- (void)settingsTapped {
    [self resetControlsTimer];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Player Settings"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rewind Interval"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        [self presentSkipIntervalPickerForward:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Forward Interval"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        [self presentSkipIntervalPickerForward:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Playback Queue"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        [self showQueue];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.settingsButton;
        sheet.popoverPresentationController.sourceRect = self.settingsButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// Rewind and forward are configured INDEPENDENTLY; each only writes its own key.
- (void)presentSkipIntervalPickerForward:(BOOL)isForward {
    NSArray<NSNumber *> *options = @[@5, @10, @15, @20];
    NSString *title = isForward ? @"Forward Interval" : @"Rewind Interval";
    NSString *key = isForward ? @"YTDMForwardInterval" : @"YTDMRewindInterval";

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger stored = [ud integerForKey:key];
    NSInteger current = (stored > 0) ? stored : 10; // default 10s

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *opt in options) {
        NSString *label = [NSString stringWithFormat:@"%@ seconds", opt];
        if (opt.integerValue == current) label = [@"✓ " stringByAppendingString:label];
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a) {
            [ud setInteger:opt.integerValue forKey:key];
            // Reflect the new value on the skip buttons straight away.
            [self refreshSkipBadges];
            [self resetControlsTimer];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.settingsButton;
        sheet.popoverPresentationController.sourceRect = self.settingsButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// ============================================================================
// PLAYBACK QUEUE
//
// The queue is a VIEW over the existing YTDMPlaybackSession playlist. It never
// creates a second AVPlayer or a parallel playback state — selecting a row
// calls the session's own playItem:inPlaylist:index:.
// ============================================================================

- (void)showQueue {
    [self resetControlsTimer];
    NSArray<YTDMDownloadItem *> *items = self.session.playlist ?: @[];
    if (items.count == 0) return;

    YTDMQueueViewController *queue = [YTDMQueueViewController new];
    queue.items = items;
    queue.currentIndex = self.session.currentIndex;

    __weak typeof(self) weakSelf = self;
    __weak YTDMQueueViewController *weakQueue = queue;
    // Selecting a row re-uses the existing session playback path.
    queue.onSelect = ^(NSInteger index) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (index < 0 || index >= (NSInteger)items.count) return;
        [strongSelf.session playItem:items[index] inPlaylist:items index:index];
        [strongSelf syncUI];
    };
    // Reordering writes back into the SAME session playlist, so next/previous
    // advance through the user's order. Not persisted to the Downloads key.
    queue.onReorder = ^(NSInteger from, NSInteger to) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSMutableArray<YTDMDownloadItem *> *updated = [items mutableCopy];
        if (from < 0 || to < 0 || from >= (NSInteger)updated.count || to >= (NSInteger)updated.count) return;
        YTDMDownloadItem *moved = updated[from];
        [updated removeObjectAtIndex:from];
        [updated insertObject:moved atIndex:to];
        [strongSelf.session setPlaylist:updated];
        weakQueue.items = updated;
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:queue];
    [self presentViewController:nav animated:YES completion:nil];
}

@end
