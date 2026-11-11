#import "YTDMDownloadsViewController.h"
#import "YTDMDownloadsManager.h"
#import "YTDMPlayerViewController.h"
#import <Photos/Photos.h>

@interface YTDMDownloadCardCell : UICollectionViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UILabel *durationBadge;
@property (nonatomic, strong) UILabel *qualityBadge;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, copy, nullable) void (^onMoreTap)(UIView *sourceView);
- (void)configureWithItem:(YTDMDownloadItem *)item;
@end

@implementation YTDMDownloadCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];

        _cardView = [UIView new];
        _cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _cardView.layer.cornerRadius = 14.0;
        _cardView.layer.masksToBounds = YES;
        [self.contentView addSubview:_cardView];

        _thumbnailView = [UIImageView new];
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        _thumbnailView.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
        [_cardView addSubview:_thumbnailView];

        _qualityBadge = [self makeBadge];
        [_cardView addSubview:_qualityBadge];

        _durationBadge = [self makeBadge];
        [_cardView addSubview:_durationBadge];

        _progressTrack = [UIView new];
        _progressTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
        _progressTrack.hidden = YES;
        [_thumbnailView addSubview:_progressTrack];

        _progressFill = [UIView new];
        _progressFill.backgroundColor = [UIColor systemRedColor];
        [_progressTrack addSubview:_progressFill];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 2;
        [_cardView addSubview:_titleLabel];

        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _metaLabel.textColor = [UIColor secondaryLabelColor];
        [_cardView addSubview:_metaLabel];

        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        _moreButton.tintColor = [UIColor secondaryLabelColor];
        [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_moreButton];
    }
    return self;
}

- (UILabel *)makeBadge {
    UILabel *lbl = [UILabel new];
    lbl.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    lbl.layer.cornerRadius = 4.0;
    lbl.layer.masksToBounds = YES;
    lbl.textAlignment = NSTextAlignmentCenter;
    return lbl;
}

- (void)configureWithItem:(YTDMDownloadItem *)item {
    self.titleLabel.text = item.title;
    self.metaLabel.text = [NSString stringWithFormat:@"%@ • %@", [item formattedFileSize], [item formattedDate]];
    self.durationBadge.text = [NSString stringWithFormat:@" %@ ", [item formattedDuration]];
    self.qualityBadge.text = [NSString stringWithFormat:@" %@ ", item.qualityLabel ?: (item.isAudio ? @"AUDIO" : @"VIDEO")];

    UIImage *thumb = [item thumbnailImage];
    if (thumb) {
        self.thumbnailView.image = thumb;
    } else {
        NSString *iconName = item.isAudio ? @"music.note" : @"play.rectangle.fill";
        self.thumbnailView.image = [UIImage systemImageNamed:iconName];
        self.thumbnailView.tintColor = [UIColor tertiaryLabelColor];
        self.thumbnailView.contentMode = UIViewContentModeCenter;
    }

    if (item.watchedRatio > 0.02 && item.watchedRatio < 0.98) {
        self.progressTrack.hidden = NO;
        CGFloat w = self.thumbnailView.bounds.size.width;
        self.progressTrack.frame = CGRectMake(0, self.thumbnailView.bounds.size.height - 3, w, 3);
        self.progressFill.frame = CGRectMake(0, 0, w * item.watchedRatio, 3);
    } else {
        self.progressTrack.hidden = YES;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.cardView.frame = CGRectMake(12, 6, w - 24, h - 12);

    CGFloat cardW = self.cardView.bounds.size.width;
    CGFloat cardH = self.cardView.bounds.size.height;
    CGFloat thumbW = 120;

    self.thumbnailView.frame = CGRectMake(0, 0, thumbW, cardH);
    self.durationBadge.frame = CGRectMake(thumbW - 52, cardH - 22, 48, 18);
    self.qualityBadge.frame = CGRectMake(4, cardH - 22, 46, 18);

    CGFloat infoX = thumbW + 12;
    CGFloat infoW = cardW - infoX - 36;
    self.titleLabel.frame = CGRectMake(infoX, 10, infoW, 40);
    self.metaLabel.frame = CGRectMake(infoX, cardH - 26, infoW, 16);
    self.moreButton.frame = CGRectMake(cardW - 36, 10, 30, 30);
}

- (void)moreTapped {
    if (self.onMoreTap) self.onMoreTap(self.moreButton);
}

@end

// ============================================================================
// DOWNLOADS VIEW CONTROLLER
// ============================================================================

@interface YTDMDownloadsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UIButton *queueButton;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UIButton *reorderButton;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *emptyView;

// MiniPlayer
@property (nonatomic, strong) UIView *miniPlayerView;
@property (nonatomic, strong) UIImageView *miniThumbView;
@property (nonatomic, strong) UILabel *miniTitleLabel;
@property (nonatomic, strong) UIButton *miniPlayPauseButton;
@property (nonatomic, strong) UIButton *miniCloseButton;

@property (nonatomic, copy) NSArray<YTDMDownloadItem *> *items;
@property (nonatomic, assign) NSInteger sortIndex; // 0: Newest, 1: Oldest, 2: Name, 3: Size
@property (nonatomic, assign) BOOL isReordering;

@end

@implementation YTDMDownloadsViewController

// ============================================================================
// PLAYER PRESENTATION
//
// Uses the project's own proven presenter, unchanged from the build that
// shipped and worked:
//
//     [self ytdm_parentViewController] ?: getTopMostController()
//
// ytdm_parentViewController walks the responder chain to the nearest real
// UIViewController; getTopMostController walks presentedViewController to the
// front of the active key window, matching the pattern already used by the
// project and by the player itself.
// ============================================================================

- (UIViewController *)ytdm_hostPresenter {
    // Same pattern the project already used successfully:
    //   [self ytdm_parentViewController] ?: getTopMostController()
    UIViewController *parent = nil;
    UIResponder *responder = self;
    while ([responder nextResponder]) {
        responder = [responder nextResponder];
        if ([responder isKindOfClass:[UIViewController class]]) {
            parent = (UIViewController *)responder;
            break;
        }
    }
    if (!parent) {
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
            if (window) break;
        }
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        parent = top;
    }
    return parent ?: self;
}

