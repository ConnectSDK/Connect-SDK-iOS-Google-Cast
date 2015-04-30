//
//  CNTCastWebAppSession.m
//  Connect SDK
//
//  Created by Jeremy White on 2/23/14.
//  Copyright (c) 2014 LG Electronics.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CNTCastWebAppSession.h"
#import "CNTConnectError.h"


@interface CNTCastWebAppSession () <GCKMediaControlChannelDelegate>
{
    CNTMediaPlayStateSuccessBlock _immediatePlayStateCallback;

    CNTServiceSubscription *_playStateSubscription;
    CNTServiceSubscription *_mediaInfoSubscription;
}

@end

@implementation CNTCastWebAppSession

@dynamic service;

- (void) connectWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_castServiceChannel)
        [self disconnectFromWebApp];
    
    CNTFailureBlock channelFailure = ^(NSError *error) {
        _castServiceChannel = nil;
        
        if (failure)
            failure(error);
    };
    
    _castServiceChannel = [[CNTCastServiceChannel alloc] initWithAppId:self.launchSession.appId session:self];

    // clean up old instance of channel, if it exists
    [self.service.castDeviceManager removeChannel:_castServiceChannel];

    _castServiceChannel.connectionSuccess = success;
    _castServiceChannel.connectionFailure = channelFailure;

    [self.service.castDeviceManager addChannel:_castServiceChannel];
}

- (void) joinWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self connectWithSuccess:success failure:failure];
}

- (void)disconnectFromWebApp
{
    if (!_castServiceChannel)
        return;

    [self.service.castDeviceManager removeChannel:_castServiceChannel];
    _castServiceChannel = nil;

    [self.service.castDeviceManager leaveApplication];
}

#pragma mark - ServiceCommandDelegate

- (int)sendSubscription:(CNTServiceSubscription *)subscription type:(CNTServiceSubscriptionType)type payload:(id)payload toURL:(NSURL *)URL withId:(int)callId
{
    if (type == CNTServiceSubscriptionTypeUnsubscribe)
    {
        if (subscription == _playStateSubscription)
            _playStateSubscription = nil;
        else if (subscription == _mediaInfoSubscription)
            _mediaInfoSubscription = nil;
    }

    return -1;
}

#pragma mark - App to app

- (void)sendText:(NSString *)message success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (message == nil)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeArgumentError andDetails:@"Cannot send nil message."]);

        return;
    }

    if (_castServiceChannel == nil)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"Cannot send a message to the web app without first connecting"]);

        return;
    }

    BOOL messageSent = [_castServiceChannel sendTextMessage:message];

    if (messageSent)
    {
        if (success)
            success(nil);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"Message could not be sent at this time."]);
    }
}

- (void)sendJSON:(NSDictionary *)message success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (message == nil)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeArgumentError andDetails:@"Cannot send nil message."]);

        return;
    }

    NSError *error;
    NSData *messageData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&error];

    if (error || messageData == nil)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeArgumentError andDetails:@"Failed to parse message dictionary into a JSON object."]);

        return;
    } else
    {
        NSString *messageJSON = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];

        [self sendText:messageJSON success:success failure:failure];
    }
}

#pragma mark - GCKMediaControlChannelDelegate methods

- (void)mediaControlChannelDidUpdateStatus:(GCKMediaControlChannel *)mediaControlChannel
{
    CNTMediaControlPlayState playState;

    switch (mediaControlChannel.mediaStatus.playerState)
    {
        case GCKMediaPlayerStateIdle:
            if (mediaControlChannel.mediaStatus.idleReason == GCKMediaPlayerIdleReasonFinished)
                playState = CNTMediaControlPlayStateFinished;
            else
                playState = CNTMediaControlPlayStateIdle;
            break;

        case GCKMediaPlayerStatePlaying:
            playState = CNTMediaControlPlayStatePlaying;
            break;

        case GCKMediaPlayerStatePaused:
            playState = CNTMediaControlPlayStatePaused;
            break;

        case GCKMediaPlayerStateBuffering:
            playState = CNTMediaControlPlayStateBuffering;
            break;

        case GCKMediaPlayerStateUnknown:
        default:
            playState = CNTMediaControlPlayStateUnknown;
    }

    if (_immediatePlayStateCallback)
    {
        _immediatePlayStateCallback(playState);
        _immediatePlayStateCallback = nil;
    }

    if (_playStateSubscription)
    {
        [_playStateSubscription.successCalls enumerateObjectsUsingBlock:^(id success, NSUInteger idx, BOOL *stop)
        {
            CNTMediaPlayStateSuccessBlock mediaPlayStateSuccess = (CNTMediaPlayStateSuccessBlock) success;

            if (mediaPlayStateSuccess)
                mediaPlayStateSuccess(playState);
        }];
    }
    
    if (_mediaInfoSubscription)
    {
        [_mediaInfoSubscription.successCalls enumerateObjectsUsingBlock:^(id success, NSUInteger idx, BOOL *stop)
         {
             CNTSuccessBlock mediaInfoSuccess = (CNTSuccessBlock) success;
             
             if (mediaInfoSuccess){
                 mediaInfoSuccess([self getMetadataInfo]);
             }
         }];
    }
}

