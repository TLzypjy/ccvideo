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
@property (nonatomic, strong, nullable) NSArray<NSString *> *playNames; // 多素材当前播放顺序
@property (nonatomic, assign) NSUInteger playIndex;                    // 多素材当前播到第几条
@property (nonatomic, assign) BOOL wantsPlayback;
- (void)settingsChanged;
- (void)ccvWindowDetached;  // 视图移出窗口 = 控制中心关闭
- (void)ccvWindowAttached;  // 视图挂回窗口 = 控制中心打开
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

// ---------- 断点续播偏好（每模块） ----------
static NSString * const kResumeNameKey = @"CCVResumeName"; // 上次暂停时的素材名
static NSString * const kResumeTimeKey = @"CCVResumeTime"; // 上次暂停时的秒数

static NSString *ccv_resumeName(NSUInteger idx) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID);
    NSString *key = CCVKeyForModule(kResumeNameKey, idx);
    return (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)CCVBundleID);
}

static double ccv_resumeTime(NSUInteger idx) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID);
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)CCVKeyForModule(kResumeTimeKey, idx), (__bridge CFStringRef)CCVBundleID);
    return [v isKindOfClass:[NSNumber class]] ? [(NSNumber *)v doubleValue] : 0.0;
}

static void ccv_saveResumePrefs(NSString *name, double t, NSUInteger idx) {
    if (name.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)CCVKeyForModule(kResumeNameKey, idx), (__bridge CFTypeRef)name, (__bridge CFStringRef)CCVBundleID);
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberDoubleType, &t);
    CFPreferencesSetAppValue((__bridge CFStringRef)CCVKeyForModule(kResumeTimeKey, idx), n, (__bridge CFStringRef)CCVBundleID);
    CFRelease(n);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID);
}

// 根视图：监听窗口挂载/卸载。控制中心关闭时模块视图会被移出窗口（协议回调不保证触发），
// 这是最可靠的"关闭 CC 暂停 / 打开 CC 播放"信号
@interface CCVRootView : UIView
@property (nonatomic, weak) CCVideoContentViewController *owner;
@end
@implementation CCVRootView
- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (!newWindow) [self.owner ccvWindowDetached];
    else [self.owner ccvWindowAttached];
}
@end

static void ccv_darwin_callback(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CCVideoContentViewController *self2 = (__bridge CCVideoContentViewController *)observer;
        if ([self2 isKindOfClass:[CCVideoContentViewController class]]) [self2 settingsChanged];
    });
}

@implementation CCVideoContentViewController

