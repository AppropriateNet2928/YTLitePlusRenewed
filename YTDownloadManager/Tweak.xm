#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <YouTubeHeader/YTIcon.h>
#import "YTDMDownloadsManager.h"
#import "YTDMDownloadsViewController.h"
#import "YTDMPlayerViewController.h"

static char kAssociatedOutURLKey;
static NSString *capturedVideoId = nil;

// ============================================================================
// WINDOW HELPERS
// ============================================================================

static UIWindow *getKeyWindow(void) {

    UIWindow *keyWindow = nil;

    for (UIScene *scene
         in [UIApplication sharedApplication].connectedScenes) {

        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive) {

            for (UIWindow *window
                 in [(UIWindowScene *)scene windows]) {

                if (window.isKeyWindow) {

                    keyWindow = window;
                    break;
                }
            }
        }

        if (keyWindow) {
            break;
        }
    }

    if (!keyWindow) {

        for (UIWindow *window
             in [UIApplication sharedApplication].windows) {

            if (window.isKeyWindow) {

                keyWindow = window;
                break;
            }
        }
    }

    return keyWindow ?:
        [UIApplication sharedApplication]
            .windows.firstObject;
}

static UIViewController *getTopMostController(void) {

    UIWindow *window = getKeyWindow();

    if (!window) {
        return nil;
    }

    UIViewController *root =
        window.rootViewController;

    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    return root;
}

// ============================================================================
// PHOTO / VIDEO SAVER
// ============================================================================

@interface YTDMPhotoSaver : NSObject

+ (void)saveVideoPath:(NSString *)path
          completion:(void (^)(BOOL success,
                               NSError *error))completion;

@end

@implementation YTDMPhotoSaver

+ (void)saveVideoPath:(NSString *)path
          completion:(void (^)(BOOL success,
                               NSError *error))completion {

    NSURL *fileURL =
        [NSURL fileURLWithPath:path];

    [PHPhotoLibrary
        requestAuthorization:
        ^(PHAuthorizationStatus status) {

        if (status ==
                PHAuthorizationStatusAuthorized ||
            status ==
                PHAuthorizationStatusLimited) {

            [[PHPhotoLibrary
                sharedPhotoLibrary]
                performChanges:^{

                [PHAssetChangeRequest
                    creationRequestForAssetFromVideoAtFileURL:
                        fileURL];

            } completionHandler:
            ^(BOOL success,
              NSError * _Nullable error) {

                if (completion) {
                    completion(success, error);
                }
            }];

        } else {

            NSError *customError =
                [NSError
                    errorWithDomain:
                        @"YTDMError"
                    code:
                        403
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"Photo Auth Denied (Check LiveContainer Settings)"
                    }];

            if (completion) {
                completion(NO, customError);
            }
        }
    }];
}

@end

// ============================================================================
// IMAGE SAVER
// ============================================================================

@interface YTDMImageSaver : NSObject

+ (void)saveImage:(UIImage *)image
      completion:(void (^)(BOOL success,
                           NSError *error))completion;

@end

@implementation YTDMImageSaver

+ (void)saveImage:(UIImage *)image
      completion:(void (^)(BOOL success,
                           NSError *error))completion {

    [PHPhotoLibrary
        requestAuthorization:
        ^(PHAuthorizationStatus status) {

        if (status ==
                PHAuthorizationStatusAuthorized ||
            status ==
                PHAuthorizationStatusLimited) {

            [[PHPhotoLibrary
                sharedPhotoLibrary]
                performChanges:^{

                [PHAssetChangeRequest
                    creationRequestForAssetFromImage:
                        image];

            } completionHandler:
            ^(BOOL success,
              NSError * _Nullable error) {

                if (completion) {
                    completion(success, error);
                }
            }];

        } else {

            NSError *customError =
                [NSError
                    errorWithDomain:
                        @"YTDMError"
                    code:
                        403
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"Photo Auth Denied (Check LiveContainer Settings)"
                    }];

            if (completion) {
                completion(NO, customError);
            }
        }
    }];
}

@end

// ============================================================================
// ANIMATED PROGRESS HUD
// ============================================================================

@interface YTDMProgressHUD : UIView

@property (nonatomic, strong)
UIVisualEffectView *blurView;

@property (nonatomic, strong)
UILabel *titleLabel;

@property (nonatomic, strong)
UILabel *statusLabel;

@property (nonatomic, strong)
UIProgressView *progressView;

@property (nonatomic, strong)
UIActivityIndicatorView *spinner;

@property (nonatomic, strong)
UILabel *feedbackIconLabel;

+ (instancetype)sharedHUD;

- (void)showInView:(UIView *)parentView;

- (void)updateProgress:(float)progress
                status:(NSString *)status;

- (void)showSuccessWithStatus:(NSString *)status;

- (void)showError:(NSString *)errorMessage;

- (void)dismiss;

@end

@implementation YTDMProgressHUD

+ (instancetype)sharedHUD {

    static YTDMProgressHUD *shared = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

        shared =
            [[self alloc]
                initWithFrame:
                    CGRectMake(0, 0, 280, 180)];
    });

    return shared;
}

- (instancetype)initWithFrame:(CGRect)frame {

    self =
        [super initWithFrame:frame];

    if (self) {

        self.layer.cornerRadius = 18;
        self.layer.masksToBounds = YES;

        UIBlurEffect *blurEffect =
            [UIBlurEffect
                effectWithStyle:
                    UIBlurEffectStyleDark];

        _blurView =
            [[UIVisualEffectView alloc]
                initWithEffect:
                    blurEffect];

        _blurView.frame =
            self.bounds;

        [self addSubview:_blurView];

        _spinner =
            [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:
                    UIActivityIndicatorViewStyleLarge];

        _spinner.color =
            [UIColor whiteColor];

        _spinner.center =
            CGPointMake(
                frame.size.width / 2,
                45);

        [_blurView.contentView
            addSubview:_spinner];

        _feedbackIconLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        0,
                        15,
                        frame.size.width,
                        60)];

        _feedbackIconLabel.textColor =
            [UIColor whiteColor];

        _feedbackIconLabel.font =
            [UIFont systemFontOfSize:
                50
                         weight:
                UIFontWeightMedium];

        _feedbackIconLabel.textAlignment =
            NSTextAlignmentCenter;

        _feedbackIconLabel.hidden =
            YES;

        [_blurView.contentView
            addSubview:
                _feedbackIconLabel];

        _titleLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        10,
                        85,
                        frame.size.width - 20,
                        20)];

        _titleLabel.text =
            @"YTDM Pro Engine";

        _titleLabel.textColor =
            [UIColor whiteColor];

        _titleLabel.font =
            [UIFont boldSystemFontOfSize:15];

        _titleLabel.textAlignment =
            NSTextAlignmentCenter;

        [_blurView.contentView
            addSubview:
                _titleLabel];

        _progressView =
            [[UIProgressView alloc]
                initWithProgressViewStyle:
                    UIProgressViewStyleDefault];

        _progressView.frame =
            CGRectMake(
                25,
                115,
                frame.size.width - 50,
                4);

        _progressView.progressTintColor =
            [UIColor systemGreenColor];

        _progressView.trackTintColor =
            [[UIColor whiteColor]
                colorWithAlphaComponent:0.2];

        _progressView.hidden =
            YES;

        [_blurView.contentView
            addSubview:
                _progressView];

        _statusLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        10,
                        122,
                        frame.size.width - 20,
                        48)];

        _statusLabel.text =
            @"Synchronizing...";

        _statusLabel.textColor =
            [[UIColor whiteColor]
                colorWithAlphaComponent:0.9];

        _statusLabel.font =
            [UIFont systemFontOfSize:11];

        _statusLabel.textAlignment =
            NSTextAlignmentCenter;

        _statusLabel.numberOfLines = 3;

        [_blurView.contentView
            addSubview:
                _statusLabel];
    }

    return self;
}

- (void)showInView:(UIView *)parentView {

    dispatch_async(
        dispatch_get_main_queue(), ^{

        self.alpha = 0.0;

        self.center =
            CGPointMake(
                parentView.bounds.size.width / 2,
                parentView.bounds.size.height / 2);

        [parentView
            addSubview:self];

        [parentView
            bringSubviewToFront:self];

        self.progressView.progress = 0.0;
        self.progressView.hidden = YES;

        self.feedbackIconLabel.hidden = YES;

        self.spinner.hidden = NO;

        [self.spinner startAnimating];

        [UIView
            animateWithDuration:0.2
            animations:^{

            self.alpha = 1.0;
        }];
    });
}

- (void)updateProgress:(float)progress
                status:(NSString *)status {

    dispatch_async(
        dispatch_get_main_queue(), ^{

        if (progress >= 0.0) {

            self.spinner.hidden = YES;

            [self.spinner
                stopAnimating];

            self.progressView.hidden = NO;

            self.progressView.progress =
                progress;
        }

        if (status) {
            self.statusLabel.text =
                status;
        }
    });
}

- (void)showSuccessWithStatus:(NSString *)status {

    dispatch_async(
        dispatch_get_main_queue(), ^{

        self.alpha = 1.0;

        self.spinner.hidden = YES;

        [self.spinner
            stopAnimating];

        self.progressView.hidden = YES;

        self.feedbackIconLabel.text =
            @"✓";

        self.feedbackIconLabel.textColor =
            [UIColor systemGreenColor];

        self.feedbackIconLabel.hidden =
            NO;

        if (status) {
            self.statusLabel.text =
                status;
        }

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)
                    (1.5 *
                     NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{

            [self dismiss];
        });
    });
}

- (void)showError:(NSString *)errorMessage {

    dispatch_async(
        dispatch_get_main_queue(), ^{

        self.alpha = 1.0;

        self.spinner.hidden = YES;

        [self.spinner
            stopAnimating];

        self.progressView.hidden = YES;

        self.feedbackIconLabel.text =
            @"✗";

        self.feedbackIconLabel.textColor =
            [UIColor systemRedColor];

        self.feedbackIconLabel.hidden =
            NO;

        self.statusLabel.text =
            errorMessage ?: @"Error.";

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)
                    (3.5 *
                     NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{

            [self dismiss];
        });
    });
}

- (void)dismiss {

    [UIView
        animateWithDuration:0.2
        animations:^{

        self.alpha = 0.0;

    } completion:^(BOOL finished) {

        [self removeFromSuperview];
    }];
}

@end

// ============================================================================
// FORWARD DECLARATION
// ============================================================================

@class YTDMStreamingFileDownloader;

// ============================================================================
// RESUMABLE STREAMING FILE DOWNLOADER
// ============================================================================

@interface YTDMStreamingFileDownloader :
NSObject <NSURLSessionDataDelegate>

@property (nonatomic, strong)
NSURLSession *session;

@property (nonatomic, strong)
NSURLSessionDataTask *task;

@property (nonatomic, strong)
NSOutputStream *outputStream;

@property (nonatomic, strong)
NSURL *destinationURL;

@property (nonatomic, strong)
NSURL *remoteURL;

@property (nonatomic, copy)
void (^completion)(NSURL *fileURL,
                   NSError *error);

@property (nonatomic, assign)
int64_t receivedBytes;

@property (nonatomic, assign)
int64_t expectedTotalBytes;

@property (nonatomic, assign)
BOOL responseAccepted;

@property (nonatomic, assign)
BOOL finished;

@property (nonatomic, assign)
BOOL retryScheduled;

@property (nonatomic, assign)
NSInteger retryCount;

@property (nonatomic, assign)
NSInteger maxRetries;

- (void)startWithURL:(NSURL *)url
     destinationURL:(NSURL *)destinationURL
          completion:(void (^)(NSURL *fileURL,
                               NSError *error))completion;

@end

@implementation YTDMStreamingFileDownloader

// ============================================================================
// START
// ============================================================================

- (void)startWithURL:(NSURL *)url
     destinationURL:(NSURL *)destinationURL
          completion:(void (^)(NSURL *fileURL,
                               NSError *error))completion {

    self.remoteURL =
        url;

    self.destinationURL =
        destinationURL;

    self.completion =
        completion;

    self.receivedBytes =
        0;

    self.expectedTotalBytes =
        NSURLSessionTransferSizeUnknown;

    self.responseAccepted =
        NO;

    self.finished =
        NO;

    self.retryScheduled =
        NO;

    self.retryCount =
        0;

    self.maxRetries =
        5;

    [[NSFileManager defaultManager]
        removeItemAtURL:
            destinationURL
        error:nil];

    [self startRequestFromOffset:
        0
        truncate:YES];
}

// ============================================================================
// START REQUEST
// ============================================================================

- (void)startRequestFromOffset:(int64_t)offset
                       truncate:(BOOL)truncate {

    if (self.finished) {
        return;
    }

    self.responseAccepted =
        NO;

    if (truncate) {

        [[NSFileManager defaultManager]
            removeItemAtURL:
                self.destinationURL
            error:nil];

        self.receivedBytes =
            0;

        self.expectedTotalBytes =
            NSURLSessionTransferSizeUnknown;
    }

    self.outputStream =
        [NSOutputStream
            outputStreamWithURL:
                self.destinationURL
            append:
                (offset > 0)];

    if (!self.outputStream) {

        [self finishWithURL:
            nil
            error:
                [NSError
                    errorWithDomain:
                        @"YTDMDownload"
                    code:
                        1001
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"Could not create the local download file."
                        }]];

        return;
    }

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration
            defaultSessionConfiguration];

    configuration.timeoutIntervalForRequest =
        60.0;

    configuration.timeoutIntervalForResource =
        24.0 *
        60.0 *
        60.0;

    configuration.requestCachePolicy =
        NSURLRequestReloadIgnoringLocalCacheData;

    self.session =
        [NSURLSession
            sessionWithConfiguration:
                configuration
            delegate:
                self
            delegateQueue:
                nil];

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                self.remoteURL];

    [request
        setHTTPMethod:
            @"GET"];

    [request
        setValue:
            @"video/mp4,video/quicktime,application/octet-stream;q=0.9,*/*;q=0.1"
        forHTTPHeaderField:
            @"Accept"];

    [request
        setValue:
            @"no-cache"
        forHTTPHeaderField:
            @"Cache-Control"];

    [request
        setValue:
            @"identity"
        forHTTPHeaderField:
            @"Accept-Encoding"];

    // ------------------------------------------------------------
    // RESUME FROM EXISTING BYTE
    // ------------------------------------------------------------

    if (offset > 0) {

        NSString *range =
            [NSString
                stringWithFormat:
                    @"bytes=%lld-",
                    offset];

        [request
            setValue:
                range
            forHTTPHeaderField:
                @"Range"];

        NSLog(
            @"[YTDM][RESUME] Requesting %@",
            range);
    }

    self.task =
        [self.session
            dataTaskWithRequest:
                request];

    [self.task resume];
}

