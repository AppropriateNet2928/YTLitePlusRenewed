#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static char kAssociatedOutURLKey;
static NSString *capturedVideoId = nil;

static UIWindow *getKeyWindow(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in [(UIWindowScene *)scene windows]) {
                if (window.isKeyWindow) { keyWindow = window; break; }
            }
        }
        if (keyWindow) break;
    }
    if (!keyWindow) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) { window.isKeyWindow ? keyWindow = window : nil; break; }
        }
    }
    return keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
}

static UIViewController *getTopMostController(void) {
    UIWindow *window = getKeyWindow();
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) { root = root.presentedViewController; }
    return root;
}

// ============================================================================
// MODERNISED PHOTO/VIDEO SAVER WITH ERROR DIAGNOSTICS
// ============================================================================
@interface YTDMPhotoSaver : NSObject
+ (void)saveVideoPath:(NSString *)path completion:(void (^)(BOOL success, NSError *error))completion;
@end

@implementation YTDMPhotoSaver
+ (void)saveVideoPath:(NSString *)path completion:(void (^)(BOOL success, NSError *error))completion {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                completion(success, error);
            }];
        } else {
            NSError *customError = [NSError errorWithDomain:@"YTDMError" code:403 userInfo:@{NSLocalizedDescriptionKey: @"Photo Auth Denied (Check LiveContainer Settings)"}];
            completion(NO, customError);
        }
    }];
}
@end

@interface YTDMImageSaver : NSObject
+ (void)saveImage:(UIImage *)image completion:(void (^)(BOOL success, NSError *error))completion;
@end

@implementation YTDMImageSaver
+ (void)saveImage:(UIImage *)image completion:(void (^)(BOOL success, NSError *error))completion {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                completion(success, error);
            }];
        } else {
            NSError *customError = [NSError errorWithDomain:@"YTDMError" code:403 userInfo:@{NSLocalizedDescriptionKey: @"Photo Auth Denied (Check LiveContainer Settings)"}];
            completion(NO, customError);
        }
    }];
}
@end

// ============================================================================
// ANIMATED PROGRESS HUD
// ============================================================================
@interface YTDMProgressHUD : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *feedbackIconLabel;

+ (instancetype)sharedHUD;
- (void)showInView:(UIView *)parentView;
- (void)updateProgress:(float)progress status:(NSString *)status;
- (void)showSuccessWithStatus:(NSString *)status;
- (void)showError:(NSString *)errorMessage;
- (void)dismiss;
@end

@implementation YTDMProgressHUD
+ (instancetype)sharedHUD {
    static YTDMProgressHUD *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] initWithFrame:CGRectMake(0, 0, 280, 180)]; });
    return shared;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 18;
        self.layer.masksToBounds = YES;
        
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.frame = self.bounds;
        [self addSubview:_blurView];
        
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        _spinner.color = [UIColor whiteColor];
        _spinner.center = CGPointMake(frame.size.width / 2, 45);
        [_blurView.contentView addSubview:_spinner];

        _feedbackIconLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, frame.size.width, 60)];
        _feedbackIconLabel.textColor = [UIColor whiteColor];
        _feedbackIconLabel.font = [UIFont systemFontOfSize:50 weight:UIFontWeightMedium];
        _feedbackIconLabel.textAlignment = NSTextAlignmentCenter;
        _feedbackIconLabel.hidden = YES;
        [_blurView.contentView addSubview:_feedbackIconLabel];
        
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 85, frame.size.width - 20, 20)];
        _titleLabel.text = @"YTDM Pro Engine";
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [_blurView.contentView addSubview:_titleLabel];
        
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.frame = CGRectMake(25, 115, frame.size.width - 50, 4);
        _progressView.progressTintColor = [UIColor systemGreenColor];
        _progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
        _progressView.hidden = YES;
        [_blurView.contentView addSubview:_progressView];
        
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 122, frame.size.width - 20, 48)];
        _statusLabel.text = @"Synchronizing...";
        _statusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
        _statusLabel.font = [UIFont systemFontOfSize:11];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.numberOfLines = 3;
        [_blurView.contentView addSubview:_statusLabel];
    }
    return self;
}

- (void)showInView:(UIView *)parentView {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.alpha = 0.0;
        self.center = CGPointMake(parentView.bounds.size.width / 2, parentView.bounds.size.height / 2);
        [parentView addSubview:self];
        [parentView bringSubviewToFront:self];
        self.progressView.progress = 0.0;
        self.progressView.hidden = YES;
        self.feedbackIconLabel.hidden = YES;
        self.spinner.hidden = NO;
        [self.spinner startAnimating];
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1.0; }];
    });
}

- (void)updateProgress:(float)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (progress >= 0.0) {
            self.spinner.hidden = YES;
            [self.spinner stopAnimating];
            self.progressView.hidden = NO;
            self.progressView.progress = progress;
        }
        if (status) self.statusLabel.text = status;
    });
}

- (void)showSuccessWithStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.alpha = 1.0;
        self.spinner.hidden = YES;
        [self.spinner stopAnimating];
        self.progressView.hidden = YES;
        self.feedbackIconLabel.text = @"✓";
        self.feedbackIconLabel.textColor = [UIColor systemGreenColor];
        self.feedbackIconLabel.hidden = NO;
        if (status) self.statusLabel.text = status;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self dismiss]; });
    });
}

