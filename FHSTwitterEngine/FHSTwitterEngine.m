//
//  FHSTwitterEngine.m
//  FHSTwitterEngine
//
//  Created by Nathaniel Symer on 8/22/12.
//  Copyright (C) 2012 Nathaniel Symer.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "FHSTwitterEngine.h"

#import "OAuthConsumer.h"
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <objc/runtime.h>
#import <AFNetworking/AFNetworking.h>

NSString * const FHSProfileBackgroundColorKey = @"profile_background_color";
NSString * const FHSProfileLinkColorKey = @"profile_link_color";
NSString * const FHSProfileSidebarBorderColorKey = @"profile_sidebar_border_color";
NSString * const FHSProfileSidebarFillColorKey = @"profile_sidebar_fill_color";
NSString * const FHSProfileTextColorKey = @"profile_text_color";

NSString * const FHSProfileNameKey = @"name";
NSString * const FHSProfileURLKey = @"url";
NSString * const FHSProfileLocationKey = @"location";
NSString * const FHSProfileDescriptionKey = @"description";


static NSString * const errorFourhundred = @"Bad Request: The request you are trying to make has missing or bad parameters.";

static NSString * const authBlockKey = @"FHSTwitterEngineOAuthCompletion";

static FHSTwitterEngine *sharedInstance = nil;

id removeNull(id rootObject) {
    if ([rootObject isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *sanitizedDictionary = [NSMutableDictionary dictionaryWithDictionary:rootObject];
        [rootObject enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            id sanitized = removeNull(obj);
            if (!sanitized) {
                [sanitizedDictionary setObject:@"" forKey:key];
            } else {
                [sanitizedDictionary setObject:sanitized forKey:key];
            }
        }];
        return [NSMutableDictionary dictionaryWithDictionary:sanitizedDictionary];
    }
    
    if ([rootObject isKindOfClass:[NSArray class]]) {
        NSMutableArray *sanitizedArray = [NSMutableArray arrayWithArray:rootObject];
        [rootObject enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            id sanitized = removeNull(obj);
            if (!sanitized) {
                [sanitizedArray replaceObjectAtIndex:[sanitizedArray indexOfObject:obj] withObject:@""];
            } else {
                [sanitizedArray replaceObjectAtIndex:[sanitizedArray indexOfObject:obj] withObject:sanitized];
            }
        }];
        return [NSMutableArray arrayWithArray:sanitizedArray];
    }

    if ([rootObject isKindOfClass:[NSNull class]]) {
        return (id)nil;
    } else {
        return rootObject;
    }
}

NSError * getBadRequestError() {
    return [NSError errorWithDomain:errorFourhundred code:400 userInfo:nil];
}

NSError * getNilReturnLengthError() {
    return [NSError errorWithDomain:@"Twitter successfully processed the request, but did not return any content" code:204 userInfo:nil];
}

@interface FHSTwitterEngineController : UIViewController <UIWebViewDelegate> 

@property (nonatomic, retain) UINavigationBar *navBar;
@property (nonatomic, retain) UIView *blockerView;
@property (nonatomic, retain) UIToolbar *pinCopyBar;

//@property (nonatomic, retain) FHSTwitterEngine *engine;
@property (nonatomic, retain) UIWebView *theWebView;
@property (nonatomic, retain) OAToken *requestToken;

//- (id)initWithEngine:(FHSTwitterEngine *)theEngine;
- (NSString *)locatePin;
- (void)showPinCopyPrompt;

@end

@interface FHSTwitterEngine()

// Login stuff
- (NSString *)getRequestTokenString;

// General Get request sender
- (id)sendRequest:(NSURLRequest *)request;

// These are here to obfuscate them from prying eyes
@property (retain, nonatomic) OAConsumer *consumer;
@property (assign, nonatomic) BOOL shouldClearConsumer;
@property (retain, nonatomic) NSDateFormatter *dateFormatter;

@end

@implementation NSString (FHSTwitterEngine)

- (NSString *)fhs_trimForTwitter {
    NSString *string = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return (string.length > 140)?[string substringToIndex:140]:string;
}

- (NSString *)fhs_stringWithRange:(NSRange)range {
    return [[self substringFromIndex:range.location]substringToIndex:range.length];
}

- (BOOL)fhs_isNumeric {
	const char *raw = (const char *)[self UTF8String];
    
	for (int i = 0; i < strlen(raw); i++) {
		if (raw[i] < '0' || raw[i] > '9') {
            return NO;
        }
	}
	return YES;
}

@end

@implementation FHSTwitterEngine

static NSString * const url_statuses_update = @"https://api.twitter.com/1.1/statuses/update.json";
//static NSString * const url_statuses_update_with_media = @"https://api.twitter.com/1.1/statuses/update_with_media.json";
static NSString * const url_media_upload = @"https://upload.twitter.com/1.1/media/upload.json";
static NSString * const url_help_test = @"https://api.twitter.com/1.1/help/test.json";
static NSString * const url_account_update_profile_background_image = @"https://api.twitter.com/1.1/account/update_profile_background_image.json";
static NSString * const url_account_update_profile_image = @"https://api.twitter.com/1.1/account/update_profile_image.json";
static NSString * const url_account_update_profile = @"https://api.twitter.com/1.1/account/update_profile.json";
static NSString * const url_account_update_profile_banner = @"https://api.twitter.com/1.1/account/update_profile_banner.json";