// ============================================================================
// RESPONSE
// ============================================================================

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
completionHandler:
(void (^)(NSURLSessionResponseDisposition disposition))
    completionHandler {

    if (self.finished) {

        completionHandler(
            NSURLSessionResponseCancel);

        return;
    }

    NSHTTPURLResponse *http =
        (NSHTTPURLResponse *)response;

    NSInteger status =
        http.statusCode;

    NSString *contentType =
        [http.allHeaderFields[@"Content-Type"]
            description]
            .lowercaseString;

    NSLog(
        @"[YTDM][FILE] HTTP STATUS = %ld",
        (long)status);

    NSLog(
        @"[YTDM][FILE] CONTENT-LENGTH = %lld",
        response.expectedContentLength);

    NSLog(
        @"[YTDM][FILE] CONTENT-RANGE = %@",
        http.allHeaderFields[@"Content-Range"]);

    // ------------------------------------------------------------
    // FIRST REQUEST
    // ------------------------------------------------------------

    if (self.receivedBytes == 0) {

        if (status < 200 ||
            status >= 300) {

            NSError *error =
                [NSError
                    errorWithDomain:
                        @"YTDMDownload"
                    code:
                        status
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            [NSString
                                stringWithFormat:
                                    @"Server returned HTTP %ld while downloading the file.",
                                    (long)status]
                    }];

            completionHandler(
                NSURLSessionResponseCancel);

            [self finishWithURL:
                nil
                error:
                    error];

            return;
        }
    }

    // ------------------------------------------------------------
    // RESUME REQUEST
    // ------------------------------------------------------------

    else {

        if (status == 206) {

            // Correct partial response.

        } else if (status == 200) {

            // Server ignored Range.
            // Restart from byte zero to avoid corruption.

            NSLog(
                @"[YTDM][RESUME] Server ignored Range. Restarting."
            );

            completionHandler(
                NSURLSessionResponseCancel);

            [self.task cancel];

            [self.outputStream close];

            self.outputStream =
                nil;

            if (self.session) {

                [self.session
                    invalidateAndCancel];
            }

            self.session =
                nil;

            self.task =
                nil;

            [self startRequestFromOffset:
                0
                truncate:YES];

            return;

        } else {

            NSError *error =
                [NSError
                    errorWithDomain:
                        @"YTDMDownload"
                    code:
                        status
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            [NSString
                                stringWithFormat:
                                    @"Server returned HTTP %ld while resuming the file.",
                                    (long)status]
                    }];

            completionHandler(
                NSURLSessionResponseCancel);

            [self finishWithURL:
                nil
                error:
                    error];

            return;
        }
    }

    // ------------------------------------------------------------
    // CONTENT TYPE
    // ------------------------------------------------------------

    if (contentType.length > 0 &&
        ![contentType containsString:@"video/"] &&
        ![contentType containsString:@"audio/"] &&
        ![contentType containsString:@"application/octet-stream"] &&
        ![contentType containsString:@"application/mp4"]) {

        NSError *error =
            [NSError
                errorWithDomain:
                    @"YTDMDownload"
                code:
                    1006
                userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString
                            stringWithFormat:
                                @"Unexpected file response type: %@",
                                contentType]
                }];

        completionHandler(
            NSURLSessionResponseCancel);

        [self finishWithURL:
            nil
            error:
                error];

        return;
    }

    // ------------------------------------------------------------
    // DETERMINE TOTAL SIZE
    // ------------------------------------------------------------

    NSString *contentRange =
        http.allHeaderFields[@"Content-Range"];

    if (status == 206 &&
        contentRange.length > 0) {

        NSRange slashRange =
            [contentRange
                rangeOfString:
                    @"/"];

        if (slashRange.location !=
                NSNotFound) {

            NSString *totalString =
                [contentRange
                    substringFromIndex:
                        slashRange.location + 1];

            int64_t total =
                [totalString
                    longLongValue];

            if (total > 0) {

                self.expectedTotalBytes =
                    total;
            }
        }

    } else if (status == 200) {

        self.expectedTotalBytes =
            response.expectedContentLength;
    }

    self.responseAccepted =
        YES;

    [self.outputStream open];

    completionHandler(
        NSURLSessionResponseAllow);
}

// ============================================================================
// DATA
// ============================================================================

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {

    if (!self.responseAccepted ||
        self.finished) {

        return;
    }

    const uint8_t *bytes =
        (const uint8_t *)data.bytes;

    NSUInteger remaining =
        data.length;

    while (remaining > 0) {

        NSInteger written =
            [self.outputStream
                write:
                    bytes
                maxLength:
                    remaining];

        if (written <= 0) {

            NSError *error =
                self.outputStream.streamError ?:
                [NSError
                    errorWithDomain:
                        @"YTDMDownload"
                    code:
                        1002
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            @"Could not write the downloaded video to disk."
                    }];

            [dataTask cancel];

            [self finishWithURL:
                nil
                error:
                    error];

            return;
        }

        bytes +=
            written;

        remaining -=
            (NSUInteger)written;

        self.receivedBytes +=
            written;
    }
}

// ============================================================================
// RETRYABLE ERROR
// ============================================================================

- (BOOL)isRetryableError:(NSError *)error {

    if (!error) {
        return NO;
    }

    if (![error.domain
            isEqualToString:
                NSURLErrorDomain]) {

        return NO;
    }

    switch (error.code) {

        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorTimedOut:
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotConnectToHost:
            return YES;

        default:
            return NO;
    }
}

// ============================================================================
// RETRY
// ============================================================================

- (void)scheduleRetryWithError:(NSError *)error {

    if (self.finished ||
        self.retryScheduled) {

        return;
    }

    if (self.retryCount >=
        self.maxRetries) {

        [self finishWithURL:
            nil
            error:
                error];

        return;
    }

    self.retryScheduled =
        YES;

    NSInteger attempt =
        self.retryCount + 1;

    self.retryCount =
        attempt;

    NSInteger delaySeconds =
        1;

    if (attempt == 2) {
        delaySeconds = 2;
    } else if (attempt == 3) {
        delaySeconds = 4;
    } else if (attempt == 4) {
        delaySeconds = 8;
    } else if (attempt >= 5) {
        delaySeconds = 16;
    }

    NSLog(
        @"[YTDM][RETRY] Connection interrupted.");

    NSLog(
        @"[YTDM][RETRY] Attempt %ld/%ld in %ld seconds.",
        (long)attempt,
        (long)self.maxRetries,
        (long)delaySeconds);

    NSLog(
        @"[YTDM][RETRY] Bytes already received: %lld",
        self.receivedBytes);

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)
                delaySeconds *
                NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{

        if (self.finished) {
            return;
        }

        self.retryScheduled =
            NO;

        [self.outputStream close];

        self.outputStream =
            nil;

        if (self.session) {

            [self.session
                invalidateAndCancel];
        }

        self.session =
            nil;

        self.task =
            nil;

        [self startRequestFromOffset:
            self.receivedBytes
            truncate:
                NO];
    });
}

// ============================================================================
// COMPLETE
// ============================================================================

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    if (self.finished) {
        return;
    }

    [self.outputStream close];

    // ------------------------------------------------------------
    // HANDLE ERROR
    // ------------------------------------------------------------

    if (error) {

        NSLog(
            @"[YTDM][FILE] NSURLSession ERROR: %@",
            error);

        NSLog(
            @"[YTDM][FILE] ERROR DOMAIN = %@",
            error.domain);

        NSLog(
            @"[YTDM][FILE] ERROR CODE = %ld",
            (long)error.code);

        // If everything was already received,
        // accept the file even if the session reports
        // a late connection error.

        if (self.expectedTotalBytes !=
                NSURLSessionTransferSizeUnknown &&
            self.expectedTotalBytes > 0 &&
            self.receivedBytes ==
                self.expectedTotalBytes) {

            NSDictionary *attrs =
                [[NSFileManager defaultManager]
                    attributesOfItemAtPath:
                        self.destinationURL.path
                    error:nil];

            unsigned long long actualSize =
                [attrs[NSFileSize]
                    unsignedLongLongValue];

            if (actualSize ==
                (unsigned long long)
                    self.expectedTotalBytes) {

                NSLog(
                    @"[YTDM][FILE] COMPLETE despite late connection error."
                );

                [self finishWithURL:
                    self.destinationURL
                    error:nil];

                return;
            }
        }

        if ([self
                isRetryableError:error]) {

            [self
                scheduleRetryWithError:
                    error];

            return;
        }

        [self finishWithURL:
            nil
            error:
                error];

        return;
    }

    // ------------------------------------------------------------
    // VERIFY TOTAL BYTE COUNT
    // ------------------------------------------------------------

    if (self.expectedTotalBytes !=
            NSURLSessionTransferSizeUnknown &&
        self.expectedTotalBytes > 0 &&
        self.receivedBytes !=
            self.expectedTotalBytes) {

        NSError *error2 =
            [NSError
                errorWithDomain:
                    @"YTDMDownload"
                code:
                    1004
                userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString
                            stringWithFormat:
                                @"Incomplete video download: received %lld of %lld bytes.",
                                self.receivedBytes,
                                self.expectedTotalBytes]
                }];

        [self
            scheduleRetryWithError:
                error2];

        return;
    }

    // ------------------------------------------------------------
    // VERIFY FILE ON DISK
    // ------------------------------------------------------------

    NSDictionary *attrs =
        [[NSFileManager defaultManager]
            attributesOfItemAtPath:
                self.destinationURL.path
            error:nil];

    unsigned long long actualSize =
        [attrs[NSFileSize]
            unsignedLongLongValue];

    if (actualSize < 1024) {

        NSError *error2 =
            [NSError
                errorWithDomain:
                    @"YTDMDownload"
                code:
                    1005
                userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString
                            stringWithFormat:
                                @"Downloaded file is invalid or incomplete (%llu bytes).",
                                actualSize]
                }];

        [self finishWithURL:
            nil
            error:
                error2];

        return;
    }

    if (self.expectedTotalBytes !=
            NSURLSessionTransferSizeUnknown &&
        self.expectedTotalBytes > 0 &&
        actualSize !=
            (unsigned long long)
                self.expectedTotalBytes) {

        NSError *error2 =
            [NSError
                errorWithDomain:
                    @"YTDMDownload"
                code:
                    1007
                userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString
                            stringWithFormat:
                                @"Final file size mismatch: %llu of %lld bytes.",
                                actualSize,
                                self.expectedTotalBytes]
                }];

        [self
            scheduleRetryWithError:
                error2];

        return;
    }

    NSLog(
        @"[YTDM][FILE] DOWNLOAD COMPLETE: %llu bytes",
        actualSize);

    [self finishWithURL:
        self.destinationURL
        error:nil];
}

// ============================================================================
// FINISH
// ============================================================================

- (void)finishWithURL:(NSURL *)fileURL
                error:(NSError *)error {

    if (self.finished) {
        return;
    }

    self.finished =
        YES;

    [self.outputStream close];

    self.outputStream =
        nil;

    NSURLSession *session =
        self.session;

    self.session =
        nil;

    self.task =
        nil;

    void (^completion)(NSURL *,
                       NSError *) =
        [self.completion copy];

    self.completion =
        nil;

    // Only delete on genuine failure.
    if (error &&
        !fileURL) {

        [[NSFileManager defaultManager]
            removeItemAtURL:
                self.destinationURL
            error:nil];
    }

    if (completion) {

        completion(
            fileURL,
            error);
    }

    if (session) {

        [session
            invalidateAndCancel];
    }
}

@end

// ============================================================================
// SERVER COMMUNICATION SERVICE
// ============================================================================

@interface YTDownloadManagerService : NSObject

@property (nonatomic, strong)
NSMutableSet *activeFileDownloaders;

@property (nonatomic, copy)
void (^fileProgressCallback)(float progress);

+ (instancetype)sharedInstance;

- (void)requestDownloadForVideoId:(NSString *)vId
                          isAudio:(BOOL)isAudio
                          quality:(NSString *)quality
                     completion:(void (^)(NSArray<NSURL *> *localURLs,
                                          NSString *errorMsg))completionBlock;

- (void)requestUpscaleDownloadForVideoId:(NSString *)vId
                                  target:(NSString *)target
                              completion:(void (^)(NSArray<NSURL *> *localURLs,
                                                   NSString *errorMsg))completionBlock;

- (void)requestStreamURLForVideoId:(NSString *)vId
                        completion:(void (^)(NSString *streamURL,
                                             NSString *errorMsg))completionBlock;

- (void)startYTDMDownloadWithWatchURL:(NSString *)watchURL
                               format:(NSString *)format
                             formatId:(NSString *)formatId
                           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                                NSString *errorMsg))completionBlock;

- (void)pollJobStatus:(NSString *)jobId
           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                NSString *errorMsg))completionBlock;

- (void)pollJobStatus:(NSString *)jobId
              upscale:(BOOL)upscale
           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                NSString *errorMsg))completionBlock;

- (void)downloadMultipleFiles:(NSArray<NSString *> *)filenames
                      forJobId:(NSString *)jobId
                    completion:(void (^)(NSArray<NSURL *> *localURLs,
                                         NSString *errorMsg))completionBlock;

- (void)downloadMultipleFilesStreaming:(NSArray<NSString *> *)filenames
                               forJobId:(NSString *)jobId
                             completion:(void (^)(NSArray<NSURL *> *localURLs,
                                                  NSString *errorMsg))completionBlock;

- (void)retainActiveFileDownloader:
    (YTDMStreamingFileDownloader *)downloader;

- (void)releaseActiveFileDownloader:
    (YTDMStreamingFileDownloader *)downloader;

@end

@implementation YTDownloadManagerService

+ (instancetype)sharedInstance {

    static YTDownloadManagerService *shared = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

        shared =
            [[self alloc] init];

        shared.activeFileDownloaders =
            [NSMutableSet set];
    });

    return shared;
}

// ============================================================================
// SERVER
// ============================================================================

- (NSString *)serverEndpoint {

    // IMPORTANT:
    // NO trailing slash.
    return @"https://5volue.goport.uz";
}

// ============================================================================
// MX-UPscale CONFIG
// ============================================================================

- (NSDictionary *)mxUpscaleConfigurationForTarget:
    (NSString *)target {

    if ([target isEqualToString:@"2K"]) {

        return @{
            @"target": @"qhd",
            @"width": @2160,
            @"height": @1440
        };
    }

    if ([target isEqualToString:@"4K"]) {

        return @{
            @"target": @"4k",
            @"width": @3840,
            @"height": @2160
        };
    }

    if ([target isEqualToString:@"8K"]) {

        return @{
            @"target": @"8k",
            @"width": @7680,
            @"height": @4320
        };
    }

    if ([target isEqualToString:@"6K"]) {

        return @{
            @"target": @"custom",
            @"width": @6144,
            @"height": @3456
        };
    }

    return nil;
}

