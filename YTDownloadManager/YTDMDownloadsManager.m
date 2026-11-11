#import "YTDMDownloadsManager.h"
#import <AVFoundation/AVFoundation.h>

NSNotificationName const YTDMDownloadsLibraryChangedNotification = @"YTDMDownloadsLibraryChangedNotification";
static NSString * const kResumePositionsKey = @"YTDM_ResumePositions";
// Downloads-tab manual order. Deliberately distinct from the playback queue key.
static NSString * const kDownloadsOrderKey = @"YTDM_DownloadsOrder";

@interface YTDMDownloadItem ()
@property (nonatomic, strong, nullable) UIImage *cachedThumbnail;
@property (nonatomic, assign) BOOL thumbnailExtractionInFlight;
@end

@implementation YTDMDownloadItem

- (nullable UIImage *)thumbnailImage {
    if (self.cachedThumbnail) return self.cachedThumbnail;
    NSString *base = [self.fileURL.path stringByDeletingPathExtension];
    NSString *thumbPath = [base stringByAppendingPathExtension:@"jpg"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
        self.cachedThumbnail = [UIImage imageWithContentsOfFile:thumbPath];
        return self.cachedThumbnail;
    }
    if (!self.isAudio) {
        // Synchronous AVFoundation frame extraction is unsafe here: this runs
        // on the main thread (player tap -> playItem -> Now Playing info), and
        // a decode/format hiccup in a Live Container jail is a hard crash.
        // Serve the cached sidecar if we have one, otherwise ask for the
        // frame off-thread and update on the next pass.
        UIImage *existing = [UIImage imageWithContentsOfFile:thumbPath];
        if (existing) {
            self.cachedThumbnail = existing;
            return existing;
        }
        if (self.thumbnailExtractionInFlight) return nil;
        self.thumbnailExtractionInFlight = YES;
        [self extractThumbnailOffThreadToPath:thumbPath];
        return nil;
    }
    return nil;
}

- (void)extractThumbnailOffThreadToPath:(NSString *)thumbPath {
    NSURL *url = self.fileURL;
    NSTimeInterval duration = self.duration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVURLAsset *asset = [AVURLAsset assetWithURL:url];
        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(480, 270);
        CMTime time = CMTimeMake(MIN(3, (int64_t)duration / 2), 1);
        CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:NULL];
        if (!imgRef) {
            dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.thumbnailExtractionInFlight = NO; });
            return;
        }
        UIImage *img = [UIImage imageWithCGImage:imgRef];
        CGImageRelease(imgRef);
        NSData *jpgData = UIImageJPEGRepresentation(img, 0.75);
        [jpgData writeToFile:thumbPath atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.thumbnailExtractionInFlight = NO;
            weakSelf.cachedThumbnail = img;
        });
    });
}

- (NSString *)formattedDuration {
    if (self.duration <= 0) return self.isAudio ? @"Audio" : @"--:--";
    NSInteger total = (NSInteger)self.duration;
    NSInteger s = total % 60, m = (total / 60) % 60, h = total / 3600;
    return h > 0 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s]
                 : [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (NSString *)formattedFileSize {
    if (self.fileSize < 1024) return [NSString stringWithFormat:@"%llu B", self.fileSize];
    if (self.fileSize < 1048576) return [NSString stringWithFormat:@"%.1f KB", self.fileSize / 1024.0];
    if (self.fileSize < 1073741824) return [NSString stringWithFormat:@"%.1f MB", self.fileSize / 1048576.0];
    return [NSString stringWithFormat:@"%.2f GB", self.fileSize / 1073741824.0];
}

- (NSString *)formattedDate {
    if (!self.dateAdded) return @"";
    static NSDateFormatter *df;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [NSDateFormatter new];
        df.dateStyle = NSDateFormatterShortStyle;
        df.timeStyle = NSDateFormatterShortStyle;
    });
    return [df stringFromDate:self.dateAdded];
}

@end

@implementation YTDMDownloadsManager

+ (instancetype)sharedManager {
    static YTDMDownloadsManager *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mgr = [YTDMDownloadsManager new]; });
    return mgr;
}

+ (NSString *)downloadsDirectory {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"YTDMDownloads"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return dir;
}

