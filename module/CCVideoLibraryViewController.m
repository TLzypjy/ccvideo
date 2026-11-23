#import "CCVideoLibraryViewController.h"
#import "CCVideoPrefs.h"
#import <objc/runtime.h>

// 素材库 UI 完整照搬 lddgifbg 1.9.x 的 LDDMaterialPickerController：
// 双行导航标题 / 3 列零间距网格 / tag 911 白色卡片 / 编辑态 CABasicAnimation 抖动 /
// 行内改名 / 红钮删除 / 圆形选中点。数据层换成 CCVideo 的单个视频文件。

static NSString * const CCVCellID = @"m";
static const char kCCVDelKey = 0;
static const char kCCVNameKey = 0;

@interface CCVideoLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate, UITextFieldDelegate>
{
    UICollectionView *_cv;
    NSArray<NSString *> *_videos;
    BOOL _editMode;
    UILongPressGestureRecognizer *_editLP;
    UITextField *_activeField;
    NSString *_activeName;
    UICollectionViewCell *_activeCell;
    UILabel *_activeLabel;
    NSIndexPath *_activeIp;
    CGFloat _preKbdOY;
    UIControl *_modeMenu; // 播放模式自定义下拉浮层（含遮罩）
}
@end

@implementation CCVideoLibraryViewController

// ---------- 双行导航标题（上行"素材库 (N)"，下行用法小字） ----------
- (void)buildBarTitleView {
    UIView *tv = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 38)];
    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(0, 1, 280, 19)];
    [l1 setTag:990];
    [l1 setText:@"素材库"];
    [l1 setTextAlignment:NSTextAlignmentCenter];
    [l1 setFont:[UIFont systemFontOfSize:16.0]];
    [l1 setTextColor:[UIColor colorWithWhite:0.0 alpha:1.0]];
    [tv addSubview:l1];
    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(0, 21, 280, 13)];
    [l2 setText:@"长按改名/删除 · v0.1.27 · 随机/顺序独立列表"];
    [l2 setTextAlignment:NSTextAlignmentCenter];
    [l2 setFont:[UIFont systemFontOfSize:10.0]];
    [l2 setTextColor:[UIColor colorWithWhite:0.45 alpha:1.0]];
    [tv addSubview:l2];
    [[self navigationItem] setTitleView:tv];
}

- (void)setBarTitle:(NSString *)t {
    UIView *tv = [[self navigationItem] titleView];
    if (tv) {
        UILabel *l = (UILabel *)[tv viewWithTag:990];
        if (l) { [l setText:t]; return; }
    }
    [self setTitle:t];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    CCVLog(@"Library viewDidLoad v0.1.27（随机/顺序独立列表）；模块%lu 当前模式%ld 随机列表%lu 顺序列表%lu",
           (unsigned long)[self index], (long)CCVPlayModeForModule([self index]),
           (unsigned long)[CCVSelectedListForModule([self index], 1) count],
           (unsigned long)[CCVSelectedListForModule([self index], 2) count]);
    [self buildBarTitleView];
    [self.navigationItem setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:@"关闭"
        style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)]];
    [self setupRightButtons];
    [self.view setBackgroundColor:[UIColor colorWithWhite:0.94 alpha:1.0]];

    UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
    [flow setMinimumInteritemSpacing:0];
    [flow setMinimumLineSpacing:0];
    [flow setSectionInset:UIEdgeInsetsMake(14, 16, 70, 16)];
    CGFloat iw = ([UIScreen mainScreen].bounds.size.width - 32.0) / 3.0;
    [flow setItemSize:CGSizeMake(iw, (iw - 12.0) + 56.0)];

    _cv = [[UICollectionView alloc] initWithFrame:[self.view bounds] collectionViewLayout:flow];
    [_cv setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [_cv setBackgroundColor:[UIColor clearColor]];
    [_cv setDataSource:self];
    [_cv setDelegate:self];
    [_cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:CCVCellID];
    _editLP = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressTapped:)];
    [_editLP setMinimumPressDuration:0.4];
    [_cv addGestureRecognizer:_editLP];
    [self.view addSubview:_cv];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbdWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbdDidShow:)
        name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbdWillHide:)
        name:UIKeyboardWillHideNotification object:nil];

    CCVEnsureDirs();
    [self reloadVideos];
}