// ============================================================================
// NORMAL DOWNLOAD
// ============================================================================

- (void)requestDownloadForVideoId:(NSString *)vId
                          isAudio:(BOOL)isAudio
                          quality:(NSString *)quality
                     completion:(void (^)(NSArray<NSURL *> *localURLs,
                                          NSString *errorMsg))completionBlock {

    NSString *watchURL =
        [NSString
            stringWithFormat:
                @"https://www.youtube.com/watch?v=%@",
                vId];

    NSString *resolvedFormatId =
        nil;

    if (isAudio) {

        resolvedFormatId =
            @"bestaudio[ext=m4a]/best";

    } else {

        if ([quality isEqualToString:@"1080p"]) {

            resolvedFormatId =
                @"bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";

        } else if ([quality isEqualToString:@"720p"]) {

            resolvedFormatId =
                @"bestvideo[height<=720][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";

        } else if ([quality isEqualToString:@"360p"]) {

            resolvedFormatId =
                @"bestvideo[height<=360][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]/best";

        } else {

            resolvedFormatId =
                @"bestvideo+bestaudio/best";
        }
    }

    [self
        startYTDMDownloadWithWatchURL:
            watchURL
        format:
            isAudio ? @"audio" : @"video"
        formatId:
            resolvedFormatId
        completion:
            completionBlock];
}

// ============================================================================
// MX-UPscale DOWNLOAD
// ============================================================================

- (void)requestUpscaleDownloadForVideoId:(NSString *)vId
                                  target:(NSString *)target
                              completion:(void (^)(NSArray<NSURL *> *localURLs,
                                                   NSString *errorMsg))completionBlock {

    if (vId.length == 0) {

        completionBlock(
            nil,
            @"No video ID.");

        return;
    }

    NSDictionary *mxConfig =
        [self
            mxUpscaleConfigurationForTarget:
                target];

    if (!mxConfig) {

        completionBlock(
            nil,
            @"Unsupported upscale target.");

        return;
    }

    NSString *watchURL =
        [NSString
            stringWithFormat:
                @"https://www.youtube.com/watch?v=%@",
                vId];

    NSString *urlStr =
        [[self serverEndpoint]
            stringByAppendingString:
                @"/api/download"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                [NSURL URLWithString:
                    urlStr]];

    [request
        setHTTPMethod:
            @"POST"];

    [request
        setValue:
            @"application/json"
        forHTTPHeaderField:
            @"Content-Type"];

    NSDictionary *payload =
        @{
            @"url": watchURL,
            @"format": @"video",
            @"upscale": @YES,
            @"upscale_target": target,
            @"source_quality": @"1080p",
            @"mx_target": mxConfig[@"target"],
            @"mx_width": mxConfig[@"width"],
            @"mx_height": mxConfig[@"height"],
            @"mx_codec": @"h264",
            @"mx_quality": @60,
            @"mx_bframes": @YES,
            @"mx_prio_speed": @YES
        };

    request.HTTPBody =
        [NSJSONSerialization
            dataWithJSONObject:
                payload
            options:
                0
            error:
                nil];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:
            request
        completionHandler:
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {

        if (error || !data) {

            completionBlock(
                nil,
                @"Upscale server unreachable.");

            return;
        }

        NSDictionary *json =
            [NSJSONSerialization
                JSONObjectWithData:
                    data
                options:
                    0
                error:
                    nil];

        if (json[@"job_id"]) {

            [self
                pollJobStatus:
                    json[@"job_id"]
                upscale:
                    YES
                completion:
                    completionBlock];

        } else {

            completionBlock(
                nil,
                json[@"error"] ?:
                    @"Upscale job initialization failed.");
        }

    }] resume];
}

// ============================================================================
// STREAM
// ============================================================================

- (void)requestStreamURLForVideoId:(NSString *)vId
                        completion:(void (^)(NSString *streamURL,
                                             NSString *errorMsg))completionBlock {

    NSString *urlStr =
        [[self serverEndpoint]
            stringByAppendingString:
                @"/api/stream"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                [NSURL URLWithString:
                    urlStr]];

    [request
        setHTTPMethod:
            @"POST"];

    [request
        setValue:
            @"application/json"
        forHTTPHeaderField:
            @"Content-Type"];

    NSDictionary *payload =
        @{
            @"url":
                [NSString
                    stringWithFormat:
                        @"https://www.youtube.com/watch?v=%@",
                        vId]
        };

    request.HTTPBody =
        [NSJSONSerialization
            dataWithJSONObject:
                payload
            options:
                0
            error:
                nil];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:
            request
        completionHandler:
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {

        if (error || !data) {

            completionBlock(
                nil,
                @"Stream Connection Error");

            return;
        }

        NSDictionary *json =
            [NSJSONSerialization
                JSONObjectWithData:
                    data
                options:
                    0
                error:
                    nil];

        if (json[@"stream_url"]) {

            completionBlock(
                json[@"stream_url"],
                nil);

        } else {

            completionBlock(
                nil,
                json[@"error"] ?:
                    @"Stream failed");
        }

    }] resume];
}

// ============================================================================
// START STANDARD JOB
// ============================================================================

- (void)startYTDMDownloadWithWatchURL:(NSString *)watchURL
                               format:(NSString *)format
                             formatId:(NSString *)formatId
                           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                                NSString *errorMsg))completionBlock {

    NSString *urlStr =
        [[self serverEndpoint]
            stringByAppendingString:
                @"/api/download"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                [NSURL URLWithString:
                    urlStr]];

    [request
        setHTTPMethod:
            @"POST"];

    [request
        setValue:
            @"application/json"
        forHTTPHeaderField:
            @"Content-Type"];

    NSMutableDictionary *payload =
        [@{
            @"url": watchURL,
            @"format": format
        } mutableCopy];

    if (formatId) {
        payload[@"format_id"] =
            formatId;
    }

    request.HTTPBody =
        [NSJSONSerialization
            dataWithJSONObject:
                payload
            options:
                0
            error:
                nil];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:
            request
        completionHandler:
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {

        if (error || !data) {

            completionBlock(
                nil,
                @"Server unreachable.");

            return;
        }

        NSDictionary *json =
            [NSJSONSerialization
                JSONObjectWithData:
                    data
                options:
                    0
                error:
                    nil];

        if (json[@"job_id"]) {

            [self
                pollJobStatus:
                    json[@"job_id"]
                upscale:
                    NO
                completion:
                    completionBlock];

        } else {

            completionBlock(
                nil,
                json[@"error"] ?:
                    @"Job init failed.");
        }

    }] resume];
}

// ============================================================================
// JOB STATUS
// ============================================================================

- (void)pollJobStatus:(NSString *)jobId
           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                NSString *errorMsg))completionBlock {

    [self
        pollJobStatus:
            jobId
        upscale:
            NO
        completion:
            completionBlock];
}

- (void)pollJobStatus:(NSString *)jobId
              upscale:(BOOL)upscale
           completion:(void (^)(NSArray<NSURL *> *localURLs,
                                NSString *errorMsg))completionBlock {

    NSString *urlStr =
        [NSString
            stringWithFormat:
                @"%@/api/status/%@",
                [self serverEndpoint],
                jobId];

    NSMutableURLRequest *request =
        [NSMutableURLRequest
            requestWithURL:
                [NSURL URLWithString:
                    urlStr]];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:
            request
        completionHandler:
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {

        if (error || !data) {

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)
                        (0.5 *
                         NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{

                [self
                    pollJobStatus:
                        jobId
                    upscale:
                        upscale
                    completion:
                        completionBlock];
            });

            return;
        }

        NSDictionary *json =
            [NSJSONSerialization
                JSONObjectWithData:
                    data
                options:
                    0
                error:
                    nil];

        NSString *status =
            json[@"status"];

        if ([status isEqualToString:@"done"]) {

            id filesData =
                json[@"files"] ?:
                json[@"filenames"] ?:
                json[@"filename"] ?:
                json[@"file_path"];

            NSMutableArray<NSString *> *
                filesToDownload =
                    [NSMutableArray array];

            if ([filesData isKindOfClass:
                    [NSArray class]]) {

                for (id fileItem
                     in filesData) {

                    if ([fileItem
                         isKindOfClass:
                            [NSString class]]) {

                        [filesToDownload
                            addObject:
                                [fileItem
                                    lastPathComponent]];
                    }
                }

            } else if ([filesData
                        isKindOfClass:
                            [NSString class]]) {

                [filesToDownload
                    addObject:
                        [filesData
                            lastPathComponent]];
            }

            if (filesToDownload.count == 0) {

                completionBlock(
                    nil,
                    @"No files found in job.");

                return;
            }

            if (upscale) {

                [self
                    downloadMultipleFilesStreaming:
                        filesToDownload
                    forJobId:
                        jobId
                    completion:
                        completionBlock];

            } else {

                [self
                    downloadMultipleFiles:
                        filesToDownload
                    forJobId:
                        jobId
                    completion:
                        completionBlock];
            }

        } else if ([status
                   isEqualToString:
                       @"error"]) {

            completionBlock(
                nil,
                json[@"error"] ?:
                    @"Server Error.");

        } else {

            NSString *serverStage =
                json[@"stage"];

            NSString *statusText =
                serverStage.length > 0
                ? [NSString
                    stringWithFormat:
                        @"%@...",
                        serverStage]
                : @"Downloading / processing on server...";

            dispatch_async(
                dispatch_get_main_queue(), ^{

                [[YTDMProgressHUD sharedHUD]
                    updateProgress:
                        -1.0
                    status:
                        statusText];
            });

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)
                        (0.5 *
                         NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{

                [self
                    pollJobStatus:
                        jobId
                    upscale:
                        upscale
                    completion:
                        completionBlock];
            });
        }

    }] resume];
}

// ============================================================================
// NORMAL FILE DOWNLOAD
// ============================================================================

- (void)downloadMultipleFiles:
    (NSArray<NSString *> *)filenames
                      forJobId:
    (NSString *)jobId
                    completion:
    (void (^)(NSArray<NSURL *> *localURLs,
              NSString *errorMsg))completionBlock {

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            0.0
        status:
            [NSString
                stringWithFormat:
                    @"Syncing files: 0/%lu",
                    (unsigned long)
                        filenames.count]];

    NSMutableArray<NSURL *> *localURLs =
        [NSMutableArray array];

    __block NSString *errStr =
        nil;

    __block NSUInteger completedCount =
        0;

    NSUInteger totalCount =
        filenames.count;

    dispatch_group_t downloadGroup =
        dispatch_group_create();

    for (NSString *filename
         in filenames) {

        dispatch_group_enter(
            downloadGroup);

        NSString *baseURLString =
            [NSString
                stringWithFormat:
                    @"%@/api/file/%@",
                    [self serverEndpoint],
                    jobId];

        NSURLComponents *components =
            [NSURLComponents
                componentsWithString:
                    baseURLString];

        components.queryItems =
            @[
                [NSURLQueryItem
                    queryItemWithName:
                        @"filename"
                    value:
                        filename]
            ];

        NSURL *remoteURL =
            components.URL;

        if (!remoteURL) {

            @synchronized(localURLs) {

                if (!errStr) {
                    errStr =
                        @"Invalid file download URL.";
                }

                completedCount++;
            }

            dispatch_group_leave(
                downloadGroup);

            continue;
        }

        NSString *uniqueFilename =
            [NSString
                stringWithFormat:
                    @"YTDM-%@-%@",
                    jobId,
                    filename];

        NSURL *destinationURL =
            [NSURL
                fileURLWithPath:
                    [NSTemporaryDirectory()
                        stringByAppendingPathComponent:
                            uniqueFilename]];

        [[NSFileManager defaultManager]
            removeItemAtURL:
                destinationURL
            error:nil];

        NSURLSessionDownloadTask *task =
            [[NSURLSession sharedSession]
                downloadTaskWithURL:
                    remoteURL
                completionHandler:
                ^(NSURL *location,
                  NSURLResponse *response,
                  NSError *error) {

            BOOL success =
                NO;

            NSError *localError =
                error;

            if (!localError &&
                location) {

                NSHTTPURLResponse *http =
                    (NSHTTPURLResponse *)response;

                if (http &&
                    (http.statusCode < 200 ||
                     http.statusCode >= 300)) {

                    localError =
                        [NSError
                            errorWithDomain:
                                @"YTDMDownload"
                            code:
                                http.statusCode
                            userInfo:@{
                                NSLocalizedDescriptionKey:
                                    [NSString
                                        stringWithFormat:
                                            @"Server returned HTTP %ld while downloading the file.",
                                            (long)
                                                http.statusCode]
                            }];
                }
            }

            if (!localError &&
                location) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        destinationURL
                    error:nil];

                if ([[NSFileManager defaultManager]
                        moveItemAtURL:
                            location
                        toURL:
                            destinationURL
                        error:
                            &localError]) {

                    NSDictionary *attrs =
                        [[NSFileManager defaultManager]
                            attributesOfItemAtPath:
                                destinationURL.path
                            error:nil];

                    unsigned long long size =
                        [attrs[NSFileSize]
                            unsignedLongLongValue];

                    if (size > 0) {

                        success =
                            YES;

                    } else {

                        localError =
                            [NSError
                                errorWithDomain:
                                    @"YTDMDownload"
                                code:
                                    1101
                                userInfo:@{
                                    NSLocalizedDescriptionKey:
                                        @"Downloaded file is empty."
                                }];
                    }
                }
            }

            if (!success) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        destinationURL
                    error:nil];
            }

            @synchronized(localURLs) {

                if (success) {

                    [localURLs
                        addObject:
                            destinationURL];

                } else if (!errStr) {

                    errStr =
                        localError.localizedDescription ?:
                        @"Download failed.";
                }

                completedCount++;

                float progress =
                    totalCount > 0
                    ? (float)completedCount /
                      (float)totalCount
                    : 1.0f;

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    [[YTDMProgressHUD sharedHUD]
                        updateProgress:
                            progress
                        status:
                            [NSString
                                stringWithFormat:
                                    @"Syncing files: %lu/%lu",
                                    (unsigned long)
                                        completedCount,
                                    (unsigned long)
                                        totalCount]];
                });
            }

            dispatch_group_leave(
                downloadGroup);

        }];

        [task resume];
    }

    dispatch_group_notify(
        downloadGroup,
        dispatch_get_main_queue(), ^{

        if (localURLs.count ==
            totalCount) {

            completionBlock(
                localURLs,
                nil);

        } else {

            completionBlock(
                nil,
                errStr ?:
                    @"Download sync failed.");
        }
    });
}

