//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioAttachmentPlayer.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSVideoAttachmentAdapter.h"
#import "ViewControllerUtils.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAudioAttachmentPlayer ()

@property (nonatomic, readonly) NSURL *mediaUrl;

@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, nullable) NSTimer *audioPlayerPoller;

@end

#pragma mark -

@implementation OWSAudioAttachmentPlayer

+ (NSURL *)mediaUrlForMediaAdapter:(TSVideoAttachmentAdapter *)mediaAdapter
                databaseConnection:(YapDatabaseConnection *)databaseConnection
{
    OWSAssert(mediaAdapter);
    OWSAssert([mediaAdapter isAudio]);
    OWSAssert(mediaAdapter.attachmentId);
    OWSAssert(databaseConnection);

    __block TSAttachment *attachment = nil;
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        attachment = [TSAttachment fetchObjectWithUniqueID:mediaAdapter.attachmentId transaction:transaction];
    }];
    OWSAssert(attachment);

    TSAttachmentStream *attachmentStream = nil;
    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
        attachmentStream = (TSAttachmentStream *)attachment;
    }
    OWSAssert(attachmentStream);

    return attachmentStream.mediaURL;
}

- (instancetype)initWithMediaAdapter:(TSVideoAttachmentAdapter *)mediaAdapter
                  databaseConnection:(YapDatabaseConnection *)databaseConnection
{
    return [self initWithMediaUrl:[OWSAudioAttachmentPlayer mediaUrlForMediaAdapter:mediaAdapter
                                                                 databaseConnection:databaseConnection]
                         delegate:mediaAdapter];
}

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioAttachmentPlayerDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(mediaUrl);
    OWSAssert(delegate);

    _delegate = delegate;
    _mediaUrl = mediaUrl;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self stop];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self stop];
}

#pragma mark - Methods

- (void)play
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.mediaUrl);
    OWSAssert(![self.delegate isAudioPlaying]);

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:YES];

    [self.audioPlayerPoller invalidate];

    self.delegate.isAudioPlaying = YES;
    self.delegate.isPaused = NO;
    [self.delegate setAudioIconToPause];

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaUrl error:&error];
        if (error) {
            DDLogError(@"%@ error: %@", self.tag, error);
            [self stop];
            return;
        }
        self.audioPlayer.delegate = self;
    }

    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];
    self.audioPlayerPoller = [NSTimer scheduledTimerWithTimeInterval:.05
                                                              target:self
                                                            selector:@selector(audioPlayerUpdated:)
                                                            userInfo:nil
                                                             repeats:YES];
}

- (void)pause
{
    OWSAssert([NSThread isMainThread]);

    self.delegate.isAudioPlaying = NO;
    self.delegate.isPaused = YES;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    double current = [self.audioPlayer currentTime] / [self.audioPlayer duration];
    [self.delegate setAudioProgressFromFloat:(float)current];
    [self.delegate setAudioIconToPlay];
}

- (void)stop
{
    OWSAssert([NSThread isMainThread]);

    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgressFromFloat:0];
    [self.delegate setAudioIconToPlay];
    self.delegate.isAudioPlaying = NO;
    self.delegate.isPaused = NO;
}

- (void)togglePlayState
{
    OWSAssert([NSThread isMainThread]);

    if (self.delegate.isAudioPlaying) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    OWSAssert([NSThread isMainThread]);

    OWSAssert(self.audioPlayer);
    OWSAssert(self.audioPlayerPoller);

    double current = [self.audioPlayer currentTime] / [self.audioPlayer duration];
    [self.delegate setAudioProgressFromFloat:(float)current];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    OWSAssert([NSThread isMainThread]);

    [self stop];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