- (NSArray<YTDMDownloadItem *> *)allDownloads {
    NSString *dir = [YTDMDownloadsManager downloadsDirectory];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    if (!files) return @[];

    NSMutableArray<YTDMDownloadItem *> *items = [NSMutableArray array];
    NSSet *validExts = [NSSet setWithObjects:@"mp4", @"mov", @"m4v", @"mkv", @"mp3", @"m4a", @"aac", @"wav", @"flac", @"opus", nil];
    NSSet *audioExts = [NSSet setWithObjects:@"mp3", @"m4a", @"aac", @"wav", @"flac", @"opus", nil];

    for (NSString *fileName in files) {
        NSString *ext = fileName.pathExtension.lowercaseString;
        if (![validExts containsObject:ext] || [fileName hasPrefix:@"."]) continue;

        NSString *fullPath = [dir stringByAppendingPathComponent:fileName];
        NSURL *fileURL = [NSURL fileURLWithPath:fullPath];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL];
        unsigned long long size = [attrs fileSize];
        NSDate *date = [attrs fileModificationDate] ?: [NSDate date];

        YTDMDownloadItem *item = [YTDMDownloadItem new];
        item.fileURL = fileURL;
        item.identifier = fileName;
        item.fileSize = size;
        item.dateAdded = date;
        item.isAudio = [audioExts containsObject:ext];

        // Check metadata sidecar
        NSString *metaPath = [[fullPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"ytdm.json"];
        NSDictionary *meta = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:metaPath]) {
            NSData *metaData = [NSData dataWithContentsOfFile:metaPath];
            if (metaData) meta = [NSJSONSerialization JSONObjectWithData:metaData options:0 error:NULL];
        }

        if (meta) {
            item.title = meta[@"title"] ?: [fileName stringByDeletingPathExtension];
            item.duration = [meta[@"duration"] doubleValue];
            item.qualityLabel = meta[@"quality"] ?: (item.isAudio ? @"Audio" : @"Video");
        } else {
            item.title = [fileName stringByDeletingPathExtension];
            item.qualityLabel = item.isAudio ? ext.uppercaseString : @"Video";
            AVURLAsset *asset = [AVURLAsset assetWithURL:fileURL];
            item.duration = CMTimeGetSeconds(asset.duration);
            // Save initial sidecar
            NSDictionary *newMeta = @{
                @"title": item.title,
                @"duration": @(item.duration),
                @"quality": item.qualityLabel,
                @"isAudio": @(item.isAudio)
            };
            NSData *data = [NSJSONSerialization dataWithJSONObject:newMeta options:0 error:NULL];
            [data writeToFile:metaPath atomically:YES];
        }

        item.watchedRatio = [self watchedRatioForURL:fileURL duration:item.duration];
        [items addObject:item];
    }

    [items sortUsingComparator:^NSComparisonResult(YTDMDownloadItem *a, YTDMDownloadItem *b) {
        return [b.dateAdded compare:a.dateAdded];
    }];

    // Apply the user's manual Downloads-tab order, if one was saved.
    // Items not present in the saved order (new downloads) keep their
    // date-sorted position at the end, so nothing is ever hidden.
    NSArray *savedOrder = [[NSUserDefaults standardUserDefaults] arrayForKey:kDownloadsOrderKey];
    if (savedOrder.count > 0) {
        NSMutableDictionary *byIdentifier = [NSMutableDictionary dictionaryWithCapacity:items.count];
        for (YTDMDownloadItem *item in items) {
            if (item.identifier) byIdentifier[item.identifier] = item;
        }
        NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:items.count];
        for (NSString *identifier in savedOrder) {
            YTDMDownloadItem *item = byIdentifier[identifier];
            if (item) {
                [ordered addObject:item];
                [byIdentifier removeObjectForKey:identifier];
            }
        }
        for (YTDMDownloadItem *item in items) {
            if (byIdentifier[item.identifier]) [ordered addObject:item];
        }
        items = ordered;
    }
    return items;
}

- (NSArray<YTDMDownloadItem *> *)videoDownloads {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isAudio == NO"];
    return [[self allDownloads] filteredArrayUsingPredicate:pred];
}

- (NSArray<YTDMDownloadItem *> *)audioDownloads {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isAudio == YES"];
    return [[self allDownloads] filteredArrayUsingPredicate:pred];
}

- (void)saveDownloadedURLs:(NSArray<NSURL *> *)urls
                   isAudio:(BOOL)isAudio
                   quality:(nullable NSString *)quality
                     title:(nullable NSString *)title
                completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *destDir = [YTDMDownloadsManager downloadsDirectory];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL anySuccess = NO;
        NSError *lastError = nil;

        for (NSURL *srcURL in urls) {
            NSString *origName = srcURL.lastPathComponent;
            NSString *baseName = origName.stringByDeletingPathExtension;
            NSString *ext = origName.pathExtension;
            if (title.length > 0) baseName = title;

            // Generate clean target filename
            NSString *targetName = [NSString stringWithFormat:@"%@.%@", baseName, ext];
            NSString *targetPath = [destDir stringByAppendingPathComponent:targetName];
            NSUInteger counter = 1;
            while ([fm fileExistsAtPath:targetPath]) {
                targetName = [NSString stringWithFormat:@"%@ (%lu).%@", baseName, (unsigned long)counter++, ext];
                targetPath = [destDir stringByAppendingPathComponent:targetName];
            }

            // Copy file to persistent Downloads folder
            NSError *copyError = nil;
            BOOL ok = [fm copyItemAtURL:srcURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];
            if (!ok && [fm fileExistsAtPath:srcURL.path]) {
                ok = [fm moveItemAtURL:srcURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];
            }

            if (ok) {
                anySuccess = YES;
                NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
                AVURLAsset *asset = [AVURLAsset assetWithURL:targetURL];
                NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
                if (!isfinite(duration)) duration = 0;

                // Write metadata sidecar
                NSDictionary *meta = @{
                    @"title": baseName,
                    @"quality": quality ?: (isAudio ? @"Audio" : @"Video"),
                    @"duration": @(duration),
                    @"isAudio": @(isAudio),
                    @"dateAdded": [NSDate date].description
                };
                NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:0 error:NULL];
                NSString *metaPath = [[targetPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"ytdm.json"];
                [metaData writeToFile:metaPath atomically:YES];

                // Generate thumbnail in background
                if (!isAudio) {
                    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                    gen.appliesPreferredTrackTransform = YES;
                    gen.maximumSize = CGSizeMake(480, 270);
                    CMTime t = CMTimeMake(MIN(3, (int64_t)duration / 2), 1);
                    CGImageRef imgRef = [gen copyCGImageAtTime:t actualTime:NULL error:NULL];
                    if (imgRef) {
                        UIImage *img = [UIImage imageWithCGImage:imgRef];
                        CGImageRelease(imgRef);
                        NSData *jpgData = UIImageJPEGRepresentation(img, 0.75);
                        NSString *thumbPath = [[targetPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
                        [jpgData writeToFile:thumbPath atomically:YES];
                    }
                }
            } else {
                lastError = copyError;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (anySuccess) {
                [[NSNotificationCenter defaultCenter] postNotificationName:YTDMDownloadsLibraryChangedNotification object:nil];
            }
            if (completion) completion(anySuccess, lastError);
        });
    });
}