- (void)showError:(NSString *)errorMessage {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.alpha = 1.0;
        self.spinner.hidden = YES;
        [self.spinner stopAnimating];
        self.progressView.hidden = YES;
        self.feedbackIconLabel.text = @"✗";
        self.feedbackIconLabel.textColor = [UIColor systemRedColor];
        self.feedbackIconLabel.hidden = NO;
        self.statusLabel.text = errorMessage ?: @"Error.";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self dismiss]; });
    });
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0.0; } completion:^(BOOL finished) { [self removeFromSuperview]; }];
}
@end

// ============================================================================
// SERVER COMMUNICATION SERVICE
// ============================================================================
@interface YTDownloadManagerService : NSObject
@property (nonatomic, copy) void (^fileProgressCallback)(float progress);
+ (instancetype)sharedInstance;
- (void)requestDownloadForVideoId:(NSString *)vId isAudio:(BOOL)isAudio quality:(NSString *)quality completion:(void (^)(NSArray<NSURL *> *localURLs, NSString *errorMsg))completionBlock;
- (void)requestStreamURLForVideoId:(NSString *)vId completion:(void (^)(NSString *streamURL, NSString *errorMsg))completionBlock;
@end

@implementation YTDownloadManagerService
+ (instancetype)sharedInstance {
    static YTDownloadManagerService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSString *)serverEndpoint {
    return @"https://bass-bell.tunn3l.sh/"; 
}

- (void)requestDownloadForVideoId:(NSString *)vId isAudio:(BOOL)isAudio quality:(NSString *)quality completion:(void (^)(NSArray<NSURL *> *localURLs, NSString *errorMsg))completionBlock {
    NSString *watchURL = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", vId];
    NSString *resolvedFormatId = nil;
    
   if (isAudio) {
    resolvedFormatId = @"bestaudio[ext=m4a]/best";
} else {
      if ([quality isEqualToString:@"1080p"]) {
        resolvedFormatId = @"bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";
    } else if ([quality isEqualToString:@"720p"]) {
        resolvedFormatId = @"bestvideo[height<=720][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";
    } else if ([quality isEqualToString:@"360p"]) {
        resolvedFormatId = @"bestvideo[height<=360][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";
    } else {
        resolvedFormatId = @"bestvideo+bestaudio/best";
    }
}
    
    [self startYTDMDownloadWithWatchURL:watchURL format:isAudio ? @"audio" : @"video" formatId:resolvedFormatId completion:completionBlock];
}

- (void)requestStreamURLForVideoId:(NSString *)vId completion:(void (^)(NSString *streamURL, NSString *errorMsg))completionBlock {
    NSString *urlStr = [[self serverEndpoint] stringByAppendingString:@"/api/stream"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *payload = @{@"url": [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", vId]};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) { completionBlock(nil, @"Stream Connection Error"); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (json[@"stream_url"]) completionBlock(json[@"stream_url"], nil);
        else completionBlock(nil, json[@"error"] ?: @"Stream failed");
    }] resume];
}

- (void)startYTDMDownloadWithWatchURL:(NSString *)watchURL format:(NSString *)format formatId:(NSString *)formatId completion:(void (^)(NSArray<NSURL *> *localURLs, NSString *errorMsg))completionBlock {
    NSString *urlStr = [[self serverEndpoint] stringByAppendingString:@"/api/download"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSMutableDictionary *payload = [@{@"url": watchURL, @"format": format} mutableCopy];
    if (formatId) payload[@"format_id"] = formatId;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) { completionBlock(nil, @"Server unreachable."); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (json[@"job_id"]) [self pollJobStatus:json[@"job_id"] completion:completionBlock];
        else completionBlock(nil, json[@"error"] ?: @"Job init failed.");
    }] resume];
}

- (void)pollJobStatus:(NSString *)jobId completion:(void (^)(NSArray<NSURL *> *localURLs, NSString *errorMsg))completionBlock {
    NSString *urlStr = [NSString stringWithFormat:@"%@/api/status/%@", [self serverEndpoint], jobId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self pollJobStatus:jobId completion:completionBlock]; });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *status = json[@"status"];
        
        if ([status isEqualToString:@"done"]) {
            id filesData = json[@"files"] ?: json[@"filenames"] ?: json[@"filename"] ?: json[@"file_path"];
            NSMutableArray<NSString *> *filesToDownload = [NSMutableArray array];
            
            if ([filesData isKindOfClass:[NSArray class]]) {
                for (id fileItem in filesData) {
                    if ([fileItem isKindOfClass:[NSString class]]) [filesToDownload addObject:[fileItem lastPathComponent]];
                }
            } else if ([filesData isKindOfClass:[NSString class]]) {
                [filesToDownload addObject:[filesData lastPathComponent]];
            }
            
            if (filesToDownload.count == 0) {
                completionBlock(nil, @"No files found in job.");
                return;
            }
            
            [self downloadMultipleFiles:filesToDownload forJobId:jobId completion:completionBlock];
        } else if ([status isEqualToString:@"error"]) {
            completionBlock(nil, json[@"error"] ?: @"Mac Error.");
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [[YTDMProgressHUD sharedHUD] updateProgress:-1.0 status:@"Downloading on Mac..."]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self pollJobStatus:jobId completion:completionBlock]; });
        }
    }] resume];
}