// ============================================================================
// RETAIN STREAMING DOWNLOADERS
// ============================================================================

- (void)retainActiveFileDownloader:
    (YTDMStreamingFileDownloader *)downloader {

    if (!downloader) {
        return;
    }

    @synchronized(
        self.activeFileDownloaders) {

        [self.activeFileDownloaders
            addObject:
                downloader];
    }
}

- (void)releaseActiveFileDownloader:
    (YTDMStreamingFileDownloader *)downloader {

    if (!downloader) {
        return;
    }

    @synchronized(
        self.activeFileDownloaders) {

        [self.activeFileDownloaders
            removeObject:
                downloader];
    }
}

// ============================================================================
// RESUMABLE STREAMING FILE DOWNLOAD
// ============================================================================

- (void)downloadMultipleFilesStreaming:
    (NSArray<NSString *> *)filenames
                              forJobId:
    (NSString *)jobId
                            completion:
    (void (^)(NSArray<NSURL *> *localURLs,
              NSString *errorMsg))completionBlock {

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            0.0
        status:
            [NSString
                stringWithFormat:
                    @"Syncing files: 0/%lu",
                    (unsigned long)
                        filenames.count]];

    NSMutableArray<NSURL *> *localURLs =
        [NSMutableArray array];

    __block NSString *errStr =
        nil;

    __block NSUInteger completedCount =
        0;

    NSUInteger totalCount =
        filenames.count;

    dispatch_group_t downloadGroup =
        dispatch_group_create();

    for (NSString *filename
         in filenames) {

        dispatch_group_enter(
            downloadGroup);

        NSString *baseURLString =
            [NSString
                stringWithFormat:
                    @"%@/api/file/%@",
                    [self serverEndpoint],
                    jobId];

        NSURLComponents *components =
            [NSURLComponents
                componentsWithString:
                    baseURLString];

        components.queryItems =
            @[
                [NSURLQueryItem
                    queryItemWithName:
                        @"filename"
                    value:
                        filename]
            ];

        NSURL *remoteURL =
            components.URL;

        if (!remoteURL) {

            @synchronized(localURLs) {

                if (!errStr) {
                    errStr =
                        @"Invalid file download URL.";
                }

                completedCount++;
            }

            dispatch_group_leave(
                downloadGroup);

            continue;
        }

        NSString *uniqueFilename =
            [NSString
                stringWithFormat:
                    @"YTDM-%@-%@",
                    jobId,
                    filename];

        NSURL *tempURL =
            [NSURL
                fileURLWithPath:
                    [NSTemporaryDirectory()
                        stringByAppendingPathComponent:
                            uniqueFilename]];

        YTDMStreamingFileDownloader *
            downloader =
                [[YTDMStreamingFileDownloader alloc]
                    init];

        [self
            retainActiveFileDownloader:
                downloader];

        [downloader
            startWithURL:
                remoteURL
            destinationURL:
                tempURL
            completion:
            ^(NSURL *fileURL,
              NSError *error) {

            [self
                releaseActiveFileDownloader:
                    downloader];

            if (error ||
                !fileURL) {

                @synchronized(localURLs) {

                    if (!errStr) {

                        errStr =
                            error.localizedDescription ?:
                            @"File download failed.";
                    }
                }

            } else {

                @synchronized(localURLs) {

                    [localURLs
                        addObject:
                            fileURL];
                }
            }

            @synchronized(localURLs) {

                completedCount++;

                float progress =
                    totalCount > 0
                    ? (float)completedCount /
                      (float)totalCount
                    : 1.0f;

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    [[YTDMProgressHUD sharedHUD]
                        updateProgress:
                            progress
                        status:
                            [NSString
                                stringWithFormat:
                                    @"Syncing files: %lu/%lu",
                                    (unsigned long)
                                        completedCount,
                                    (unsigned long)
                                        totalCount]];
                });

                if (self.fileProgressCallback) {

                    self.fileProgressCallback(
                        progress);
                }
            }

            dispatch_group_leave(
                downloadGroup);
        }];
    }

    dispatch_group_notify(
        downloadGroup,
        dispatch_get_main_queue(), ^{

        if (localURLs.count ==
            totalCount) {

            completionBlock(
                localURLs,
                nil);

        } else {

            completionBlock(
                nil,
                errStr ?:
                    @"Download sync failed.");
        }
    });
}

@end

// ============================================================================
// DOWNLOAD QUEUE ITEM
// ============================================================================

@interface YTDMDownloadQueueItem : NSObject

@property (nonatomic, copy)
NSString *videoId;

@property (nonatomic, copy)
NSString *videoTitle;

@property (nonatomic, assign)
BOOL isAudio;

@property (nonatomic, copy)
NSString *quality;

@property (nonatomic, copy)
NSString *upscaleTarget;

@property (nonatomic, assign)
BOOL upscaleEnabled;

@property (nonatomic, copy)
NSString *status;

@property (nonatomic, assign)
float currentProgress;

@property (nonatomic, strong)
NSURL *savedSandboxURL;

@end

@implementation YTDMDownloadQueueItem
@end

// ============================================================================
// DOWNLOAD QUEUE MANAGER
// ============================================================================

@interface YTDMDownloadQueueManager :
NSObject <UIDocumentPickerDelegate>

@property (nonatomic, strong)
NSMutableArray<YTDMDownloadQueueItem *> *
    videoDownloadQueue;

@property (nonatomic, strong)
NSMutableArray<YTDMDownloadQueueItem *> *
    audioDownloadQueue;

@property (nonatomic, assign)
BOOL isDownloading;

@property (nonatomic, assign)
BOOL isCurrentlyReordering;

+ (instancetype)sharedInstance;

- (BOOL)enqueueVideoId:(NSString *)vId
              isAudio:(BOOL)isAudio
              quality:(NSString *)quality;

- (BOOL)enqueueUpscaleVideoId:(NSString *)vId
                       target:(NSString *)target;

- (void)clearDownloadQueue;

- (void)removeItem:
    (YTDMDownloadQueueItem *)item;

- (void)startBatchDownloading;

- (void)moveItemFromSection:(NSInteger)sourceSection
                    fromRow:(NSInteger)sourceRow
                  toSection:(NSInteger)destSection
                      toRow:(NSInteger)destRow;

- (void)cleanUpTemporaryFiles;

- (void)recalculateTitles;

@end

@implementation YTDMDownloadQueueManager

+ (instancetype)sharedInstance {

    static YTDMDownloadQueueManager *shared =
        nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

        shared =
            [[self alloc] init];
    });

    return shared;
}

- (instancetype)init {

    self =
        [super init];

    if (self) {

        _videoDownloadQueue =
            [NSMutableArray array];

        _audioDownloadQueue =
            [NSMutableArray array];

        _isDownloading =
            NO;

        _isCurrentlyReordering =
            NO;
    }

    return self;
}

// ============================================================================
// TITLES
// ============================================================================

- (void)recalculateTitles {

    for (NSUInteger i = 0;
         i < _videoDownloadQueue.count;
         i++) {

        YTDMDownloadQueueItem *item =
            _videoDownloadQueue[i];

        if (item.upscaleEnabled) {

            item.videoTitle =
                [NSString
                    stringWithFormat:
                        @"Video %lu (%@)",
                        (unsigned long)
                            (i + 1),
                        item.upscaleTarget];

        } else {

            if (!item.quality) {
                item.quality =
                    @"720p";
            }

            item.videoTitle =
                [NSString
                    stringWithFormat:
                        @"Video %lu (%@)",
                        (unsigned long)
                            (i + 1),
                        item.quality];
        }
    }

    for (NSUInteger i = 0;
         i < _audioDownloadQueue.count;
         i++) {

        YTDMDownloadQueueItem *item =
            _audioDownloadQueue[i];

        item.videoTitle =
            [NSString
                stringWithFormat:
                    @"Audio %lu",
                    (unsigned long)
                        (i + 1)];
    }
}

// ============================================================================
// ENQUEUE NORMAL
// ============================================================================

- (BOOL)enqueueVideoId:(NSString *)vId
              isAudio:(BOOL)isAudio
              quality:(NSString *)quality {

    if (!vId) {
        return NO;
    }

    @synchronized(self) {

        YTDMDownloadQueueItem *item =
            [[YTDMDownloadQueueItem alloc]
                init];

        item.videoId =
            vId;

        item.isAudio =
            isAudio;

        item.quality =
            isAudio
            ? nil
            : quality;

        item.upscaleEnabled =
            NO;

        item.upscaleTarget =
            nil;

        item.status =
            @"Waiting...";

        item.currentProgress =
            0.0;

        if (isAudio) {

            if (_audioDownloadQueue.count >= 20) {
                return NO;
            }

            [_audioDownloadQueue
                addObject:
                    item];

        } else {

            if (_videoDownloadQueue.count >= 20) {
                return NO;
            }

            [_videoDownloadQueue
                addObject:
                    item];
        }

        [self
            recalculateTitles];
    }

    if (!_isCurrentlyReordering) {

        [[NSNotificationCenter defaultCenter]
            postNotificationName:
                @"YTDMDownloadQueueUpdated"
            object:nil];
    }

    return YES;
}

// ============================================================================
// ENQUEUE UPSCALE
// ============================================================================

- (BOOL)enqueueUpscaleVideoId:(NSString *)vId
                       target:(NSString *)target {

    if (vId.length == 0 ||
        target.length == 0) {

        return NO;
    }

    if (![target isEqualToString:@"2K"] &&
        ![target isEqualToString:@"4K"] &&
        ![target isEqualToString:@"8K"] &&
        ![target isEqualToString:@"6K"]) {

        return NO;
    }

    @synchronized(self) {

        if (_videoDownloadQueue.count >= 20) {
            return NO;
        }

        YTDMDownloadQueueItem *item =
            [[YTDMDownloadQueueItem alloc]
                init];

        item.videoId =
            vId;

        item.isAudio =
            NO;

        item.quality =
            @"1080p";

        item.upscaleEnabled =
            YES;

        item.upscaleTarget =
            target;

        item.status =
            @"Waiting...";

        item.currentProgress =
            0.0;

        [_videoDownloadQueue
            addObject:
                item];

        [self
            recalculateTitles];
    }

    if (!_isCurrentlyReordering) {

        [[NSNotificationCenter defaultCenter]
            postNotificationName:
                @"YTDMDownloadQueueUpdated"
            object:nil];
    }

    return YES;
}

// ============================================================================
// CLEAR
// ============================================================================

- (void)clearDownloadQueue {

    @synchronized(self) {

        [self
            cleanUpTemporaryFiles];

        [_videoDownloadQueue
            removeAllObjects];

        [_audioDownloadQueue
            removeAllObjects];
    }

    if (!_isCurrentlyReordering) {

        [[NSNotificationCenter defaultCenter]
            postNotificationName:
                @"YTDMDownloadQueueUpdated"
            object:nil];
    }
}

// ============================================================================
// REMOVE
// ============================================================================

- (void)removeItem:
    (YTDMDownloadQueueItem *)item {

    @synchronized(self) {

        if (item.savedSandboxURL) {

            [[NSFileManager defaultManager]
                removeItemAtURL:
                    item.savedSandboxURL
                error:nil];
        }

        [_videoDownloadQueue
            removeObject:
                item];

        [_audioDownloadQueue
            removeObject:
                item];

        [self
            recalculateTitles];
    }

    if (!_isCurrentlyReordering) {

        [[NSNotificationCenter defaultCenter]
            postNotificationName:
                @"YTDMDownloadQueueUpdated"
            object:nil];
    }
}

// ============================================================================
// REORDER
// ============================================================================

- (void)moveItemFromSection:(NSInteger)sourceSection
                    fromRow:(NSInteger)sourceRow
                  toSection:(NSInteger)destSection
                      toRow:(NSInteger)destRow {

    @synchronized(self) {

        _isCurrentlyReordering =
            YES;

        NSMutableArray *sourceArray =
            (sourceSection == 0)
            ? _videoDownloadQueue
            : _audioDownloadQueue;

        NSMutableArray *destArray =
            (destSection == 0)
            ? _videoDownloadQueue
            : _audioDownloadQueue;

        if (sourceRow >=
            sourceArray.count) {

            _isCurrentlyReordering =
                NO;

            return;
        }

        YTDMDownloadQueueItem *movedItem =
            sourceArray[sourceRow];

        [sourceArray
            removeObjectAtIndex:
                sourceRow];

        movedItem.isAudio =
            (destSection == 1);

        if (movedItem.isAudio) {

            movedItem.quality =
                nil;

            movedItem.upscaleEnabled =
                NO;

            movedItem.upscaleTarget =
                nil;

        } else {

            if (!movedItem.upscaleEnabled &&
                !movedItem.quality) {

                movedItem.quality =
                    @"720p";
            }
        }

        if (destRow >
            destArray.count) {

            destRow =
                destArray.count;
        }

        [destArray
            insertObject:
                movedItem
            atIndex:
                destRow];

        [self
            recalculateTitles];

        _isCurrentlyReordering =
            NO;
    }
}

// ============================================================================
// START BATCH
// ============================================================================

- (void)startBatchDownloading {

    @synchronized(self) {

        if (_isDownloading) {
            return;
        }

        _isDownloading =
            YES;

        for (YTDMDownloadQueueItem *item
             in _videoDownloadQueue) {

            item.status =
                @"Waiting...";

            item.currentProgress =
                0.0;

            if (item.savedSandboxURL) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        item.savedSandboxURL
                    error:nil];

                item.savedSandboxURL =
                    nil;
            }
        }

        for (YTDMDownloadQueueItem *item
             in _audioDownloadQueue) {

            item.status =
                @"Waiting...";

            item.currentProgress =
                0.0;

            if (item.savedSandboxURL) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        item.savedSandboxURL
                    error:nil];

                item.savedSandboxURL =
                    nil;
            }
        }

        [self
            processNext];
    }
}

// ============================================================================
// PROCESS NEXT
// ============================================================================

