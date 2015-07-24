//
//  CastServiceTests.m
//  ConnectSDK
//
//  Created by Eugene Nikolskyi on 2015-07-23.
//  Copyright (c) 2015 LG Electronics. All rights reserved.
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

#import "CastService_Private.h"

#import "SubtitleTrack.h"

@interface CastServiceTests : XCTestCase

@end

@implementation CastServiceTests

#pragma mark - Subtitle Tests

- (void)testPlayVideoWithoutSubtitlesShouldLoadMediaWithoutMediaTracks {
    [self checkPlayVideoWithMediaInfo:[self mediaInfoWithoutSubtitle]
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            XCTAssertEqual(mediaInformation.mediaTracks.count, 0);
        }];
}

- (void)_testPlayVideoWithSubtitlesShouldLoadMediaWithOneMediaTrack {
    [self checkPlayVideoWithMediaInfo:[self mediaInfoWithSubtitle]
shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
    XCTAssertEqual(mediaInformation.mediaTracks.count, 1);
}];
}

#pragma mark - Helpers

- (void)checkPlayVideoWithMediaInfo:(MediaInfo *)mediaInfo
shouldLoadMediaWithMediaInformationPassingTest:(void (^)(GCKMediaInformation *mediaInformation))checkBlock {
    // using partial mock here to inject a few Cast fakes
    CastService *service = OCMPartialMock([CastService new]);

    id /*GCKMediaControlChannel **/ controlChannelMock = OCMClassMock([GCKMediaControlChannel class]);
    OCMStub([service createMediaControlChannel]).andReturn(controlChannelMock);

    id /*GCKDeviceManager **/ deviceManagerStub = OCMClassMock([GCKDeviceManager class]);
    OCMStub([service createDeviceManagerWithDevice:OCMOCK_ANY
                              andClientPackageName:OCMOCK_ANY]).andReturn(deviceManagerStub);
    [service connect];
    [service deviceManagerDidConnect:deviceManagerStub];

    XCTestExpectation *mediaLoadedExpectation = [self expectationWithDescription:@"media did load"];

    OCMExpect([controlChannelMock loadMedia:
            [OCMArg checkWithBlock:^BOOL(GCKMediaInformation *mediaInformation) {
                checkBlock(mediaInformation);

                [mediaLoadedExpectation fulfill];
                return YES;
            }]
                                   autoplay:YES]);

    [[OCMStub([deviceManagerStub launchApplication:OCMOCK_ANY
                                 relaunchIfRunning:NO]).andReturn(42) ignoringNonObjectArgs]
        andDo:^(NSInvocation *invocation) {
            id /*GCKApplicationMetadata **/ metadataStub = OCMClassMock([GCKApplicationMetadata class]);
            OCMStub([metadataStub applicationID]).andReturn(service.castWebAppId);
            [service deviceManager:deviceManagerStub
       didConnectToCastApplication:metadataStub
                         sessionID:@"s"
               launchedApplication:YES];
        }];

    [service playMediaWithMediaInfo:mediaInfo
                         shouldLoop:NO
                            success:nil
                            failure:nil];

    [self waitForExpectationsWithTimeout:kDefaultAsyncTestTimeout handler:nil];
    OCMVerifyAll(controlChannelMock);
}

#pragma mark - Subtitle Helpers

- (MediaInfo *)mediaInfoWithSubtitle {
    NSURL *subtitleURL = [NSURL URLWithString:@"http://example.com/"];
    MediaInfo *mediaInfo = [self mediaInfoWithoutSubtitle];
    SubtitleTrack *track = [SubtitleTrack trackWithURL:subtitleURL
                                              andBlock:^(SubtitleTrackBuilder *builder) {
                                                  builder.language = @"en";
                                                  builder.label = @"Test";
                                              }];
    mediaInfo.subtitleTrack = track;

    return mediaInfo;
}

- (MediaInfo *)mediaInfoWithoutSubtitle {
    NSString *sampleURL = @"http://example.com/";
    NSString *sampleMimeType = @"audio/ogg";
    MediaInfo *mediaInfo = [[MediaInfo alloc] initWithURL:[NSURL URLWithString:sampleURL]
                                                 mimeType:sampleMimeType];

    return mediaInfo;
}

@end