- (NSDictionary *)postTweet:(NSString *)tweetString
       imagePaths:(NSArray *)imagePaths
        inReplyTo:(NSString *)irt
         location:(CLLocation *)location
          placeId:(NSString *)placeId
       screenName:(NSString *)screenName
{
    if (tweetString.length == 0 && imagePaths.count == 0) {
        return nil;
    }
    
    NSURL *baseURL = [NSURL URLWithString:url_media_upload];
    
    NSMutableArray *imageIdStrs = @[].mutableCopy;
    for (NSString *imageFilePath in imagePaths) {
        NSData *imageData = UIImageJPEGRepresentation([UIImage imageWithContentsOfFile:imageFilePath], 0.92);
        OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:[self accessTokenWithScreenName:screenName]];
        
        CFUUIDRef theUUID = CFUUIDCreate(nil);
        CFStringRef string = CFUUIDCreateString(nil, theUUID);
        CFRelease(theUUID);
        NSString *boundary = [NSString stringWithString:(NSString *)string];
        CFRelease(string);
        
        [request setHTTPMethod:@"POST"];
        [request setHTTPShouldHandleCookies:NO];
        
        NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
        [request setValue:contentType forHTTPHeaderField:@"content-type"];
        
        NSMutableData *body = [NSMutableData dataWithLength:0];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"media\"; filename=\"upload.jpg\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Type: image/jpeg\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:imageData];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [request prepare];
        [request setHTTPBody:body];
        
        NSURLResponse *response;
        NSError *error;
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        if (data) {
            id parsedJSONResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([parsedJSONResponse isKindOfClass:[NSDictionary class]]) {
                NSDictionary *media = parsedJSONResponse;
                NSString *mediaIdStr = media[@"media_id_string"];
                [imageIdStrs addObject:mediaIdStr];
            }
            CGFloat progress = ([imagePaths indexOfObject:imageFilePath] + 1) * 1.0 / imagePaths.count * 0.8 + 0.1;
            dispatch_async(GCDMainThread, ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"HSUPostTweetProgressChangedNotification"
                                                                    object:@(progress)];
            });
        } else {
            return nil;
        }
    }
    
    baseURL = [NSURL URLWithString:url_statuses_update];
    OARequestParameter *status = [OARequestParameter requestParameterWithName:@"status" value:[tweetString fhs_trimForTwitter]];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:[self accessTokenWithScreenName:screenName]];
    
    NSMutableArray *params = [NSMutableArray arrayWithObjects:status, nil];
    
    if (irt.length > 0) {
        [params addObject:[OARequestParameter requestParameterWithName:@"in_reply_to_status_id" value:irt]];
    }
    
    if (location) {
        [params addObject:[OARequestParameter requestParameterWithName:@"lat" value:[@(location.coordinate.latitude) description]]];
        [params addObject:[OARequestParameter requestParameterWithName:@"long" value:[@(location.coordinate.longitude) description]]];
        if (placeId) {
            [params addObject:[OARequestParameter requestParameterWithName:@"place_id" value:placeId]];
        }
        [params addObject:[OARequestParameter requestParameterWithName:@"display_coordinates" value:@"true"]];
    }
    
    if (imageIdStrs.count) {
        NSString *mediaIdStr = [imageIdStrs componentsJoinedByString:@","];
        [params addObject:[OARequestParameter requestParameterWithName:@"media_ids" value:mediaIdStr]];
    }
    [request setHTTPMethod:@"POST"];
    [request setParameters:params];
    [request prepare];
    
    NSURLResponse *response;
    NSError *error;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (data) {
        id parsedJSONResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return parsedJSONResponse;
    }
    return nil;
}

- (NSError *)setUseProfileBackgroundImage:(BOOL)shouldUseBGImg {
    NSURL *baseURL = [NSURL URLWithString:url_account_update_profile_background_image];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    OARequestParameter *skipStatus = [OARequestParameter requestParameterWithName:@"skip_status" value:@"true"];
    OARequestParameter *useImage = [OARequestParameter requestParameterWithName:@"profile_use_background_image" value:shouldUseBGImg?@"true":@"false"];
    return [self sendPOSTRequest:request withParameters:[NSArray arrayWithObjects:skipStatus, useImage, nil]];
}

- (NSError *)setBannerImageWithImageData:(NSData *)data {
    if (data.length == 0) {
        return getBadRequestError();
    }
    
    if (data.length >= 800000) {
        return [NSError errorWithDomain:@"The image you are trying to upload is too large." code:422 userInfo:nil];
    }
    
    NSURL *baseURL = [NSURL URLWithString:url_account_update_profile_banner];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    OARequestParameter *image = [OARequestParameter requestParameterWithName:@"banner" value:[data base64EncodingWithLineLength:0]];
    return [self sendPOSTRequest:request withParameters:[NSArray arrayWithObjects:image, nil]];
}

- (NSError *)setProfileBackgroundImageWithImageData:(NSData *)data tiled:(BOOL)isTiled {
    if (data.length == 0) {
        return getBadRequestError();
    }
    
    if (data.length >= 800000) {
        return [NSError errorWithDomain:@"The image you are trying to upload is too large." code:422 userInfo:nil];
    }
    
    NSURL *baseURL = [NSURL URLWithString:url_account_update_profile_background_image];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    OARequestParameter *tiled = [OARequestParameter requestParameterWithName:@"tiled" value:isTiled?@"true":@"false"];
    OARequestParameter *skipStatus = [OARequestParameter requestParameterWithName:@"skip_status" value:@"true"];
    OARequestParameter *useImage = [OARequestParameter requestParameterWithName:@"profile_use_background_image" value:@"true"];
    OARequestParameter *image = [OARequestParameter requestParameterWithName:@"image" value:[data base64EncodingWithLineLength:0]];
    return [self sendPOSTRequest:request withParameters:[NSArray arrayWithObjects:tiled, skipStatus, useImage, image, nil]];
}