- (void)downloadMultipleFiles:(NSArray<NSString *> *)filenames forJobId:(NSString *)jobId completion:(void (^)(NSArray<NSURL *> *localURLs, NSString *errorMsg))completionBlock {
    [[YTDMProgressHUD sharedHUD] updateProgress:0.0 status:[NSString stringWithFormat:@"Syncing files: 0/%lu", (unsigned long)filenames.count]];
    NSMutableArray<NSURL *> *localURLs = [NSMutableArray array];
    __block NSString *errStr = nil;
    NSUInteger totalCount = filenames.count;
    __block NSUInteger completedCount = 0;

    dispatch_group_t downloadGroup = dispatch_group_create();

    for (NSString *filename in filenames) {
        dispatch_group_enter(downloadGroup);
        NSString *encodedName = [filename stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlString = [NSString stringWithFormat:@"%@/api/file/%@?filename=%@", [self serverEndpoint], jobId, encodedName];
        
        [[[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:urlString] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (error || !location) {
                errStr = error.localizedDescription;
            } else {
                NSString *tempDir = NSTemporaryDirectory();
                NSURL *destURL = [NSURL fileURLWithPath:[tempDir stringByAppendingPathComponent:filename]];
                [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                
                if ([[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:nil]) {
                    @synchronized(localURLs) { [localURLs addObject:destURL]; }
                }
            }
            
            @synchronized(localURLs) {
                completedCount++;
                float progress = (float)completedCount / (float)totalCount;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[YTDMProgressHUD sharedHUD] updateProgress:progress status:[NSString stringWithFormat:@"Syncing files: %lu/%lu", (unsigned long)completedCount, (unsigned long)totalCount]];
                });
                if (self.fileProgressCallback) self.fileProgressCallback(progress);
            }
            dispatch_group_leave(downloadGroup);
        }] resume];
    }

    dispatch_group_notify(downloadGroup, dispatch_get_main_queue(), ^{
        if (localURLs.count > 0) {
            completionBlock(localURLs, nil);
        } else {
            completionBlock(nil, errStr ?: @"Download sync failed.");
        }
    });
}
@end

// ============================================================================
// DOWNLOAD QUEUE ENGINE
// ============================================================================
@interface YTDMDownloadQueueItem : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *videoTitle;
@property (nonatomic, assign) BOOL isAudio;
@property (nonatomic, copy) NSString *quality;
@property (nonatomic, copy) NSString *status; 
@property (nonatomic, assign) float currentProgress;
@property (nonatomic, strong) NSURL *savedSandboxURL; 
@end

@implementation YTDMDownloadQueueItem
@end

@interface YTDMDownloadQueueManager : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<YTDMDownloadQueueItem *> *videoDownloadQueue;
@property (nonatomic, strong) NSMutableArray<YTDMDownloadQueueItem *> *audioDownloadQueue;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) BOOL isCurrentlyReordering;

+ (instancetype)sharedInstance;
- (BOOL)enqueueVideoId:(NSString *)vId isAudio:(BOOL)isAudio quality:(NSString *)quality;
- (void)clearDownloadQueue;
- (void)removeItem:(YTDMDownloadQueueItem *)item;
- (void)startBatchDownloading;
- (void)moveItemFromSection:(NSInteger)sourceSection fromRow:(NSInteger)sourceRow toSection:(NSInteger)destSection toRow:(NSInteger)destRow;
- (void)cleanUpTemporaryFiles;
- (void)recalculateTitles;
@end

@implementation YTDMDownloadQueueManager
+ (instancetype)sharedInstance {
    static YTDMDownloadQueueManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _videoDownloadQueue = [NSMutableArray array];
        _audioDownloadQueue = [NSMutableArray array];
        _isDownloading = NO;
        _isCurrentlyReordering = NO;
    }
    return self;
}

- (void)recalculateTitles {
    for (NSUInteger i = 0; i < _videoDownloadQueue.count; i++) {
        YTDMDownloadQueueItem *item = _videoDownloadQueue[i];
        if (!item.quality) item.quality = @"720p";
        item.videoTitle = [NSString stringWithFormat:@"Video %lu (%@)", (unsigned long)(i + 1), item.quality];
    }
    for (NSUInteger i = 0; i < _audioDownloadQueue.count; i++) {
        YTDMDownloadQueueItem *item = _audioDownloadQueue[i];
        item.videoTitle = [NSString stringWithFormat:@"Audio %lu", (unsigned long)(i + 1)];
    }
}

