//
//  CNTCastService.m
//  Connect SDK
//
//  Created by Jeremy White on 2/7/14.
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

#import <GoogleCast/GoogleCast.h>
#import "CNTCastService.h"
#import "CNTConnectError.h"
#import "CNTCastWebAppSession.h"

#define kCastServiceMuteSubscriptionName @"mute"
#define kCastServiceVolumeSubscriptionName @"volume"

@interface CNTCastService () <CNTServiceCommandDelegate>

@end

@implementation CNTCastService
{
    int UID;

    NSString *_currentAppId;
    NSString *_launchingAppId;

    NSMutableDictionary *_launchSuccessBlocks;
    NSMutableDictionary *_launchFailureBlocks;

    NSMutableDictionary *_sessions; // TODO: are we using this? get rid of it if not
    NSMutableArray *_subscriptions;

    float _currentVolumeLevel;
    BOOL _currentMuteStatus;
}

- (void) commonSetup
{
    _launchSuccessBlocks = [NSMutableDictionary new];
    _launchFailureBlocks = [NSMutableDictionary new];

    _sessions = [NSMutableDictionary new];
    _subscriptions = [NSMutableArray new];

    UID = 0;
}

- (instancetype) init
{
    self = [super init];

    if (self)
        [self commonSetup];

    return self;
}

- (instancetype)initWithServiceConfig:(CNTServiceConfig *)serviceConfig
{
    self = [super initWithServiceConfig:serviceConfig];

    if (self)
        [self commonSetup];

    return self;
}

+ (NSDictionary *) discoveryParameters
{
    return @{
             @"serviceId": kCNTConnectSDKCastServiceId
             };
}

- (BOOL)isConnectable
{
    return YES;
}

- (void) updateCapabilities
{
    NSArray *capabilities = [NSArray new];

    capabilities = [capabilities arrayByAddingObjectsFromArray:kCNTMediaPlayerCapabilities];
    capabilities = [capabilities arrayByAddingObjectsFromArray:kCNTVolumeControlCapabilities];
    capabilities = [capabilities arrayByAddingObjectsFromArray:@[
            kCNTMediaControlPlay,
            kCNTMediaControlPause,
            kCNTMediaControlStop,
            kCNTMediaControlDuration,
            kCNTMediaControlSeek,
            kCNTMediaControlPosition,
            kCNTMediaControlPlayState,
            kCNTMediaControlPlayStateSubscribe,
            kCNTMediaControlMetadata,
            kCNTMediaControlMetadataSubscribe,

            kCNTWebAppLauncherLaunch,
            kCNTWebAppLauncherMessageSend,
            kCNTWebAppLauncherMessageReceive,
            kCNTWebAppLauncherMessageSendJSON,
            kCNTWebAppLauncherMessageReceiveJSON,
            kCNTWebAppLauncherConnect,
            kCNTWebAppLauncherDisconnect,
            kCNTWebAppLauncherJoin,
            kCNTWebAppLauncherClose
    ]];

    [self setCapabilities:capabilities];
}

- (void) sendNotSupportedFailure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeNotSupported andDetails:nil]);
}

-(NSString *)castWebAppId
{
    if(_castWebAppId == nil){
        _castWebAppId = kGCKMediaDefaultReceiverApplicationID;
    }
    return _castWebAppId;
}

#pragma mark - Connection

- (void)connect
{
    if (self.connected)
        return;

    if (!_castDevice)
    {
        UInt32 devicePort = (UInt32) self.serviceDescription.port;
        _castDevice = [[GCKDevice alloc] initWithIPAddress:self.serviceDescription.address servicePort:devicePort];
    }
    
    if (!_castDeviceManager)
    {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *clientPackageName = [info objectForKey:@"CFBundleIdentifier"];
        
        _castDeviceManager = [[GCKDeviceManager alloc] initWithDevice:_castDevice clientPackageName:clientPackageName];
        _castDeviceManager.delegate = self;
    }
    
    [_castDeviceManager connect];
}