- (NSError *)setProfileBackgroundImageWithImageAtPath:(NSString *)file tiled:(BOOL)isTiled {
    return [self setProfileBackgroundImageWithImageData:[NSData dataWithContentsOfFile:file] tiled:isTiled];
}

- (NSError *)setProfileImageWithImageData:(NSData *)data {
    if (data.length == 0) {
        return getBadRequestError();
    }
    
    if (data.length >= 700000) {
        return [NSError errorWithDomain:@"The image you are trying to upload is too large." code:422 userInfo:nil];
    }
    
    NSURL *baseURL = [NSURL URLWithString:url_account_update_profile_image];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    OARequestParameter *skipStatus = [OARequestParameter requestParameterWithName:@"skip_status" value:@"true"];
    OARequestParameter *image = [OARequestParameter requestParameterWithName:@"image" value:[data base64EncodingWithLineLength:0]];
    return [self sendPOSTRequest:request withParameters:[NSArray arrayWithObjects:image, skipStatus, nil]];
}

- (NSError *)setProfileImageWithImageAtPath:(NSString *)file {
    return [self setProfileImageWithImageData:[NSData dataWithContentsOfFile:file]];
}

- (NSError *)updateUserProfileWithDictionary:(NSDictionary *)settings {
    
    if (!settings) {
        return getBadRequestError();
    }
    
    // all of the values are just non-normalized strings. They appear:
    
    //   setting   - length in characters
    // name        -        20
    // url         -        100
    // location    -        30
    // description -        160
    
    NSString *name = [settings objectForKey:FHSProfileNameKey];
    NSString *url = [settings objectForKey:FHSProfileURLKey];
    NSString *location = [settings objectForKey:FHSProfileLocationKey];
    NSString *description = [settings objectForKey:FHSProfileDescriptionKey];
    
    NSURL *baseURL = [NSURL URLWithString:url_account_update_profile];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    OARequestParameter *skipStatus = [OARequestParameter requestParameterWithName:@"skip_status" value:@"true"];
    
    NSMutableArray *params = [NSMutableArray arrayWithObjects:skipStatus, nil];
    
    if (name.length > 0) {
        [params addObject:[OARequestParameter requestParameterWithName:@"name" value:name]];
    }
    
    if (url.length > 0) {
        [params addObject:[OARequestParameter requestParameterWithName:@"url" value:url]];
    }
    
    if (location.length > 0) {
        [params addObject:[OARequestParameter requestParameterWithName:@"location" value:location]];
    }
    
    if (description.length > 0) {
        [params addObject:[OARequestParameter requestParameterWithName:@"description" value:description]];
    }
    
    return [self sendPOSTRequest:request withParameters:params];
}

- (id)testService {
    NSURL *baseURL = [NSURL URLWithString:url_help_test];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:baseURL consumer:self.consumer token:self.accessToken];
    
    id retValue = [self sendGETRequest:request withParameters:nil];
    
    if ([retValue isKindOfClass:[NSString class]]) {
        if ([(NSString *)retValue isEqualToString:@"ok"]) {
            return @"YES";
        } else {
            return @"NO";
        }
    } else if ([retValue isKindOfClass:[NSError class]]) {
        return retValue;
    }
    
    return getBadRequestError();
}

- (id)init {
    self = [super init];
    if (self) {
        // Twitter API datestamps are UTC
        // Don't question this code.
        self.dateFormatter = [[[NSDateFormatter alloc]init]autorelease];
        _dateFormatter.locale = [[[NSLocale alloc]initWithLocaleIdentifier:@"en_US"]autorelease];
        _dateFormatter.dateStyle = NSDateFormatterLongStyle;
        _dateFormatter.formatterBehavior = NSDateFormatterBehavior10_4;
        _dateFormatter.dateFormat = @"EEE MMM dd HH:mm:ss ZZZZ yyyy";
    }
    return self;
}

// The shared* class method
+ (FHSTwitterEngine *)sharedEngine {
    @synchronized (self) {
        if (sharedInstance == nil) {
            [[self alloc]init];
        }
    }
    return sharedInstance;
}

// Override stuff to make sure that the singleton is never dealloc'd. Fun.
+ (id)allocWithZone:(NSZone *)zone {
    @synchronized(self) {
        if (sharedInstance == nil) {
            sharedInstance = [super allocWithZone:zone];
            return sharedInstance;
        }
    }
    return nil;
}

- (id)retain {
    return self;
}

- (oneway void)release {
    // Do nothing
}

- (id)autorelease {
    return self;
}

- (NSUInteger)retainCount {
    return NSUIntegerMax;
}