- (void)loadView {
    // 用自定义根视图，借助 willMoveToWindow 感知控制中心开/关
    CCVRootView *v = [[CCVRootView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    v.owner = self;
    v.backgroundColor = [UIColor clearColor];
    self.view = v;
}

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
    CCVLog(@"content viewDidLoad v0.1.34 模块%lu", (unsigned long)self.moduleIndex);
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
        names = CCVSelectedListForModule(self.moduleIndex, mode); // 随机/顺序各读自己的列表
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
                               : [CCVSelectedListForModule(self.moduleIndex, mode) componentsJoinedByString:@","]];
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

    // 断点续播：读上次暂停位置（素材名+秒数）
    NSString *savedName = ccv_resumeName(self.moduleIndex);
    double savedTime = ccv_resumeTime(self.moduleIndex);
    BOOL canResume = savedName.length > 0 && savedTime > 0.3 && [names containsObject:savedName];

    if (mode == 0 || names.count == 1) {
        // 固定（或只有一个素材）：单素材无缝循环
        // AVPlayerLooper 要求 actionAtItemEnd=None，由 looper 自行接管循环
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(names[0])]];
        if (canResume && [names[0] isEqualToString:savedName]) {
            [item seekToTime:CMTimeMakeWithSeconds(savedTime, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
            CCVLog(@"resume: 恢复断点 模块%lu %@ @%.1fs", (unsigned long)self.moduleIndex, savedName, savedTime);
        }
        self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    } else {
        // 随机/顺序多素材：不用 AVQueuePlayer 队列自动前进（实测 item 播完队列不消费，
        // 导致卡住），改为手动逐条播放：每次只放当前一条，播完通知里主动换下一条
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        // 断点续播：把上次暂停的素材排到队首，后续素材按原顺序接在其后
        NSMutableArray *order = [NSMutableArray arrayWithArray:names];
        if (canResume) {
            NSUInteger idx = [order indexOfObject:savedName];
            if (idx != NSNotFound && idx > 0) {
                NSArray *head = [order subarrayWithRange:NSMakeRange(0, idx)];
                [order removeObjectsInRange:NSMakeRange(0, idx)];
                [order addObjectsFromArray:head];
            }
            CCVLog(@"resume: 恢复断点 模块%lu %@ @%.1fs（%lu 条列表）", (unsigned long)self.moduleIndex, savedName, savedTime, (unsigned long)order.count);
        }
        self.playNames = order;
        self.playIndex = 0;
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(order[0])]];
        if (canResume && [order[0] isEqualToString:savedName]) {
            [item seekToTime:CMTimeMakeWithSeconds(savedTime, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
        }
        [self.player insertItem:item afterItem:nil]; // removeAllItems 后队列为空，只放当前一条
        // 监听播放结束，播完主动接下一条
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(playerItemDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    }
    [self applyDisplayMode];
    if (self.wantsPlayback) [self.player play];
}

// 多素材播放：播完主动替换成下一条（不依赖 AVQueuePlayer 的队列前进）
- (void)playerItemDidEnd:(NSNotification *)n {
    if (CCVPlayModeForModule(self.moduleIndex) == 0) return; // 固定模式由 looper 接管
    if (n.object != self.player.currentItem) return;         // 忽略别的 VC/已被替换的 item 的通知
    NSArray<NSString *> *names = self.playNames;
    if (names.count < 2) return;
    NSUInteger next = self.playIndex + 1;
    if (next >= names.count) {
        next = 0;
        if (CCVPlayModeForModule(self.moduleIndex) == 1) {
            // 随机模式每轮重新洗牌
            NSMutableArray *shuffled = [names mutableCopy];
            for (NSInteger i = shuffled.count - 1; i > 0; i--) {
                NSInteger j = arc4random_uniform((uint32_t)(i + 1));
                [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
            }
            names = shuffled;
            self.playNames = names;
        }
    }
    self.playIndex = next;
    NSString *name = names[next];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:CCVVideoPathForName(name)]];
    // 只使用 AVQueuePlayer 官方支持的队列操作：清掉播完的，插入下一条
    [self.player removeAllItems];
    [self.player insertItem:item afterItem:nil];
    CCVLog(@"queue: 自动接播下一条 模块%lu %@（%lu/%lu）", (unsigned long)self.moduleIndex, name, (unsigned long)(next + 1), (unsigned long)names.count);
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
    [self.player play]; // AVPlayer 暂停后 play 自动从暂停位置继续
}

// 暂停时记录断点（素材名+秒数），VC 重建后也能恢复
- (void)saveResumePoint {
    AVPlayerItem *cur = self.player.currentItem;
    if (!cur || cur.status != AVPlayerItemStatusReadyToPlay) return;
    if (![cur.asset isKindOfClass:[AVURLAsset class]]) return;
    NSURL *url = ((AVURLAsset *)cur.asset).URL;
    double t = CMTimeGetSeconds(cur.currentTime);
    if (!url || !(t > 0.3) || !isfinite(t)) return; // 开头位置不用记
    for (NSString *n in [self currentVideoNames]) {
        if ([[NSURL fileURLWithPath:CCVVideoPathForName(n)] isEqual:url]) {
            ccv_saveResumePrefs(n, t, self.moduleIndex);
            CCVLog(@"resume: 记录断点 模块%lu %@ @%.1fs", (unsigned long)self.moduleIndex, n, t);
            return;
        }
    }
}

- (void)pausePlayback {
    self.wantsPlayback = NO;
    [self saveResumePoint];
    [self.player pause];
}

// ---------- 窗口挂载/卸载（关闭 CC 暂停、打开 CC 续播的可靠信号） ----------
- (void)ccvWindowDetached {
    [self pausePlayback];
}

- (void)ccvWindowAttached {
    [self playIfVisible];
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