- (void)disconnect
{
    if (!self.connected)
        return;

    self.connected = NO;

    [_castDeviceManager leaveApplication];
    [_castDeviceManager disconnect];

    if (self.delegate && [self.delegate respondsToSelector:@selector(deviceService:disconnectedWithError:)])
        dispatch_on_main(^{ [self.delegate deviceService:self disconnectedWithError:nil]; });
}

#pragma mark - Subscriptions

- (int)sendSubscription:(CNTServiceSubscription *)subscription type:(CNTServiceSubscriptionType)type payload:(id)payload toURL:(NSURL *)URL withId:(int)callId
{
    if (type == CNTServiceSubscriptionTypeUnsubscribe)
        [_subscriptions removeObject:subscription];
    else if (type == CNTServiceSubscriptionTypeSubscribe)
        [_subscriptions addObject:subscription];

    return callId;
}

- (int) getNextId
{
    UID = UID + 1;
    return UID;
}

#pragma mark - GCKDeviceManagerDelegate

- (void)deviceManagerDidConnect:(GCKDeviceManager *)deviceManager
{
    DLog(@"connected");

    self.connected = YES;

    _castMediaControlChannel = [[GCKMediaControlChannel alloc] init];
    [_castDeviceManager addChannel:_castMediaControlChannel];

    dispatch_on_main(^{ [self.delegate deviceServiceConnectionSuccess:self]; });
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didConnectToCastApplication:(GCKApplicationMetadata *)applicationMetadata sessionID:(NSString *)sessionID launchedApplication:(BOOL)launchedApplication
{
    DLog(@"%@ (%@)", applicationMetadata.applicationName, applicationMetadata.applicationID);

    _currentAppId = applicationMetadata.applicationID;

    CNTWebAppLaunchSuccessBlock success = [_launchSuccessBlocks objectForKey:applicationMetadata.applicationID];

    CNTLaunchSession *launchSession = [CNTLaunchSession launchSessionForAppId:applicationMetadata.applicationID];
    launchSession.name = applicationMetadata.applicationName;
    launchSession.sessionId = sessionID;
    launchSession.sessionType = CNTLaunchSessionTypeWebApp;
    launchSession.service = self;

    CNTCastWebAppSession *webAppSession = [[CNTCastWebAppSession alloc] initWithLaunchSession:launchSession service:self];
    webAppSession.metadata = applicationMetadata;

    [_sessions setObject:webAppSession forKey:applicationMetadata.applicationID];

    if (success)
        dispatch_on_main(^{ success(webAppSession); });

    [_launchSuccessBlocks removeObjectForKey:applicationMetadata.applicationID];
    [_launchFailureBlocks removeObjectForKey:applicationMetadata.applicationID];
    _launchingAppId = nil;
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didDisconnectFromApplicationWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);

    if (!_currentAppId)
        return;

    CNTWebAppSession *webAppSession = [_sessions objectForKey:_currentAppId];

    if (!webAppSession || !webAppSession.delegate)
        return;

    [webAppSession.delegate webAppSessionDidDisconnect:webAppSession];
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didFailToConnectToApplicationWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);

    if (_launchingAppId)
    {
        CNTFailureBlock failure = [_launchFailureBlocks objectForKey:_launchingAppId];

        if (failure)
            dispatch_on_main(^{ failure(error); });

        [_launchSuccessBlocks removeObjectForKey:_launchingAppId];
        [_launchFailureBlocks removeObjectForKey:_launchingAppId];
        _launchingAppId = nil;
    }
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didFailToConnectWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);

    if (self.connected)
        [self disconnect];
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didFailToStopApplicationWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didReceiveApplicationMetadata:(GCKApplicationMetadata *)applicationMetadata
{
    DLog(@"%@", applicationMetadata);

    _currentAppId = applicationMetadata.applicationID;
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager volumeDidChangeToLevel:(float)volumeLevel isMuted:(BOOL)isMuted
{
    DLog(@"volume: %f isMuted: %d", volumeLevel, isMuted);

    _currentVolumeLevel = volumeLevel;
    _currentMuteStatus = isMuted;

    [_subscriptions enumerateObjectsUsingBlock:^(CNTServiceSubscription *subscription, NSUInteger idx, BOOL *stop)
    {
        NSString *eventName = (NSString *) subscription.payload;

        if (eventName)
        {
            if ([eventName isEqualToString:kCastServiceVolumeSubscriptionName])
            {
                [subscription.successCalls enumerateObjectsUsingBlock:^(id success, NSUInteger successIdx, BOOL *successStop)
                {
                    CNTVolumeSuccessBlock volumeSuccess = (CNTVolumeSuccessBlock) success;

                    if (volumeSuccess)
                        dispatch_on_main(^{ volumeSuccess(volumeLevel); });
                }];
            }

            if ([eventName isEqualToString:kCastServiceMuteSubscriptionName])
            {
                [subscription.successCalls enumerateObjectsUsingBlock:^(id success, NSUInteger successIdx, BOOL *successStop)
                {
                    CNTMuteSuccessBlock muteSuccess = (CNTMuteSuccessBlock) success;

                    if (muteSuccess)
                        dispatch_on_main(^{ muteSuccess(isMuted); });
                }];
            }
        }
    }];
}

- (void)deviceManager:(GCKDeviceManager *)deviceManager didDisconnectWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);

    self.connected = NO;
    
    _castMediaControlChannel.delegate = nil;
    _castMediaControlChannel = nil;
    _castDeviceManager = nil;

    dispatch_on_main(^{ [self.delegate deviceService:self disconnectedWithError:error]; });
}