- (NSArray *)generateRequestStringsFromArray:(NSArray *)array {
    
    NSString *initialString = [array componentsJoinedByString:@","];
    
    if (array.count <= 100) {
        return [NSArray arrayWithObjects:initialString, nil];
    }
    
    int offset = 0;
    int remainder = fmod(array.count, 100);
    int numberOfStrings = (array.count-remainder)/100;
    
    NSMutableArray *reqStrs = [NSMutableArray array];
    
    for (int i = 1; i <= numberOfStrings; ++i) {
        NSString *ninetyNinththItem = (NSString *)[array objectAtIndex:(i*100)-1];
        NSRange range = [initialString rangeOfString:ninetyNinththItem];
        int endOffset = range.location+range.length;
        NSRange rangeOfAString = NSMakeRange(offset, endOffset-offset);
        offset = endOffset;
        NSString *endResult = [initialString fhs_stringWithRange:rangeOfAString];
        
        if ([[endResult substringToIndex:1]isEqualToString:@","]) {
            endResult = [endResult substringFromIndex:1];
        }
        
        [reqStrs addObject:endResult];
    }
    
    NSString *remainderString = [initialString stringByReplacingOccurrencesOfString:[reqStrs componentsJoinedByString:@","] withString:@""];
    
    if ([[remainderString substringToIndex:1]isEqualToString:@","]) {
        remainderString = [remainderString substringFromIndex:1];
    }
    
    [reqStrs addObject:remainderString];
    
    return reqStrs;
}

- (void)sendPOSTRequest:(OAMutableURLRequest *)request
         withParameters:(NSArray *)params
                success:(void (^)(id responseObj))success
                failure:(void (^)(NSError *error))failure
               progress:(void (^)(double progress))progress
{
    if (![self isAuthorized]) {
        [self loadAccessToken];
        if (![self isAuthorized]) {
            failure([NSError errorWithDomain:@"You are not authorized via OAuth" code:401 userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]]);
        }
    }
    
    [request setHTTPMethod:@"POST"];
    [request setParameters:params];
    [request prepare];
    
    [self sendRequest:request success:success failure:failure progress:progress];
}


- (void)sendRequest:(NSURLRequest *)request
            success:(void (^)(id responseObj))success
            failure:(void (^)(NSError *error))failure
           progress:(void (^)(double progress))progress
{
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        progress(0);
        failure(error);
    }];
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        double uploadProgress = totalBytesWritten/(double)totalBytesExpectedToWrite;
        if ([request.HTTPMethod isEqualToString:@"GET"]) {
            progress(uploadProgress * 1 / 3);
        } else {
            progress(uploadProgress * 2 / 3);
        }
    }];
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        double downloadProgress;
        if (totalBytesExpectedToRead > 0) {
            downloadProgress = totalBytesRead/(double)totalBytesExpectedToRead;
        } else {
            downloadProgress = 1;
        }
        if ([request.HTTPMethod isEqualToString:@"GET"]) {
            progress(downloadProgress * 2 / 3 + 1 / 3.0);
        } else {
            progress(downloadProgress * 1 / 3 + 2 / 3.0);
        }
    }];
    [operation start];
}

//
// sendRequest:
//

- (id)sendRequest:(NSURLRequest *)request {
    
    if (_shouldClearConsumer) {
        self.shouldClearConsumer = NO;
        self.consumer = nil;
    }
    
    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    if (error) {
        if (data) {
            NSDictionary *responseObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (responseObj) {
                if (responseObj[@"errors"] && [responseObj[@"errors"] count] > 0) {
                    if ([responseObj[@"errors"][0][@"code"] intValue] == 32) {
                        return [NSError errorWithDomain:@"API Error" code:32 userInfo:responseObj];
                    }
                }
            }
        }
        
        return error;
    }
    
    if (response == nil) {
        return error;
    }
    
    if (response.statusCode >= 304) {
        return error;
    }
    
    if (data.length == 0) {
        return error;
    }
    
    return data;
}