- (void)processNext {

    @synchronized(self) {

        __block YTDMDownloadQueueItem *nextItem =
            nil;

        __block BOOL anyItemDownloading =
            NO;

        for (YTDMDownloadQueueItem *item
             in _videoDownloadQueue) {

            if ([item.status
                 isEqualToString:
                    @"Downloading..."]) {

                anyItemDownloading =
                    YES;
            }

            if (!nextItem &&
                [item.status
                 isEqualToString:
                    @"Waiting..."]) {

                nextItem =
                    item;
            }
        }

        for (YTDMDownloadQueueItem *item
             in _audioDownloadQueue) {

            if ([item.status
                 isEqualToString:
                    @"Downloading..."]) {

                anyItemDownloading =
                    YES;
            }

            if (!nextItem &&
                [item.status
                 isEqualToString:
                    @"Waiting..."]) {

                nextItem =
                    item;
            }
        }

        if (nextItem) {

            if (anyItemDownloading) {
                return;
            }

            nextItem.status =
                @"Downloading...";

            [[NSNotificationCenter defaultCenter]
                postNotificationName:
                    @"YTDMDownloadQueueUpdated"
                object:nil];

            __weak YTDMDownloadQueueItem *
                weakItem =
                nextItem;

            [YTDownloadManagerService
                sharedInstance]
                .fileProgressCallback =
                ^(float progress) {

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    YTDMDownloadQueueItem *
                        strongItem =
                        weakItem;

                    if (!strongItem) {
                        return;
                    }

                    strongItem.currentProgress =
                        progress;

                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:
                            @"YTDMDownloadQueueProgressNotification"
                        object:
                            strongItem];
                });
            };

            // ------------------------------------------------------------
            // MX UPSCALE
            // ------------------------------------------------------------

            if (nextItem.upscaleEnabled &&
                nextItem.upscaleTarget.length > 0) {

                NSString *target =
                    [nextItem.upscaleTarget copy];

                [[YTDownloadManagerService
                    sharedInstance]
                    requestUpscaleDownloadForVideoId:
                        nextItem.videoId
                    target:
                        target
                    completion:
                    ^(NSArray<NSURL *> *localURLs,
                      NSString *errorMsg) {

                    dispatch_async(
                        dispatch_get_main_queue(), ^{

                        if (localURLs &&
                            localURLs.count > 0) {

                            NSURL *sourceURL =
                                localURLs.firstObject;

                            NSString *cacheDir =
                                [NSSearchPathForDirectoriesInDomains(
                                    NSCachesDirectory,
                                    NSUserDomainMask,
                                    YES)
                                    firstObject];

                            NSString *safePermanentPath =
                                [cacheDir
                                    stringByAppendingPathComponent:
                                        sourceURL.lastPathComponent];

                            NSURL *permanentURL =
                                [NSURL
                                    fileURLWithPath:
                                        safePermanentPath];

                            [[NSFileManager defaultManager]
                                removeItemAtURL:
                                    permanentURL
                                error:nil];

                            if ([[NSFileManager defaultManager]
                                moveItemAtURL:
                                    sourceURL
                                toURL:
                                    permanentURL
                                error:nil]) {

                                nextItem.savedSandboxURL =
                                    permanentURL;

                                nextItem.status =
                                    @"Completed";

                                nextItem.currentProgress =
                                    1.0;

                            } else {

                                nextItem.status =
                                    @"Storage Error";
                            }

                        } else {

                            nextItem.status =
                                @"Failed";
                        }

                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:
                                @"YTDMDownloadQueueUpdated"
                            object:nil];

                        [self
                            processNext];
                    });
                }];

                return;
            }

            // ------------------------------------------------------------
            // NORMAL DOWNLOAD
            // ------------------------------------------------------------

            [[YTDownloadManagerService
                sharedInstance]
                requestDownloadForVideoId:
                    nextItem.videoId
                isAudio:
                    nextItem.isAudio
                quality:
                    nextItem.quality
                completion:
                ^(NSArray<NSURL *> *localURLs,
                  NSString *errorMsg) {

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    if (localURLs &&
                        localURLs.count > 0) {

                        NSURL *sourceURL =
                            localURLs.firstObject;

                        NSString *cacheDir =
                            [NSSearchPathForDirectoriesInDomains(
                                NSCachesDirectory,
                                NSUserDomainMask,
                                YES)
                                firstObject];

                        NSString *safePermanentPath =
                            [cacheDir
                                stringByAppendingPathComponent:
                                    sourceURL.lastPathComponent];

                        NSURL *permanentURL =
                            [NSURL
                                fileURLWithPath:
                                    safePermanentPath];

                        [[NSFileManager defaultManager]
                            removeItemAtURL:
                                permanentURL
                            error:nil];

                        if ([[NSFileManager defaultManager]
                            moveItemAtURL:
                                sourceURL
                            toURL:
                                permanentURL
                            error:nil]) {

                            nextItem.savedSandboxURL =
                                permanentURL;

                            nextItem.status =
                                @"Completed";

                            nextItem.currentProgress =
                                1.0;

                        } else {

                            nextItem.status =
                                @"Storage Error";
                        }

                    } else {

                        nextItem.status =
                            @"Failed";
                    }

                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:
                            @"YTDMDownloadQueueUpdated"
                        object:nil];

                    [self
                        processNext];
                });
            }];

        } else {

            if (anyItemDownloading) {
                return;
            }

            _isDownloading =
                NO;

            dispatch_async(
                dispatch_get_main_queue(), ^{

                [self
                    finalizeBatchProcess];
            });
        }
    }
}

// ============================================================================
// FINALIZE BATCH
// ============================================================================

- (void)finalizeBatchProcess {

    [[YTDMProgressHUD sharedHUD]
        dismiss];

    NSMutableArray<NSURL *> *
        finalStandardVideoURLs =
            [NSMutableArray array];

    NSMutableArray<NSURL *> *
        finalHighResVideoURLs =
            [NSMutableArray array];

    NSMutableArray<NSURL *> *
        finalAudioURLs =
            [NSMutableArray array];

    @synchronized(self) {

        for (YTDMDownloadQueueItem *item
             in _videoDownloadQueue) {

            if ([item.status
                 isEqualToString:
                    @"Completed"] &&
                item.savedSandboxURL) {

                BOOL isHighRes =
                    item.upscaleEnabled ||
                    [item.quality isEqualToString:@"2K"] ||
                    [item.quality isEqualToString:@"4K"] ||
                    [item.quality isEqualToString:@"6K"] ||
                    [item.quality isEqualToString:@"8K"];

                if (isHighRes) {

                    [finalHighResVideoURLs
                        addObject:
                            item.savedSandboxURL];

                } else {

                    [finalStandardVideoURLs
                        addObject:
                            item.savedSandboxURL];
                }
            }
        }

        for (YTDMDownloadQueueItem *item
             in _audioDownloadQueue) {

            if ([item.status
                 isEqualToString:
                    @"Completed"] &&
                item.savedSandboxURL) {

                [finalAudioURLs
                    addObject:
                        item.savedSandboxURL];
            }
        }
    }

    NSMutableArray<NSURL *> *
        combinedAllURLs =
            [NSMutableArray
                arrayWithArray:
                    finalStandardVideoURLs];

    [combinedAllURLs
        addObjectsFromArray:
            finalHighResVideoURLs];

    [combinedAllURLs
        addObjectsFromArray:
            finalAudioURLs];

    if (combinedAllURLs.count == 0) {
        return;
    }

    UIViewController *topMost =
        getTopMostController();

    if (!topMost) {
        return;
    }

    UIAlertController *actionSheet =
        [UIAlertController
            alertControllerWithTitle:
                @"Queue Downloads Completed!"
            message:
                @"Choose how to export your batch files:"
            preferredStyle:
                UIAlertControllerStyleActionSheet];

    if (finalStandardVideoURLs.count > 0) {

        [actionSheet
            addAction:
            [UIAlertAction
                actionWithTitle:
                    @"📸 Save Standard Videos to Photos"
                style:
                    UIAlertActionStyleDefault
                handler:
                ^(UIAlertAction *a) {

            [[YTDMProgressHUD sharedHUD]
                showInView:
                    getKeyWindow()];

            __block NSInteger remainingPhotos =
                finalStandardVideoURLs.count;

            __block NSString *
                lastErrorMessage =
                    nil;

            for (NSURL *vURL
                 in finalStandardVideoURLs) {

                [YTDMPhotoSaver
                    saveVideoPath:
                        vURL.path
                    completion:
                    ^(BOOL success,
                      NSError *error) {

                    dispatch_async(
                        dispatch_get_main_queue(), ^{

                        if (!success) {

                            lastErrorMessage =
                                error.localizedDescription;
                        }

                        remainingPhotos--;

                        if (remainingPhotos == 0) {

                            if (!lastErrorMessage) {

                                [[YTDMProgressHUD sharedHUD]
                                    showSuccessWithStatus:
                                        @"Saved to Gallery!"];

                            } else {

                                [[YTDMProgressHUD sharedHUD]
                                    showError:
                                        [NSString
                                            stringWithFormat:
                                                @"Error: %@",
                                                lastErrorMessage]];
                            }

                            dispatch_after(
                                dispatch_time(
                                    DISPATCH_TIME_NOW,
                                    (int64_t)
                                        (2.0 *
                                         NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{

                                [self
                                    cleanUpTemporaryFiles];
                            });
                        }
                    });
                }];
            }
        }]];
    }

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"📁 Save All to Files (Document Picker)"
            style:
                UIAlertActionStyleDefault
            handler:
            ^(UIAlertAction *a) {

        if (@available(iOS 14.0, *)) {

            UIDocumentPickerViewController *picker =
                [[UIDocumentPickerViewController alloc]
                    initForExportingURLs:
                        combinedAllURLs
                    asCopy:
                        YES];

            picker.delegate =
                self;

            objc_setAssociatedObject(
                picker,
                &kAssociatedOutURLKey,
                combinedAllURLs,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [topMost
                presentViewController:
                    picker
                animated:
                    YES
                completion:
                    nil];
        }
    }]];

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"🔗 Open Share Sheet"
            style:
                UIAlertActionStyleDefault
            handler:
            ^(UIAlertAction *a) {

        UIActivityViewController *share =
            [[UIActivityViewController alloc]
                initWithActivityItems:
                    combinedAllURLs
                applicationActivities:
                    nil];

        share.completionWithItemsHandler =
            ^(UIActivityType actType,
              BOOL completed,
              NSArray *retItems,
              NSError *err) {

            [self
                cleanUpTemporaryFiles];
        };

        [topMost
            presentViewController:
                share
            animated:
                YES
            completion:
                nil];
    }]];

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"Cancel & Clear Temp"
            style:
                UIAlertActionStyleCancel
            handler:
            ^(UIAlertAction *a) {

        [self
            cleanUpTemporaryFiles];
    }]];

    [topMost
        presentViewController:
            actionSheet
        animated:
            YES
        completion:
            nil];
}

// ============================================================================
// DOCUMENT PICKER
// ============================================================================

- (void)documentPicker:
    (UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:
    (NSArray<NSURL *> *)urls {

    [self
        cleanUpTemporaryFiles];
}

- (void)documentPickerWasCancelled:
    (UIDocumentPickerViewController *)controller {

    [self
        cleanUpTemporaryFiles];
}

// ============================================================================
// CLEANUP
// ============================================================================

- (void)cleanUpTemporaryFiles {

    @synchronized(self) {

        for (YTDMDownloadQueueItem *item
             in _videoDownloadQueue) {

            if (item.savedSandboxURL) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        item.savedSandboxURL
                    error:nil];

                item.savedSandboxURL =
                    nil;
            }
        }

        for (YTDMDownloadQueueItem *item
             in _audioDownloadQueue) {

            if (item.savedSandboxURL) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        item.savedSandboxURL
                    error:nil];

                item.savedSandboxURL =
                    nil;
            }
        }
    }
}

@end

// ============================================================================
// DOWNLOAD QUEUE INSPECTOR
// ============================================================================

@interface YTDMDownloadQueueViewController :
UIViewController
<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong)
UITableView *tableView;

@end

@implementation YTDMDownloadQueueViewController

- (void)viewDidLoad {

    [super viewDidLoad];

    self.title =
        @"Download Queue Inspector";

    self.view.backgroundColor =
        [UIColor systemBackgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithTitle:
                @"Close"
            style:
                UIBarButtonItemStyleDone
            target:
                self
            action:
                @selector(close)];

    UIBarButtonItem *downloadAllBtn =
        [[UIBarButtonItem alloc]
            initWithTitle:
                @"Download All"
            style:
                UIBarButtonItemStylePlain
            target:
                self
            action:
                @selector(triggerDownloadBatch)];

    downloadAllBtn.tintColor =
        [UIColor systemGreenColor];

    UIBarButtonItem *clearBtn =
        [[UIBarButtonItem alloc]
            initWithTitle:
                @"Clear All"
            style:
                UIBarButtonItemStylePlain
            target:
                self
            action:
                @selector(clearAll)];

    self.navigationItem.rightBarButtonItems =
        @[clearBtn, downloadAllBtn];

    self.tableView =
        [[UITableView alloc]
            initWithFrame:
                self.view.bounds
            style:
                UITableViewStyleInsetGrouped];

    self.tableView.dataSource =
        self;

    self.tableView.delegate =
        self;

    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [self.tableView
        setEditing:
            YES
        animated:
            NO];

    [self.view
        addSubview:
            self.tableView];

    [[NSNotificationCenter defaultCenter]
        addObserver:
            self
        selector:
            @selector(reloadQueueData)
        name:
            @"YTDMDownloadQueueUpdated"
        object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:
            self
        selector:
            @selector(handleProgressNotification:)
        name:
            @"YTDMDownloadQueueProgressNotification"
        object:nil];
}

- (void)viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];

    [self.tableView
        reloadData];
}

- (void)dealloc {

    [[NSNotificationCenter defaultCenter]
        removeObserver:
            self];
}

- (void)reloadQueueData {

    if ([YTDMDownloadQueueManager
            sharedInstance]
        .isCurrentlyReordering) {

        return;
    }

    dispatch_async(
        dispatch_get_main_queue(), ^{

        [self.tableView
            reloadData];
    });
}

- (void)handleProgressNotification:
    (NSNotification *)notification {

    YTDMDownloadQueueItem *updatedItem =
        (YTDMDownloadQueueItem *)
            notification.object;

    dispatch_async(
        dispatch_get_main_queue(), ^{

        for (UITableViewCell *cell
             in self.tableView.visibleCells) {

            UILabel *titleContext =
                [cell.contentView
                    viewWithTag:
                        8822];

            if (titleContext &&
                [titleContext.text
                    isEqualToString:
                        updatedItem.videoTitle]) {

                UIProgressView *pv =
                    [cell.contentView
                        viewWithTag:
                            8821];

                UILabel *statusLbl =
                    (UILabel *)
                        cell.accessoryView;

                if (pv) {

                    pv.hidden =
                        NO;

                    [pv
                        setProgress:
                            updatedItem.currentProgress
                        animated:
                            YES];
                }

                if (statusLbl) {

                    statusLbl.text =
                        [NSString
                            stringWithFormat:
                                @"%.0f%%",
                                updatedItem.currentProgress *
                                100.0];
                }
            }
        }
    });
}

- (void)close {

    [self
        dismissViewControllerAnimated:
            YES
        completion:
            nil];
}