#pragma mark - Media Player

- (id <CNTMediaPlayer>) mediaPlayer
{
    return self;
}

- (CNTCapabilityPriorityLevel) mediaPlayerPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void) displayImage:(NSURL *)imageURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType success:(CNTMediaPlayerDisplaySuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeArgumentError andDetails:nil]);
}

- (void) displayImage:(CNTMediaInfo *)mediaInfo
              success:(CNTMediaPlayerDisplaySuccessBlock)success
              failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeArgumentError andDetails:nil]);
}

- (void) playMedia:(NSURL *)mediaURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType shouldLoop:(BOOL)shouldLoop success:(CNTMediaPlayerDisplaySuccessBlock)success failure:(CNTFailureBlock)failure
{
    
    CNTMediaInfo *mediaInfo = [[CNTMediaInfo alloc] initWithURL:mediaURL mimeType:mimeType];
    mediaInfo.title = title;
    mediaInfo.description = description;
    CNTImageInfo *imageInfo = [[CNTImageInfo alloc] initWithURL:iconURL type:CNTImageTypeThumb];
    [mediaInfo addImage:imageInfo];
    
    [self playMediaWithMediaInfo:mediaInfo shouldLoop:shouldLoop success:^(CNTMediaLaunchObject *mediaLanchObject) {
        success(mediaLanchObject.session,mediaLanchObject.mediaControl);
    } failure:failure];
    
}

- (void) playMedia:(CNTMediaInfo *)mediaInfo shouldLoop:(BOOL)shouldLoop success:(CNTMediaPlayerDisplaySuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSURL *iconURL;
    if(mediaInfo.images){
        CNTImageInfo *imageInfo = [mediaInfo.images firstObject];
        iconURL = imageInfo.url;
    }
    [self playMedia:mediaInfo.url iconURL:iconURL title:mediaInfo.title description:mediaInfo.description mimeType:mediaInfo.mimeType shouldLoop:shouldLoop success:success failure:failure];
}

- (void)playMediaWithMediaInfo:(CNTMediaInfo *)mediaInfo shouldLoop:(BOOL)shouldLoop success:(CNTMediaPlayerSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSURL *iconURL;
    if(mediaInfo.images){
        CNTImageInfo *imageInfo = [mediaInfo.images firstObject];
        iconURL = imageInfo.url;
    }
    
    GCKMediaMetadata *metaData = [[GCKMediaMetadata alloc] initWithMetadataType:GCKMediaMetadataTypeMovie];
    [metaData setString:mediaInfo.title forKey:kGCKMetadataKeyTitle];
    [metaData setString:mediaInfo.description forKey:kGCKMetadataKeySubtitle];
    
    if (iconURL)
    {
        GCKImage *iconImage = [[GCKImage alloc] initWithURL:iconURL width:100 height:100];
        [metaData addImage:iconImage];
    }
    
    GCKMediaInformation *mediaInformation = [[GCKMediaInformation alloc] initWithContentID:mediaInfo.url.absoluteString streamType:GCKMediaStreamTypeBuffered contentType:mediaInfo.mimeType metadata:metaData streamDuration:1000 customData:nil];
    
    [self.service playMedia:mediaInformation webAppId:self.launchSession.appId success:^(CNTMediaLaunchObject *mediaLanchObject){
         self.launchSession.sessionId = mediaLanchObject.session.sessionId;
        mediaLanchObject.session = self.launchSession;
        mediaLanchObject.mediaControl = self.mediaControl;
         if (success)
             success(mediaLanchObject);
     } failure:failure];
    
}