// for sending those requests manually, when OAConsumer fails to be useful...
- (id)manuallySendPOSTRequest:(OAMutableURLRequest *)request {
    id retobj = [self sendRequest:request];
    
    if (retobj == nil) {
        return getNilReturnLengthError();
    }
    
    if ([retobj isKindOfClass:[NSError class]]) {
        return retobj;
    }
    
    id parsedJSONResponse = removeNull([NSJSONSerialization JSONObjectWithData:(NSData *)retobj options:NSJSONReadingMutableContainers error:nil]);
    
    if ([parsedJSONResponse isKindOfClass:[NSDictionary class]]) {
        NSString *errorMessage = [parsedJSONResponse objectForKey:@"error"];
        NSArray *errorArray = [parsedJSONResponse objectForKey:@"errors"];
        if (errorMessage.length > 0) {
            return [NSError errorWithDomain:errorMessage code:[[parsedJSONResponse objectForKey:@"code"]intValue] userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
        } else if (errorArray.count > 0) {
            if (errorArray.count > 1) {
                return [NSError errorWithDomain:@"Multiple Errors" code:1337 userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
            } else {
                NSDictionary *theError = [errorArray objectAtIndex:0];
                return [NSError errorWithDomain:[theError objectForKey:@"message"] code:[[theError objectForKey:@"code"]integerValue] userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
            }
        }
    }
    
    return parsedJSONResponse;
}

- (id)sendPOSTRequest:(OAMutableURLRequest *)request withParameters:(NSArray *)params {
    
    if (![self isAuthorized]) {
        [self loadAccessToken];
        if (![self isAuthorized]) {
            return [NSError errorWithDomain:@"You are not authorized via OAuth" code:401 userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
        }
    }
    
    [request setHTTPMethod:@"POST"];
    [request setParameters:params];
    [request prepare];
    
    return [self manuallySendPOSTRequest:request];
}

- (id)sendGETRequest:(OAMutableURLRequest *)request withParameters:(NSArray *)params {
    
    if (![self isAuthorized]) {
        [self loadAccessToken];
        if (![self isAuthorized]) {
            return [NSError errorWithDomain:@"You are not authorized via OAuth" code:401 userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
        }
    }
    
    [request setHTTPMethod:@"GET"];
    [request setParameters:params];
    [request prepare];

    id retobj = [self sendRequest:request];
    
    if (retobj == nil) {
        return getNilReturnLengthError();
    }
    
    if ([retobj isKindOfClass:[NSError class]]) {
        return retobj;
    }
    
    id parsedJSONResponse = removeNull([NSJSONSerialization JSONObjectWithData:(NSData *)retobj options:NSJSONReadingMutableContainers error:nil]);
    
    if ([parsedJSONResponse isKindOfClass:[NSDictionary class]]) {
        NSString *errorMessage = [parsedJSONResponse objectForKey:@"error"];
        NSArray *errorArray = [parsedJSONResponse objectForKey:@"errors"];
        if (errorMessage.length > 0) {
            return [NSError errorWithDomain:errorMessage code:[[parsedJSONResponse objectForKey:@"code"]intValue] userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
        } else if (errorArray.count > 0) {
            if (errorArray.count > 1) {
                return [NSError errorWithDomain:@"Multiple Errors" code:1337 userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
            } else {
                NSDictionary *theError = [errorArray objectAtIndex:0];
                return [NSError errorWithDomain:[theError objectForKey:@"message"] code:[[theError objectForKey:@"code"]integerValue] userInfo:[NSDictionary dictionaryWithObject:request forKey:@"request"]];
            }
        }
    }
    
    return parsedJSONResponse;
}


//
// OAuth
//

- (NSString *)getRequestTokenString {
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/oauth/request_token"];
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:url consumer:self.consumer token:nil];
    [request setHTTPMethod:@"POST"];
    [request prepare];
    
    id retobj = [self sendRequest:request];
    
    if ([retobj isKindOfClass:[NSData class]]) {
        return [[[NSString alloc]initWithData:(NSData *)retobj encoding:NSUTF8StringEncoding]autorelease];
    }
    
    return nil;
}

- (BOOL)finishAuthWithRequestToken:(OAToken *)reqToken {

    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
    
    OAMutableURLRequest *request = [OAMutableURLRequest requestWithURL:url consumer:self.consumer token:reqToken];
    [request setHTTPMethod:@"POST"];
    [request prepare];
    
    if (_shouldClearConsumer) {
        self.shouldClearConsumer = NO;
        self.consumer = nil;
    }
    
    id retobj = [self sendRequest:request];
    
    if ([retobj isKindOfClass:[NSError class]]) {
        return NO;
    }
    
    NSString *response = [[[NSString alloc]initWithData:(NSData *)retobj encoding:NSUTF8StringEncoding]autorelease];
    
    if (response.length == 0) {
        return NO;
    }
    
    [self storeAccessToken:response];
    
    return YES;
}

//
// Access Token Management
//

- (void)loadAccessToken {
    
    NSString *savedHttpBody = nil;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(loadAccessToken)]) {
        savedHttpBody = [self.delegate loadAccessToken];
    } else {
        savedHttpBody = [[NSUserDefaults standardUserDefaults]objectForKey:@"SavedAccessHTTPBody"];
    }
    
    self.accessToken = [OAToken tokenWithHTTPResponseBody:savedHttpBody];
    self.loggedInUsername = [self extractValueForKey:@"screen_name" fromHTTPBody:savedHttpBody];
    self.loggedInID = [self extractValueForKey:@"user_id" fromHTTPBody:savedHttpBody];
}

- (OAToken *)accessTokenWithScreenName:(NSString *)screenName
{
    if (screenName) {
        NSString *savedHttpBody = [self.delegate loadAccessTokenWithScreenName:screenName];
        return [OAToken tokenWithHTTPResponseBody:savedHttpBody];
    }
    return self.accessToken;
}

- (void)storeAccessToken:(NSString *)accessTokenZ {
    self.accessToken = [OAToken tokenWithHTTPResponseBody:accessTokenZ];
    self.loggedInUsername = [self extractValueForKey:@"screen_name" fromHTTPBody:accessTokenZ];
    self.loggedInID = [self extractValueForKey:@"user_id" fromHTTPBody:accessTokenZ];
    
    if ([self.delegate respondsToSelector:@selector(storeAccessToken:)]) {
        [self.delegate storeAccessToken:accessTokenZ];
    } else {
        [[NSUserDefaults standardUserDefaults]setObject:accessTokenZ forKey:@"SavedAccessHTTPBody"];
    }
}

- (NSString *)extractValueForKey:(NSString *)target fromHTTPBody:(NSString *)body {
    if (body.length == 0) {
        return nil;
    }
    
    if (target.length == 0) {
        return nil;
    }
	
	NSArray *tuples = [body componentsSeparatedByString:@"&"];
	if (tuples.count < 1) {
        return nil;
    }
	
	for (NSString *tuple in tuples) {
		NSArray *keyValueArray = [tuple componentsSeparatedByString:@"="];
		
		if (keyValueArray.count >= 2) {
			NSString *key = [keyValueArray objectAtIndex:0];
			NSString *value = [keyValueArray objectAtIndex:1];
			
			if ([key isEqualToString:target]) {
                return value;
            }
		}
	}
	
	return nil;
}

- (BOOL)isAuthorized {
    if (!self.consumer) {
        return NO;
    }
    
	if (self.accessToken.key && self.accessToken.secret) {
        if (self.accessToken.key.length > 0 && self.accessToken.secret.length > 0) {
            return YES;
        }
    }
    
	return NO;
}

- (void)clearAccessToken {
    [self storeAccessToken:@""];
	self.accessToken = nil;
    self.loggedInUsername = nil;
}

- (NSDate *)getDateFromTwitterCreatedAt:(NSString *)twitterDate {
    return [self.dateFormatter dateFromString:twitterDate];
}

- (void)clearConsumer {
    self.consumer = nil;
}

- (void)permanentlySetConsumerKey:(NSString *)consumerKey andSecret:(NSString *)consumerSecret {
    self.shouldClearConsumer = NO;
    self.consumer = [OAConsumer consumerWithKey:consumerKey secret:consumerSecret];
}

- (void)temporarilySetConsumerKey:(NSString *)consumerKey andSecret:(NSString *)consumerSecret {
    self.shouldClearConsumer = YES;
    self.consumer = [OAConsumer consumerWithKey:consumerKey secret:consumerSecret];
}

- (void)showOAuthLoginControllerFromViewController:(UIViewController *)sender {
    [self showOAuthLoginControllerFromViewController:sender withCompletion:nil];
}

- (void)showOAuthLoginControllerFromViewController:(UIViewController *)sender withCompletion:(void(^)(int success))block {
    FHSTwitterEngineController *vc = [[[FHSTwitterEngineController alloc]init]autorelease];
    vc.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    objc_setAssociatedObject(authBlockKey, "FHSTwitterEngineOAuthCompletion", block, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sender presentViewController:vc animated:YES completion:nil];
}

+ (BOOL)isConnectedToInternet {
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    if (reachability) {
        SCNetworkReachabilityFlags flags;
        BOOL worked = SCNetworkReachabilityGetFlags(reachability, &flags);
        CFRelease(reachability);
        
        if (worked) {
            
            if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
                return NO;
            }
            
            if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
                return YES;
            }
            
            
            if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) || (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
                if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
                    return YES;
                }
            }
            
            if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
                return YES;
            }
        }
        
    }
    return NO;
}