- (void)clearAll {

    [[YTDMDownloadQueueManager
        sharedInstance]
        clearDownloadQueue];
}

- (void)triggerDownloadBatch {

    [[YTDMProgressHUD sharedHUD]
        showInView:
            getKeyWindow()];

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            0.0
        status:
            @"Syncing Download Queue..."];

    [[YTDMDownloadQueueManager
        sharedInstance]
        startBatchDownloading];
}

- (NSInteger)numberOfSectionsInTableView:
    (UITableView *)tableView {

    return 2;
}

- (NSInteger)tableView:
    (UITableView *)tableView
numberOfRowsInSection:
    (NSInteger)section {

    return
        (section == 0)
        ? [YTDMDownloadQueueManager
              sharedInstance]
              .videoDownloadQueue.count
        : [YTDMDownloadQueueManager
              sharedInstance]
              .audioDownloadQueue.count;
}

- (NSString *)tableView:
    (UITableView *)tableView
titleForHeaderInSection:
    (NSInteger)section {

    if (section == 0) {

        return
            [YTDMDownloadQueueManager
                sharedInstance]
                .videoDownloadQueue.count > 0
            ? @"📹 Video Download Queue"
            : nil;
    }

    return
        [YTDMDownloadQueueManager
            sharedInstance]
            .audioDownloadQueue.count > 0
        ? @"🎵 Audio Download Queue"
        : nil;
}

- (CGFloat)tableView:
    (UITableView *)tableView
heightForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    return 65.0;
}

- (UITableViewCell *)tableView:
    (UITableView *)tableView
cellForRowAtIndexPath:
    (NSIndexPath *)indexPath {

    static NSString *cellId =
        @"OptimizedQueueCell";

    UITableViewCell *cell =
        [tableView
            dequeueReusableCellWithIdentifier:
                cellId];

    UILabel *titleLabel =
        nil;

    UIProgressView *progressView =
        nil;

    UILabel *statusLabel =
        nil;

    if (!cell) {

        cell =
            [[UITableViewCell alloc]
                initWithStyle:
                    UITableViewCellStyleDefault
                reuseIdentifier:
                    cellId];

        cell.showsReorderControl =
            YES;

        titleLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        16,
                        12,
                        cell.contentView.frame.size.width - 150,
                        20)];

        titleLabel.font =
            [UIFont
                systemFontOfSize:
                    13
                weight:
                    UIFontWeightBold];

        titleLabel.tag =
            8822;

        [cell.contentView
            addSubview:
                titleLabel];

        progressView =
            [[UIProgressView alloc]
                initWithProgressViewStyle:
                    UIProgressViewStyleDefault];

        progressView.frame =
            CGRectMake(
                16,
                44,
                cell.contentView.frame.size.width - 140,
                4);

        progressView.progressTintColor =
            [UIColor systemBlueColor];

        progressView.tag =
            8821;

        [cell.contentView
            addSubview:
                progressView];

        statusLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        cell.contentView.frame.size.width - 120,
                        15,
                        100,
                        30)];

        statusLabel.font =
            [UIFont
                systemFontOfSize:
                    12
                weight:
                    UIFontWeightBold];

        statusLabel.textAlignment =
            NSTextAlignmentRight;

        cell.accessoryView =
            statusLabel;

    } else {

        titleLabel =
            [cell.contentView
                viewWithTag:
                    8822];

        progressView =
            [cell.contentView
                viewWithTag:
                    8821];

        statusLabel =
            (UILabel *)cell.accessoryView;
    }

    YTDMDownloadQueueItem *item =
        (indexPath.section == 0)
        ? [YTDMDownloadQueueManager
              sharedInstance]
              .videoDownloadQueue[indexPath.row]
        : [YTDMDownloadQueueManager
              sharedInstance]
              .audioDownloadQueue[indexPath.row];

    titleLabel.text =
        item.videoTitle;

    if ([item.status
         isEqualToString:
            @"Downloading..."]) {

        statusLabel.text =
            [NSString
                stringWithFormat:
                    @"%.0f%%",
                    item.currentProgress *
                    100.0];

        statusLabel.textColor =
            [UIColor systemGreenColor];

        progressView.hidden =
            NO;

    } else {

        statusLabel.text =
            item.status;

        statusLabel.textColor =
            [item.status
                isEqualToString:
                    @"Completed"]
            ? [UIColor systemBlueColor]
            : [UIColor systemGrayColor];

        progressView.hidden =
            ![item.status
                isEqualToString:
                    @"Completed"];
    }

    [progressView
        setProgress:
            item.currentProgress
        animated:
            NO];

    return cell;
}

- (BOOL)tableView:
    (UITableView *)tableView
canMoveRowAtIndexPath:
    (NSIndexPath *)indexPath {

    return YES;
}

- (void)tableView:
    (UITableView *)tableView
moveRowAtIndexPath:
    (NSIndexPath *)sourceIndexPath
toIndexPath:
    (NSIndexPath *)destinationIndexPath {

    [[YTDMDownloadQueueManager
        sharedInstance]
        moveItemFromSection:
            sourceIndexPath.section
        fromRow:
            sourceIndexPath.row
        toSection:
            destinationIndexPath.section
        toRow:
            destinationIndexPath.row];
}

- (void)tableView:
    (UITableView *)tableView
commitEditingStyle:
    (UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:
    (NSIndexPath *)indexPath {

    if (editingStyle ==
        UITableViewCellEditingStyleDelete) {

        YTDMDownloadQueueItem *item =
            (indexPath.section == 0)
            ? [YTDMDownloadQueueManager
                  sharedInstance]
                  .videoDownloadQueue[indexPath.row]
            : [YTDMDownloadQueueManager
                  sharedInstance]
                  .audioDownloadQueue[indexPath.row];

        [[YTDMDownloadQueueManager
            sharedInstance]
            removeItem:
                item];
    }
}

@end

// ============================================================================
// DOWNLOADS TAB
//
// Injects a pivot bar item that opens YTDMDownloadsViewController.
// Items are built with the same YTIPivotBarRenderer factory call the native
// tab bar uses, and the hosting browse controller adopts the downloads
// controller as a child, so YouTube owns navigation and we only supply
// content.
// ============================================================================

static NSString * const YTDMPivotIdentifier = @"FEYTDMDownloads";
static NSString * const YTDMPivotTitle = @"Downloads";
static const void *YTDMDownloadsAssociation = &YTDMDownloadsAssociation;
static IMP YTDMPreviousSetPivotRenderer;
// Original implementations are kept in a plain C table keyed by class and
// selector name. Associated objects cannot hold them: a Class is not an ObjC
// object type under ARC, and bridging an IMP to id is rejected outright.
static NSMutableDictionary<NSString *, NSValue *> *YTDMPreviousIMPs(void) {
    static NSMutableDictionary<NSString *, NSValue *> *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = [NSMutableDictionary dictionary];
    });
    return table;
}

static NSString *YTDMOriginalKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"YTDM.original.%@.%@",
            NSStringFromClass(cls),
            NSStringFromSelector(selector)];
}

// Installs a replacement using class_addMethod first, so an inherited
// viewDidLoad is shadowed on the subclass instead of being overwritten on
// whichever class actually declares it. Overwriting a superclass
// implementation with a function that assumes the subclass layout is what
// makes the replacement run against the wrong self.
static void YTDMInstallInstanceHook(Class cls,
                                    SEL selector,
                                    IMP replacement) {
    if (cls == Nil ||
        selector == NULL ||
        replacement == NULL) {
        return;
    }

    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return;
    }

    // If this class is already hooked, the captured original is stored and
    // swapping the implementation again is safe. Otherwise the method we
    // just read is our own replacement and must never be captured.
    NSString *key = YTDMOriginalKey(cls, selector);
    if (YTDMPreviousIMPs()[key] != nil) {
        method_setImplementation(
            class_getInstanceMethod(cls, selector),
            replacement);
        return;
    }

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);

    if (!class_addMethod(cls,
                         selector,
                         replacement,
                         types)) {
        method_setImplementation(
            class_getInstanceMethod(cls, selector),
            replacement);
    }

    @synchronized (YTDMPreviousIMPs()) {
        YTDMPreviousIMPs()[key] =
            [NSValue valueWithPointer:(const void *)original];
    }
}

static BOOL YTDMDownloadsTabEnabled(void) {
    id value =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:
                @"YTDM_ShowDownloadsTab"];
    return value ? [value boolValue] : YES;
}

