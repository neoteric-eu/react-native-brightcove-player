#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "BrightcovePlayer.h"
#import "BrightcovePlayerOfflineVideoManager.h"
#import <BrightcovePlayerSDK/BCOVFPSBrightcoveAuthProxy.h>

@interface BrightcovePlayer () <BCOVPlaybackControllerDelegate, BCOVPUIPlayerViewDelegate>

@end

@implementation BrightcovePlayer

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    return self;
}

- (void)setup {
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];

    _playbackController = [self createPlaybackController];
    _playbackController.allowsExternalPlayback = true;
    _playbackController.usesExternalPlaybackWhileExternalScreenIsActive = true;
    _playbackController.delegate = self;
    _playbackController.autoPlay = NO;
    _playbackController.autoAdvance = YES;
    // Prevents the Brightcove SDK from making an unnecessary AVPlayerLayer
    // since the AVPlayerViewController already makes one
    _playbackController.options = @{ kBCOVAVPlayerViewControllerCompatibilityKey: @YES };

    _playerViewController = [[AVPlayerViewController alloc] init];
    _playerViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_playerViewController.view];
    [NSLayoutConstraint activateConstraints:@[
                                              [_playerViewController.view.topAnchor constraintEqualToAnchor:self.topAnchor],
                                              [_playerViewController.view.rightAnchor constraintEqualToAnchor:self.rightAnchor],
                                              [_playerViewController.view.leftAnchor constraintEqualToAnchor:self.leftAnchor],
                                              [_playerViewController.view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                                              ]];
    _targetVolume = 1.0;
    _autoPlay = NO;
}

- (void)setupService {
    if ((!_playbackService || _playbackServiceDirty) && _accountId && _policyKey) {
        _playbackServiceDirty = NO;
        _playbackService = [[BCOVPlaybackService alloc] initWithAccountId:_accountId policyKey:_policyKey];
    }
}

- (void)loadMovie {
    if (_videoToken) {
        BCOVVideo *video = [[BrightcovePlayerOfflineVideoManager sharedManager] videoObjectFromOfflineVideoToken:_videoToken];
        if (video && video.playableOffline) {
            [self.playbackController setVideos: @[ video ]];
            return;
        }
    }
    if (!_playbackService) return;
    if (_videoId) {
        [_playbackService findVideoWithVideoID:_videoId parameters:nil completion:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
            if (video) {
                [self.playbackController setVideos: @[ video ]];
            }
        }];
    } else if (_referenceId) {
        [_playbackService findVideoWithReferenceID:_referenceId parameters:nil completion:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
            if (video) {
                [self.playbackController setVideos: @[ video ]];
            }
        }];
    }
}

#pragma mark BCOVPlaybackControllerDelegate Methods

- (id<BCOVPlaybackController>)createPlaybackController {
    
    // Create a BCOVFPSBrightcoveAuthProxy object.
      // Use the built-in authorization proxy to take advantage of Dynamic Delivery.
      // The application id and publisher id are not needed with Dynamic Delivery.
      // You also don't need to worry about retrieving any application certificates.
      BCOVFPSBrightcoveAuthProxy *proxy = [[BCOVFPSBrightcoveAuthProxy alloc] initWithPublisherId:nil
                                                                                    applicationId:nil];
    
    BCOVBasicSessionProvider *psp = [BCOVPlayerSDKManager.sharedManager createBasicSessionProviderWithOptions:nil];
    BCOVBasicSessionProvider *fsp = [BCOVPlayerSDKManager.sharedManager createFairPlaySessionProviderWithAuthorizationProxy:proxy upstreamSessionProvider:psp];
    
    return [BCOVPlayerSDKManager.sharedManager createPlaybackControllerWithSessionProvider:fsp viewStrategy:nil];
}

- (void)playbackController:(id<BCOVPlaybackController>)controller didAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
    self.playerViewController.player = session.player;
}

- (void)setReferenceId:(NSString *)referenceId {
    _referenceId = referenceId;
    _videoId = NULL;
    [self setupService];
    [self loadMovie];
}

- (void)setVideoId:(NSString *)videoId {
    _videoId = videoId;
    _referenceId = NULL;
    [self setupService];
    [self loadMovie];
}

- (void)setVideoToken:(NSString *)videoToken {
    _videoToken = videoToken;
    [self loadMovie];
}

- (void)setAccountId:(NSString *)accountId {
    _accountId = accountId;
    _playbackServiceDirty = YES;
    [self setupService];
    [self loadMovie];
}

