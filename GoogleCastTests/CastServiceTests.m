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

@property(nonatomic, strong) CastService *service;
@end

@implementation CastServiceTests

- (void)setUp {
    [super setUp];

    // using partial mock here to inject a few Cast fakes
    self.service = OCMPartialMock([CastService new]);
}

#pragma mark - General Tests

- (void)testInstanceShouldHaveVTTCapability {
    XCTAssertNotEqual([self.service.capabilities indexOfObject:kMediaPlayerSubtitleVTT],
                      NSNotFound);
}

#pragma mark - Subtitle Tests

- (void)testPlayVideoWithoutSubtitlesShouldLoadMediaWithoutMediaTracks {
    [self checkPlayVideoWithMediaInfo:[self mediaInfoWithoutSubtitle]
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            XCTAssertEqual(mediaInformation.mediaTracks.count, 0);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldLoadMediaWithOneMediaTrack {
    [self checkPlayVideoWithMediaInfo:[self mediaInfoWithSubtitle]
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            XCTAssertEqual(mediaInformation.mediaTracks.count, 1);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackContentIdentifierAsURL {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.contentIdentifier,
                                  mediaInfo.subtitleTrack.url.absoluteString);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackContentTypeAsMIMEType {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.contentType, mediaInfo.subtitleTrack.mimeType);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackTypeAsText {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqual(track.type, GCKMediaTrackTypeText);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackSubtypeAsSubtitles {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqual(track.textSubtype, GCKMediaTextTrackSubtypeSubtitles);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackNameAsLabel {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.name, mediaInfo.subtitleTrack.label);
        }];
}

- (void)testPlayVideoWithSubtitlesShouldSetMediaTrackLanguageCodeAsLanguage {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitle];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.languageCode, mediaInfo.subtitleTrack.language);
        }];
}

- (void)testPlayVideoWithSubtitlesWithoutMIMETypeShouldNotSetMediaTrackContentType {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitleMIMEType:nil
                                                      language:@"en"
                                                      andLabel:@"a"];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertNil(track.contentType);
        }];
}

- (void)testPlayVideoWithSubtitlesWithoutLabelShouldNotSetMediaTrackName {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitleMIMEType:@"text/vtt"
                                                      language:@"en"
                                                      andLabel:nil];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertNil(track.name);
        }];
}

- (void)testPlayVideoWithSubtitlesWithoutLanguageShouldSetMediaTrackLanguageCodeAsDefault {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitleMIMEType:@"text/vtt"
                                                      language:nil
                                                      andLabel:@"a"];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.languageCode, @"en");
        }];
}

- (void)testPlayVideoWithSubtitlesWithIncorrectLanguageShouldSetMediaTrackLanguageCodeAsLanguage {
    MediaInfo *mediaInfo = [self mediaInfoWithSubtitleMIMEType:@"text/vtt"
                                                      language:@"unknown_!#%$"
                                                      andLabel:@"a"];
    [self checkPlayVideoWithMediaInfo:mediaInfo
        shouldLoadMediaWithMediaInformationPassingTest:^(GCKMediaInformation *mediaInformation) {
            GCKMediaTrack *track = [mediaInformation.mediaTracks firstObject];
            XCTAssertEqualObjects(track.languageCode,
                                  mediaInfo.subtitleTrack.language);
        }];
}

#pragma mark - Helpers

- (void)checkPlayVideoWithMediaInfo:(MediaInfo *)mediaInfo
shouldLoadMediaWithMediaInformationPassingTest:(void (^)(GCKMediaInformation *mediaInformation))checkBlock {
    id /*GCKMediaControlChannel **/ controlChannelMock = OCMClassMock([GCKMediaControlChannel class]);
    OCMStub([self.service createMediaControlChannel]).andReturn(controlChannelMock);

    id /*GCKDeviceManager **/ deviceManagerStub = OCMClassMock([GCKDeviceManager class]);
    OCMStub([self.service createDeviceManagerWithDevice:OCMOCK_ANY
                                   andClientPackageName:OCMOCK_ANY]).andReturn(deviceManagerStub);
    [self.service connect];
    [self.service deviceManagerDidConnect:deviceManagerStub];

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
            OCMStub([metadataStub applicationID]).andReturn(self.service.castWebAppId);
            [self.service deviceManager:deviceManagerStub
            didConnectToCastApplication:metadataStub
                              sessionID:@"s"
                    launchedApplication:YES];
        }];

    [self.service playMediaWithMediaInfo:mediaInfo
                              shouldLoop:NO
                                 success:nil
                                 failure:nil];

    [self waitForExpectationsWithTimeout:kDefaultAsyncTestTimeout handler:nil];
    OCMVerifyAll(controlChannelMock);
}

#pragma mark - Subtitle Helpers

- (MediaInfo *)mediaInfoWithSubtitle {
    return [self mediaInfoWithSubtitleMIMEType:@"text/vtt"
                                      language:@"en"
                                      andLabel:@"Test"];
}

- (MediaInfo *)mediaInfoWithSubtitleMIMEType:(NSString *)mimeType
                                    language:(NSString *)language
                                    andLabel:(NSString *)label {
    NSURL *subtitleURL = [NSURL URLWithString:@"http://example.com/"];
    MediaInfo *mediaInfo = [self mediaInfoWithoutSubtitle];
    SubtitleTrack *track = [SubtitleTrack trackWithURL:subtitleURL
                                              andBlock:^(SubtitleTrackBuilder *builder) {
                                                  builder.mimeType = mimeType;
                                                  builder.language = language;
                                                  builder.label = label;
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
