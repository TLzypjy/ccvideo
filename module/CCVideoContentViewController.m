#import "CCVideoContentViewController.h"
#import "CCVideoPrefs.h"
#import <AVFoundation/AVFoundation.h>

@interface CCVideoContentViewController ()
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;   // 主视频层（显示模式决定 gravity）
@property (nonatomic, strong) AVPlayerLayer *bgPlayerLayer; // 完整适应模式的模糊背景底层（铺满）
@property (nonatomic, strong) UIVisualEffectView *blurView; // 背景模糊
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, strong) UIView *videoContainer;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, copy, nullable) NSString *loadedVideoName; // 固定模式当前素材名（去重用）
@property (nonatomic, copy, nullable) NSString *playlistSignature; // 播放列表签名（模式+文件列表），变了才重建队列
@property (nonatomic, assign) BOOL wantsPlayback;
- (void)settingsChanged;
@end

static NSArray *ccv_shuffled(NSArray *items) {
    // 随机模式： Fisher-Yates 洗牌，返回重新排列的数组
    NSMutableArray *a = [items mutableCopy];
    for (NSInteger i = a.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [a exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    return a;
}

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

    // 图层顺序（底→顶）：铺满视频层 → 模糊层 → 完整视频层
    // （完整适应 = 底层铺满做模糊背景源，模糊层盖住它，主层完整显示在最上）
    _bgPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    _bgPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _bgPlayerLayer.hidden = YES;
    [_videoContainer.layer addSublayer:_bgPlayerLayer];

    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _blurView.hidden = YES;
    [_videoContainer addSubview:_blurView];

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
    _placeholderLabel.text = @"视频模块\n\n在设置 → 视频模块 → 素材库\n导入并选择视频";
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
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
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

// 显示模式（全局）：0=裁切填满 1=完整适应(模糊背景补边) 2=拉伸填满
- (NSString *)videoGravity {
    switch (CCVDisplayMode()) {
        case 0:  return AVLayerVideoGravityResizeAspectFill;
        case 2:  return AVLayerVideoGravityResize;
        default: return AVLayerVideoGravityResizeAspect;
    }
}

- (void)applyDisplayMode {
    NSInteger mode = CCVDisplayMode();
    BOOL fit = (mode == 1);
    self.bgPlayerLayer.hidden = !fit;
    self.blurView.hidden = !fit;
    self.playerLayer.videoGravity = [self videoGravity];
}

// 当前模块实际要播的文件名列表（固定=单选；随机/顺序=多选列表）
- (NSArray<NSString *> *)currentVideoNames {
    NSInteger mode = CCVPlayModeForModule(self.moduleIndex);
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names;
    if (mode == 0) {
        NSString *n = CCVSelectedVideoNameForModule(self.moduleIndex);
        names = n.length ? @[n] : @[];
    } else {
        names = CCVSelectedListForModule(self.moduleIndex);
        if (mode == 1) names = ccv_shuffled(names); // 随机模式：打乱顺序
    }
    // 只保留真实存在的文件
    NSMutableArray *valid = [NSMutableArray array];
    for (NSString *n in names) {
        if (n.length && [fm fileExistsAtPath:CCVVideoPathForName(n)]) [valid addObject:n];
    }
    return valid;
}

- (void)loadVideoIfNeeded {
    NSInteger mode = CCVPlayModeForModule(self.moduleIndex);
    NSArray<NSString *> *names = [self currentVideoNames];
    // 签名含模式+模式专属选中数据，任一变化都重建
    NSString *sig = [NSString stringWithFormat:@"%ld|%@", (long)mode,
                     mode == 0 ? CCVSelectedVideoNameForModule(self.moduleIndex)
                               : [CCVSelectedListForModule(self.moduleIndex) componentsJoinedByString:@","]];
    if ([sig isEqualToString:self.playlistSignature ?: @""]) return;
    self.playlistSignature = sig;
    self.loadedVideoName = names.firstObject;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.looper disableLooping];
    self.looper = nil;
    [self.player removeAllItems];

    BOOL ok = names.count > 0;
    self.videoContainer.hidden = !ok;
    self.placeholderLabel.hidden = ok;
    if (!ok) {
        [self.player pause];
        self.wantsPlayback = NO;
        return;
    }

    if (mode == 0 || names.count == 1) {
        // 固定（或只有一个素材）：单素材无缝循环
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(names[0])]];
        self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    } else {
        // 随机/顺序多素材：整批入队，播完循环（随机模式签名不变时保持同一洗牌序）
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *n in names) {
            [items addObject:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(n)]]];
        }
        for (AVPlayerItem *it in items) [self.player insertItem:it afterItem:nil];
        // 监听播放结束，队尾补播实现无缝循环
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(playerItemDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    }
    [self applyDisplayMode];
    if (self.wantsPlayback) [self.player play];
}

// 多素材队尾循环：有 item 播完时，若队列快空了就再补一轮（随机模式重新洗牌）
- (void)playerItemDidEnd:(NSNotification *)n {
    if (CCVPlayModeForModule(self.moduleIndex) == 0 || self.player.items.count > 1) return;
    NSArray<NSString *> *names = [self currentVideoNames];
    if (names.count < 2) return;
    for (NSString *name in names) {
        [self.player insertItem:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(name)]] afterItem:nil];
    }
    // 若播完的 item 仍卡在队首，前进到新插入的；否则 currentItem 为空，play 自动从队首开始
    if (self.player.currentItem && self.player.items.firstObject == self.player.currentItem
        && self.player.items.count > 1) {
        [self.player advanceToNextItem];
    }
    if (self.wantsPlayback) [self.player play];
}

- (void)settingsChanged {
    // 先同步偏好再读取
    CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID);
    [self applyDisplayMode];
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
    self.bgPlayerLayer.frame = self.videoContainer.bounds;
    self.blurView.frame = self.videoContainer.bounds;
    self.playerLayer.frame = self.videoContainer.bounds;
    CGFloat r = MIN(self.view.bounds.size.width, self.view.bounds.size.height) * 0.22;
    self.videoContainer.layer.cornerRadius = MIN(MAX(r, 12.0), 40.0);
}

@end