- (void)dealloc {
    [self setConsumer:nil];
    [self setDateFormatter:nil];
    [self setLoggedInUsername:nil];
    [self setLoggedInID:nil];
    [self setDelegate:nil];
    [self setAccessToken:nil];
    [super dealloc];
}

@end

@implementation FHSTwitterEngineController

static NSString * const newPinJS = @"var d = document.getElementById('oauth-pin'); if (d == null) d = document.getElementById('oauth_pin'); if (d) { var d2 = d.getElementsByTagName('code'); if (d2.length > 0) d2[0].innerHTML; }";
static NSString * const oldPinJS = @"var d = document.getElementById('oauth-pin'); if (d == null) d = document.getElementById('oauth_pin'); if (d) d = d.innerHTML; d;";

- (void)loadView {
    [super loadView];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(pasteboardChanged:) name:UIPasteboardChangedNotification object:nil];
    
    self.view = [[[UIView alloc]initWithFrame:CGRectMake(0, 0, 320, 460)]autorelease];
    self.view.backgroundColor = [UIColor grayColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    if (MIN([[UIDevice currentDevice].systemVersion floatValue], __IPHONE_OS_VERSION_MAX_ALLOWED/10000.0) >= 7) {
        self.navBar = [[[UINavigationBar alloc]initWithFrame:CGRectMake(0, 0, 320, 64)]autorelease];
    } else {
        self.navBar = [[[UINavigationBar alloc]initWithFrame:CGRectMake(0, 0, 320, 44)]autorelease];
    }
    _navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    
    self.theWebView = [[[UIWebView alloc]initWithFrame:CGRectMake(0, self.navBar.frame.size.height, 320, 416)]autorelease];
    _theWebView.hidden = YES;
    _theWebView.delegate = self;
    _theWebView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _theWebView.dataDetectorTypes = UIDataDetectorTypeNone;
    _theWebView.backgroundColor = [UIColor darkGrayColor];
	
	[self.view addSubview:_theWebView];
	[self.view addSubview:_navBar];
    
	self.blockerView = [[[UIView alloc]initWithFrame:CGRectMake(0, 0, 200, 60)]autorelease];
	_blockerView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
	_blockerView.center = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
	_blockerView.clipsToBounds = YES;
    _blockerView.layer.cornerRadius = 10;
    
    self.pinCopyBar = [[[UIToolbar alloc]initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, 44)]autorelease];
    _pinCopyBar.barStyle = UIBarStyleBlackTranslucent;
    _pinCopyBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    _pinCopyBar.items = [NSArray arrayWithObjects:[[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]autorelease], [[[UIBarButtonItem alloc]initWithTitle:@"Select and Copy the PIN" style: UIBarButtonItemStylePlain target:nil action: nil]autorelease], [[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]autorelease], nil];
	
	UILabel	*label = [[UILabel alloc]initWithFrame:CGRectMake(0, 5, _blockerView.bounds.size.width, 15)];
	label.text = @"Please Wait...";
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor whiteColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.font = [UIFont boldSystemFontOfSize:15];
	[_blockerView addSubview:label];
    [label release];
	
	UIActivityIndicatorView	*spinner = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	spinner.center = CGPointMake(_blockerView.bounds.size.width/2, (_blockerView.bounds.size.height/2)+10);
	[_blockerView addSubview:spinner];
	[self.view addSubview:_blockerView];
	[spinner startAnimating];
    [spinner release];
	
	UINavigationItem *navItem = [[[UINavigationItem alloc]initWithTitle:@"Twitter Login"]autorelease];
	navItem.leftBarButtonItem = [[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)]autorelease];
	[_navBar pushNavigationItem:navItem animated:NO];
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    dispatch_async(GCDBackgroundThread, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc]init];
        
        NSString *reqString = [[FHSTwitterEngine sharedEngine]getRequestTokenString];
        
        if (reqString.length == 0) {
            dispatch_sync(GCDMainThread, ^{
                void(^block)(BOOL success) = objc_getAssociatedObject(authBlockKey, "FHSTwitterEngineOAuthCompletion");
                objc_removeAssociatedObjects(authBlockKey);
                
                if (block) {
                    block(NO);
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            });
            [pool release];
            return;
        }
        
        self.requestToken = [OAToken tokenWithHTTPResponseBody:reqString];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.twitter.com/oauth/authorize?oauth_token=%@",_requestToken.key]]];
        
        dispatch_sync(GCDMainThread, ^{
            NSAutoreleasePool *poolTwo = [[NSAutoreleasePool alloc]init];
            [_theWebView loadRequest:request];
            [poolTwo release];
        });
        
        [pool release];
    });
}