- (void)ytdm_presentPlayerForItem:(YTDMDownloadItem *)item
                         playlist:(NSArray<YTDMDownloadItem *> *)playlist
                            index:(NSInteger)index {

    if (!item) return;

    YTDMPlayerViewController *player =
        [[YTDMPlayerViewController alloc] initWithItem:item
                                            inPlaylist:playlist
                                                 index:index];

    __weak typeof(self) weakSelf = self;
    player.onDismiss = ^{
        [weakSelf reloadFiles];
        [weakSelf syncMiniPlayer];
    };

    [[self ytdm_hostPresenter] presentViewController:player animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.sortIndex = 0;

    [self setupHeader];
    [self setupCollectionView];
    [self setupEmptyView];
    [self setupMiniPlayer];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFiles)
                                                 name:YTDMDownloadsLibraryChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncMiniPlayer)
                                                 name:YTDMPlaybackStateChangedNotification object:nil];
    [self reloadFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadFiles];
    [self syncMiniPlayer];
}

- (void)setupHeader {
    self.headerView = [UIView new];
    self.headerView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:self.headerView];

    self.headerTitleLabel = [UILabel new];
    self.headerTitleLabel.text = @"Downloads";
    self.headerTitleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.headerTitleLabel.textColor = [UIColor labelColor];
    [self.headerView addSubview:self.headerTitleLabel];

    // Queue button
    self.queueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [self.queueButton setImage:[UIImage systemImageNamed:@"list.bullet.rectangle.portrait" withConfiguration:cfg] forState:UIControlStateNormal];
    self.queueButton.tintColor = [UIColor labelColor];
    [self.queueButton addTarget:self action:@selector(openQueueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.queueButton];

    // Sort button
    self.sortButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sortButton setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down" withConfiguration:cfg] forState:UIControlStateNormal];
    self.sortButton.tintColor = [UIColor labelColor];
    [self.sortButton addTarget:self action:@selector(sortTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.sortButton];

    // Reorder button — enables "Order however you want" in the Downloads tab
    self.reorderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.reorderButton setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down.circle" withConfiguration:cfg] forState:UIControlStateNormal];
    self.reorderButton.tintColor = [UIColor labelColor];
    [self.reorderButton addTarget:self action:@selector(reorderTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.reorderButton];

    // Segments
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Videos", @"Audio"]];
    self.segmentControl.selectedSegmentIndex = 0;
    [self.segmentControl addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.headerView addSubview:self.segmentControl];
}

- (void)setupCollectionView {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumLineSpacing = 4;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[YTDMDownloadCardCell class] forCellWithReuseIdentifier:@"CardCell"];
    [self.view addSubview:self.collectionView];
}

- (void)setupEmptyView {
    self.emptyView = [UIView new];
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"tray.and.arrow.down.fill"]];
    icon.tintColor = [UIColor tertiaryLabelColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:icon];

    UILabel *title = [UILabel new];
    title.text = @"No Downloads Yet";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    title.textColor = [UIColor labelColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:title];

    UILabel *sub = [UILabel new];
    sub.text = @"Videos and audio saved from YTDM will appear here.";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 2;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:self.emptyView.centerYAnchor constant:-40],
        [icon.widthAnchor constraintEqualToConstant:64],
        [icon.heightAnchor constraintEqualToConstant:64],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:14],
        [title.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [sub.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [sub.widthAnchor constraintEqualToConstant:260]
    ]];
}