// 布局完成后强制 3 列（任何宽度下 item 精确 = 行宽/3）
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_cv) return;
    UICollectionViewFlowLayout *fl = (UICollectionViewFlowLayout *)[_cv collectionViewLayout];
    CGFloat want = ([_cv bounds].size.width - 32.0) / 3.0;
    if (want > 1.0 && fabs([fl itemSize].width - want) > 1.0) {
        [fl setItemSize:CGSizeMake(want, (want - 12.0) + 56.0)];
        [fl setMinimumInteritemSpacing:0];
        [fl setSectionInset:UIEdgeInsetsMake(14, 16, 70, 16)];
        [fl invalidateLayout];
    }
}

- (void)reloadVideos {
    _videos = CCVVideoFileNames();
    NSArray *raw = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:CCVVideoDir error:nil];
    CCVLog(@"library: reloadVideos 显示=%lu 目录原始=%lu (%@)",
           (unsigned long)[_videos count], (unsigned long)[raw count], raw);
    [self setBarTitle:[NSString stringWithFormat:@"素材库 (%lu)", (unsigned long)[_videos count]]];
    [_cv reloadData];
}

// ---------- 顶栏 ----------
- (void)closeTapped {
    UINavigationController *nc = [self navigationController];
    if (nc && [[nc viewControllers] count] > 1) {
        [nc popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

// ---------- 长按进编辑态 + 抖动 ----------
- (void)longPressTapped:(id)lp {
    if ([lp state] != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:_cv];
    NSIndexPath *ip = [_cv indexPathForItemAtPoint:p];
    if (!ip) return;
    [self enterEditing];
}

- (void)enterEditing {
    if (_editMode) return;
    _editMode = YES;
    [self setBarTitle:@"长按完成退出"];
    [self.navigationItem setRightBarButtonItems:@[[[UIBarButtonItem alloc] initWithTitle:@"完成"
        style:UIBarButtonItemStylePlain target:self action:@selector(exitEditing)]]];
    [_cv reloadData];
    [_editLP setEnabled:NO]; // 防长按抢占删除钮点击
    [self startJiggling];
}

- (void)exitEditing {
    if (!_editMode) return;
    if (_activeField) [_activeField resignFirstResponder];
    [self stopJiggling];
    _editMode = NO;
    [_editLP setEnabled:YES];
    [self setupRightButtons];
    [self setBarTitle:[NSString stringWithFormat:@"素材库 (%lu)", (unsigned long)[_videos count]]];
    [_cv reloadData];
}

// 抖动动画挂在卡片(tag 911) layer 上，删除钮是卡片子视图 -> 随卡片一起抖
- (void)jiggleCard:(UIView *)card {
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
    [anim setFromValue:[NSNumber numberWithDouble:-0.03]];
    [anim setToValue:[NSNumber numberWithDouble:0.03]];
    [anim setDuration:0.12];
    [anim setAutoreverses:YES];
    [anim setRepeatCount:100000];
    [[card layer] addAnimation:anim forKey:@"lddJiggle"];
}

- (void)startJiggling {
    for (UICollectionViewCell *c in [_cv visibleCells]) {
        UIView *card = [c viewWithTag:911];
        if (card) [self jiggleCard:card];
    }
}

- (void)stopJiggling {
    for (UICollectionViewCell *c in [_cv visibleCells]) {
        UIView *card = [c viewWithTag:911];
        if (card) [[card layer] removeAnimationForKey:@"lddJiggle"];
    }
}

// ---------- 数据 ----------
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)[_videos count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    NSInteger row = [ip row];
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:CCVCellID forIndexPath:ip];
    for (UIView *v in [[[cell contentView] subviews] copy]) [v removeFromSuperview];
    if (!_videos || row >= (NSInteger)[_videos count]) return cell;

    NSString *name = [_videos objectAtIndex:(NSUInteger)row];
    NSString *base = [name stringByDeletingPathExtension];
    double w = ([UIScreen mainScreen].bounds.size.width - 32.0) / 3.0;
    double cardW = w - 12.0;
    double imgH = cardW;

    // 白色圆角卡片（不裁切，让删除钮伸出右上角；图片圆角由 iv 自己裁切）
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(6, 0, cardW, imgH)];
    [card setBackgroundColor:[UIColor whiteColor]];
    [card setTag:911];
    [[card layer] setCornerRadius:14.0];

    UIImage *thumb = nil;
    NSString *thumbPath = CCVThumbPathForVideoName(name);
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
        thumb = [UIImage imageWithContentsOfFile:thumbPath];
    } else {
        [self generateThumbnailFor:name]; // 异步生成后 reload
    }
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, cardW, imgH)];
    [iv setImage:thumb];
    [iv setContentMode:UIViewContentModeScaleAspectFill];
    [iv setBackgroundColor:[UIColor colorWithWhite:0.85 alpha:1.0]];
    [[iv layer] setCornerRadius:14.0];
    [[iv layer] setMasksToBounds:YES];
    [card addSubview:iv];

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(6, 6, 34, 16)];
    [badge setText:@"视频"];
    [badge setFont:[UIFont systemFontOfSize:9.0]];
    [badge setTextAlignment:NSTextAlignmentCenter];
    [badge setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.55]];
    [badge setTextColor:[UIColor whiteColor]];
    [[badge layer] setCornerRadius:8.0];
    [[badge layer] setMasksToBounds:YES];
    [card addSubview:badge];

    // 左下角播放标志
    UIView *vb = [[UIView alloc] initWithFrame:CGRectMake(6, imgH - 30, 24, 24)];
    [vb setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.45]];
    [[vb layer] setCornerRadius:12.0];
    [[vb layer] setMasksToBounds:YES];
    UILabel *pl = [[UILabel alloc] initWithFrame:CGRectMake(0, -1, 24, 24)];
    [pl setText:@"▶"];
    [pl setFont:[UIFont systemFontOfSize:11.0]];
    [pl setTextAlignment:NSTextAlignmentCenter];
    [pl setTextColor:[UIColor whiteColor]];
    [vb addSubview:pl];
    [card addSubview:vb];

    // 编辑态红色删除钮（随卡片抖动）
    if (_editMode) {
        UIButton *delv = [[UIButton alloc] initWithFrame:CGRectMake(cardW - 14, -12, 26, 26)];
        [delv setBackgroundColor:[UIColor redColor]];
        [[delv layer] setCornerRadius:13.0];
        [[delv layer] setMasksToBounds:YES];
        [delv setTitle:@"-" forState:UIControlStateNormal];
        [delv setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [delv.titleLabel setFont:[UIFont boldSystemFontOfSize:19.0]];
        [delv addTarget:self action:@selector(delBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:delv];
        objc_setAssociatedObject(delv, &kCCVDelKey, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [[cell contentView] addSubview:card];

    // 名字胶囊
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(10, imgH + 7, cardW - 8, 22)];
    [pill setBackgroundColor:[UIColor colorWithWhite:0.62 alpha:0.85]];
    [[pill layer] setCornerRadius:11.0];
    [[pill layer] setMasksToBounds:YES];
    UILabel *plb = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cardW - 8, 22)];
    [plb setText:base];
    [plb setFont:[UIFont systemFontOfSize:11.0]];
    [plb setTextAlignment:NSTextAlignmentCenter];
    [plb setTextColor:[UIColor whiteColor]];
    [plb setLineBreakMode:(NSLineBreakMode)5]; // NSLineBreakByTruncatingMiddle
    [plb setTag:922];
    [pill addSubview:plb];
    [[cell contentView] addSubview:pill];
    UITapGestureRecognizer *ng = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nameTapped:)];
    [pill addGestureRecognizer:ng];
    objc_setAssociatedObject(ng, &kCCVNameKey, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 选中圆点（编辑态隐藏）：固定模式=蓝点单选，随机/顺序=绿点多选（再点一次取消）
    if (!_editMode) {
        NSInteger mode = CCVPlayModeForModule([self index]);
        BOOL on = (mode == 0) ? [CCVSelectedVideoNameForModule([self index]) isEqualToString:name]
                              : CCVListContainsVideo(name, [self index], mode);
        UIColor *onColor = (mode == 0) ? [UIColor systemBlueColor] : [UIColor systemGreenColor];
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(6 + cardW / 2 - 9, imgH + 33, 18, 18)];
        [[dot layer] setCornerRadius:9.0];
        [[dot layer] setMasksToBounds:YES];
        [dot setBackgroundColor:on ? onColor : [UIColor colorWithWhite:0.80 alpha:1.0]];
        [[cell contentView] addSubview:dot];
    }

    // 编辑态创建即抖（不依赖 reloadData 后 visibleCells 时机）
    if (_editMode) [self jiggleCard:card];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (_editMode) return;
    NSInteger row = [ip row];
    if (!_videos || row >= (NSInteger)[_videos count]) return;
    [self selectVideoNamed:[_videos objectAtIndex:(NSUInteger)row]];
}

