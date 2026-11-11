#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const YTDMDownloadsLibraryChangedNotification;

@interface YTDMDownloadItem : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, copy) NSString *qualityLabel;
@property (nonatomic, strong) NSDate *dateAdded;
@property (nonatomic, assign) BOOL isAudio;
@property (nonatomic, assign) CGFloat watchedRatio;

- (nullable UIImage *)thumbnailImage;
- (NSString *)formattedDuration;
- (NSString *)formattedFileSize;
- (NSString *)formattedDate;

@end

@interface YTDMDownloadsManager : NSObject

+ (instancetype)sharedManager;
+ (NSString *)downloadsDirectory;

- (NSArray<YTDMDownloadItem *> *)allDownloads;
- (NSArray<YTDMDownloadItem *> *)videoDownloads;
- (NSArray<YTDMDownloadItem *> *)audioDownloads;

- (void)saveDownloadedURLs:(NSArray<NSURL *> *)urls
                   isAudio:(BOOL)isAudio
                   quality:(nullable NSString *)quality
                     title:(nullable NSString *)title
                completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;

- (BOOL)deleteItem:(YTDMDownloadItem *)item;
- (BOOL)renameItem:(YTDMDownloadItem *)item toName:(NSString *)newName;
- (void)saveResumePosition:(NSTimeInterval)position duration:(NSTimeInterval)duration forURL:(NSURL *)url;
- (NSTimeInterval)resumePositionForURL:(NSURL *)url;

// Manual ordering for the Downloads tab ("Order however you want").
// Stored as an array of YTDMDownloadItem.identifier values and kept entirely
// separate from the playback queue order.
- (void)setDownloadsOrder:(NSArray<YTDMDownloadItem *> *)orderedItems;
- (void)resetDownloadsOrder;

@end

NS_ASSUME_NONNULL_END
