#import <UIKit/UIKit.h>    
#import <objc/runtime.h>  
#import "GPBMessage.h"

// ============================================================================
//                               PART 1: CONFIG
// ============================================================================

static NSString * const kEndpointPlayer       = @"/player";
static NSString * const kEndpointNext         = @"/next";
static NSString * const kEndpointBrowse       = @"/browse";
static NSString * const kEndpointInitPlayback  = @"/initplayback";
static NSString * const kEndpointVideoPlayback = @"/videoplayback";

static NSString * const kJSONKeyContext       = @"context";
static NSString * const kJSONKeyClient        = @"client";
static NSString * const kJSONKeyVideoId       = @"videoId";
static NSString * const kJSONKeyBrowseId      = @"browseId";
static NSString * const kJSONKeyContinuation  = @"continuation";

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
    if (![incomingBody isKindOfClass:[NSDictionary class]]) return incomingBody;
    
    NSMutableDictionary *mutatedBody = [incomingBody mutableCopy];
    
    NSDictionary *incomingContext = incomingBody[kJSONKeyContext];
    NSMutableDictionary *mutableContext = [incomingContext isKindOfClass:[NSDictionary class]] ? [incomingContext mutableCopy] : [NSMutableDictionary dictionary];
    
    NSDictionary *vrBlueprint = [YTDirectPlaybackClient contextBlueprint];
    NSDictionary *vrClientData = vrBlueprint[kJSONKeyContext][kJSONKeyClient];
    
    if (vrClientData) {
        NSMutableDictionary *mutableClientData = [vrClientData mutableCopy];
        
        // Re injection of visitorData
        if (self.visitorData.length > 0) {
            mutableClientData[@"visitorData"] = self.visitorData;
        }
        mutableContext[kJSONKeyClient] = [mutableClientData copy];
    }
    
    mutatedBody[kJSONKeyContext] = [mutableContext copy];
    return [mutatedBody copy];
}
@end

// ============================================================================
//                          PART 4: NETWORK INTERCEPTOR
// ============================================================================

%hook NSMutableURLRequest

- (id)initWithURL:(NSURL *)URL cachePolicy:(unsigned long long)cachePolicy timeoutInterval:(double)timeoutInterval {
    self = %orig;
    if (!self || !URL) return self;
    
    NSString *path = [URL.path lowercaseString];
    
    if ([path containsString:[kEndpointPlayer lowercaseString]] || 
        [path containsString:[kEndpointNext lowercaseString]] || 
        [path containsString:[kEndpointBrowse lowercaseString]] ||
        [path containsString:[kEndpointInitPlayback lowercaseString]]) {
        
        
        if (self.HTTPBody) {
            NSDictionary *incomingJSON = [NSJSONSerialization JSONObjectWithData:self.HTTPBody options:0 error:nil];
            if ([incomingJSON isKindOfClass:[NSDictionary class]]) {
                
                NSDictionary *incomingContext = incomingJSON[kJSONKeyContext];
                if ([incomingContext isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *incomingClient = incomingContext[kJSONKeyClient];
                    if ([incomingClient isKindOfClass:[NSDictionary class]] && incomingClient[@"visitorData"]) {
                        [YTInnertubeSession sharedSession].visitorData = incomingClient[@"visitorData"];
                    }
                }
                
                NSDictionary *mutatedJSON = [[YTInnertubeSession sharedSession] buildPayloadWithIncomingBody:incomingJSON];
                NSData *mutatedData = [NSJSONSerialization dataWithJSONObject:mutatedJSON options:0 error:nil];
                if (mutatedData) {
                    self.HTTPBody = mutatedData;
                }
            }
        }
        
 
        NSDictionary *computedHeaders = [YTDirectPlaybackClient apiHeadersForVisitorData:[YTInnertubeSession sharedSession].visitorData];
        for (NSString *headerKey in computedHeaders) {
            [self setValue:computedHeaders[headerKey] forHTTPHeaderField:headerKey];
        }
        
      
        if ([path containsString:[kEndpointInitPlayback lowercaseString]]) {
            NSString *urlString = self.URL.absoluteString;
            if (urlString.length > 0) {
                
    
                NSRegularExpression *regexC = [NSRegularExpression regularExpressionWithPattern:@"([?&])c=[^&]+" options:0 error:nil];
                urlString = [regexC stringByReplacingMatchesInString:urlString options:0 range:NSMakeRange(0, urlString.length) withTemplate:@"$1c=ANDROID_VR"];
                
              
                NSRegularExpression *regexCver = [NSRegularExpression regularExpressionWithPattern:@"([?&])cver=[^&]+" options:0 error:nil];
                urlString = [regexCver stringByReplacingMatchesInString:urlString options:0 range:NSMakeRange(0, urlString.length) withTemplate:@"$1cver=1.65.10"];
                
                NSURL *newURL = [NSURL URLWithString:urlString];
                if (newURL) {
                    [self setURL:newURL];
                }
            }
        }
    }
    
     
    if ([path containsString:@"/videoplayback"]) {
        NSString *urlString = self.URL.absoluteString;
        if (urlString.length > 0) {
            
            NSRegularExpression *regexUA = [NSRegularExpression regularExpressionWithPattern:@"([?&])user_agent=[^&]+" options:0 error:nil];
            
            urlString = [regexUA stringByReplacingMatchesInString:urlString 
                                                         options:0 
                                                           range:NSMakeRange(0, urlString.length) 
                                                    withTemplate:@"$1user_agent=com.google.android.apps.youtube.vr.oculus%2F1.65.10%20%28Linux%3B%20U%3B%20Android%2012L%3B%20eureka-user%20Build%2FSQ3A.220605.009.A1%29%20gzip"];
            
            NSURL *newURL = [NSURL URLWithString:urlString];
            if (newURL) {
                [self setURL:newURL];
            }
        }
    }
    
    return self;
}

%end


// ========================================================================================
//    PART 5: EXPERIMENTAL PoToken BYPASS (Special Thanks to @tywtyw2002 for the idea)
// ========================================================================================

@interface YTIIosPlaybackOnesieConfig : GPBMessage
- (BOOL)hasCommonConfig;
@end

// In order to use the base_url from YTIOnesieHotConfig, we have to hook this class in order for url and ustreamer_config from YTIIosPlaybackOnesieConfig to become null. This MAY bypass PoToken.

%hook YTIIosPlaybackOnesieConfig

- (BOOL)hasCommonConfig {
return 0; 
}

%end

//Keep in mind this is experimental and there is a good chance that it won't have any effect whatsoever, tho I may update this when I get clue how to maybe patch it better. And sorry if one hooked class seems exaggerated for me to call a PoToken bypass......