- (void) closeMedia:(CNTLaunchSession *)launchSession success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self closeWithSuccess:success failure:failure];
}

#pragma mark - Media Control

- (id <CNTMediaControl>)mediaControl
{
    return self;
}

- (CNTCapabilityPriorityLevel)mediaControlPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void)getDurationWithSuccess:(CNTMediaDurationSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (self.service.castMediaControlChannel.mediaStatus)
    {
        if (success)
            success(self.service.castMediaControlChannel.mediaStatus.mediaInformation.streamDuration);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"There is no media currently available"]);
    }
}

- (void)seek:(NSTimeInterval)position success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (!self.service.castMediaControlChannel.mediaStatus)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"There is no media currently available"]);

        return;
    }

    NSInteger result = [self.service.castMediaControlChannel seekToTimeInterval:position];

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
    } else
    {
        if (success)
            success(nil);
    }
}

- (void)getPlayStateWithSuccess:(CNTMediaPlayStateSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (!self.service.castMediaControlChannel.mediaStatus)
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"There is no media currently available"]);

        return;
    }

    _immediatePlayStateCallback = success;

    NSInteger result = [self.service.castMediaControlChannel requestStatus];

    if (result == kGCKInvalidRequestID)
    {
        _immediatePlayStateCallback = nil;

        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
    }
}

- (CNTServiceSubscription *)subscribePlayStateWithSuccess:(CNTMediaPlayStateSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (!_playStateSubscription)
        _playStateSubscription = [CNTServiceSubscription subscriptionWithDelegate:self target:nil payload:nil callId:-1];

    [_playStateSubscription addSuccess:success];
    [_playStateSubscription addFailure:failure];

    [self.service.castMediaControlChannel requestStatus];

    return _playStateSubscription;
}

- (void)getPositionWithSuccess:(CNTMediaPositionSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (self.service.castMediaControlChannel.mediaStatus)
    {
        if (success)
            success(self.service.castMediaControlChannel.approximateStreamPosition);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"There is no media currently available"]);
    }
}

- (void)closeWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_castServiceChannel)
        [self disconnectFromWebApp];

    [self.service.webAppLauncher closeWebApp:self.launchSession success:success failure:failure];
}

-(void)getMediaMetaDataWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure{
    if (self.service.castMediaControlChannel.mediaStatus)
    {
        if (success){
        
            success([self getMetadataInfo]);
        }
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeError andDetails:@"There is no media currently available"]);
    }
}

- (CNTServiceSubscription *)subscribeMediaInfoWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure{
    if (!_mediaInfoSubscription)
        _mediaInfoSubscription = [CNTServiceSubscription subscriptionWithDelegate:self target:nil payload:nil callId:-1];
    
    [_mediaInfoSubscription addSuccess:success];
    [_mediaInfoSubscription addFailure:failure];
    
    [self.service.castMediaControlChannel requestStatus];
    
    return _mediaInfoSubscription;
}

-(NSDictionary *)getMetadataInfo{
    
    NSMutableDictionary *mediaMetaData = [NSMutableDictionary dictionary];
    GCKMediaMetadata *metaData = self.service.castMediaControlChannel.mediaStatus.mediaInformation.metadata;
    
    if([metaData objectForKey:@"com.google.cast.metadata.TITLE"])
        [mediaMetaData setObject:[metaData objectForKey:@"com.google.cast.metadata.TITLE"] forKey:@"title"];
    
    if([metaData objectForKey:@"com.google.cast.metadata.SUBTITLE"])
        [mediaMetaData setObject:[metaData objectForKey:@"com.google.cast.metadata.SUBTITLE"] forKey:@"subtitle"];
    
    if([metaData objectForKey:@"images"]){
        NSArray *images = [metaData objectForKey:@"images"];
        if([images count] > 0){
            [mediaMetaData setObject: [[images firstObject] objectForKey:@"url"] forKey:@"iconURL"];
        }
    }else
    if(metaData.images){
        NSArray *images = metaData.images;
        if([images count] > 0){
            GCKImage *image = [images firstObject];
            [mediaMetaData setObject:image.URL.absoluteString forKey:@"iconURL"];
        }
        
    }
    
    return mediaMetaData;
}

@end