#pragma mark - Media Player

- (id<CNTMediaPlayer>)mediaPlayer
{
    return self;
}

- (CNTCapabilityPriorityLevel)mediaPlayerPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void)displayImage:(NSURL *)imageURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType success:(CNTMediaPlayerDisplaySuccessBlock)success failure:(CNTFailureBlock)failure
{
    GCKMediaMetadata *metaData = [[GCKMediaMetadata alloc] initWithMetadataType:GCKMediaMetadataTypePhoto];
    [metaData setString:title forKey:kGCKMetadataKeyTitle];
    [metaData setString:description forKey:kGCKMetadataKeySubtitle];

    if (iconURL)
    {
        GCKImage *iconImage = [[GCKImage alloc] initWithURL:iconURL width:100 height:100];
        [metaData addImage:iconImage];
    }
    
    GCKMediaInformation *mediaInformation = [[GCKMediaInformation alloc] initWithContentID:imageURL.absoluteString streamType:GCKMediaStreamTypeNone contentType:mimeType metadata:metaData streamDuration:0 customData:nil];

    [self playMedia:mediaInformation webAppId:self.castWebAppId success:^(CNTMediaLaunchObject *mediaLanchObject) {
        success(mediaLanchObject.session,mediaLanchObject.mediaControl);
    } failure:failure];
}

- (void) displayImage:(CNTMediaInfo *)mediaInfo
              success:(CNTMediaPlayerDisplaySuccessBlock)success
              failure:(CNTFailureBlock)failure
{
    NSURL *iconURL;
    if(mediaInfo.images){
        CNTImageInfo *imageInfo = [mediaInfo.images firstObject];
        iconURL = imageInfo.url;
    }
    
    [self displayImage:mediaInfo.url iconURL:iconURL title:mediaInfo.title description:mediaInfo.description mimeType:mediaInfo.mimeType success:success failure:failure];
}

- (void) displayImageWithMediaInfo:(CNTMediaInfo *)mediaInfo success:(CNTMediaPlayerSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSURL *iconURL;
    if(mediaInfo.images){
        CNTImageInfo *imageInfo = [mediaInfo.images firstObject];
        iconURL = imageInfo.url;
    }
    
    GCKMediaMetadata *metaData = [[GCKMediaMetadata alloc] initWithMetadataType:GCKMediaMetadataTypePhoto];
    [metaData setString:mediaInfo.title forKey:kGCKMetadataKeyTitle];
    [metaData setString:mediaInfo.description forKey:kGCKMetadataKeySubtitle];
    
    if (iconURL)
    {
        GCKImage *iconImage = [[GCKImage alloc] initWithURL:iconURL width:100 height:100];
        [metaData addImage:iconImage];
    }
    
    GCKMediaInformation *mediaInformation = [[GCKMediaInformation alloc] initWithContentID:mediaInfo.url.absoluteString streamType:GCKMediaStreamTypeNone contentType:mediaInfo.mimeType metadata:metaData streamDuration:0 customData:nil];
    
    [self playMedia:mediaInformation webAppId:self.castWebAppId success:success failure:failure];
}