- (void)gotPin:(NSString *)pin {
    _requestToken.verifier = pin;
    BOOL ret = [[FHSTwitterEngine sharedEngine]finishAuthWithRequestToken:_requestToken];
    
    void(^block)(BOOL success) = objc_getAssociatedObject(authBlockKey, "FHSTwitterEngineOAuthCompletion");
    objc_removeAssociatedObjects(authBlockKey);
    
    if (block) {
        block(ret);
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pasteboardChanged:(NSNotification *)note {
	
	if (![note.userInfo objectForKey:UIPasteboardChangedTypesAddedKey]) {
        return;
    }
    
    NSString *string = [[UIPasteboard generalPasteboard]string];
	
	if (string.length != 7 || !string.fhs_isNumeric) {
        return;
    }
	
	[self gotPin:string];
}

- (NSString *)locatePin {
	NSString *pin = [[_theWebView stringByEvaluatingJavaScriptFromString:newPinJS]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (pin.length == 7) {
		return pin;
	} else {
		pin = [[_theWebView stringByEvaluatingJavaScriptFromString:oldPinJS]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if (pin.length == 7) {
			return pin;
		}
	}
	
	return nil;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    _theWebView.userInteractionEnabled = YES;
    NSString *authPin = [self locatePin];
    
    if (authPin.length > 0) {
        [self gotPin:authPin];
        return;
    }
    
    NSString *formCount = [webView stringByEvaluatingJavaScriptFromString:@"document.forms.length"];
    
    if ([formCount isEqualToString:@"0"]) {
        [self showPinCopyPrompt];
    }
	
	[UIView beginAnimations:nil context:nil];
	_blockerView.hidden = YES;
	[UIView commitAnimations];
	
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    _theWebView.hidden = NO;
}

- (void)showPinCopyPrompt {
	if (_pinCopyBar.superview) {
        return;
    }
    
	_pinCopyBar.center = CGPointMake(_pinCopyBar.bounds.size.width/2, _pinCopyBar.bounds.size.height/2);
	[self.view insertSubview:_pinCopyBar belowSubview:_navBar];
    
    _theWebView.frame = CGRectMake(0, _theWebView.frame.origin.y + _pinCopyBar.frame.size.height, _theWebView.frame.size.width, _theWebView.frame.size.height-_pinCopyBar.frame.size.height);
	
	[UIView beginAnimations:nil context:nil];
    _pinCopyBar.center = CGPointMake(_pinCopyBar.bounds.size.width/2, _navBar.bounds.size.height+_pinCopyBar.bounds.size.height/2);
	[UIView commitAnimations];
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    _theWebView.userInteractionEnabled = NO;
    [_theWebView setHidden:YES];
    [_blockerView setHidden:NO];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
    if ([request.URL.absoluteString hasPrefix:@"https://mobile.twitter.com/signup"]) { // 关闭注册功能
        UIAlertView *alert = [[UIAlertView alloc]
                              initWithTitle:NSLocalizedString(@"注册功能已关闭", nil)
                              message:NSLocalizedString(@"由于注册的人太多，twitter已关闭本应用所用代理的注册权限", nil)
                              delegate:self
                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                              otherButtonTitles:nil, nil];
        [alert show];
        return NO;
    }
    if (strstr([request.URL.absoluteString UTF8String], "denied=")) {
		[self dismissViewControllerAnimated:YES completion:nil];
        return NO;
    }
    
    NSData *data = request.HTTPBody;
	char *raw = data?(char *)[data bytes]:"";
	
	if (raw && (strstr(raw, "cancel=") || strstr(raw, "deny="))) {
		[self dismissViewControllerAnimated:YES completion:nil];
		return NO;
	}
    
	return YES;
}

- (void)close {
    void(^block)(BOOL success) = objc_getAssociatedObject(authBlockKey, "FHSTwitterEngineOAuthCompletion");
    objc_removeAssociatedObjects(authBlockKey);
    
    if (block) {
        block(-1);
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissModalViewControllerAnimated:(BOOL)animated {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [[NSNotificationCenter defaultCenter]removeObserver:self];
    [_theWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@""]]];
    [super dismissModalViewControllerAnimated:animated];
}

- (void)dealloc {
    [self setNavBar:nil];
    [self setBlockerView:nil];
    [self setPinCopyBar:nil];
    [self setTheWebView:nil];
    [self setRequestToken:nil];
    [super dealloc];
}

@end


static char const encodingTable[64] = {
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/' };

@implementation NSData (Base64)

+ (NSData *)dataWithBase64EncodedString:(NSString *)string {
	return [[[NSData alloc]initWithBase64EncodedString:string]autorelease];
}

- (id)initWithBase64EncodedString:(NSString *)string {
	NSMutableData *mutableData = nil;
    
	if (string) {
		unsigned long ixtext = 0;
		unsigned char ch = 0;
        unsigned char inbuf[4] = {0,0,0,0};
        unsigned char outbuf[3] = {0,0,0};
		short ixinbuf = 0;
		BOOL flignore = NO;
		BOOL flendtext = NO;
        
		NSData *base64Data = [string dataUsingEncoding:NSASCIIStringEncoding];
		const unsigned char *base64Bytes = [base64Data bytes];
		mutableData = [NSMutableData dataWithCapacity:base64Data.length];
		unsigned long lentext = [base64Data length];
        
        while (!(ixtext >= lentext)) {
            
			ch = base64Bytes[ixtext++];
			flignore = NO;
            
			if ((ch >= 'A') && (ch <= 'Z')) {
                ch = ch - 'A';
            } else if ((ch >= 'a') && (ch <= 'z')) {
                ch = ch - 'a' + 26;
            } else if ((ch >= '0') && (ch <= '9')) {
                ch = ch - '0' + 52;
            } else if (ch == '+') {
                ch = 62;
            } else if (ch == '=') {
                flendtext = YES;
            } else if (ch == '/') {
                ch = 63;
            } else {
                flignore = YES;
            }
            
			if (!flignore) {
				short ctcharsinbuf = 3;
				BOOL flbreak = NO;
                
				if (flendtext) {
					if (!ixinbuf) {
                        break;
                    }
                    
					if (ixinbuf == 1 || ixinbuf == 2) {
                        ctcharsinbuf = 1;
                    } else {
                        ctcharsinbuf = 2;
                    }
                    
					ixinbuf = 3;
					flbreak = YES;
				}
                
				inbuf[ixinbuf++] = ch;
                
				if (ixinbuf == 4) {
					ixinbuf = 0;
					outbuf[0] = (inbuf[0] << 2) | ((inbuf[1] & 0x30) >> 4);
					outbuf[1] = ((inbuf[1] & 0x0F) << 4) | ((inbuf[2] & 0x3C) >> 2);
					outbuf[2] = ((inbuf[2] & 0x03) << 6) | (inbuf[3] & 0x3F);
                    
					for (int i = 0; i < ctcharsinbuf; i++) {
						[mutableData appendBytes:&outbuf[i] length:1];
                    }
				}
                
				if (flbreak)  {
                    break;
                }
			}
		}
	}
    
	self = [self initWithData:mutableData];
	return self;
}

- (NSString *)base64EncodingWithLineLength:(unsigned int)lineLength {
    
	const unsigned char	*bytes = [self bytes];
	unsigned long ixtext = 0;
	unsigned long lentext = [self length];
	long ctremaining = 0;
    unsigned char inbuf[3] = {0,0,0};
    unsigned char outbuf[4] = {0,0,0,0};
    
	short charsonline = 0;
    short ctcopy = 0;
	unsigned long ix = 0;
    
    NSMutableString *result = [NSMutableString stringWithCapacity:lentext];
    
	while (YES) {
		ctremaining = lentext-ixtext;
        
		if (ctremaining <= 0) {
            break;
        }
        
		for (int i = 0; i < 3; i++) {
			ix = ixtext + i;
            inbuf[i] = (ix < lentext)?bytes[ix]:0;
		}
        
		outbuf[0] = (inbuf[0] & 0xFC) >> 2;
		outbuf[1] = ((inbuf[0] & 0x03) << 4) | ((inbuf[1] & 0xF0) >> 4);
		outbuf[2] = ((inbuf[1] & 0x0F) << 2) | ((inbuf[2] & 0xC0) >> 6);
		outbuf[3] = inbuf[2] & 0x3F;
        
		switch (ctremaining) {
            case 1:
                ctcopy = 2;
                break;
            case 2:
                ctcopy = 3;
                break;
            default:
                ctcopy = 4;
                break;
		}
        
		for (int i = 0; i < ctcopy; i++) {
			[result appendFormat:@"%c",encodingTable[outbuf[i]]];
        }
        
		for (int i = ctcopy; i < 4; i++) {
            [result appendString:@"="];
        }
        
		ixtext += 3;
		charsonline += 4;
        
		if (lineLength > 0) {
			if (charsonline >= lineLength) {
				charsonline = 0;
				[result appendString:@"\n"];
			}
		}
	}
	return result;
}

@end