- (void)clearDownloadQueue {
    @synchronized(self) {
        [self cleanUpTemporaryFiles];
        [_videoDownloadQueue removeAllObjects];
        [_audioDownloadQueue removeAllObjects];
    }
    if (!_isCurrentlyReordering) [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueUpdated" object:nil];
}

- (void)removeItem:(YTDMDownloadQueueItem *)item {
    @synchronized(self) {
        if (item.savedSandboxURL) [[NSFileManager defaultManager] removeItemAtURL:item.savedSandboxURL error:nil];
        [_videoDownloadQueue removeObject:item];
        [_audioDownloadQueue removeObject:item];
        [self recalculateTitles];
    }
    if (!_isCurrentlyReordering) [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueUpdated" object:nil];
}

- (BOOL)enqueueVideoId:(NSString *)vId isAudio:(BOOL)isAudio quality:(NSString *)quality {
    if (!vId) return NO;
    
    @synchronized(self) {
        YTDMDownloadQueueItem *item = [[YTDMDownloadQueueItem alloc] init];
        item.videoId = vId;
        item.isAudio = isAudio;
        item.quality = isAudio ? nil : quality;
        item.status = @"Waiting...";
        item.currentProgress = 0.0;
        
        if (isAudio) {
            if (_audioDownloadQueue.count >= 20) return NO;
            [_audioDownloadQueue addObject:item];
        } else {
            if (_videoDownloadQueue.count >= 20) return NO;
            [_videoDownloadQueue addObject:item];
        }
        [self recalculateTitles];
    }
    if (!_isCurrentlyReordering) [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueUpdated" object:nil];
    return YES;
}

- (void)moveItemFromSection:(NSInteger)sourceSection fromRow:(NSInteger)sourceRow toSection:(NSInteger)destSection toRow:(NSInteger)destRow {
    @synchronized(self) {
        _isCurrentlyReordering = YES; 
        NSMutableArray *sourceArray = (sourceSection == 0) ? _videoDownloadQueue : _audioDownloadQueue;
        NSMutableArray *destArray = (destSection == 0) ? _videoDownloadQueue : _audioDownloadQueue;
        
        if (sourceRow >= sourceArray.count) { _isCurrentlyReordering = NO; return; }
        YTDMDownloadQueueItem *movedItem = sourceArray[sourceRow];
        [sourceArray removeObjectAtIndex:sourceRow];
        
        movedItem.isAudio = (destSection == 1);
        if (movedItem.isAudio) {
            movedItem.quality = nil;
        } else {
            if (!movedItem.quality) movedItem.quality = @"720p"; 
        }
        
        if (destRow > destArray.count) destRow = destArray.count;
        [destArray insertObject:movedItem atIndex:destRow];
        
        [self recalculateTitles];
        _isCurrentlyReordering = NO;
    }
}

- (void)startBatchDownloading {
    @synchronized(self) {
        if (_isDownloading) return;
        _isDownloading = YES;
        
        for (YTDMDownloadQueueItem *item in _videoDownloadQueue) {
            item.status = @"Waiting...";
            item.currentProgress = 0.0;
            if (item.savedSandboxURL) { [[NSFileManager defaultManager] removeItemAtURL:item.savedSandboxURL error:nil]; item.savedSandboxURL = nil; }
        }
        for (YTDMDownloadQueueItem *item in _audioDownloadQueue) {
            item.status = @"Waiting...";
            item.currentProgress = 0.0;
            if (item.savedSandboxURL) { [[NSFileManager defaultManager] removeItemAtURL:item.savedSandboxURL error:nil]; item.savedSandboxURL = nil; }
        }
        
        [self processNext];
    }
}

- (void)processNext {
    @synchronized(self) {
        __block YTDMDownloadQueueItem *nextItem = nil;
        __block BOOL anyItemDownloading = NO;
        
        for (YTDMDownloadQueueItem *item in _videoDownloadQueue) {
            if ([item.status isEqualToString:@"Downloading..."]) { anyItemDownloading = YES; }
            if (!nextItem && [item.status isEqualToString:@"Waiting..."]) { nextItem = item; }
        }
        for (YTDMDownloadQueueItem *item in _audioDownloadQueue) {
            if ([item.status isEqualToString:@"Downloading..."]) { anyItemDownloading = YES; }
            if (!nextItem && [item.status isEqualToString:@"Waiting..."]) { nextItem = item; }
        }
        
        if (nextItem) {
            if (anyItemDownloading) return;
            
            nextItem.status = @"Downloading...";
            [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueUpdated" object:nil];
            
            [YTDownloadManagerService sharedInstance].fileProgressCallback = ^(float progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    nextItem.currentProgress = progress;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueProgressNotification" object:nextItem];
                });
            };
            
            [[YTDownloadManagerService sharedInstance] requestDownloadForVideoId:nextItem.videoId isAudio:nextItem.isAudio quality:nextItem.quality completion:^(NSArray<NSURL *> *localURLs, NSString *errorMsg) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (localURLs && localURLs.count > 0) {
                        NSURL *sourceURL = localURLs.firstObject;
                        NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
                        NSString *safePermanentPath = [cacheDir stringByAppendingPathComponent:sourceURL.lastPathComponent];
                        NSURL *permanentURL = [NSURL fileURLWithPath:safePermanentPath];
                        
                        [[NSFileManager defaultManager] removeItemAtURL:permanentURL error:nil];
                        if ([[NSFileManager defaultManager] moveItemAtURL:sourceURL toURL:permanentURL error:nil]) {
                            nextItem.savedSandboxURL = permanentURL;
                            nextItem.status = @"Completed";
                            nextItem.currentProgress = 1.0;
                        } else {
                            nextItem.status = @"Storage Error";
                        }
                    } else {
                        nextItem.status = @"Failed";
                    }
                    
                    // FIXED: Removed the duplicate [.defaultCenter] call that broken the block compilation structure
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTDMDownloadQueueUpdated" object:nil];
                    [self processNext]; 
                });
            }];
        } else {
            if (anyItemDownloading) return;
            _isDownloading = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ [self finalizeBatchProcess]; });
        }
    }
}

