#import <UIKit/UIKit.h>   
#import <objc/runtime.h>  

// ============================================================================
//                               PART 1: CONFIG
// ============================================================================

static NSString * const kEndpointPlayer     = @"/player";
static NSString * const kEndpointNext       = @"/next";
static NSString * const kEndpointBrowse     = @"/browse";

static NSString * const kJSONKeyContext     = @"context";
static NSString * const kJSONKeyClient      = @"client";
static NSString * const kJSONKeyVideoId     = @"videoId";
static NSString * const kJSONKeyBrowseId    = @"browseId";
static NSString * const kJSONKeyContinuation = @"continuation";

// ============================================================================
//                          PART 2: PLAYBACK CLIENT
// ============================================================================

@interface YTDirectPlaybackClient : NSObject
+ (NSDictionary *)apiHeadersForVisitorData:(NSString *)visitorData;
+ (NSDictionary *)contextBlueprint;
@end

@implementation YTDirectPlaybackClient

+ (NSDictionary *)apiHeadersForVisitorData:(NSString *)visitorData {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    headers[@"Content-Type"] = @"application/json";
    headers[@"Accept-Language"] = @"*";
    
    // Identitate curată de Android VR (Oculus Quest) pentru a ocoli restricțiile
    headers[@"X-YouTube-Client-Name"] = @"28";
    headers[@"X-YouTube-Client-Version"] = @"1.65.10";
    headers[@"User-Agent"] = @"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip";
    headers[@"Origin"] = @"https://www.youtube.com";
    
    if (visitorData.length > 0) {
        headers[@"X-Goog-Visitor-Id"] = visitorData;
    }
    
    return [headers copy];
}

+ (NSDictionary *)contextBlueprint {
    return @{
        kJSONKeyContext: @{
            kJSONKeyClient: @{
                @"clientName": @"ANDROID_VR",
                @"clientVersion": @"1.65.10",
                @"hl": @"en",
                @"timeZone": @"UTC",
                @"utcOffsetMinutes": @0,
                @"deviceMake": @"Oculus",
                @"deviceModel": @"Quest 3",
                @"androidSdkVersion": @32,
                @"osName": @"Android",
                @"osVersion": @"12L",
                @"userAgent": @"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
            }
        }
    };
}
@end

// ============================================================================
//                          PART 3: INNERTUBE SESSION
// ============================================================================

@interface YTInnertubeSession : NSObject
@property (nonatomic, copy) NSString *visitorData;
+ (instancetype)sharedSession;
- (NSDictionary *)buildPayloadWithIncomingBody:(NSDictionary *)incomingBody;
@end

@implementation YTInnertubeSession
+ (instancetype)sharedSession {
    static YTInnertubeSession *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[YTInnertubeSession alloc] init]; });
    return shared;
}

- (NSDictionary *)buildPayloadWithIncomingBody:(NSDictionary *)incomingBody {
    NSMutableDictionary *body = [[YTDirectPlaybackClient contextBlueprint] mutableCopy];
    
    // Păstrăm parametrii de navigare și identificare ai clipului video din cererea originală
    if (incomingBody[kJSONKeyVideoId]) {
        body[kJSONKeyVideoId] = incomingBody[kJSONKeyVideoId];
    }
    if (incomingBody[kJSONKeyBrowseId]) {
        body[kJSONKeyBrowseId] = incomingBody[kJSONKeyBrowseId];
    }
    if (incomingBody[kJSONKeyContinuation]) {
        body[kJSONKeyContinuation] = incomingBody[kJSONKeyContinuation];
    }
    if (incomingBody[@"params"]) {
        body[@"params"] = incomingBody[@"params"];
    }
    
    return [body copy];
}
@end

// ============================================================================
//                          PART 4: NETWORK INTERCEPTOR
// ============================================================================

%hook NSMutableURLRequest

- (id)initWithURL:(NSURL *)URL cachePolicy:(unsigned long long)cachePolicy timeoutInterval:(double)timeoutInterval {
    self = %orig;
    if (!self || !URL) return self;
    
    NSString *path = URL.path;
    // Interceptăm doar endpoint-urile critice de streaming și navigare
    if ([path containsString:kEndpointPlayer] || [path containsString:kEndpointNext] || [path containsString:kEndpointBrowse]) {
        
        // Atașăm headerele specifice profilului VR (fără a șterge token-ul nativ de login dacă există)
        NSDictionary *computedHeaders = [YTDirectPlaybackClient apiHeadersForVisitorData:[YTInnertubeSession sharedSession].visitorData];
        for (NSString *headerKey in computedHeaders) {
            [self setValue:computedHeaders[headerKey] forHTTPHeaderField:headerKey];
        }
        
        // Modificăm payload-ul JSON trimis către serverele YouTube
        if (self.HTTPBody) {
            NSDictionary *incomingJSON = [NSJSONSerialization JSONObjectWithData:self.HTTPBody options:0 error:nil];
            if ([incomingJSON isKindOfClass:[NSDictionary class]]) {
                
                // Extragem visitorData trimis de YouTube pentru a menține sesiunea validă
                NSDictionary *incomingContext = incomingJSON[kJSONKeyContext];
                if ([incomingContext isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *incomingClient = incomingContext[kJSONKeyClient];
                    if ([incomingClient isKindOfClass:[NSDictionary class]] && incomingClient[@"visitorData"]) {
                        [YTInnertubeSession sharedSession].visitorData = incomingClient[@"visitorData"];
                    }
                }
                
                // Reconstruim corpul cererii conform arhitecturii Android VR
                NSDictionary *mutatedJSON = [[YTInnertubeSession sharedSession] buildPayloadWithIncomingBody:incomingJSON];
                NSData *mutatedData = [NSJSONSerialization dataWithJSONObject:mutatedJSON options:0 error:nil];
                if (mutatedData) {
                    self.HTTPBody = mutatedData;
                }
            }
        }
    }
    
    return self;
}

%end