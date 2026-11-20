#import "CCVideoContentViewController.h"
#import "CCVideoPrefs.h"
#import <AVFoundation/AVFoundation.h>

@interface CCVideoContentViewController ()
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, strong) UIView *videoContainer;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, copy, nullable) NSString *loadedVideoName;
@property (nonatomic, assign) BOOL wantsPlayback;
- (void)settingsChanged;
@end

static void ccv_darwin_callback(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CCVideoContentViewController *self2 = (__bridge CCVideoContentViewController *)observer;
        if ([self2 isKindOfClass:[CCVideoContentViewController class]]) [self2 settingsChanged];
    });
}

@implementation CCVideoContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _videoContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    _videoContainer.backgroundColor = [UIColor blackColor];
    _videoContainer.clipsToBounds = YES;
    _videoContainer.hidden = YES;
    [self.view addSubview:_videoContainer];

    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    _playerLayer.videoGravity = [self videoGravity];
    [_videoContainer.layer addSublayer:_playerLayer];

    _placeholderLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    _placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _placeholderLabel.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    _placeholderLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _placeholderLabel.font = [UIFont systemFontOfSize:11];
    _placeholderLabel.textAlignment = NSTextAlignmentCenter;
    _placeholderLabel.numberOfLines = 0;
    _placeholderLabel.text = @"视频模块\n\n在设置 → 控制中心 → 视频模块 → 素材库\n导入并选择视频";
    [self.view addSubview:_placeholderLabel];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    ccv_darwin_callback,
                                    (__bridge CFStringRef)CCVDarwinSettingsChanged,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    [self loadVideoIfNeeded];
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self));
    [_looper disableLooping];
}

- (AVQueuePlayer *)player {
    if (!_player) {
        _player = [[AVQueuePlayer alloc] init];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone; // 由 AVPlayerLooper 无缝循环
        _player.muted = YES; // 固定静音
    }
    return _player;
}

- (NSString *)videoGravity {
    return [CCVPrefs() boolForKey:CCVKeyAspectFill] ? AVLayerVideoGravityResizeAspectFill
                                                    : AVLayerVideoGravityResizeAspect;
}

- (void)loadVideoIfNeeded {
    NSString *name = CCVSelectedVideoName();
    if ([name isEqualToString:self.loadedVideoName ?: @""]) return;
    self.loadedVideoName = name;

    [self.looper disableLooping];
    self.looper = nil;
    [self.player removeAllItems];

    NSString *path = CCVVideoPathForName(name);
    BOOL ok = name.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
    self.videoContainer.hidden = !ok;
    self.placeholderLabel.hidden = ok;
    if (!ok) {
        [self.player pause];
        self.wantsPlayback = NO;
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    self.playerLayer.videoGravity = [self videoGravity];
    if (self.wantsPlayback) [self.player play];
}

- (void)settingsChanged {
    // 先同步偏好再读取
    CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID);
    self.playerLayer.videoGravity = [self videoGravity];
    [self loadVideoIfNeeded];
}

- (void)playIfVisible {
    self.wantsPlayback = YES;
    if (self.videoContainer.hidden) return;
    [self.player play];
}

- (void)pausePlayback {
    self.wantsPlayback = NO;
    [self.player pause];
}

// ---------- 生命周期：只在可见时播放，省电 ----------
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self playIfVisible];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pausePlayback];
}

- (void)willBecomeActive {
    [self playIfVisible];
}

- (void)willResignActive {
    [self pausePlayback];
}

- (void)controlCenterWillPresent {
    [self playIfVisible];
}

- (void)controlCenterDidDismiss {
    [self pausePlayback];
}

// ---------- 模块协议 ----------
- (CGFloat)preferredExpandedContentHeight { return 0; }
- (CGFloat)preferredExpandedContentWidth  { return 0; }
- (BOOL)providesOwnPlatter { return YES; } // 无底板，视频铺满模块

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.videoContainer.frame = self.view.bounds;
    self.playerLayer.frame = self.videoContainer.bounds;
    CGFloat r = MIN(self.view.bounds.size.width, self.view.bounds.size.height) * 0.22;
    self.videoContainer.layer.cornerRadius = MIN(MAX(r, 12.0), 40.0);
}

@end