- (void)finalizeBatchProcess {
    [[YTDMProgressHUD sharedHUD] dismiss];
    
    NSMutableArray<NSURL *> *finalStandardVideoURLs = [NSMutableArray array];
    NSMutableArray<NSURL *> *finalHighResVideoURLs = [NSMutableArray array];
    NSMutableArray<NSURL *> *finalAudioURLs = [NSMutableArray array];
    
    @synchronized(self) {
        for (YTDMDownloadQueueItem *item in _videoDownloadQueue) {
            if ([item.status isEqualToString:@"Completed"] && item.savedSandboxURL) {
                BOOL isHighRes = [item.quality isEqualToString:@"2K"] || [item.quality isEqualToString:@"4K"] || [item.quality isEqualToString:@"6K"];
                if (isHighRes) {
                    [finalHighResVideoURLs addObject:item.savedSandboxURL];
                } else {
                    [finalStandardVideoURLs addObject:item.savedSandboxURL];
                }
            }
        }
        for (YTDMDownloadQueueItem *item in _audioDownloadQueue) {
            if ([item.status isEqualToString:@"Completed"] && item.savedSandboxURL) [finalAudioURLs addObject:item.savedSandboxURL];
        }
    }
    
    NSMutableArray<NSURL *> *combinedAllURLs = [NSMutableArray arrayWithArray:finalStandardVideoURLs];
    [combinedAllURLs addObjectsFromArray:finalHighResVideoURLs];
    [combinedAllURLs addObjectsFromArray:finalAudioURLs];
    
    if (combinedAllURLs.count == 0) return;
    
    UIViewController *topMost = getTopMostController();
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Queue Downloads Completed!" message:@"Choose how to export your batch files:" preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Note: This option only appears if standard clips (360p, 720p, 1080p) are downloaded and will strictly save those compatible items
    if (finalStandardVideoURLs.count > 0) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"📸 Save Standard Videos to Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];
            __block NSInteger remainingPhotos = finalStandardVideoURLs.count;
            __block NSString *lastErrorMessage = nil;
            
            for (NSURL *vURL in finalStandardVideoURLs) {
                [YTDMPhotoSaver saveVideoPath:vURL.path completion:^(BOOL success, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (!success) {
                            lastErrorMessage = error.localizedDescription;
                        }
                        remainingPhotos--;
                        if (remainingPhotos == 0) {
                            if (!lastErrorMessage) {
                                [[YTDMProgressHUD sharedHUD] showSuccessWithStatus:@"Saved to Gallery!"];
                            } else {
                                [[YTDMProgressHUD sharedHUD] showError:[NSString stringWithFormat:@"Error: %@", lastErrorMessage]];
                            }
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                [self cleanUpTemporaryFiles];
                            });
                        }
                    });
                }];
            }
        }]];
    }
    
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📁 Save All to Files (Document Picker)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (@available(iOS 14.0, *)) {
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:combinedAllURLs asCopy:YES];
            picker.delegate = self; 
            objc_setAssociatedObject(picker, &kAssociatedOutURLKey, combinedAllURLs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [topMost presentViewController:picker animated:YES completion:nil];
        }
    }]];
    
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔗 Open Share Sheet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:combinedAllURLs applicationActivities:nil];
        share.completionWithItemsHandler = ^(UIActivityType actType, BOOL completed, NSArray *retItems, NSError *err) {
            [self cleanUpTemporaryFiles];
        };
        [topMost presentViewController:share animated:YES completion:nil];
    }]];
    
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel & Clear Temp" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [self cleanUpTemporaryFiles];
    }]];
    
    [topMost presentViewController:actionSheet animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { [self cleanUpTemporaryFiles]; }
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self cleanUpTemporaryFiles]; }

- (void)cleanUpTemporaryFiles {
    @synchronized(self) {
        for (YTDMDownloadQueueItem *item in _videoDownloadQueue) {
            if (item.savedSandboxURL) { [[NSFileManager defaultManager] removeItemAtURL:item.savedSandboxURL error:nil]; item.savedSandboxURL = nil; }
        }
        for (YTDMDownloadQueueItem *item in _audioDownloadQueue) {
            if (item.savedSandboxURL) { [[NSFileManager defaultManager] removeItemAtURL:item.savedSandboxURL error:nil]; item.savedSandboxURL = nil; }
        }
    }
}
@end

// ============================================================================
// DOWNLOAD QUEUE INSPECTOR INTERFACE
// ============================================================================
@interface YTDMDownloadQueueViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation YTDMDownloadQueueViewController
- (void)viewDidLoad {
    // FIXED: Removed the stray '[super iPad]' statement caused by a likely typo/autocorrect context mismatch
    [super viewDidLoad];
    self.title = @"Download Queue Inspector";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    
    UIBarButtonItem *downloadAllBtn = [[UIBarButtonItem alloc] initWithTitle:@"Download All" style:UIBarButtonItemStylePlain target:self action:@selector(triggerDownloadBatch)];
    downloadAllBtn.tintColor = [UIColor systemGreenColor];
    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Clear All" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    self.navigationItem.rightBarButtonItems = @[clearBtn, downloadAllBtn];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView setEditing:YES animated:NO]; 
    [self.view addSubview:self.tableView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadQueueData) name:@"YTDMDownloadQueueUpdated" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleProgressNotification:) name:@"YTDMDownloadQueueProgressNotification" object:nil];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)reloadQueueData { if ([YTDMDownloadQueueManager sharedInstance].isCurrentlyReordering) return; dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; }); }