- (NSUInteger)index {
    return self.moduleIndex == 0 ? 1 : self.moduleIndex;
}

- (void)selectVideoNamed:(NSString *)name {
    if (!name || _editMode) return;
    NSUInteger idx = [self index];
    NSInteger mode = CCVPlayModeForModule(idx);
    if (mode == 0) {
        // 固定：单选，覆盖旧值
        CCVSetSelectedVideo(name, idx);
    } else {
        // 随机/顺序：多选，加/删（按当前模式写入各自独立的列表）
        CCVToggleVideoInList(name, idx, mode);
    }
    CCVPostDarwin(CCVDarwinSettingsChanged);
    [_cv reloadData];
}

// ---------- 点名字：非编辑态=选中，编辑态=行内改名 ----------
- (void)nameTapped:(UITapGestureRecognizer *)g {
    NSString *name = objc_getAssociatedObject(g, &kCCVNameKey);
    if (!name) return;
    UIView *pill = [g view];
    UIView *contentV = [pill superview];
    UICollectionViewCell *cell = (UICollectionViewCell *)[contentV superview];
    if (!cell) return;
    if (!_editMode) { [self selectVideoNamed:name]; return; }
    [self beginRename:name inCell:cell atPill:pill];
}

- (void)beginRename:(NSString *)name inCell:(UICollectionViewCell *)cell atPill:(UIView *)pill {
    if (_activeField) [_activeField resignFirstResponder];
    UILabel *lab = (UILabel *)[pill viewWithTag:922];
    CGRect lf = [pill frame];
    if (lab) [lab setHidden:YES];
    _activeIp = [_cv indexPathForCell:cell];
    _preKbdOY = [_cv contentOffset].y;

    UITextField *tf = [[UITextField alloc] initWithFrame:lf];
    [tf setText:name];
    [tf setFont:[UIFont systemFontOfSize:11.0]];
    [tf setTextAlignment:NSTextAlignmentCenter];
    [tf setBorderStyle:UITextBorderStyleRoundedRect];
    [tf setReturnKeyType:UIReturnKeyDone];
    [tf setClearButtonMode:UITextFieldViewModeWhileEditing];
    [tf setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [tf setAutocorrectionType:UITextAutocorrectionTypeNo];
    [tf setDelegate:self];
    [tf setTag:955];
    [[cell contentView] addSubview:tf];
    _activeField = tf;
    _activeName = name;
    _activeCell = cell;
    _activeLabel = lab;
    [tf becomeFirstResponder];
}

// ---------- 键盘遮挡处理（照搬） ----------
- (CGFloat)kbdTargetOffsetForCell:(UIView *)cell kbH:(CGFloat)kbH {
    CGRect fr = [cell frame];
    CGRect cvb = [_cv bounds];
    UIEdgeInsets ins = [_cv contentInset];
    CGFloat want = fr.origin.y + fr.size.height + 46.0 - (cvb.size.height - kbH);
    CGFloat st = [_cv safeAreaInsets].top;
    if (want < -st) want = -st;
    CGFloat maxOff = [_cv contentSize].height + ins.bottom - cvb.size.height;
    if (maxOff < 0) maxOff = 0;
    if (want > maxOff) want = maxOff;
    return want;
}

- (CGFloat)clampOffsetY:(CGFloat)y {
    CGFloat minOff = -[_cv safeAreaInsets].top;
    CGFloat maxOff = [_cv contentSize].height - [_cv bounds].size.height;
    if (maxOff < minOff) maxOff = minOff;
    if (y < minOff) y = minOff;
    if (y > maxOff) y = maxOff;
    return y;
}

- (void)kbdWillShow:(NSNotification *)n {
    if (!_activeIp) return;
    CGFloat kbH = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    if (kbH <= 0 || !_activeCell) return;
    UIEdgeInsets ins = [_cv contentInset];
    ins.bottom = kbH + 8.0;
    [_cv setContentInset:ins];
    CGPoint pt = [_cv contentOffset];
    pt.y = [self kbdTargetOffsetForCell:(UIView *)_activeCell kbH:kbH];
    [_cv setContentOffset:pt animated:YES];
}

- (void)kbdDidShow:(NSNotification *)n {
    if (!_activeIp) return;
    CGFloat kbH = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    if (kbH <= 0 || !_activeCell) return;
    UIEdgeInsets ins = [_cv contentInset];
    ins.bottom = kbH + 8.0;
    [_cv setContentInset:ins];
    CGPoint pt = [_cv contentOffset];
    pt.y = [self kbdTargetOffsetForCell:(UIView *)_activeCell kbH:kbH];
    [_cv setContentOffset:pt animated:YES];
}

- (void)kbdWillHide:(NSNotification *)n {
    UIEdgeInsets ins = [_cv contentInset];
    ins.bottom = 0;
    [_cv setContentInset:ins];
    CGPoint rp = [_cv contentOffset];
    rp.y = [self clampOffsetY:_preKbdOY];
    [_cv setContentOffset:rp animated:NO];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)tf {
    if (tf != _activeField) return;
    NSString *old = _activeName;
    NSString *nn = [tf text];
    [tf removeFromSuperview];
    CGPoint rp = [_cv contentOffset];
    rp.y = [self clampOffsetY:_preKbdOY];
    [_cv setContentOffset:rp animated:YES];
    _activeField = nil;
    _activeName = nil;
    _activeCell = nil;
    _activeIp = nil;
    if (_activeLabel) { [_activeLabel setHidden:NO]; _activeLabel = nil; }
    if (old && nn && [nn length] > 0) [self doRename:old to:nn];
}

// ---------- 改名 / 删除 ----------
- (void)doRename:(NSString *)old to:(NSString *)newName {
    NSString *trimmed = [newName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@""];
    if (trimmed.length == 0) return;

    NSString *ext = [old pathExtension];
    NSString *newNameFull = [NSString stringWithFormat:@"%@.%@", trimmed, ext];
    if ([newNameFull isEqualToString:old]) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = CCVVideoPathForName(old);
    NSString *dst = [CCVVideoDir stringByAppendingPathComponent:newNameFull];
    if ([fm fileExistsAtPath:dst]) { [self showAlert:@"已存在同名素材" title:@"改名失败"]; return; }
    if (![fm moveItemAtPath:src toPath:dst error:nil]) { [self showAlert:@"文件移动失败" title:@"改名失败"]; return; }

    NSString *oldThumb = CCVThumbPathForVideoName(old);
    NSString *newThumb = CCVThumbPathForVideoName(newNameFull);
    if ([fm fileExistsAtPath:oldThumb]) [fm moveItemAtPath:oldThumb toPath:newThumb error:nil];
    if ([CCVSelectedVideoNameForModule([self index]) isEqualToString:old]) {
        CCVSetSelectedVideo(newNameFull, [self index]);
        [CCVPrefs() synchronize];
        CCVPostDarwin(CCVDarwinSettingsChanged);
    }
    [self reloadVideos];
}

- (void)delBtnTapped:(UIButton *)btn {
    NSString *name = objc_getAssociatedObject(btn, &kCCVDelKey);
    if (name) [self confirmDelete:name];
}

- (void)confirmDelete:(NSString *)name {
    NSString *base = [name stringByDeletingPathExtension];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:base
        message:@"删除该视频素材？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:CCVVideoPathForName(name) error:nil];
        [fm removeItemAtPath:CCVThumbPathForVideoName(name) error:nil];
        if ([CCVSelectedVideoNameForModule([self index]) isEqualToString:name]) {
            CCVSetSelectedVideo(@"", [self index]);
            [CCVPrefs() synchronize];
            CCVPostDarwin(CCVDarwinSettingsChanged);
        }
        [self reloadVideos];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlert:(NSString *)msg title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// ---------- 播放模式：固定（单选蓝点）/ 随机、顺序（多选绿点） ----------
- (void)setupRightButtons {
    if (_editMode) {
        [self.navigationItem setRightBarButtonItems:@[[[UIBarButtonItem alloc] initWithTitle:@"完成"
            style:UIBarButtonItemStylePlain target:self action:@selector(exitEditing)]]];
        return;
    }
    UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithTitle:@"导入"
        style:UIBarButtonItemStylePlain target:self action:@selector(importTapped)];
    NSInteger mode = CCVPlayModeForModule([self index]);
    NSString *label = @[@"固定▾", @"随机▾", @"顺序▾"][mode];
    UIBarButtonItem *modeItem = [[UIBarButtonItem alloc] initWithTitle:label
        style:UIBarButtonItemStylePlain target:self action:@selector(modeButtonTapped:)];
    // 右侧从左到右显示顺序 = 数组从后到前；让"导入"在最右，"模式"挨着它左边
    [self.navigationItem setRightBarButtonItems:@[importItem, modeItem]];
}

// 自定义下拉浮层：圆角毛玻璃卡片 + 三行选项 + 选中打勾，盖在内容上方（非系统弹窗）
- (void)dismissModeMenu {
    if (!_modeMenu) return;
    [UIView animateWithDuration:0.12 animations:^{ [_modeMenu setAlpha:0.0]; }
        completion:^(BOOL finished) { [_modeMenu removeFromSuperview]; }];
    _modeMenu = nil;
}

- (void)modeRowTapped:(UIButton *)btn {
    NSInteger mode = btn.tag;
    [self dismissModeMenu];
    [self setPlayMode:mode];
}

- (void)modeButtonTapped:(UIBarButtonItem *)sender {
    if (_modeMenu) { [self dismissModeMenu]; return; }

    UIView *anchor = nil;
    @try { // 拿到按钮视图用于定位浮层（KVC 私有只读，取不到就走右侧兜底）
        id barView = [sender valueForKey:@"view"];
        if ([barView isKindOfClass:[UIView class]]) anchor = barView;
    } @catch (NSException *e) { anchor = nil; }

    NSInteger cur = CCVPlayModeForModule([self index]);

    // 挂到 window：坐标系即屏幕，不会被导航栏裁剪，也不会被 self.view 的偏移顶到状态栏
    UIView *hostView = [self view].window ?: [self view];
    UIControl *mask = [[UIControl alloc] initWithFrame:[hostView bounds]];
    [mask setBackgroundColor:[UIColor clearColor]];
    [mask addTarget:self action:@selector(dismissModeMenu) forControlEvents:UIControlEventTouchUpInside];

    CGFloat menuW = 124.0;
    CGFloat rowH  = 40.0;
    CGFloat menuH = rowH * 3;
    // 锚在"模式"按钮正下方、右边缘与按钮对齐；拿不到按钮就落在导航栏下方右侧
    CGFloat menuX = CGRectGetWidth([mask bounds]) - menuW - 12.0;
    CGFloat menuY = 104.0;
    if (anchor) {
        CGRect ar = [anchor convertRect:[anchor bounds] toView:hostView];
        if (ar.size.width > 0) {
            menuX = MIN(MAX(CGRectGetMaxX(ar) - menuW, 8.0), CGRectGetWidth([mask bounds]) - menuW - 8.0);
            menuY = CGRectGetMaxY(ar) + 8.0;
        }
    }
    CCVLog(@"modeMenu: 弹出 x=%.0f y=%.0f w=%.0f h=%.0f anchor=%@ host=%@",
           (double)menuX, (double)menuY, (double)menuW, (double)menuH,
           anchor ? @"有" : @"无", [self view].window ? @"window" : @"view");
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(menuX, menuY, menuW, menuH)];
    [menu setBackgroundColor:[UIColor clearColor]];
    [[menu layer] setCornerRadius:12.0];
    [[menu layer] setShadowColor:[[UIColor blackColor] CGColor]];
    [[menu layer] setShadowOpacity:0.20];
    [[menu layer] setShadowRadius:14.0];
    [[menu layer] setShadowOffset:CGSizeMake(0, 4)];
    // 真·毛玻璃背景（先加，行按钮后加盖在其上）；圆角自裁，menu 本身不裁以免阴影被切
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    [blur setFrame:[menu bounds]];
    [[blur layer] setCornerRadius:12.0];
    [[blur layer] setMasksToBounds:YES];
    [blur setUserInteractionEnabled:NO];
    [menu addSubview:blur];

    // 行顺序按图：固定/顺序/随机；tag 用真实 mode（0固定 1随机 2顺序），别直接用行号
    NSArray *titles = @[@"固定显示", @"顺序显示", @"随机显示"];
    NSArray *rowModes = @[@0, @2, @1];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        [row setFrame:CGRectMake(0, i * rowH, menuW, rowH)];
        [row setTag:[rowModes[i] integerValue]];
        [row setBackgroundColor:[UIColor clearColor]];
        [row setTitle:titles[i] forState:UIControlStateNormal];
        [row setTitleColor:[UIColor colorWithWhite:0.12 alpha:1.0] forState:UIControlStateNormal];
        [[row titleLabel] setFont:[UIFont systemFontOfSize:15.0]];
        [row setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
        [row setTitleEdgeInsets:UIEdgeInsetsMake(0, 16, 0, 0)];
        [row addTarget:self action:@selector(modeRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:row];

        if ([rowModes[i] integerValue] == cur) { // 选中项右侧打勾
            UILabel *check = [[UILabel alloc] initWithFrame:CGRectMake(menuW - 34, i * rowH + 13, 22, 20)];
            [check setText:@"✓"];
            [check setFont:[UIFont boldSystemFontOfSize:15.0]];
            [check setTextColor:[UIColor systemBlueColor]];
            [check setUserInteractionEnabled:NO];
            [menu addSubview:check];
        }
        if (i < 2) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(14, (i + 1) * rowH - 0.5, menuW - 28, 0.5)];
            [sep setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.10]];
            [sep setUserInteractionEnabled:NO];
            [menu addSubview:sep];
        }
    }

    [mask addSubview:menu];
    [hostView addSubview:mask];
    _modeMenu = mask;
    [menu setTransform:CGAffineTransformMakeScale(0.88, 0.88)];
    [menu setAlpha:0.0];
    [UIView animateWithDuration:0.16 animations:^{
        [menu setTransform:CGAffineTransformIdentity];
        [menu setAlpha:1.0];
    }];
}