- (void) playMedia:(NSURL *)videoURL iconURL:(NSURL *)iconURL title:(NSString *)title description:(NSString *)description mimeType:(NSString *)mimeType shouldLoop:(BOOL)shouldLoop success:(CNTMediaPlayerDisplaySuccessBlock)success failure:(CNTFailureBlock)failure
{
    GCKMediaMetadata *metaData = [[GCKMediaMetadata alloc] initWithMetadataType:GCKMediaMetadataTypeMovie];
    [metaData setString:title forKey:kGCKMetadataKeyTitle];
    [metaData setString:description forKey:kGCKMetadataKeySubtitle];

    if (iconURL)
    {
        GCKImage *iconImage = [[GCKImage alloc] initWithURL:iconURL width:100 height:100];
        [metaData addImage:iconImage];
    }
    
    GCKMediaInformation *mediaInformation = [[GCKMediaInformation alloc] initWithContentID:videoURL.absoluteString streamType:GCKMediaStreamTypeBuffered contentType:mimeType metadata:metaData streamDuration:1000 customData:nil];

    [self playMedia:mediaInformation webAppId:self.castWebAppId success:^(CNTMediaLaunchObject *mediaLanchObject) {
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

- (void) playMediaWithMediaInfo:(CNTMediaInfo *)mediaInfo shouldLoop:(BOOL)shouldLoop success:(CNTMediaPlayerSuccessBlock)success failure:(CNTFailureBlock)failure{
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
    
    [self playMedia:mediaInformation webAppId:self.castWebAppId success:success failure:failure];
}

- (void) playMedia:(GCKMediaInformation *)mediaInformation webAppId:(NSString *)mediaAppId success:(CNTMediaPlayerSuccessBlock)success failure:(CNTFailureBlock)failure
{
    CNTWebAppLaunchSuccessBlock webAppLaunchBlock = ^(CNTWebAppSession *webAppSession)
    {
        NSInteger result = [_castMediaControlChannel loadMedia:mediaInformation autoplay:YES];

        if (result == kGCKInvalidRequestID)
        {
            if (failure)
                failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
        } else
        {
            webAppSession.launchSession.sessionType = CNTLaunchSessionTypeMedia;

            _castMediaControlChannel.delegate = (CNTCastWebAppSession *) webAppSession;

            if (success){
                    CNTMediaLaunchObject *launchObject = [[CNTMediaLaunchObject alloc] initWithLaunchSession:webAppSession.launchSession andMediaControl:webAppSession.mediaControl];
                    success(launchObject);
            }
        }
    };

    _launchingAppId = mediaAppId;

    [_launchSuccessBlocks setObject:webAppLaunchBlock forKey:mediaAppId];

    if (failure)
        [_launchFailureBlocks setObject:failure forKey:mediaAppId];

    BOOL result = [_castDeviceManager launchApplication:mediaAppId relaunchIfRunning:NO];

    if (!result)
    {
        [_launchSuccessBlocks removeObjectForKey:mediaAppId];
        [_launchFailureBlocks removeObjectForKey:mediaAppId];

        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
    }
}

- (void)closeMedia:(CNTLaunchSession *)launchSession success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    BOOL result = [_castDeviceManager stopApplicationWithSessionID:launchSession.sessionId];

    if (result)
    {
        if (success)
            success(nil);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
    }
}

#pragma mark - Media Control

- (id<CNTMediaControl>)mediaControl
{
    return self;
}

- (CNTCapabilityPriorityLevel)mediaControlPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void)playWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSInteger result;

    @try
    {
        result = [_castMediaControlChannel play];
    } @catch (NSException *exception)
    {
        // this exception will be caught when trying to send command with no video
        result = kGCKInvalidRequestID;
    }

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            failure(nil);
    } else
    {
        if (success)
            success(nil);
    }
}