- (void)handleProgressNotification:(NSNotification *)notification {
    YTDMDownloadQueueItem *updatedItem = (YTDMDownloadQueueItem *)notification.object;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UITableViewCell *cell in self.tableView.visibleCells) {
            UILabel *titleContext = [cell.contentView viewWithTag:8822];
            if (titleContext && [titleContext.text isEqualToString:updatedItem.videoTitle]) {
                UIProgressView *pv = [cell.contentView viewWithTag:8821];
                UILabel *statusLbl = (UILabel *)cell.accessoryView;
                if (pv) { pv.hidden = NO; [pv setProgress:updatedItem.currentProgress animated:YES]; }
                if (statusLbl) statusLbl.text = [NSString stringWithFormat:@"%.0f%%", updatedItem.currentProgress * 100.0];
            }
        }
    });
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)clearAll { [[YTDMDownloadQueueManager sharedInstance] clearDownloadQueue]; }
- (void)triggerDownloadBatch {
    [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];
    [[YTDMProgressHUD sharedHUD] updateProgress:0.0 status:@"Syncing Download Queue..."];
    [[YTDMDownloadQueueManager sharedInstance] startBatchDownloading];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? [YTDMDownloadQueueManager sharedInstance].videoDownloadQueue.count : [YTDMDownloadQueueManager sharedInstance].audioDownloadQueue.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return [YTDMDownloadQueueManager sharedInstance].videoDownloadQueue.count > 0 ? @"📹 Video Download Queue" : nil;
    return [YTDMDownloadQueueManager sharedInstance].audioDownloadQueue.count > 0 ? @"🎵 Audio Download Queue" : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 65.0; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"OptimizedQueueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    UILabel *titleLabel = nil; UIProgressView *progressView = nil; UILabel *statusLabel = nil;
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.showsReorderControl = YES;
        titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, cell.contentView.frame.size.width - 150, 20)];
        titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        titleLabel.tag = 8822;
        [cell.contentView addSubview:titleLabel];
        
        progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        progressView.frame = CGRectMake(16, 44, cell.contentView.frame.size.width - 140, 4);
        progressView.progressTintColor = [UIColor systemBlueColor];
        progressView.tag = 8821;
        [cell.contentView addSubview:progressView];
        
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.contentView.frame.size.width - 120, 15, 100, 30)];
        statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        statusLabel.textAlignment = NSTextAlignmentRight;
        cell.accessoryView = statusLabel;
    } else {
        titleLabel = [cell.contentView viewWithTag:8822]; progressView = [cell.contentView viewWithTag:8821]; statusLabel = (UILabel *)cell.accessoryView;
    }
    
    YTDMDownloadQueueItem *item = (indexPath.section == 0) ? [YTDMDownloadQueueManager sharedInstance].videoDownloadQueue[indexPath.row] : [YTDMDownloadQueueManager sharedInstance].audioDownloadQueue[indexPath.row];
    titleLabel.text = item.videoTitle;
    
    if ([item.status isEqualToString:@"Downloading..."]) {
        statusLabel.text = [NSString stringWithFormat:@"%.0f%%", item.currentProgress * 100.0];
        statusLabel.textColor = [UIColor systemGreenColor];
        progressView.hidden = NO;
    } else {
        statusLabel.text = item.status;
        statusLabel.textColor = [item.status isEqualToString:@"Completed"] ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        progressView.hidden = ![item.status isEqualToString:@"Completed"];
    }
    [progressView setProgress:item.currentProgress animated:NO];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    [[YTDMDownloadQueueManager sharedInstance] moveItemFromSection:sourceIndexPath.section fromRow:sourceIndexPath.row toSection:destinationIndexPath.section toRow:destinationIndexPath.row];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        YTDMDownloadQueueItem *item = (indexPath.section == 0) ? [YTDMDownloadQueueManager sharedInstance].videoDownloadQueue[indexPath.row] : [YTDMDownloadQueueManager sharedInstance].audioDownloadQueue[indexPath.row];
        [[YTDMDownloadQueueManager sharedInstance] removeItem:item];
    }
}
@end

// ============================================================================
// STABLE VIDEO ID CAPTURE
// ============================================================================
%hook YTSingleVideo
- (NSString *)videoId { NSString *vId = %orig; if (vId.length > 0) capturedVideoId = [vId copy]; return vId; }
%end

// ============================================================================
// CONTROLS OVERLAY HOOK
// ============================================================================
@interface YTMainAppControlsOverlayView : UIView
- (UIViewController *)ytdm_parentViewController;
- (void)ytdm_openDownloadQueueInspector;
- (void)ytdm_triggerSilentDownloadWithQuality:(NSString *)quality isAudio:(BOOL)isAudio;
- (void)ytdm_presentSaveOptionsForURLs:(NSArray<NSURL *> *)outURLs isAudio:(BOOL)isAudio quality:(NSString *)quality;
- (void)ytdm_copyToClipboardWithText:(NSString *)text alertMsg:(NSString *)alertMsg;
- (void)ytdm_playInSystemPlayer;
- (void)ytdm_downloadThumbnail;
@end

%hook YTMainAppControlsOverlayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIButton *downloadBtn = [self viewWithTag:9912];
    if (downloadBtn && !downloadBtn.hidden && downloadBtn.alpha > 0.01) {
        CGPoint localPoint = [downloadBtn convertPoint:point fromView:self];
        if ([downloadBtn pointInside:localPoint withEvent:event]) return downloadBtn;
    }
    return %orig;
}