- (void)setupMiniPlayer {
    self.miniPlayerView = [UIView new];
    self.miniPlayerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.miniPlayerView.layer.cornerRadius = 12.0;
    self.miniPlayerView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.miniPlayerView.layer.shadowOpacity = 0.15;
    self.miniPlayerView.layer.shadowRadius = 8.0;
    self.miniPlayerView.layer.shadowOffset = CGSizeMake(0, 2);
    self.miniPlayerView.hidden = YES;
    [self.view addSubview:self.miniPlayerView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(miniPlayerTapped)];
    [self.miniPlayerView addGestureRecognizer:tap];

    self.miniThumbView = [UIImageView new];
    self.miniThumbView.layer.cornerRadius = 8.0;
    self.miniThumbView.clipsToBounds = YES;
    self.miniThumbView.contentMode = UIViewContentModeScaleAspectFill;
    [self.miniPlayerView addSubview:self.miniThumbView];

    self.miniTitleLabel = [UILabel new];
    self.miniTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.miniTitleLabel.textColor = [UIColor labelColor];
    [self.miniPlayerView addSubview:self.miniTitleLabel];

    self.miniPlayPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.miniPlayPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    self.miniPlayPauseButton.tintColor = [UIColor labelColor];
    [self.miniPlayPauseButton addTarget:self action:@selector(miniPlayPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniPlayerView addSubview:self.miniPlayPauseButton];

    self.miniCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.miniCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.miniCloseButton.tintColor = [UIColor secondaryLabelColor];
    [self.miniCloseButton addTarget:self action:@selector(miniCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniPlayerView addSubview:self.miniCloseButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topSafe = self.view.safeAreaInsets.top ?: 20;

    CGFloat headerH = 88;
    self.headerView.frame = CGRectMake(0, topSafe, w, headerH);
    self.headerTitleLabel.frame = CGRectMake(16, 8, 160, 30);
    self.queueButton.frame = CGRectMake(w - 84, 6, 36, 34);
    self.sortButton.frame = CGRectMake(w - 44, 6, 36, 34);
    self.reorderButton.frame = CGRectMake(w - 128, 6, 36, 34);
    self.segmentControl.frame = CGRectMake(16, 46, w - 32, 32);

    CGFloat colY = topSafe + headerH + 6;
    self.collectionView.frame = CGRectMake(0, colY, w, h - colY);
    self.emptyView.frame = self.collectionView.frame;

    CGFloat btmSafe = self.view.safeAreaInsets.bottom ?: 10;
    self.miniPlayerView.frame = CGRectMake(12, h - btmSafe - 64, w - 24, 56);
    self.miniThumbView.frame = CGRectMake(8, 8, 40, 40);
    self.miniTitleLabel.frame = CGRectMake(56, 18, w - 160, 20);
    self.miniPlayPauseButton.frame = CGRectMake(w - 96, 13, 30, 30);
    self.miniCloseButton.frame = CGRectMake(w - 60, 13, 30, 30);
}

- (void)reloadFiles {
    NSArray *raw;
    if (self.segmentControl.selectedSegmentIndex == 1) {
        raw = [[YTDMDownloadsManager sharedManager] videoDownloads];
    } else if (self.segmentControl.selectedSegmentIndex == 2) {
        raw = [[YTDMDownloadsManager sharedManager] audioDownloads];
    } else {
        raw = [[YTDMDownloadsManager sharedManager] allDownloads];
    }

    NSMutableArray *sorted = [raw mutableCopy];
    if (self.isReordering) {
        // Manual order already applied by YTDMDownloadsManager.allDownloads.
        // A date/name/size sort would discard it, so skip sorting entirely.
    } else if (self.sortIndex == 0) { // Newest
        [sorted sortUsingComparator:^NSComparisonResult(YTDMDownloadItem *a, YTDMDownloadItem *b) {
            return [b.dateAdded compare:a.dateAdded];
        }];
    } else if (self.sortIndex == 1) { // Oldest
        [sorted sortUsingComparator:^NSComparisonResult(YTDMDownloadItem *a, YTDMDownloadItem *b) {
            return [a.dateAdded compare:b.dateAdded];
        }];
    } else if (self.sortIndex == 2) { // Name A-Z
        [sorted sortUsingComparator:^NSComparisonResult(YTDMDownloadItem *a, YTDMDownloadItem *b) {
            return [a.title localizedCaseInsensitiveCompare:b.title];
        }];
    } else if (self.sortIndex == 3) { // Size largest
        [sorted sortUsingComparator:^NSComparisonResult(YTDMDownloadItem *a, YTDMDownloadItem *b) {
            return [@(b.fileSize) compare:@(a.fileSize)];
        }];
    }

    self.items = sorted;
    self.emptyView.hidden = self.items.count > 0;
    [self.collectionView reloadData];
}

- (void)segmentChanged {
    [self reloadFiles];
}

- (void)openQueueTapped {
    // The previous implementation looked up a class that does not exist, so
    // this button silently did nothing. Open the real player instead, which
    // owns the queue UI and the YTDMPlaybackSession playlist.
    YTDMPlaybackSession *sess = [YTDMPlaybackSession sharedSession];
    if (!sess.currentItem) {
        // Nothing playing yet — start the first item and show its queue.
        YTDMDownloadItem *first = self.items.firstObject;
        if (!first) return;
        sess = [YTDMPlaybackSession sharedSession];
        [sess playItem:first inPlaylist:self.items index:0];
    }
    [self ytdm_presentPlayerForItem:sess.currentItem
                                playlist:sess.playlist
                                   index:sess.currentIndex];
}

- (void)sortTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sort Downloads" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@"Date (Newest First)", @"Date (Oldest First)", @"Title (A - Z)", @"File Size (Largest First)"];
    for (NSInteger i = 0; i < opts.count; i++) {
        NSString *title = (self.sortIndex == i) ? [@"✓ " stringByAppendingString:opts[i]] : opts[i];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.sortIndex = i;
            [self reloadFiles];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.sortButton;
        sheet.popoverPresentationController.sourceRect = self.sortButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// MiniPlayer
- (void)syncMiniPlayer {
    YTDMPlaybackSession *sess = [YTDMPlaybackSession sharedSession];
    if (sess.currentItem && sess.isPlaying) {
        self.miniPlayerView.hidden = NO;
        self.miniTitleLabel.text = sess.currentItem.title;
        self.miniThumbView.image = [sess.currentItem thumbnailImage];
        NSString *icon = sess.isPlaying ? @"pause.fill" : @"play.fill";
        [self.miniPlayPauseButton setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    } else {
        self.miniPlayerView.hidden = YES;
    }
}

- (void)miniPlayerTapped {
    YTDMPlaybackSession *sess = [YTDMPlaybackSession sharedSession];
    if (!sess.currentItem) return;
    [self ytdm_presentPlayerForItem:sess.currentItem
                                playlist:sess.playlist
                                   index:sess.currentIndex];
}

- (void)miniPlayPauseTapped {
    [[YTDMPlaybackSession sharedSession] togglePlayPause];
    [self syncMiniPlayer];
}

- (void)miniCloseTapped {
    [[YTDMPlaybackSession sharedSession] stop];
    [self syncMiniPlayer];
}

// CollectionView DataSource & Delegate
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.items.count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return CGSizeMake(cv.bounds.size.width, 96);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    YTDMDownloadCardCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"CardCell" forIndexPath:ip];
    YTDMDownloadItem *item = self.items[ip.item];
    [cell configureWithItem:item];

    __weak typeof(self) weakSelf = self;
    cell.onMoreTap = ^(UIView *src) {
        [weakSelf showMenuForItem:item fromView:src];
    };
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    YTDMDownloadItem *item = self.items[ip.item];
    [self ytdm_presentPlayerForItem:item playlist:self.items index:ip.item];
}

- (void)showMenuForItem:(YTDMDownloadItem *)item fromView:(UIView *)src {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"▶ Play" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSUInteger idx = [self.items indexOfObject:item];
        if (idx == NSNotFound) idx = 0;
        [self ytdm_presentPlayerForItem:item playlist:self.items index:idx];
    }]];

    if (!item.isAudio) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"📸 Save to Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:item.fileURL];
                    } completionHandler:^(BOOL success, NSError *error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIAlertController *res = [UIAlertController alertControllerWithTitle:success ? @"Saved to Photos!" : @"Error"
                                                                                         message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                            [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:res animated:YES completion:nil];
                        });
                    }];
                }
            }];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔗 Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[item.fileURL] applicationActivities:nil];
        if (act.popoverPresentationController) {
            act.popoverPresentationController.sourceView = src;
            act.popoverPresentationController.sourceRect = src.bounds;
        }
        [self presentViewController:act animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"✏️ Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [prompt addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item.title; }];
        [prompt addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *sa) {
            NSString *newName = prompt.textFields.firstObject.text;
            [[YTDMDownloadsManager sharedManager] renameItem:item toName:newName];
        }]];
        [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:prompt animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🗑 Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        UIAlertController *conf = [UIAlertController alertControllerWithTitle:@"Delete Download?"
                                                                      message:[NSString stringWithFormat:@"Are you sure you want to delete \"%@\"?", item.title]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [conf addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *da) {
            [[YTDMDownloadsManager sharedManager] deleteItem:item];
        }]];
        [conf addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:conf animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = src;
        sheet.popoverPresentationController.sourceRect = src.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)collectionView:(UICollectionView *)collectionView moveItemAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    // Manual ordering for the Downloads tab. Kept in a dedicated persistence
    // key so it never interferes with the playback queue order.
    if (!self.isReordering) return;
    NSMutableArray *downloads = [self.items mutableCopy];
    if (sourceIndexPath.item < downloads.count && destinationIndexPath.item < downloads.count) {
        YTDMDownloadItem *item = downloads[sourceIndexPath.item];
        [downloads removeObjectAtIndex:sourceIndexPath.item];
        [downloads insertObject:item atIndex:destinationIndexPath.item];
        self.items = downloads;
        [[YTDMDownloadsManager sharedManager] setDownloadsOrder:downloads];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.isReordering; // Order however you want
}

- (void)reorderTapped {
    self.isReordering = !self.isReordering;
    self.collectionView.dragInteractionEnabled = self.isReordering;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                      weight:UIImageSymbolWeightSemibold];
    NSString *symbol = self.isReordering ? @"checkmark.circle.fill" : @"arrow.up.arrow.down.circle";
    [self.reorderButton setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    self.reorderButton.tintColor = self.isReordering ? [UIColor systemBlueColor] : [UIColor labelColor];

    if (self.isReordering) {
        // Custom sort modes would fight the manual order; force the manual one.
        self.sortIndex = 0;
        [self reloadFiles];
        UIAlertController *hint = [UIAlertController alertControllerWithTitle:@"Reorder Mode"
                                                                       message:@"Drag downloads into any order you want.\n\nThis order is saved for the Downloads tab only — your playback queue keeps its own order."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [hint addAction:[UIAlertAction actionWithTitle:@"Got it" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:hint animated:YES completion:nil];
    } else {
        [[YTDMDownloadsManager sharedManager] setDownloadsOrder:self.items];
    }
    [self.collectionView reloadData];
}

@end