- (void)pauseWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSInteger result;

    @try
    {
        result = [_castMediaControlChannel pause];
    } @catch (NSException *exception)
    {
        // this exception will be caught when trying to send command with no video
        result = kGCKInvalidRequestID;
    }

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            failure(nil);
    } else
    {
        if (success)
            success(nil);
    }
}

- (void)stopWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSInteger result;

    @try
    {
        result = [_castMediaControlChannel stop];
    } @catch (NSException *exception)
    {
        // this exception will be caught when trying to send command with no video
        result = kGCKInvalidRequestID;
    }

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            failure(nil);
    } else
    {
        if (success)
            success(nil);
    }
}

- (void)rewindWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeNotSupported andDetails:nil]);
}

- (void)fastForwardWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeNotSupported andDetails:nil]);
}


#pragma mark - CNTWebAppLauncher

- (id<CNTWebAppLauncher>)webAppLauncher
{
    return self;
}

- (CNTCapabilityPriorityLevel)webAppLauncherPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void)launchWebApp:(NSString *)webAppId success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self launchWebApp:webAppId relaunchIfRunning:YES success:success failure:failure];
}

- (void)launchWebApp:(NSString *)webAppId relaunchIfRunning:(BOOL)relaunchIfRunning success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [_launchSuccessBlocks removeObjectForKey:webAppId];
    [_launchFailureBlocks removeObjectForKey:webAppId];

    if (success)
        [_launchSuccessBlocks setObject:success forKey:webAppId];

    if (failure)
        [_launchFailureBlocks setObject:failure forKey:webAppId];

    _launchingAppId = webAppId;

    BOOL result = [_castDeviceManager launchApplication:webAppId relaunchIfRunning:relaunchIfRunning];

    if (!result)
    {
        [_launchSuccessBlocks removeObjectForKey:webAppId];
        [_launchFailureBlocks removeObjectForKey:webAppId];
        _launchingAppId = nil;

        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:@"Could not detect if web app launched -- make sure you have the Google Cast Receiver JavaScript file in your web app"]);
    }
}

- (void)launchWebApp:(NSString *)webAppId params:(NSDictionary *)params success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeNotSupported andDetails:nil]);
}

- (void)launchWebApp:(NSString *)webAppId params:(NSDictionary *)params relaunchIfRunning:(BOOL)relaunchIfRunning success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (failure)
        failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeNotSupported andDetails:nil]);
}

- (void)joinWebApp:(CNTLaunchSession *)webAppLaunchSession success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    CNTWebAppLaunchSuccessBlock mySuccess = ^(CNTWebAppSession *webAppSession)
    {
        CNTSuccessBlock joinSuccess = ^(id responseObject)
        {
            if (success)
                success(webAppSession);
        };

        [webAppSession connectWithSuccess:joinSuccess failure:failure];
    };

    [_launchSuccessBlocks setObject:mySuccess forKey:webAppLaunchSession.appId];

    if (failure)
        [_launchFailureBlocks setObject:failure forKey:webAppLaunchSession.appId];

    _launchingAppId = webAppLaunchSession.appId;

    BOOL result = [_castDeviceManager joinApplication:webAppLaunchSession.appId];

    if (!result)
    {
        [_launchSuccessBlocks removeObjectForKey:webAppLaunchSession.appId];
        [_launchFailureBlocks removeObjectForKey:webAppLaunchSession.appId];
        _launchingAppId = nil;

        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:@"Could not detect if web app launched -- make sure you have the Google Cast Receiver JavaScript file in your web app"]);
    }
}

- (void) joinWebAppWithId:(NSString *)webAppId success:(CNTWebAppLaunchSuccessBlock)success failure:(CNTFailureBlock)failure
{
    CNTLaunchSession *launchSession = [CNTLaunchSession launchSessionForAppId:webAppId];
    launchSession.sessionType = CNTLaunchSessionTypeWebApp;
    launchSession.service = self;

    [self joinWebApp:launchSession success:success failure:failure];
}

- (void)closeWebApp:(CNTLaunchSession *)launchSession success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    BOOL result = [self.castDeviceManager stopApplication];

    if (result)
    {
        if (success)
            success(nil);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil]);
    }
}

- (void) pinWebApp:(NSString *)webAppId success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self sendNotSupportedFailure:failure];
}