- (void)layoutSubviews {
    %orig;
    UIButton *downloadBtn = [self viewWithTag:9912];
    if (!downloadBtn) {
        downloadBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        downloadBtn.tag = 9912;
        [downloadBtn setTitle:@"⬇️" forState:UIControlStateNormal];
        downloadBtn.titleLabel.font = [UIFont systemFontOfSize:14];
        downloadBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        downloadBtn.layer.cornerRadius = 16;
        downloadBtn.userInteractionEnabled = YES;
        
        if (@available(iOS 14.0, *)) {
            downloadBtn.showsMenuAsPrimaryAction = YES;
            __weak typeof(self) weakSelf = self;
            

            UIAction *v1080 = [UIAction actionWithTitle:@"Video (1080p)" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_triggerSilentDownloadWithQuality:@"1080p" isAudio:NO]; }];
            UIAction *v720 = [UIAction actionWithTitle:@"Video (720p)" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_triggerSilentDownloadWithQuality:@"720p" isAudio:NO]; }];
            UIAction *v360 = [UIAction actionWithTitle:@"Video (360p)" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_triggerSilentDownloadWithQuality:@"360p" isAudio:NO]; }];
            UIAction *audioOnly = [UIAction actionWithTitle:@"Audio Only" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_triggerSilentDownloadWithQuality:nil isAudio:YES]; }];
            UIMenu *instantMenu = [UIMenu menuWithTitle:@"Direct Download" children:@[v1080, v720, v360, audioOnly]];

            UIAction *viewQueue = [UIAction actionWithTitle:@"Open Download Queue Inspector" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_openDownloadQueueInspector]; }];
            UIAction *q1080 = [UIAction actionWithTitle:@"Add Video (1080p) to Download Queue" image:nil identifier:nil handler:^(UIAction *a) { [[YTDMDownloadQueueManager sharedInstance] enqueueVideoId:capturedVideoId isAudio:NO quality:@"1080p"]; }];
            UIAction *q720 = [UIAction actionWithTitle:@"Add Video (720p) to Download Queue" image:nil identifier:nil handler:^(UIAction *a) { [[YTDMDownloadQueueManager sharedInstance] enqueueVideoId:capturedVideoId isAudio:NO quality:@"720p"]; }];
            UIAction *q360 = [UIAction actionWithTitle:@"Add Video (360p) to Download Queue" image:nil identifier:nil handler:^(UIAction *a) { [[YTDMDownloadQueueManager sharedInstance] enqueueVideoId:capturedVideoId isAudio:NO quality:@"360p"]; }];
            UIAction *audioQueue = [UIAction actionWithTitle:@"Add Audio to Download Queue" image:nil identifier:nil handler:^(UIAction *a) { [[YTDMDownloadQueueManager sharedInstance] enqueueVideoId:capturedVideoId isAudio:YES quality:nil]; }];
            UIMenu *queueMenu = [UIMenu menuWithTitle:@"Download Queue System" children:@[viewQueue, q1080, q720, q360, audioQueue]];
            
            UIAction *playSys = [UIAction actionWithTitle:@"Play in System Player" image:[UIImage systemImageNamed:@"play.fill"] identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_playInSystemPlayer]; }];
            UIAction *dlThumb = [UIAction actionWithTitle:@"Download Thumbnail" image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction *a) { [weakSelf ytdm_downloadThumbnail]; }];
            
            UIAction *copyLink = [UIAction actionWithTitle:@"Copy Video Link" image:nil identifier:nil handler:^(UIAction *a) {
                if (capturedVideoId) [weakSelf ytdm_copyToClipboardWithText:[NSString stringWithFormat:@"https://youtu.be/%@", capturedVideoId] alertMsg:@"Copied Link!"];
            }];

            downloadBtn.menu = [UIMenu menuWithTitle:@"YTDM Suite" children:@[instantMenu, queueMenu, playSys, dlThumb, copyLink]];
        }
        [self addSubview:downloadBtn];
    }
    downloadBtn.frame = CGRectMake(12, 120, 32, 32);
    [self bringSubviewToFront:downloadBtn];
}

%new - (UIViewController *)ytdm_parentViewController {
    UIResponder *responder = self;
    while ([responder nextResponder]) {
        responder = [responder nextResponder];
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
    }
    return nil;
}

%new - (void)ytdm_openDownloadQueueInspector {
    YTDMDownloadQueueViewController *queueVC = [[YTDMDownloadQueueViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:queueVC];
    [[self ytdm_parentViewController] ?: getTopMostController() presentViewController:nav animated:YES completion:nil];
}

%new - (void)ytdm_triggerSilentDownloadWithQuality:(NSString *)quality isAudio:(BOOL)isAudio {
    if (capturedVideoId.length == 0) { [[YTDMProgressHUD sharedHUD] showError:@"No context."]; return; }
    [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];
    
    [[YTDownloadManagerService sharedInstance] requestDownloadForVideoId:capturedVideoId isAudio:isAudio quality:quality completion:^(NSArray<NSURL *> *localURLs, NSString *errorMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!localURLs) { [[YTDMProgressHUD sharedHUD] showError:errorMsg]; return; }
            [[YTDMProgressHUD sharedHUD] showSuccessWithStatus:@"Complete!"];
            [self ytdm_presentSaveOptionsForURLs:localURLs isAudio:isAudio quality:quality];
        });
    }];
}