static id YTDMHookedValue(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (receiver == nil || ![receiver respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static void YTDMHookedSetValue(id receiver,
                               NSString *selectorName,
                               id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (receiver == nil || ![receiver respondsToSelector:selector]) {
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, value);
}

static id YTDMHookedNew(NSString *className) {
    Class cls = NSClassFromString(className);
    return cls == Nil ? nil : [[cls alloc] init];
}

static id YTDMMakePivotItem(void) {

    Class rendererClass =
        NSClassFromString(@"YTIPivotBarRenderer");

    SEL factory =
        NSSelectorFromString(
            @"pivotSupportedRenderersWithBrowseId:title:iconType:");

    if (rendererClass != Nil &&
        [rendererClass respondsToSelector:factory]) {

        id renderer =
            ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(
                rendererClass,
                factory,
                YTDMPivotIdentifier,
                YTDMPivotTitle,
                (NSInteger)YT_TAB_LIBRARY);

        id item =
            YTDMHookedValue(renderer,
                            @"pivotBarItemRenderer");

        if (item != nil) {
            YTDMHookedSetValue(item,
                               @"setPivotIdentifier:",
                               YTDMPivotIdentifier);
        }

        if (renderer != nil) {
            return renderer;
        }
    }

    id browseEndpoint =
        YTDMHookedNew(@"YTIBrowseEndpoint");
    id command =
        YTDMHookedNew(@"YTICommand");
    id itemRenderer =
        YTDMHookedNew(@"YTIPivotBarItemRenderer");
    id supportedRenderer =
        YTDMHookedNew(@"YTIPivotBarSupportedRenderers");
    Class formattedClass =
        NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector =
        NSSelectorFromString(@"formattedStringWithString:");

    if (browseEndpoint == nil ||
        command == nil ||
        itemRenderer == nil ||
        supportedRenderer == nil ||
        formattedClass == Nil ||
        ![formattedClass respondsToSelector:formattedSelector]) {
        return nil;
    }

    YTDMHookedSetValue(browseEndpoint,
                       @"setBrowseId:",
                       YTDMPivotIdentifier);
    YTDMHookedSetValue(command,
                       @"setBrowseEndpoint:",
                       browseEndpoint);
    YTDMHookedSetValue(itemRenderer,
                       @"setPivotIdentifier:",
                       YTDMPivotIdentifier);
    YTDMHookedSetValue(itemRenderer,
                       @"setNavigationEndpoint:",
                       command);
    YTDMHookedSetValue(itemRenderer,
                       @"setTitle:",
                       ((id (*)(id, SEL, id))objc_msgSend)(
                           formattedClass,
                           formattedSelector,
                           YTDMPivotTitle));

    id icon =
        YTDMHookedValue(itemRenderer,
                        @"icon");
    SEL setIconType =
        NSSelectorFromString(@"setIconType:");

    if ([icon respondsToSelector:setIconType]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(
            icon,
            setIconType,
            (NSInteger)YT_TAB_LIBRARY);
    }

    YTDMHookedSetValue(supportedRenderer,
                       @"setPivotBarItemRenderer:",
                       itemRenderer);

    return supportedRenderer;
}

static NSArray *YTDMTabItems(id renderer,
                             NSString **setterName) {

    NSArray<NSString *> *getters = @[
        @"itemsArray",
        @"items",
        @"pivotBarItemsArray",
        @"pivotBarItems"
    ];

    NSArray<NSString *> *setters = @[
        @"setItemsArray:",
        @"setItems:",
        @"setPivotBarItemsArray:",
        @"setPivotBarItems:"
    ];

    for (NSUInteger index = 0;
         index < getters.count;
         index++) {

        id value =
            YTDMHookedValue(renderer,
                            getters[index]);

        if ([value isKindOfClass:NSArray.class]) {
            if (setterName != NULL) {
                *setterName = setters[index];
            }
            return value;
        }
    }

    return nil;
}

static NSString *YTDMBrowseIdentifier(
    UIViewController *controller) {

    id endpoint =
        YTDMHookedValue(controller,
                        @"navigationEndpoint");

    if (endpoint == nil) {
        endpoint =
            YTDMHookedValue(controller,
                            @"navEndpoint");
    }

    if (endpoint == nil) {
        @try {
            endpoint =
                [controller valueForKey:@"_navEndpoint"];
        } @catch (__unused NSException *exception) {
        }
    }

    id browseEndpoint =
        YTDMHookedValue(endpoint,
                        @"browseEndpoint");

    if (browseEndpoint == nil &&
        [endpoint respondsToSelector:
            NSSelectorFromString(@"browseId")]) {
        browseEndpoint = endpoint;
    }

    return YTDMHookedValue(browseEndpoint,
                           @"browseId");
}

static void YTDMAttachDownloads(
    UIViewController *controller) {

    if (!YTDMDownloadsTabEnabled() ||
        ![YTDMBrowseIdentifier(controller)
            isEqualToString:YTDMPivotIdentifier] ||
        objc_getAssociatedObject(
            controller,
            YTDMDownloadsAssociation) != nil) {
        return;
    }

    YTDMDownloadsViewController *downloads =
        [[YTDMDownloadsViewController alloc] init];

    [controller addChildViewController:downloads];

    downloads.view.frame =
        controller.view.bounds;
    downloads.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [controller.view addSubview:downloads.view];

    [downloads didMoveToParentViewController:controller];

    objc_setAssociatedObject(
        controller,
        YTDMDownloadsAssociation,
        downloads,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTDMTryAttachDownloads(
    UIViewController *controller) {

    YTDMAttachDownloads(controller);

    if (objc_getAssociatedObject(
            controller,
            YTDMDownloadsAssociation) == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTDMAttachDownloads(controller);
        });
    }
}

static void YTDMPivotRendererSet(id receiver,
                                 SEL selector,
                                 id renderer) {

    IMP previous = YTDMPreviousSetPivotRenderer;

    if (renderer != nil &&
        YTDMDownloadsTabEnabled()) {

        NSString *setterName = nil;
        NSArray *items =
            YTDMTabItems(renderer,
                         &setterName);

        if (items != nil) {

            NSMutableArray *filtered =
                [items mutableCopy];

            BOOL alreadyPresent = NO;

            for (id item in filtered) {
                NSString *identifier =
                    YTDMHookedValue(
                        YTDMHookedValue(
                            item,
                            @"pivotBarItemRenderer"),
                        @"pivotIdentifier");
                if ([identifier
                        isEqualToString:
                            YTDMPivotIdentifier]) {
                    alreadyPresent = YES;
                    break;
                }
            }

            if (!alreadyPresent) {

                id downloadItem =
                    YTDMMakePivotItem();

                if (downloadItem != nil) {

                    [filtered addObject:downloadItem];

                    SEL setter =
                        NSSelectorFromString(setterName);

                    if ([items
                            isKindOfClass:
                                NSMutableArray.class]) {
                        [(NSMutableArray *)items
                            setArray:filtered];
                    } else if ([renderer
                                   respondsToSelector:
                                       setter]) {
                        ((void (*)(id, SEL, id))
                            objc_msgSend)(
                                renderer,
                                setter,
                                filtered);
                    }
                }
            }
        }
    }

    if (previous != NULL) {
        ((void (*)(id, SEL, id))previous)(
            receiver,
            selector,
            renderer);
    }
}

static void YTDMPivotControllerDidLoad(
    id receiver,
    SEL selector) {

    Class cls = object_getClass(receiver);
    NSValue *stored = cls == Nil
        ? nil
        : YTDMPreviousIMPs()[YTDMOriginalKey(cls, selector)];
    IMP original = (IMP)[stored pointerValue];

    if (original != NULL && original != (IMP)YTDMPivotControllerDidLoad) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }

    if ([receiver isKindOfClass:UIViewController.class]) {
        YTDMTryAttachDownloads(
            (UIViewController *)receiver);
    }
}

// YTAppViewController and the browse wrappers host the content controller
// that the pivot bar swaps in, so each one is a candidate landing point.
__attribute__((constructor))
static void YTDMDownloadsTabInit(void) {

    id value =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:
                @"YTDM_ShowDownloadsTab"];

    if (value == nil) {
        [[NSUserDefaults standardUserDefaults]
            setBool:YES
            forKey:
                @"YTDM_ShowDownloadsTab"];
    }

    Class pivotBarView =
        NSClassFromString(@"YTPivotBarView");

    SEL rendererSetter =
        NSSelectorFromString(@"setRenderer:");

    if (pivotBarView == Nil ||
        ![pivotBarView
            instancesRespondToSelector:
                rendererSetter]) {
        return;
    }

    YTDMInstallInstanceHook(pivotBarView,
                            rendererSetter,
                            (IMP)YTDMPivotRendererSet);

    NSValue *rendererOriginal =
        YTDMPreviousIMPs()[YTDMOriginalKey(pivotBarView, rendererSetter)];

    if (rendererOriginal == nil) {
        return;
    }

    YTDMPreviousSetPivotRenderer =
        (IMP)[rendererOriginal pointerValue];

    NSArray<NSString *> *hostClasses = @[
        @"YTAppViewController",
        @"YTBrowseViewController",
        @"YTBrowseResponseViewController",
        @"YTWrapperFlatViewController"
    ];

    for (NSString *className in hostClasses) {

        Class hostClass =
            NSClassFromString(className);

        if (hostClass == Nil) {
            continue;
        }

        YTDMInstallInstanceHook(
            hostClass,
            @selector(viewDidLoad),
            (IMP)YTDMPivotControllerDidLoad);
    }
}



%hook YTSingleVideo

- (NSString *)videoId {

    NSString *vId =
        %orig;

    if (vId.length > 0) {

        capturedVideoId =
            [vId copy];
    }

    return vId;
}

%end

// ============================================================================
// YTVIDEOOVERLAY BUTTON CREATION
// ============================================================================

#import <dlfcn.h>
#import <objc/message.h>

#define TweakKey @"YTDownloadManager"

#define AccessibilityLabelKey @"accessibilityLabel"
#define ToggleKey @"toggle"
#define AsTextKey @"asText"
#define SelectorKey @"selector"
#define UpdateImageOnVisibleKey @"updateImageOnVisible"
#define ExtraBooleanKeys @"extraBooleanKeys"

@interface _ASDisplayView : UIView
@end

@interface YTMainAppControlsOverlayView : UIView
- (UIImage *)buttonImage:(NSString *)tweakId;
- (void)didPressDownload:(id)arg;
@end

@interface YTInlinePlayerBarContainerView : UIView
- (UIImage *)buttonImage:(NSString *)tweakId;
- (void)didPressDownload:(id)arg;
@end

@interface YTPlayerViewController : UIViewController
- (NSString *)currentVideoID;
- (void)setCurrentVideoID:(NSString *)videoID;
@end

static void initYTVideoOverlay(NSString *tweakKey, NSDictionary *metadata) {

    dlopen(
        [[NSString stringWithFormat:
            @"%@/Frameworks/YTVideoOverlay.dylib",
            [[NSBundle mainBundle] bundlePath]]
        UTF8String],
        RTLD_LAZY);

    dlopen(
        "/Library/MobileSubstrate/DynamicLibraries/YTVideoOverlay.dylib",
        RTLD_LAZY);

    Class managerClass =
        NSClassFromString(@"YTSettingsSectionItemManager");

    if ([managerClass
         respondsToSelector:
            @selector(registerTweak:metadata:)]) {

        ((void (*)(id, SEL, NSString *, NSDictionary *))objc_msgSend)(
            managerClass,
            @selector(registerTweak:metadata:),
            tweakKey,
            metadata);
    }
}

static UIImage *downloadOverlayButtonImage(void) {

    if (@available(iOS 13.0, *)) {

        UIImage *image =
            [UIImage systemImageNamed:@"arrow.down.circle"];

        if (!image) {
            image =
                [UIImage systemImageNamed:@"arrow.down"];
        }

        return image;
    }

    return nil;
}

static NSString *currentCapturedVideoId(void) {

    if (capturedVideoId.length > 0) {
        return capturedVideoId;
    }

    UIViewController *topVC =
        getTopMostController();

    if ([topVC respondsToSelector:@selector(currentVideoID)]) {

        NSString *vId =
            [(id)topVC currentVideoID];

        if (vId.length > 0) {
            return vId;
        }
    }

    return nil;
}

// ============================================================================
//                             MENU
// ============================================================================


@interface UIView (YTDownloadManager) 

- (UIViewController *)ytdm_parentViewController;
- (void)ytdm_openDownloadQueueInspector;
- (void)ytdm_triggerSilentDownloadWithQuality:(NSString *)quality isAudio:(BOOL)isAudio;
- (void)ytdm_triggerUpscaleDownloadWithTarget:(NSString *)target;
- (void)ytdm_presentSaveOptionsForURLs:(NSArray<NSURL *> *)outURLs isAudio:(BOOL)isAudio quality:(NSString *)quality;
- (void)ytdm_copyToClipboardWithText:(NSString *)text alertMsg:(NSString *)alertMsg;
- (void)ytdm_playInSystemPlayer;
- (void)ytdm_downloadThumbnail;
- (void)ytdm_copyToClipboardWithText: (NSString *)text alertMsg:(NSString *)alertMsg;
@end

static UIMenu *YTDMBuildMenu(UIView *owner) {

    if (@available(iOS 14.0, *)) {

        __weak UIView *weakOwner = owner;

        UIAction *v1080 =
            [UIAction
                actionWithTitle:@"Video (1080p)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerSilentDownloadWithQuality:@"1080p"
                        isAudio:NO];
                }];

        UIAction *v720 =
            [UIAction
                actionWithTitle:@"Video (720p)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerSilentDownloadWithQuality:@"720p"
                        isAudio:NO];
                }];

        UIAction *v360 =
            [UIAction
                actionWithTitle:@"Video (360p)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerSilentDownloadWithQuality:@"360p"
                        isAudio:NO];
                }];

        UIAction *audioOnly =
            [UIAction
                actionWithTitle:@"Audio Only"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerSilentDownloadWithQuality:nil
                        isAudio:YES];
                }];

        UIMenu *instantMenu =
            [UIMenu
                menuWithTitle:@"Direct Download"
                children:@[
                    v1080,
                    v720,
                    v360,
                    audioOnly
                ]];

        UIAction *upscale2K =
            [UIAction
                actionWithTitle:@"Video (2K / QHD)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerUpscaleDownloadWithTarget:@"2K"];
                }];

        UIAction *upscale4K =
            [UIAction
                actionWithTitle:@"Video (4K)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerUpscaleDownloadWithTarget:@"4K"];
                }];

        UIAction *upscale8K =
            [UIAction
                actionWithTitle:@"Video (8K)"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_triggerUpscaleDownloadWithTarget:@"8K"];
                }];

        UIMenu *upscaleMenu =
            [UIMenu
                menuWithTitle:@"MX-UPscale"
                children:@[
                    upscale2K,
                    upscale4K,
                    upscale8K
                ]];

        UIAction *viewQueue =
            [UIAction
                actionWithTitle:@"Open Download Queue Inspector"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_openDownloadQueueInspector];
                }];

        UIAction *q1080 =
            [UIAction
                actionWithTitle:@"Add Video (1080p) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueVideoId:vId
                            isAudio:NO
                            quality:@"1080p"];
                    }
                }];

        UIAction *q720 =
            [UIAction
                actionWithTitle:@"Add Video (720p) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueVideoId:vId
                            isAudio:NO
                            quality:@"720p"];
                    }
                }];

        UIAction *q360 =
            [UIAction
                actionWithTitle:@"Add Video (360p) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueVideoId:vId
                            isAudio:NO
                            quality:@"360p"];
                    }
                }];

        UIAction *audioQueue =
            [UIAction
                actionWithTitle:@"Add Audio to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueVideoId:vId
                            isAudio:YES
                            quality:nil];
                    }
                }];

        UIAction *q2K =
            [UIAction
                actionWithTitle:@"Add Video (2K / QHD) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueUpscaleVideoId:vId
                            target:@"2K"];
                    }
                }];

        UIAction *q4K =
            [UIAction
                actionWithTitle:@"Add Video (4K) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueUpscaleVideoId:vId
                            target:@"4K"];
                    }
                }];

        UIAction *q8K =
            [UIAction
                actionWithTitle:@"Add Video (8K) to Download Queue"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {
                    NSString *vId = currentCapturedVideoId();
                    if (vId.length > 0) {
                        [[YTDMDownloadQueueManager sharedInstance]
                            enqueueUpscaleVideoId:vId
                            target:@"8K"];
                    }
                }];

        UIMenu *upscaleQueueMenu =
            [UIMenu
                menuWithTitle:@"MX-UPscale Queue"
                children:@[
                    q2K,
                    q4K,
                    q8K
                ]];

        UIMenu *queueMenu =
            [UIMenu
                menuWithTitle:@"Download Queue System"
                children:@[
                    viewQueue,
                    q1080,
                    q720,
                    q360,
                    audioQueue,
                    upscaleQueueMenu
                ]];

        UIAction *playSys =
            [UIAction
                actionWithTitle:@"Play in System Player"
                image:[UIImage systemImageNamed:@"play.fill"]
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_playInSystemPlayer];
                }];

        UIAction *dlThumb =
            [UIAction
                actionWithTitle:@"Download Thumbnail"
                image:[UIImage systemImageNamed:@"photo"]
                identifier:nil
                handler:^(UIAction *a) {
                    [weakOwner
                        ytdm_downloadThumbnail];
                }];

        UIAction *copyLink =
            [UIAction
                actionWithTitle:@"Copy Video Link"
                image:nil
                identifier:nil
                handler:^(UIAction *a) {

                    NSString *vId =
                        currentCapturedVideoId();

                    if (vId.length > 0) {

                        [weakOwner
                            ytdm_copyToClipboardWithText:
                                [NSString
                                    stringWithFormat:
                                        @"https://youtu.be/%@",
                                        vId]
                            alertMsg:
                                @"Copied Link!"];
                    }
                }];

        return
            [UIMenu
                menuWithTitle:@"YTDM Suite"
                children:@[
                    instantMenu,
                    upscaleMenu,
                    queueMenu,
                    playSys,
                    dlThumb,
                    copyLink
                ]];
    }

    return nil;
}

// YTVideoOverlay creates the button. This only attaches the Tweak.xm menu
// to the actual button after YouTube has placed it in the view hierarchy.
static void YTDMConfigureOverlayButtons(UIView *view) {

    if (!view) {
        return;
    }

    NSMutableArray *pending =
        [NSMutableArray arrayWithObject:view];

    while (pending.count > 0) {

        UIView *candidate =
            pending.lastObject;

        [pending removeLastObject];

        if ([candidate isKindOfClass:[UIButton class]]) {

            UIButton *button =
                (UIButton *)candidate;

            if ([button.accessibilityLabel
                 isEqualToString:@"Download"]) {

                if (@available(iOS 14.0, *)) {

                    button.menu =
                        YTDMBuildMenu(view);

                    button.showsMenuAsPrimaryAction =
                        YES;
                    button.tintColor = [UIColor whiteColor];
                }
            }
        }

        [pending
            addObjectsFromArray:
                candidate.subviews];
    }
}

// ============================================================================
// YTVIDEOOVERLAY HOOKS — CREATION ONLY
// ============================================================================

%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {

    if ([tweakId
         isEqualToString:
            TweakKey]) {

        return
            downloadOverlayButtonImage();
    }

    return %orig;
}

%new(v@:@)
- (void)didPressDownload:(id)arg {

    // Kept for YTVideoOverlay compatibility. Normally the native UIMenu
    // primary-action path handles the tap before this selector is needed.
    if ([arg isKindOfClass:[UIButton class]]) {

        UIButton *button =
            (UIButton *)arg;

        if (@available(iOS 14.0, *)) {

            button.menu =
                YTDMBuildMenu(self);

            button.showsMenuAsPrimaryAction =
                YES;
        }
    }
}

- (void)didMoveToWindow {

    %orig;

    dispatch_async(
        dispatch_get_main_queue(), ^{
            YTDMConfigureOverlayButtons(self);
        });
}

- (void)layoutSubviews {

    %orig;

    YTDMConfigureOverlayButtons(self);
}

%end

%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {

    if ([tweakId
         isEqualToString:
            TweakKey]) {

        return
            downloadOverlayButtonImage();
    }

    return %orig;
}

%new(v@:@)
- (void)didPressDownload:(id)arg {

    if ([arg isKindOfClass:[UIButton class]]) {

        UIButton *button =
            (UIButton *)arg;

        if (@available(iOS 14.0, *)) {

            button.menu =
                YTDMBuildMenu(self);

            button.showsMenuAsPrimaryAction =
                YES;
        }
    }
}

- (void)didMoveToWindow {

    %orig;

    dispatch_async(
        dispatch_get_main_queue(), ^{
            YTDMConfigureOverlayButtons(self);
        });
}

- (void)layoutSubviews {

    %orig;

    YTDMConfigureOverlayButtons(self);
}