- (BOOL)deleteItem:(YTDMDownloadItem *)item {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [item.fileURL.path stringByDeletingPathExtension];
    [fm removeItemAtURL:item.fileURL error:NULL];
    [fm removeItemAtPath:[base stringByAppendingPathExtension:@"ytdm.json"] error:NULL];
    [fm removeItemAtPath:[base stringByAppendingPathExtension:@"jpg"] error:NULL];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMDownloadsLibraryChangedNotification object:nil];
    return YES;
}

- (BOOL)renameItem:(YTDMDownloadItem *)item toName:(NSString *)newName {
    if (!newName.length || [newName isEqualToString:item.title]) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = item.fileURL.path.stringByDeletingLastPathComponent;
    NSString *ext = item.fileURL.pathExtension;
    NSString *newPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", newName, ext]];
    if ([fm fileExistsAtPath:newPath]) return NO;

    [fm moveItemAtPath:item.fileURL.path toPath:newPath error:NULL];
    NSString *oldBase = [item.fileURL.path stringByDeletingPathExtension];
    NSString *newBase = [newPath stringByDeletingPathExtension];
    [fm moveItemAtPath:[oldBase stringByAppendingPathExtension:@"jpg"] toPath:[newBase stringByAppendingPathExtension:@"jpg"] error:NULL];

    NSString *metaPath = [newBase stringByAppendingPathExtension:@"ytdm.json"];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfFile:[oldBase stringByAppendingPathExtension:@"ytdm.json"]];
    if (data) {
        meta = [[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] mutableCopy] ?: [NSMutableDictionary dictionary];
        [fm removeItemAtPath:[oldBase stringByAppendingPathExtension:@"ytdm.json"] error:NULL];
    }
    meta[@"title"] = newName;
    [[NSJSONSerialization dataWithJSONObject:meta options:0 error:NULL] writeToFile:metaPath atomically:YES];

    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMDownloadsLibraryChangedNotification object:nil];
    return YES;
}

- (CGFloat)watchedRatioForURL:(NSURL *)url duration:(NSTimeInterval)duration {
    if (duration <= 0) return 0;
    NSTimeInterval pos = [self resumePositionForURL:url];
    if (pos <= 0) return 0;
    CGFloat ratio = pos / duration;
    return ratio > 0.95 ? 1.0 : ratio;
}

- (void)saveResumePosition:(NSTimeInterval)position duration:(NSTimeInterval)duration forURL:(NSURL *)url {
    if (!url || duration <= 0) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *table = [[ud dictionaryForKey:kResumePositionsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = url.lastPathComponent;
    if (position > 5.0 && position < duration * 0.98) {
        table[key] = @{@"t": @(position), @"d": @(duration)};
    } else {
        [table removeObjectForKey:key];
    }
    [ud setObject:table forKey:kResumePositionsKey];
}

- (NSTimeInterval)resumePositionForURL:(NSURL *)url {
    if (!url) return 0;
    NSDictionary *table = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kResumePositionsKey];
    NSDictionary *rec = table[url.lastPathComponent];
    if (!rec) return 0;
    return [rec[@"t"] doubleValue];
}

- (void)setDownloadsOrder:(NSArray<YTDMDownloadItem *> *)orderedItems {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:orderedItems.count];
    for (YTDMDownloadItem *item in orderedItems) {
        if (item.identifier) [identifiers addObject:item.identifier];
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:identifiers forKey:kDownloadsOrderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMDownloadsLibraryChangedNotification object:nil];
}

- (void)resetDownloadsOrder {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDownloadsOrderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTDMDownloadsLibraryChangedNotification object:nil];
}

@end