%new - (void)ytdm_presentSaveOptionsForURLs:(NSArray<NSURL *> *)outURLs
                                   isAudio:(BOOL)isAudio
                                   quality:(NSString *)quality
{
    UIViewController *topController = [self ytdm_parentViewController] ?: getTopMostController();

    UIAlertController *actionSheet =
    [UIAlertController alertControllerWithTitle:@"Download Completed!"
                                        message:@"Choose how to export your file:"
                                 preferredStyle:UIAlertControllerStyleActionSheet];

    // Save to Photos (video only)
    if (!isAudio) {

        [actionSheet addAction:[UIAlertAction actionWithTitle:@"📸 Save to Photos"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *a) {

            NSURL *targetURL = outURLs.firstObject;

            [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];

            [YTDMPhotoSaver saveVideoPath:targetURL.path
                               completion:^(BOOL success, NSError *error) {

                dispatch_async(dispatch_get_main_queue(), ^{

                    if (success) {
                        [[YTDMProgressHUD sharedHUD] showSuccessWithStatus:@"Saved to Gallery!"];
                    } else {
                        NSString *msg =
                        [NSString stringWithFormat:@"Error: %@",
                         error.localizedDescription ?: @"Unknown"];

                        [[YTDMProgressHUD sharedHUD] showError:msg];
                    }

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(2.0 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{

                        for (NSURL *url in outURLs) {
                            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
                        }

                    });

                });

            }];

        }]];
    }

    // Save to Files
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📁 Save to Files"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *a) {

        if (@available(iOS 14.0, *)) {

            UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForExportingURLs:outURLs
                                                                  asCopy:YES];

            picker.delegate = [YTDMDownloadQueueManager sharedInstance];

            objc_setAssociatedObject(
                picker,
                &kAssociatedOutURLKey,
                outURLs,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [topController presentViewController:picker
                                        animated:YES
                                      completion:nil];
        }

    }]];

    // Share Sheet
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔗 Open Share Sheet"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *a) {

        UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:outURLs
                                          applicationActivities:nil];

        share.completionWithItemsHandler =
        ^(UIActivityType activityType,
          BOOL completed,
          NSArray *returnedItems,
          NSError *activityError) {

            for (NSURL *url in outURLs) {
                [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            }

        };

        [topController presentViewController:share
                                    animated:YES
                                  completion:nil];

    }]];

    // Cancel
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:^(UIAlertAction *a) {

        for (NSURL *url in outURLs) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }

    }]];

    [topController presentViewController:actionSheet
                                animated:YES
                              completion:nil];
}

%new - (void)ytdm_playInSystemPlayer {
    if (capturedVideoId.length == 0) { [[YTDMProgressHUD sharedHUD] showError:@"No context."]; return; }
    [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];
    [[YTDMProgressHUD sharedHUD] updateProgress:-1.0 status:@"Fetching stream..."];

    [[YTDownloadManagerService sharedInstance] requestStreamURLForVideoId:capturedVideoId completion:^(NSString *streamURL, NSString *errorMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!streamURL) { [[YTDMProgressHUD sharedHUD] showError:errorMsg]; return; }
            [[YTDMProgressHUD sharedHUD] dismiss];

            NSURL *url = [NSURL URLWithString:streamURL];
            AVPlayer *player = [AVPlayer playerWithURL:url];
            AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
            playerViewController.player = player;

            UIViewController *topController = [self ytdm_parentViewController] ?: getTopMostController();
            [topController presentViewController:playerViewController animated:YES completion:^{ [playerViewController.player play]; }];
        });
    }];
}

%new - (void)ytdm_downloadThumbnail {
    if (capturedVideoId.length == 0) { [[YTDMProgressHUD sharedHUD] showError:@"No context."]; return; }
    [[YTDMProgressHUD sharedHUD] showInView:getKeyWindow()];
    [[YTDMProgressHUD sharedHUD] updateProgress:-1.0 status:@"Downloading thumbnail..."];

    NSString *thumbURLStr = [NSString stringWithFormat:@"https://img.youtube.com/vi/%@/maxresdefault.jpg", capturedVideoId];
    NSURL *thumbURL = [NSURL URLWithString:thumbURLStr];

    [[[NSURLSession sharedSession] downloadTaskWithURL:thumbURL completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !location) { [[YTDMProgressHUD sharedHUD] showError:@"Failed to get thumbnail."]; return; }
            NSData *data = [NSData dataWithContentsOfURL:location];
            UIImage *image = [UIImage imageWithData:data];
            if (!image) { [[YTDMProgressHUD sharedHUD] showError:@"Invalid image data."]; return; }

            [YTDMImageSaver saveImage:image completion:^(BOOL success, NSError *phError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [[YTDMProgressHUD sharedHUD] showSuccessWithStatus:@"Thumbnail Saved!"];
                    } else {
                        NSString *fullError = [NSString stringWithFormat:@"Failed: %@", phError.localizedDescription ?: @"Unknown"];
                        [[YTDMProgressHUD sharedHUD] showError:fullError];
                    }
                });
            }];
        });
    }] resume];
}

%new - (void)ytdm_copyToClipboardWithText:(NSString *)text alertMsg:(NSString *)alertMsg {
    if (text) { [UIPasteboard generalPasteboard].string = text; [[YTDMProgressHUD sharedHUD] showSuccessWithStatus:alertMsg]; }
}
%end

// ============================================================================
// ATS BYPASS
// ============================================================================
%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSDictionary *origDict = %orig;
    if (origDict) {
        NSMutableDictionary *m = [origDict mutableCopy];
        NSMutableDictionary *ats = [m[@"NSAppTransportSecurity"] mutableCopy] ?: [NSMutableDictionary dictionary];
        ats[@"NSAllowsArbitraryLoads"] = @YES; m[@"NSAppTransportSecurity"] = ats; return m;
    }
    return origDict;
}
%end