- (void)setPlayMode:(NSInteger)mode {
    NSUInteger idx = [self index];
    NSInteger old = CCVPlayModeForModule(idx);
    if (old == mode) return;
    CCVLog(@"playmode: 模块%lu %ld -> %ld", (unsigned long)idx, (long)old, (long)mode);
    CCVSetPlayMode(mode, idx);
    // 三种模式的选中数据各自独立存储：切换时不做任何迁移，
    // 否则顺序里选的素材会被带到随机（反之亦然）。各模式进去看到的是自己的选择。
    CCVPostDarwin(CCVDarwinSettingsChanged);
    [self setupRightButtons];
    [self reloadVideos];
}

// ---------- 导入（PHPicker，免相册权限） ----------
- (void)importTapped {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 0;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    CCVLog(@"import: picker 完成，选中 %lu 个", (unsigned long)[results count]);
    [picker dismissViewControllerAnimated:YES completion:nil];
    if ([results count] == 0) return;

    // 关键：相册视频加载可能耗时十几秒（iCloud 回源/大文件），这期间用户很可能已经
    // 返回设置页甚至切换模块，素材库 VC 被 pop 释放。若这里用 weakSelf，回调时 self
    // 已变 nil，[nil save...] 静默返回 NO —— 视频明明加载成功却"导入失败"。
    // 因此 block 内强持有 self 直到导入完成，确保保存逻辑一定执行。
    typeof(self) mySelf = self;
    __block int imported = 0;
    int pending = 0;
    dispatch_group_t group = dispatch_group_create();
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        CCVLog(@"import: types=%@ suggested=%@", provider.registeredTypeIdentifiers, provider.suggestedName ?: @"nil");
        // 找可加载的视频类型：优先 public.movie，否则在注册类型里兜底找 movie/mpeg-4/quicktime
        NSString *type = nil;
        if ([provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
            type = @"public.movie";
        } else {
            for (NSString *t in provider.registeredTypeIdentifiers) {
                if ([t containsString:@"movie"] || [t containsString:@"mpeg-4"] || [t containsString:@"quicktime"]) { type = t; break; }
            }
        }
        if (!type) { CCVLog(@"import: 跳过（无视频类型）"); continue; }
        dispatch_group_enter(group);
        pending++;
        [provider loadFileRepresentationForTypeIdentifier:type
            completionHandler:^(NSURL *url, NSError *error) {
            CCVLog(@"import: load 回调 url=%@ err=%@", url.path ?: @"nil", error);
            if (url && [mySelf saveImportedVideoFromURL:url suggestedName:provider.suggestedName]) {
                imported++;
            } else {
                CCVLog(@"import: 保存失败");
            }
            dispatch_group_leave(group);
        }];
    }
    if (pending == 0) {
        CCVLog(@"import: 没有可加载的视频类型");
        [self showAlert:@"没有可导入的视频" title:@"导入完成"];
        return;
    }
    __block BOOL done = NO;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        done = YES;
        [mySelf reloadVideos];
        CCVLog(@"import: 完成 imported=%d", imported);
        // 页面已被关掉时只提示到日志，避免往已销毁页面 present 弹窗
        if (mySelf.view.window && mySelf.navigationController) {
            [mySelf showAlert:(imported > 0 ? [NSString stringWithFormat:@"已导入 %d 个视频到素材库", imported] : @"没有可导入的视频")
                        title:@"导入完成"];
        } else {
            CCVLog(@"import: 页面已关闭，跳过弹窗提示");
        }
    });
    // 兜底：个别视频（iCloud 未下载等）load 回调可能迟迟不来，30 秒后强制刷新界面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!done) {
            CCVLog(@"import: 30s 超时兜底 reload");
            [mySelf reloadVideos];
        }
    });
}