- (void)setPolicyKey:(NSString *)policyKey {
    _policyKey = policyKey;
    _playbackServiceDirty = YES;
    [self setupService];
    [self loadMovie];
}

- (void)setAutoPlay:(BOOL)autoPlay {
    _autoPlay = autoPlay;
}

- (void)setPlay:(BOOL)play {
    if (_playing == play) return;
    if (play) {
        [[AVAudioSession sharedInstance] setActive:true error:nil];
        [_playbackController play];
    } else {
        [_playbackController pause];
    }
}

- (void)setFullscreen:(BOOL)fullscreen {
//    if (fullscreen) {
//        [_playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeFull];
//    } else {
//        [_playerView performScreenTransitionWithScreenMode:BCOVPUIScreenModeNormal];
//    }
}

- (void)setVolume:(NSNumber*)volume {
    _targetVolume = volume.doubleValue;
    [self refreshVolume];
}

- (void)setBitRate:(NSNumber*)bitRate {
    _targetBitRate = bitRate.doubleValue;
    [self refreshBitRate];
}

- (void)setPlaybackRate:(NSNumber*)playbackRate {
    _targetPlaybackRate = playbackRate.doubleValue;
    if (_playing) {
        [self refreshPlaybackRate];
    }
}

- (void)refreshVolume {
    if (!_playbackSession) return;
    _playbackSession.player.volume = _targetVolume;
}

- (void)refreshBitRate {
    if (!_playbackSession) return;
    AVPlayerItem *item = _playbackSession.player.currentItem;
    if (!item) return;
    item.preferredPeakBitRate = _targetBitRate;
}

- (void)refreshPlaybackRate {
    if (!_playbackSession || !_targetPlaybackRate) return;
    _playbackSession.player.rate = _targetPlaybackRate;
}

- (void)setDisableDefaultControl:(BOOL)disable {
//    _playerView.controlsView.hidden = disable;
}

- (void)seekTo:(NSNumber *)time {
    [_playbackController seekToTime:CMTimeMakeWithSeconds([time floatValue], NSEC_PER_SEC) completionHandler:^(BOOL finished) {
    }];
}

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent {
    if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlaybackBufferEmpty || lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventFail ||
        lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventError ||
        lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventTerminate) {
        _playbackSession = nil;
        return;
    }
    _playbackSession = session;
    if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventReady) {
        [self refreshVolume];
        [self refreshBitRate];
        if (self.onReady) {
            self.onReady(@{});
        }
        if (_autoPlay) {
            [_playbackController play];
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPlay) {
        _playing = true;
        [self refreshPlaybackRate];
        if (self.onPlay) {
            self.onPlay(@{});
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventPause) {
        _playing = false;
        if (self.onPause) {
            self.onPause(@{});
        }
    } else if (lifecycleEvent.eventType == kBCOVPlaybackSessionLifecycleEventEnd) {
        if (self.onEnd) {
            self.onEnd(@{});
        }
    }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didChangeDuration:(NSTimeInterval)duration {
    if (self.onChangeDuration) {
        self.onChangeDuration(@{
                                @"duration": @(duration)
                                });
    }
}

-(void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didProgressTo:(NSTimeInterval)progress {
    if (self.onProgress && progress > 0 && progress != INFINITY) {
        self.onProgress(@{
                          @"currentTime": @(progress)
                          });
    }

//    float bufferProgress = _playerView.controlsView.progressSlider.bufferProgress;
//    if (_lastBufferProgress != bufferProgress) {
//        _lastBufferProgress = bufferProgress;
//        self.onUpdateBufferProgress(@{
//                                      @"bufferProgress": @(bufferProgress),
//                                      });
//    }
}

-(void)playerView:(BCOVPUIPlayerView *)playerView didTransitionToScreenMode:(BCOVPUIScreenMode)screenMode {
    if (screenMode == BCOVPUIScreenModeNormal) {
        if (self.onExitFullscreen) {
            self.onExitFullscreen(@{});
        }
    } else if (screenMode == BCOVPUIScreenModeFull) {
        if (self.onEnterFullscreen) {
            self.onEnterFullscreen(@{});
        }
    }
}

-(void)dispose {
    [self.playbackController setVideos:@[]];
}

#pragma mark UIView Methods

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.onTouchesBegan) {
        self.onTouchesBegan(@{});
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (self.onTouchesEnded) {
        NSUInteger taps = [[[event allTouches] anyObject] tapCount];
        self.onTouchesEnded(@{@"tapCount" : @(taps)});
    }
}

@end