%end

// ============================================================================
// PLAYER CONTROLLER VIDEO ID TRACKING
// ============================================================================

%hook YTPlayerViewController

- (void)setCurrentVideoID:(NSString *)videoID {

    %orig;

    if (videoID.length > 0) {
        capturedVideoId =
            [videoID copy];
    }
}

%end

// ============================================================================
// YTVIDEOOVERLAY REGISTRATION
// ============================================================================

%ctor {

    id val =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:
                @"Enable YTDownloadManager"];

    BOOL enabled =
        val
        ? [val boolValue]
        : YES;

    if (!enabled) {
        return;
    }

    NSString *overlayEnabledKey =
        [NSString
            stringWithFormat:
                @"YTVideoOverlay-%@-Enabled",
                TweakKey];

    if ([[NSUserDefaults standardUserDefaults]
         objectForKey:
            overlayEnabledKey] == nil) {

        [[NSUserDefaults standardUserDefaults]
            setBool:YES
            forKey:
                overlayEnabledKey];
    }

    initYTVideoOverlay(
        TweakKey,
        @{
            @"accessibilityLabel": @"Download",
            @"AccessibilityLabel": @"Download",
            @"selector": @"didPressDownload:",
            @"Selector": @"didPressDownload:",
            @"updateImageOnVisible": @YES,
            @"UpdateImageOnVisible": @YES,
        });
}

// ============================================================================
// DOWNLOAD-MANAGER ACTIONS — exact implementations from Tweak.xm
// ============================================================================

// PARENT VIEW CONTROLLER
// ============================================================================

@implementation UIView (YTDownloadManager) 


- (UIViewController *)ytdm_parentViewController {

    UIResponder *responder =
        self;

    while ([responder nextResponder]) {

        responder =
            [responder nextResponder];

        if ([responder
             isKindOfClass:
                [UIViewController class]]) {

            return
                (UIViewController *)responder;
        }
    }

    return nil;
}

// ============================================================================
// QUEUE INSPECTOR
// ============================================================================

- (void)ytdm_openDownloadQueueInspector {

    YTDMDownloadQueueViewController *queueVC =
        [[YTDMDownloadQueueViewController alloc]
            init];

    UINavigationController *nav =
        [[UINavigationController alloc]
            initWithRootViewController:
                queueVC];

    UIViewController *parent =
        [self ytdm_parentViewController];

    if (!parent) {
        parent =
            getTopMostController();
    }

    [parent
        presentViewController:
            nav
        animated:
            YES
        completion:
            nil];
}

// ============================================================================
// NORMAL DIRECT DOWNLOAD
// ============================================================================

- (void)ytdm_triggerSilentDownloadWithQuality:
    (NSString *)quality
    isAudio:(BOOL)isAudio {

    if (capturedVideoId.length == 0) {

        [[YTDMProgressHUD sharedHUD]
            showError:
                @"No context."];

        return;
    }

    [[YTDMProgressHUD sharedHUD]
        showInView:
            getKeyWindow()];

    [[YTDownloadManagerService
        sharedInstance]
        requestDownloadForVideoId:
            capturedVideoId
        isAudio:
            isAudio
        quality:
            quality
        completion:
        ^(NSArray<NSURL *> *localURLs,
          NSString *errorMsg) {

        dispatch_async(
            dispatch_get_main_queue(), ^{

            if (!localURLs) {

                [[YTDMProgressHUD sharedHUD]
                    showError:
                        errorMsg];

                return;
            }

            [[YTDMProgressHUD sharedHUD]
                showSuccessWithStatus:
                    @"Complete!"];

            [self
                ytdm_presentSaveOptionsForURLs:
                    localURLs
                isAudio:
                    isAudio
                quality:
                    quality];
        });
    }];
}

// ============================================================================
// MX UPSCALE DIRECT DOWNLOAD
// ============================================================================

- (void)ytdm_triggerUpscaleDownloadWithTarget:
    (NSString *)target {

    if (capturedVideoId.length == 0) {

        [[YTDMProgressHUD sharedHUD]
            showError:
                @"No context."];

        return;
    }

    NSString *status =
        [NSString
            stringWithFormat:
                @"Preparing %@ MX-UPscale...",
                target];

    [[YTDMProgressHUD sharedHUD]
        showInView:
            getKeyWindow()];

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            -1.0
        status:
            status];

    [[YTDownloadManagerService
        sharedInstance]
        requestUpscaleDownloadForVideoId:
            capturedVideoId
        target:
            target
        completion:
        ^(NSArray<NSURL *> *localURLs,
          NSString *errorMsg) {

        dispatch_async(
            dispatch_get_main_queue(), ^{

            if (!localURLs ||
                localURLs.count == 0) {

                [[YTDMProgressHUD sharedHUD]
                    showError:
                        errorMsg ?:
                            @"MX-UPscale failed."];

                return;
            }

            [[YTDMProgressHUD sharedHUD]
                showSuccessWithStatus:
                    [NSString
                        stringWithFormat:
                            @"%@ Complete!",
                            target]];

            [self
                ytdm_presentSaveOptionsForURLs:
                    localURLs
                isAudio:
                    NO
                quality:
                    target];
        });
    }];
}

// ============================================================================
// SAVE OPTIONS
// ============================================================================

- (void)ytdm_presentSaveOptionsForURLs:
    (NSArray<NSURL *> *)outURLs
    isAudio:(BOOL)isAudio
    quality:(NSString *)quality {

    UIViewController *topController =
        [self
            ytdm_parentViewController];

    if (!topController) {

        topController =
            getTopMostController();
    }

    if (!topController) {
        return;
    }

    UIAlertController *actionSheet =
        [UIAlertController
            alertControllerWithTitle:
                @"Download Completed!"
            message:
                @"Choose how to export your file:"
            preferredStyle:
                UIAlertControllerStyleActionSheet];

    if ([[NSUserDefaults standardUserDefaults]
         boolForKey:@"YTDM_ShowDownloadsTab"]) {

        [actionSheet
            addAction:
            [UIAlertAction
                actionWithTitle:
                    @"📥 Save to Downloads"
                style:
                    UIAlertActionStyleDefault
                handler:
                ^(UIAlertAction *a) {

            [[YTDMProgressHUD sharedHUD]
                showInView:
                    getKeyWindow()];

            [[YTDMDownloadsManager sharedManager]
                saveDownloadedURLs:
                    outURLs
                isAudio:
                    isAudio
                quality:
                    quality
                title:
                    nil
                completion:
                ^(BOOL success, NSError *error) {

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    if (success) {

                        [[YTDMProgressHUD sharedHUD]
                            showSuccessWithStatus:
                                @"Saved to Downloads!"];

                    } else {

                        NSString *msg =
                            [NSString
                                stringWithFormat:
                                    @"Error: %@",
                                    error.localizedDescription
                                    ?: @"Unknown"];

                        [[YTDMProgressHUD sharedHUD]
                            showError:
                                msg];
                    }
                });
            }];
        }]];
    }

    if (!isAudio) {

        [actionSheet
            addAction:
            [UIAlertAction
                actionWithTitle:
                    @"📸 Save to Photos"
                style:
                    UIAlertActionStyleDefault
                handler:
                ^(UIAlertAction *a) {

            NSURL *targetURL =
                outURLs.firstObject;

            [[YTDMProgressHUD sharedHUD]
                showInView:
                    getKeyWindow()];

            [YTDMPhotoSaver
                saveVideoPath:
                    targetURL.path
                completion:
                ^(BOOL success,
                  NSError *error) {

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    if (success) {

                        [[YTDMProgressHUD sharedHUD]
                            showSuccessWithStatus:
                                @"Saved to Gallery!"];

                    } else {

                        NSString *msg =
                            [NSString
                                stringWithFormat:
                                    @"Error: %@",
                                    error.localizedDescription
                                    ?: @"Unknown"];

                        [[YTDMProgressHUD sharedHUD]
                            showError:
                                msg];
                    }

                    dispatch_after(
                        dispatch_time(
                            DISPATCH_TIME_NOW,
                            (int64_t)
                                (2.0 *
                                 NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{

                        for (NSURL *url
                             in outURLs) {

                            [[NSFileManager defaultManager]
                                removeItemAtURL:
                                    url
                                error:nil];
                        }
                    });
                });
            }];
        }]];
    }

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"📁 Save to Files"
            style:
                UIAlertActionStyleDefault
            handler:
            ^(UIAlertAction *a) {

        if (@available(iOS 14.0, *)) {

            UIDocumentPickerViewController *picker =
                [[UIDocumentPickerViewController alloc]
                    initForExportingURLs:
                        outURLs
                    asCopy:
                        YES];

            picker.delegate =
                [YTDMDownloadQueueManager
                    sharedInstance];

            objc_setAssociatedObject(
                picker,
                &kAssociatedOutURLKey,
                outURLs,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [topController
                presentViewController:
                    picker
                animated:
                    YES
                completion:
                    nil];
        }
    }]];

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"🔗 Open Share Sheet"
            style:
                UIAlertActionStyleDefault
            handler:
            ^(UIAlertAction *a) {

        UIActivityViewController *share =
            [[UIActivityViewController alloc]
                initWithActivityItems:
                    outURLs
                applicationActivities:
                    nil];

        share.completionWithItemsHandler =
            ^(UIActivityType activityType,
              BOOL completed,
              NSArray *returnedItems,
              NSError *activityError) {

            for (NSURL *url
                 in outURLs) {

                [[NSFileManager defaultManager]
                    removeItemAtURL:
                        url
                    error:nil];
            }
        };

        [topController
            presentViewController:
                share
            animated:
                YES
            completion:
                nil];
    }]];

    [actionSheet
        addAction:
        [UIAlertAction
            actionWithTitle:
                @"Cancel"
            style:
                UIAlertActionStyleCancel
            handler:
            ^(UIAlertAction *a) {

        for (NSURL *url
             in outURLs) {

            [[NSFileManager defaultManager]
                removeItemAtURL:
                    url
                error:nil];
        }
    }]];

    [topController
        presentViewController:
            actionSheet
        animated:
            YES
        completion:
            nil];
}

// ============================================================================
// SYSTEM PLAYER
// ============================================================================

- (void)ytdm_playInSystemPlayer {

    if (capturedVideoId.length == 0) {

        [[YTDMProgressHUD sharedHUD]
            showError:
                @"No context."];

        return;
    }

    [[YTDMProgressHUD sharedHUD]
        showInView:
            getKeyWindow()];

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            -1.0
        status:
            @"Fetching stream..."];

    [[YTDownloadManagerService
        sharedInstance]
        requestStreamURLForVideoId:
            capturedVideoId
        completion:
        ^(NSString *streamURL,
          NSString *errorMsg) {

        dispatch_async(
            dispatch_get_main_queue(), ^{

            if (!streamURL) {

                [[YTDMProgressHUD sharedHUD]
                    showError:
                        errorMsg];

                return;
            }

            [[YTDMProgressHUD sharedHUD]
                dismiss];

            NSURL *url =
                [NSURL
                    URLWithString:
                        streamURL];

            AVPlayer *player =
                [AVPlayer
                    playerWithURL:
                        url];

            AVPlayerViewController *
                playerViewController =
                    [[AVPlayerViewController alloc]
                        init];

            playerViewController.player =
                player;

            UIViewController *topController =
                [self
                    ytdm_parentViewController];

            if (!topController) {

                topController =
                    getTopMostController();
            }

            [topController
                presentViewController:
                    playerViewController
                animated:
                    YES
                completion:^{

                [playerViewController.player
                    play];
            }];
        });
    }];
}

// ============================================================================
// THUMBNAIL
// ============================================================================

- (void)ytdm_downloadThumbnail {

    if (capturedVideoId.length == 0) {

        [[YTDMProgressHUD sharedHUD]
            showError:
                @"No context."];

        return;
    }

    [[YTDMProgressHUD sharedHUD]
        showInView:
            getKeyWindow()];

    [[YTDMProgressHUD sharedHUD]
        updateProgress:
            -1.0
        status:
            @"Downloading thumbnail..."];

    NSString *thumbURLStr =
        [NSString
            stringWithFormat:
                @"https://img.youtube.com/vi/%@/maxresdefault.jpg",
                capturedVideoId];

    NSURL *thumbURL =
        [NSURL
            URLWithString:
                thumbURLStr];

    [[[NSURLSession sharedSession]
        downloadTaskWithURL:
            thumbURL
        completionHandler:
        ^(NSURL *location,
          NSURLResponse *response,
          NSError *error) {

        dispatch_async(
            dispatch_get_main_queue(), ^{

            if (error ||
                !location) {

                [[YTDMProgressHUD sharedHUD]
                    showError:
                        @"Failed to get thumbnail."];

                return;
            }

            NSData *data =
                [NSData
                    dataWithContentsOfURL:
                        location];

            UIImage *image =
                [UIImage
                    imageWithData:
                        data];

            if (!image) {

                [[YTDMProgressHUD sharedHUD]
                    showError:
                        @"Invalid image data."];

                return;
            }

            [YTDMImageSaver
                saveImage:
                    image
                completion:
                ^(BOOL success,
                  NSError *phError) {

                dispatch_async(
                    dispatch_get_main_queue(), ^{

                    if (success) {

                        [[YTDMProgressHUD sharedHUD]
                            showSuccessWithStatus:
                                @"Thumbnail Saved!"];

                    } else {

                        NSString *fullError =
                            [NSString
                                stringWithFormat:
                                    @"Failed: %@",
                                    phError.localizedDescription
                                    ?: @"Unknown"];

                        [[YTDMProgressHUD sharedHUD]
                            showError:
                                fullError];
                    }
                });
            }];
        });

    }] resume];
}

// ============================================================================
// COPY LINK
// ============================================================================

- (void)ytdm_copyToClipboardWithText:
    (NSString *)text
    alertMsg:(NSString *)alertMsg {

    if (text) {

        [UIPasteboard
            generalPasteboard]
            .string =
                text;

        [[YTDMProgressHUD sharedHUD]
            showSuccessWithStatus:
                alertMsg];
    }
}

@end

// ============================================================================
// ATS BYPASS
// ============================================================================

%hook NSBundle

- (NSDictionary *)infoDictionary {

    NSDictionary *origDict =
        %orig;

    if (origDict) {

        NSMutableDictionary *m =
            [origDict mutableCopy];

        NSMutableDictionary *ats =
            [m[@"NSAppTransportSecurity"]
                mutableCopy]
            ?:
            [NSMutableDictionary dictionary];

        ats[@"NSAllowsArbitraryLoads"] =
            @YES;

        m[@"NSAppTransportSecurity"] =
            ats;

        return m;
    }

    return origDict;
}

%end