- (BOOL)saveImportedVideoFromURL:(NSURL *)tmpURL suggestedName:(NSString *)suggestedName {
    NSFileManager *fm = [NSFileManager defaultManager];
    CCVEnsureDirs();
    NSString *ext = tmpURL.pathExtension.length ? tmpURL.pathExtension : @"mp4";
    NSString *base = suggestedName.length ? suggestedName : @"导入视频";
    NSCharacterSet *badChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    base = [[base componentsSeparatedByCharactersInSet:badChars] componentsJoinedByString:@""];

    NSString *dest = nil;
    for (int i = 0; i < 100; i++) {
        NSString *candidate = (i == 0) ? [NSString stringWithFormat:@"%@.%@", base, ext]
                                       : [NSString stringWithFormat:@"%@ (%d).%@", base, i, ext];
        if (![fm fileExistsAtPath:[CCVVideoDir stringByAppendingPathComponent:candidate]]) {
            dest = [CCVVideoDir stringByAppendingPathComponent:candidate];
            break;
        }
    }
    if (!dest) { CCVLog(@"import: 试了 100 个名字都重名，放弃"); return NO; }
    NSError *cpErr = nil;
    if (![fm copyItemAtPath:tmpURL.path toPath:dest error:&cpErr]) {
        CCVLog(@"import: 拷贝失败 %@ -> %@ err=%@", tmpURL.path, dest, cpErr);
        return NO;
    }
    CCVLog(@"import: 已保存到 %@", dest);

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:dest] options:nil];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    [gen setAppliesPreferredTrackTransform:YES];
    [gen setMaximumSize:CGSizeMake(360, 360)];
    CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.3, 600) actualTime:nil error:nil];
    if (img) {
        UIImage *thumb = [UIImage imageWithCGImage:img];
        CGImageRelease(img);
        [UIImagePNGRepresentation(thumb) writeToFile:CCVThumbPathForVideoName(dest.lastPathComponent) atomically:YES];
    }
    return YES;
}

- (void)generateThumbnailFor:(NSString *)name {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSString *path = CCVVideoPathForName(name);
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        [gen setAppliesPreferredTrackTransform:YES];
        [gen setMaximumSize:CGSizeMake(360, 360)];
        CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.3, 600) actualTime:nil error:nil];
        if (img) {
            UIImage *thumb = [UIImage imageWithCGImage:img];
            CGImageRelease(img);
            [UIImagePNGRepresentation(thumb) writeToFile:CCVThumbPathForVideoName(name) atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{ [_cv reloadData]; });
        }
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
