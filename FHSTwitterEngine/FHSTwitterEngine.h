//
//  FHSTwitterEngine.h
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

//
//
//  //// FHSTwitterEngine Version 1.6.1 ////
//    Modified OAuthConsumer Version 1.2.2
//
//


//
// FHSTwitterEngine
// The synchronous Twitter engine that doesn’t suck!!
//

// FHSTwitterEngine is Synchronous
// That means you will have to thread. Boo Hoo.

// Setup
// Just add the FHSTwitterEngine folder to you project.

// USAGE
// See README.markdown

//
// NOTE TO CONTRIBUTORS
// Use NSJSONSerialization with removeNull(). Life is easy that way.
//


#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// These are for the dispatch_async() calls that you use to get around the synchronous-ness
#define GCDBackgroundThread dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
#define GCDMainThread dispatch_get_main_queue()

// oEmbed align modes
typedef enum {
    FHSTwitterEngineAlignModeLeft,
    FHSTwitterEngineAlignModeRight,
    FHSTwitterEngineAlignModeCenter,
    FHSTwitterEngineAlignModeNone
} FHSTwitterEngineAlignMode;

// Image sizes
typedef enum {
    FHSTwitterEngineImageSizeMini, // 24px by 24px
    FHSTwitterEngineImageSizeNormal, // 48x48
    FHSTwitterEngineImageSizeBigger, // 73x73
    FHSTwitterEngineImageSizeOriginal // original size of image
} FHSTwitterEngineImageSize;

typedef enum {
    FHSTwitterEngineResultTypeMixed,
    FHSTwitterEngineResultTypeRecent,
    FHSTwitterEngineResultTypePopular
} FHSTwitterEngineResultType;

// Remove NSNulls from NSDictionary and NSArray
// Credit for this function goes to Conrad Kramer
id removeNull(id rootObject);

extern NSString * const FHSProfileBackgroundColorKey;
extern NSString * const FHSProfileLinkColorKey;
extern NSString * const FHSProfileSidebarBorderColorKey;
extern NSString * const FHSProfileSidebarFillColorKey;
extern NSString * const FHSProfileTextColorKey;

extern NSString * const FHSProfileNameKey;
extern NSString * const FHSProfileURLKey;
extern NSString * const FHSProfileLocationKey;
extern NSString * const FHSProfileDescriptionKey;

@protocol FHSTwitterEngineAccessTokenDelegate <NSObject>

- (void)storeAccessToken:(NSString *)accessToken;
- (NSString *)loadAccessToken;
- (NSString *)loadAccessTokenWithScreenName:(NSString *)screenName;

@end

@class OAToken;
@class OAConsumer;
@class OAMutableURLRequest;

@interface FHSTwitterEngine : NSObject <UIWebViewDelegate>

- (NSDictionary *)postTweet:(NSString *)tweetString
                 imagePaths:(NSArray *)imagePaths
                  inReplyTo:(NSString *)irt
                   location:(CLLocation *)location
                    placeId:(NSString *)placeId
                 screenName:(NSString *)screenName;
- (NSError *)setUseProfileBackgroundImage:(BOOL)shouldUseBGImg;
- (NSError *)setBannerImageWithImageData:(NSData *)data;
- (NSError *)setProfileBackgroundImageWithImageData:(NSData *)data tiled:(BOOL)isTiled;
- (NSError *)setProfileBackgroundImageWithImageAtPath:(NSString *)file tiled:(BOOL)isTiled;
- (NSError *)setProfileImageWithImageData:(NSData *)data;
- (NSError *)setProfileImageWithImageAtPath:(NSString *)file;
- (NSError *)updateUserProfileWithDictionary:(NSDictionary *)settings;
+ (FHSTwitterEngine *)sharedEngine;
- (NSArray *)generateRequestStringsFromArray:(NSArray *)array;
- (void)sendPOSTRequest:(OAMutableURLRequest *)request
         withParameters:(NSArray *)params
                success:(void (^)(id responseObj))success
                failure:(void (^)(NSError *error))failure
               progress:(void (^)(double progress))progress;
- (void)sendRequest:(NSURLRequest *)request
            success:(void (^)(id responseObj))success
            failure:(void (^)(NSError *error))failure
           progress:(void (^)(double progress))progress;- (id)sendRequest:(NSURLRequest *)request;
- (id)manuallySendPOSTRequest:(OAMutableURLRequest *)request;
- (id)sendPOSTRequest:(OAMutableURLRequest *)request withParameters:(NSArray *)params;
- (id)sendGETRequest:(OAMutableURLRequest *)request withParameters:(NSArray *)params;
- (NSString *)getRequestTokenString;
- (BOOL)finishAuthWithRequestToken:(OAToken *)reqToken;
//
// Access Token Management
//

- (void)loadAccessToken;
- (void)storeAccessToken:(NSString *)accessTokenZ;
- (NSString *)extractValueForKey:(NSString *)target fromHTTPBody:(NSString *)body;
- (BOOL)isAuthorized;
- (void)clearAccessToken;
- (NSDate *)getDateFromTwitterCreatedAt:(NSString *)twitterDate;
- (void)clearConsumer;
- (void)permanentlySetConsumerKey:(NSString *)consumerKey andSecret:(NSString *)consumerSecret;
- (void)temporarilySetConsumerKey:(NSString *)consumerKey andSecret:(NSString *)consumerSecret;
- (void)showOAuthLoginControllerFromViewController:(UIViewController *)sender;
- (void)showOAuthLoginControllerFromViewController:(UIViewController *)sender withCompletion:(void(^)(int success))block;

+ (BOOL)isConnectedToInternet;

// Determines if entities should be included
@property (nonatomic, assign) BOOL includeEntities;

// Logged in user's username
@property (nonatomic, retain) NSString *loggedInUsername;

// Logged in user's Twitter ID
@property (nonatomic, retain) NSString *loggedInID;

// Will be called to store the accesstoken
@property (nonatomic, assign) id<FHSTwitterEngineAccessTokenDelegate> delegate;

// Access Token
@property (nonatomic, retain) OAToken *accessToken;

@end

@interface NSData (Base64)
+ (NSData *)dataWithBase64EncodedString:(NSString *)string;
- (id)initWithBase64EncodedString:(NSString *)string;
- (NSString *)base64EncodingWithLineLength:(unsigned int)lineLength;
@end

@interface NSString (FHSTwitterEngine)
- (NSString *)fhs_trimForTwitter;
- (NSString *)fhs_stringWithRange:(NSRange)range;
- (BOOL)fhs_isNumeric;
@end