-(void)unPinWebApp:(NSString *)webAppId success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self sendNotSupportedFailure:failure];
}

- (void)isWebAppPinned:(NSString *)webAppId success:(CNTWebAppPinStatusBlock)success failure:(CNTFailureBlock)failure
{
    [self sendNotSupportedFailure:failure];
}

- (CNTServiceSubscription *)subscribeIsWebAppPinned:(NSString*)webAppId success:(CNTWebAppPinStatusBlock)success failure:(CNTFailureBlock)failure
{
    [self sendNotSupportedFailure:failure];
    return nil;
}

#pragma mark - Volume Control

- (id <CNTVolumeControl>)volumeControl
{
    return self;
}

- (CNTCapabilityPriorityLevel)volumeControlPriority
{
    return CNTCapabilityPriorityLevelHigh;
}

- (void)volumeUpWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self getVolumeWithSuccess:^(float volume)
    {
        if (volume >= 1.0)
        {
            if (success)
                success(nil);
        } else
        {
            float newVolume = volume + 0.01;

            if (newVolume > 1.0)
                newVolume = 1.0;

            [self setVolume:newVolume success:success failure:failure];
        }
    } failure:failure];
}

- (void)volumeDownWithSuccess:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    [self getVolumeWithSuccess:^(float volume)
    {
        if (volume <= 0.0)
        {
            if (success)
                success(nil);
        } else
        {
            float newVolume = volume - 0.01;

            if (newVolume < 0.0)
                newVolume = 0.0;

            [self setVolume:newVolume success:success failure:failure];
        }
    } failure:failure];
}

- (void)setMute:(BOOL)mute success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSInteger result = [self.castDeviceManager setMuted:mute];

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            [CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:nil];
    } else
    {
        [self.castDeviceManager requestDeviceStatus];

        if (success)
            success(nil);
    }
}

- (void)getMuteWithSuccess:(CNTMuteSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_currentMuteStatus)
    {
        if (success)
            success(_currentMuteStatus);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:@"Cannot get this information without media loaded"]);
    }
}

- (CNTServiceSubscription *)subscribeMuteWithSuccess:(CNTMuteSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_currentMuteStatus)
    {
        if (success)
            success(_currentMuteStatus);
    }

    CNTServiceSubscription *subscription = [CNTServiceSubscription subscriptionWithDelegate:self target:nil payload:kCastServiceMuteSubscriptionName callId:[self getNextId]];
    [subscription addSuccess:success];
    [subscription addFailure:failure];
    [subscription subscribe];

    return subscription;
}

- (void)setVolume:(float)volume success:(CNTSuccessBlock)success failure:(CNTFailureBlock)failure
{
    NSInteger result;
    NSString *failureMessage;

    @try
    {
        result = [self.castDeviceManager setVolume:volume];
    } @catch (NSException *ex)
    {
        // this is likely caused by having no active media session
        result = kGCKInvalidRequestID;
        failureMessage = @"There is no active media session to set volume on";
    }

    if (result == kGCKInvalidRequestID)
    {
        if (failure)
            [CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:failureMessage];
    } else
    {
        [self.castDeviceManager requestDeviceStatus];

        if (success)
            success(nil);
    }
}

- (void)getVolumeWithSuccess:(CNTVolumeSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_currentVolumeLevel)
    {
        if (success)
            success(_currentVolumeLevel);
    } else
    {
        if (failure)
            failure([CNTConnectError generateErrorWithCode:CNTConnectStatusCodeTvError andDetails:@"Cannot get this information without media loaded"]);
    }
}

- (CNTServiceSubscription *)subscribeVolumeWithSuccess:(CNTVolumeSuccessBlock)success failure:(CNTFailureBlock)failure
{
    if (_currentVolumeLevel)
    {
        if (success)
            success(_currentVolumeLevel);
    }

    CNTServiceSubscription *subscription = [CNTServiceSubscription subscriptionWithDelegate:self target:nil payload:kCastServiceVolumeSubscriptionName callId:[self getNextId]];
    [subscription addSuccess:success];
    [subscription addFailure:failure];
    [subscription subscribe];

    [self.castDeviceManager requestDeviceStatus];

    return subscription;
}

@end
