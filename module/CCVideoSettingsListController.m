#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"

// ---------- 自定义卡片 cell：显示模式（卡片内只有分段按钮，标题/说明由组头/组脚显示在卡片外） ----------
@interface CCVDisplayModeCell : PSTableCell
@property (nonatomic, strong) UISegmentedControl *segment;
+ (CGFloat)preferredHeight;
@end

@implementation CCVDisplayModeCell

+ (CGFloat)preferredHeight {
    return 56; // 与滑杆行相近的卡片高度
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.backgroundView = nil;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        // 确保触摸链畅通（基类可能对某些 cell 类型关闭 contentView 交互）
        self.userInteractionEnabled = YES;
        self.contentView.userInteractionEnabled = YES;

        // 卡片背景（跟随深浅色）
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.11 alpha:1.0]
                : [UIColor whiteColor];
        }];
        card.layer.cornerRadius = 22;
        self.backgroundView = card;

        _segment = [[UISegmentedControl alloc] initWithItems:@[@"裁切填满", @"完整适应", @"拉伸填满"]];
        _segment.selectedSegmentIndex = CCVDisplayMode();
        _segment.enabled = YES;
        if (specifier.target) {
            [_segment addTarget:specifier.target action:@selector(displayModeChanged:) forControlEvents:UIControlEventValueChanged];
        }
        [self.contentView addSubview:_segment];

        // 隐藏基类按 specifier name 画的行标题（否则"显示模式"会叠在分段按钮上）
        self.textLabel.text = @"";
        self.textLabel.hidden = YES;
        if (self.detailTextLabel) self.detailTextLabel.hidden = YES;
    }
    return self;
}

// 强制把分段区域的触摸交给 UISegmentedControl（防止基类/表格截走导致点不了）
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint local = [self convertPoint:point toView:self.segment];
    if (self.segment && ![self.segment isHidden] && [self.segment pointInside:local withEvent:event]) {
        return self.segment;
    }
    return [super hitTest:point withEvent:event];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (_segment) _segment.selectedSegmentIndex = CCVDisplayMode();
    self.textLabel.text = @"";
    self.textLabel.hidden = YES;
    if (self.detailTextLabel) self.detailTextLabel.hidden = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.segment.frame = CGRectMake(20, (h - 32) / 2, w - 40, 32);
}

@end

// ---------- 统一行 cell：模块行（黑字+箭头+左滑删除）与创建模块（蓝字）共用一个类 ----------
// 为什么统一：PSListController 复用 cell 时（1) 基类的 specifier 属性不保证刷新，
// (2) 不同 cellClass 可能共用复用池导致类串位（模块行拿到创建 cell → 点了变创建）。
// 统一类 + 自己保存 specifier（ccvSpec）+ 行为由 specifier 属性决定，彻底杜绝串位。
// 另外：卡片必须不透明、删除按钮默认隐藏——否则按钮会透过半透明卡片"常显"。
@interface CCVRowCell : PSTableCell <UIGestureRecognizerDelegate>
@property (nonatomic, strong) PSSpecifier *ccvSpec;  // 自己保存（不依赖基类只读 specifier）
@property (nonatomic, assign) BOOL isCreate;
@property (nonatomic, strong) UIView *cardWrap;
@property (nonatomic, strong) UILabel *rowTitle;
@property (nonatomic, strong) UILabel *chevron;
@property (nonatomic, strong) UIControl *tapZone;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, assign) CGFloat dragBase;
@property (nonatomic, assign) BOOL swipeOpen;
@end

@implementation CCVRowCell

static const CGFloat CCVSwipeWidth = 76.0;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier]) {
        self.ccvSpec = specifier;
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = YES;
        self.contentView.userInteractionEnabled = YES;

        // 隐藏基类按 specifier name 画的行标题（否则与我们的标题叠成大字）
        self.textLabel.text = @"";
        self.textLabel.hidden = YES;
        if (self.detailTextLabel) self.detailTextLabel.hidden = YES;

        // 红色删除按钮（垫在卡片下面，左滑露出；默认隐藏防透出）
        _deleteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _deleteBtn.backgroundColor = [UIColor systemRedColor];
        _deleteBtn.layer.cornerRadius = 22;
        [_deleteBtn setTitle:@"删除" forState:UIControlStateNormal];
        [_deleteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _deleteBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        _deleteBtn.hidden = YES;
        [_deleteBtn addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_deleteBtn];

        // 卡片容器（整体平移）
        _cardWrap = [[UIView alloc] init];
        _cardWrap.backgroundColor = [UIColor clearColor];
        _cardWrap.userInteractionEnabled = NO;
        [self.contentView addSubview:_cardWrap];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.11 alpha:1.0]
                : [UIColor whiteColor]; // 不透明：底下的删除按钮不能透出来
        }];
        card.layer.cornerRadius = 22;
        card.userInteractionEnabled = NO;
        [_cardWrap addSubview:card];

        _rowTitle = [[UILabel alloc] init];
        _rowTitle.font = [UIFont systemFontOfSize:12];
        _rowTitle.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1.0];
        }];
        _rowTitle.userInteractionEnabled = NO;
        [_cardWrap addSubview:_rowTitle];

        _chevron = [[UILabel alloc] init];
        _chevron.text = @"›";
        _chevron.font = [UIFont boldSystemFontOfSize:14];
        _chevron.textAlignment = NSTextAlignmentCenter;
        _chevron.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.5 alpha:1.0]
                : [UIColor colorWithWhite:0.75 alpha:1.0];
        }];
        _chevron.userInteractionEnabled = NO;
        [_cardWrap addSubview:_chevron];

        // 全尺寸透明触摸区（hitTest 强制转发到这里；左滑手势也挂在它上面）
        _tapZone = [[UIControl alloc] init];
        _tapZone.backgroundColor = [UIColor clearColor];
        [_tapZone addTarget:self action:@selector(rowTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_tapZone];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [_tapZone addGestureRecognizer:pan];

        [self applySpecifierStyle];
    }
    return self;
}

// 按 specifier 属性套样式（创建行蓝字无箭头无滑动；模块行黑字带箭头可滑动）
- (void)applySpecifierStyle {
    PSSpecifier *spec = self.ccvSpec;
    self.isCreate = [[spec propertyForKey:@"isCreate"] boolValue];
    self.rowTitle.text = spec.name;
    if (self.isCreate) {
        self.rowTitle.textColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        self.chevron.hidden = YES;
        self.deleteBtn.hidden = YES;
    } else {
        self.rowTitle.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1.0];
        }];
        self.chevron.hidden = NO;
        self.deleteBtn.hidden = !self.swipeOpen; // 未滑动时绝不显示
    }
}

- (void)closeSwipeAnimated:(BOOL)animated {
    self.swipeOpen = NO;
    void (^block)(void) = ^{ self.cardWrap.transform = CGAffineTransformIdentity; };
    if (animated) [UIView animateWithDuration:0.2 animations:block];
    else block();
    if (!self.isCreate) self.deleteBtn.hidden = YES;
}

// 与表格竖向滚动并行识别：横向滑动归我们，竖向滚动归表格
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithOtherGesture:(UIGestureRecognizer *)other {
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    if (self.isCreate) return; // 创建行不可滑动删除
    CGPoint t = [p translationInView:self];
    if (p.state == UIGestureRecognizerStateBegan) {
        self.dragBase = self.swipeOpen ? -CCVSwipeWidth : 0;
    } else if (p.state == UIGestureRecognizerStateChanged) {
        if (fabs(t.x) <= fabs(t.y)) return; // 竖向交给表格滚动
        CGFloat x = self.dragBase + t.x;
        if (x > 0) x = 0;
        if (x < -CCVSwipeWidth) x = -CCVSwipeWidth;
        self.deleteBtn.hidden = NO; // 一开始滑就露出按钮（在卡片底下，未滑出部分被不透明卡片盖住）
        self.cardWrap.transform = CGAffineTransformMakeTranslation(x, 0);
    } else if (p.state == UIGestureRecognizerStateEnded || p.state == UIGestureRecognizerStateCancelled) {
        if (fabs(t.x) <= fabs(t.y)) return;
        CGPoint v = [p velocityInView:self];
        CGFloat x = self.dragBase + t.x;
        BOOL open = (x < -CCVSwipeWidth / 2.0) || (v.x < -400 && x < 0);
        self.swipeOpen = open;
        [UIView animateWithDuration:0.2 animations:^{
            self.cardWrap.transform = CGAffineTransformMakeTranslation(open ? -CCVSwipeWidth : 0, 0);
        }];
        if (!open) self.deleteBtn.hidden = YES;
    }
}

- (void)rowTapped {
    if (!self.isCreate && self.swipeOpen) { // 展开态先收起
        [self closeSwipeAnimated:YES];
        return;
    }
    PSSpecifier *spec = self.ccvSpec;
    id target = [spec target];
    if (self.isCreate) {
        if ([target respondsToSelector:@selector(createModule:)]) {
            [target performSelector:@selector(createModule:) withObject:spec];
        }
    } else if ([spec propertyForKey:@"moduleIndex"]) {
        if ([target respondsToSelector:@selector(openModule:)]) {
            [target performSelector:@selector(openModule:) withObject:spec];
        }
    }
}

- (void)deleteTapped {
    PSSpecifier *spec = self.ccvSpec;
    id target = [spec target];
    if ([target respondsToSelector:@selector(deleteModule:)]) {
        [target performSelector:@selector(deleteModule:) withObject:spec];
    }
}

// 展开态：删除按钮区域的触摸给按钮；其余给触摸区
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isCreate && self.swipeOpen && self.deleteBtn &&
        [self.deleteBtn pointInside:[self convertPoint:point toView:self.deleteBtn] withEvent:event]) {
        return self.deleteBtn;
    }
    if (self.tapZone && [self.tapZone pointInside:[self convertPoint:point toView:self.tapZone] withEvent:event]) {
        return self.tapZone;
    }
    return [super hitTest:point withEvent:event];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.ccvSpec = specifier; // 关键：复用时自己刷新 specifier，不信基类
    [self closeSwipeAnimated:NO];
    [self applySpecifierStyle];
    self.textLabel.text = @"";
    self.textLabel.hidden = YES;
    if (self.detailTextLabel) self.detailTextLabel.hidden = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.deleteBtn.frame = CGRectMake(w - CCVSwipeWidth, 0, CCVSwipeWidth, h);
    self.cardWrap.frame = CGRectMake(0, 0, w, h);
    UIView *card = self.cardWrap.subviews.firstObject;
    card.frame = CGRectMake(0, 0, w, h);
    self.rowTitle.frame = CGRectMake(20, (h - 16) / 2, w - 60, 16);
    self.chevron.frame = CGRectMake(w - 34, (h - 18) / 2, 24, 18);
    self.tapZone.frame = self.contentView.bounds;
}

@end

// ---------- 主页：模块列表 + 创建模块 ----------
@implementation CCVideoSettingsListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视频模块";
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSUInteger n = CCVMaxModules();
        CFPreferencesAppSynchronize((__bridge CFStringRef)CCVBundleID); // 拿到 SpringBoard 侧写入的最新诊断

        // 小分类：模块行 + 创建模块紧挨着（同一个组）
        PSSpecifier *g0 = [PSSpecifier preferenceSpecifierNamed:@""
                target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        NSMutableString *footer = [NSMutableString stringWithFormat:
            @"点击模块名可选择素材，左滑模块行可删除该模块。已创建 %lu / 8 个，创建/删除的模块在下次注销后同步到控制中心。",
            (unsigned long)n];
        NSString *syncErr = [CCVPrefs() stringForKey:@"LastSyncError"];
        if (syncErr.length) [footer appendFormat:@"\n⚠️ 模块文件同步失败：%@", syncErr];
        NSString *sbsDiag = [CCVPrefs() stringForKey:@"SBSDiag"];
        NSString *sbsErr = [CCVPrefs() stringForKey:@"SBSError"];
        if (sbsErr.length) [footer appendFormat:@"\n⚠️ SpringBoard助手：%@", sbsErr];
        if (sbsDiag.length) [footer appendFormat:@"\n[SBS] %@", sbsDiag];
        [g0 setProperty:footer forKey:@"footerText"];
        [specs addObject:g0];

        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *mod = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"视频模块%@", @(i)]
                    target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
            [mod setProperty:@(i) forKey:@"moduleIndex"];
            [mod setProperty:[CCVRowCell class] forKey:@"cellClass"]; // 统一行 cell（黑字+箭头+左滑删除）
            mod.buttonAction = @selector(openModule:);                // 兜底触发
            [specs addObject:mod];
        }

        if (n < CCV_MAX_MODULES) {
            PSSpecifier *create = [PSSpecifier preferenceSpecifierNamed:@"创建模块"
                    target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [create setProperty:@YES forKey:@"isCreate"];                  // 统一 cell 据此显示蓝字/禁滑动
            [create setProperty:[CCVRowCell class] forKey:@"cellClass"];   // 与模块行同一个类（复用不串位）
            create.buttonAction = @selector(createModule:);                // 兜底触发
            [specs addObject:create];
        }

        // 显示模式（全局）：标题作组头、说明作组脚，卡片内只有分段按钮
        PSSpecifier *gMode = [PSSpecifier preferenceSpecifierNamed:@"显示模式"
                target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [gMode setProperty:@"选择图片和视频的显示方式：\n· 裁切填满：保持比例、放大并裁剪超出部分\n· 完整适应：完整显示原图，空白区域用模糊背景补齐\n· 拉伸填满：忽略比例，直接铺满模块" forKey:@"footerText"];
        [specs addObject:gMode];
        PSSpecifier *dm = [PSSpecifier preferenceSpecifierNamed:@"显示模式"
                target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
        [dm setProperty:[CCVDisplayModeCell class] forKey:@"cellClass"];
        [specs addObject:dm];

        // 每个模块的尺寸设置内联在主页（模块 1 沿用原分组名，与旧版界面一致）
        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:(i == 1 ? @"模块尺寸" : [NSString stringWithFormat:@"视频模块%lu 尺寸", (unsigned long)i])
                    target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [specs addObject:g2];
            [specs addObject:[self sliderForModule:i named:@"X" selBase:@"PortraitW" key:CCVKeyForModule(CCVKeyPortraitW, i) other:CCVKeyForModule(CCVKeyLandscapeW, i)]];
            [specs addObject:[self sliderForModule:i named:@"Y" selBase:@"PortraitH" key:CCVKeyForModule(CCVKeyPortraitH, i) other:CCVKeyForModule(CCVKeyLandscapeH, i)]];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

// iOS16 上 specifierAtIndexPath 可能返回 nil 的兜底：按"组=节、其余 specifier=行"重放映射。
// 之前直接 specs[row] 是错的（组头占 specs 下标但不占表格行）——那会把模块 3~N 映射到错误的
// specifier 上（包括创建行的 specifier → 点模块变成创建模块）。
- (PSSpecifier *)ccvSpecifierAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *specs = [self specifiers];
    if (!specs || indexPath.section < 0 || indexPath.row < 0) return nil;
    NSInteger section = -1, row = 0;
    for (PSSpecifier *s in specs) {
        if (s.cellType == PSGroupCell) {
            section++;
            row = 0;
            continue;
        }
        if (section == indexPath.section && row == indexPath.row) return s;
        row++;
    }
    return nil;
}

// 模块行（黑字）点击 -> 直接进入该模块的素材库选素材
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self ccvSpecifierAtIndexPath:indexPath];
    if (spec && [spec propertyForKey:@"moduleIndex"]) {
        [self openModule:spec];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)openModule:(PSSpecifier *)spec {
    // 去重：素材库已经推到顶就不再推（tap 触摸区/didSelect/buttonAction 可能多路触发）
    if ([self.navigationController.topViewController isKindOfClass:[CCVideoLibraryViewController class]]) return;
    NSUInteger idx = [[spec propertyForKey:@"moduleIndex"] integerValue];
    if (idx == 0) idx = 1;
    CCVideoLibraryViewController *vc = [[CCVideoLibraryViewController alloc] init];
    vc.moduleIndex = idx;
    [self.navigationController pushViewController:vc animated:YES];
}

// 删除模块：第 idx 个删掉，后面模块的键值整体前移，MaxModules 减一。
// SpringBoard 侧收到通知会把多出来的 CCVideoN.bundle 从控制中心目录移除（下次注销后控制中心同步减少）。
- (void)deleteModule:(PSSpecifier *)spec {
    NSUInteger idx = [[spec propertyForKey:@"moduleIndex"] integerValue];
    NSUInteger n = CCVMaxModules();
    if (idx < 1 || idx > n || n <= 1) return;

    NSArray<NSString *> *keys = @[CCVKeySelectedVideo, CCVKeyPortraitW, CCVKeyPortraitH,
                                  CCVKeyLandscapeW, CCVKeyLandscapeH, CCVKeyAspectFill];
    NSUserDefaults *prefs = CCVPrefs();
    if (idx < n) {
        for (NSUInteger j = idx; j < n; j++) {
            for (NSString *base in keys) {
                id v = [prefs objectForKey:CCVKeyForModule(base, j + 1)];
                if (v == nil) {
                    [prefs removeObjectForKey:CCVKeyForModule(base, j)];
                } else {
                    [prefs setObject:v forKey:CCVKeyForModule(base, j)];
                }
            }
        }
    }
    for (NSString *base in keys) {
        [prefs removeObjectForKey:CCVKeyForModule(base, n)];
    }
    CCVSetMaxModules(n - 1);
    [prefs synchronize];
    [self syncBundlesAndRecordDiag]; // 同步移除多余 bundle 文件
    CCVPostDarwin(CCVDarwinSettingsChanged);

    _specifiers = nil;
    [self reloadSpecifiers];
}

// 创建模块：直接创建（无弹窗、不注销）。设置进程直接同步 bundle 文件（不走 SpringBoard 助手），
// 失败原因写进诊断键，页脚可见。
- (void)createModule:(PSSpecifier *)spec {
    NSUInteger n = CCVMaxModules();
    if (n >= CCV_MAX_MODULES) return;
    CCVSetMaxModules(n + 1);
    [self syncBundlesAndRecordDiag];
    CCVPostDarwin(CCVDarwinSettingsChanged);
    _specifiers = nil;
    [self reloadSpecifiers];
}

// 用设置进程同步 PendingBundles -> ControlCenter/Bundles（与 SpringBoard 同为 mobile 用户，目录已 0777）
- (void)syncBundlesAndRecordDiag {
    NSError *err = nil;
    CCVSyncPendingBundles(&err);
    [CCVPrefs() setObject:(err ? err.localizedDescription : @"") forKey:@"LastSyncError"];
    [CCVPrefs() synchronize];
}

// ---------- 每模块尺寸滑杆（与子页同一套 get/set） ----------
- (PSSpecifier *)sliderForModule:(NSUInteger)idx named:(NSString *)name selBase:(NSString *)selBase key:(NSString *)key other:(NSString *)other {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                    target:self
                                                      set:NSSelectorFromString([NSString stringWithFormat:@"set%@:forSpecifier:", selBase])
                                                       get:NSSelectorFromString([NSString stringWithFormat:@"get%@:", selBase])
                                                    detail:nil
                                                      cell:PSSliderCell
                                                       edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@1 forKey:@"min"];
    [s setProperty:@4 forKey:@"max"];
    [s setProperty:@2 forKey:@"defaultValue"];
    [s setProperty:@YES forKey:@"isSegmented"];
    [s setProperty:@3 forKey:@"segmentCount"];
    [s setProperty:@YES forKey:@"showValue"];
    [s setProperty:other forKey:@"otherKey"];
    // leftImage 必须是 UIImage 对象（传图片名字符串会让 UISlider setMinimumValueImage: 崩溃）
    NSString *dirIcon = [selBase isEqualToString:@"PortraitW"] ? @"X" : @"Y";
    UIImage *dirImg = nil;
    NSString *iconPath = [[NSBundle bundleForClass:[self class]] pathForResource:dirIcon ofType:@"png"];
    if (iconPath) dirImg = [UIImage imageWithContentsOfFile:iconPath];
    if (dirImg) [s setProperty:dirImg forKey:@"leftImage"];
    return s;
}

- (id)getPortraitW:(PSSpecifier *)spec  { return @([self sizeForSpecifier:spec]); }
- (id)getPortraitH:(PSSpecifier *)spec  { return @([self sizeForSpecifier:spec]); }

- (NSInteger)sizeForSpecifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"] ?: CCVKeyPortraitW;
    NSInteger v = [CCVPrefs() integerForKey:key];
    if (v <= 0) v = 2;
    return MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

- (void)setPortraitW:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value spec:spec]; }
- (void)setPortraitH:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value spec:spec]; }

- (void)saveSize:(id)value spec:(PSSpecifier *)spec {
    NSInteger v = [(NSNumber *)value integerValue];
    v = MIN(MAX(v, (NSInteger)1), (NSInteger)4);
    NSString *key = [spec propertyForKey:@"key"] ?: CCVKeyPortraitW;
    NSString *other = [spec propertyForKey:@"otherKey"];
    [CCVPrefs() setInteger:v forKey:key];
    if (other.length) [CCVPrefs() setInteger:v forKey:other];
    CCVPostSizeChange();
}

// ---------- 全局显示模式（适用所有模块） ----------
- (void)displayModeChanged:(UISegmentedControl *)seg {
    [CCVPrefs() setInteger:seg.selectedSegmentIndex forKey:CCVKeyDisplayMode];
    [CCVPrefs() synchronize];
    CCVPostDarwin(CCVDarwinSettingsChanged);
}

// 自定义显示模式卡片/统一行：行高自己接管（PSListController 下 +preferredHeightForSpecifier: 不可靠）
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self ccvSpecifierAtIndexPath:indexPath];
    Class cls = [spec propertyForKey:@"cellClass"];
    if (cls == [CCVDisplayModeCell class]) {
        return [CCVDisplayModeCell preferredHeight];
    }
    if (cls == [CCVRowCell class]) {
        return 44; // 模块行与创建模块行统一高度
    }
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

@end

// ---------- 子页：单模块设置（素材库 / 尺寸 / 播放，键带编号） ----------
@implementation CCVideoModuleListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"视频模块%@", @(self.moduleIndex == 0 ? 1 : self.moduleIndex)];
}

- (NSUInteger)index {
    return self.moduleIndex == 0 ? 1 : self.moduleIndex;
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSUInteger idx = [self index];

        PSSpecifier *g1 = [PSSpecifier preferenceSpecifierNamed:@"视频素材" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g1 setProperty:@"视频会静音循环播放。进入素材库可从相册导入视频、点选或长按删除。" forKey:@"footerText"];
        [specs addObject:g1];

        PSSpecifier *lib = [PSSpecifier preferenceSpecifierNamed:@"素材库" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        lib.buttonAction = @selector(openLibrary:);
        [specs addObject:lib];

        // 模块尺寸：原生分段滑杆（4 挡 + 数值显示）
        PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:@"模块尺寸" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g2 setProperty:@"X=横向 / Y=竖向，各 4 挡（1~4 格）。换挡即时生效，无需注销。" forKey:@"footerText"];
        [specs addObject:g2];
        [specs addObject:[self sliderNamed:@"X" key:CCVKeyForModule(CCVKeyPortraitW, idx) selBase:@"PortraitW" other:CCVKeyForModule(CCVKeyLandscapeW, idx)]];
        [specs addObject:[self sliderNamed:@"Y" key:CCVKeyForModule(CCVKeyPortraitH, idx) selBase:@"PortraitH" other:CCVKeyForModule(CCVKeyLandscapeH, idx)]];

        PSSpecifier *g4 = [PSSpecifier preferenceSpecifierNamed:@"播放" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g4 setProperty:@"画面填充：铺满模块（可能裁切）；关闭则完整显示（可能留黑边）。修改尺寸与选择视频即时生效，无需注销。" forKey:@"footerText"];
        [specs addObject:g4];

        PSSpecifier *fill = [PSSpecifier preferenceSpecifierNamed:@"画面填充" target:self set:@selector(setFill:forSpecifier:) get:@selector(getFill:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:fill];

        _specifiers = specs;
    }
    return _specifiers;
}

// 原生分段滑杆：get/set sel 名固定（键已带编号），otherKey 同步另一方向键
- (PSSpecifier *)sliderNamed:(NSString *)name key:(NSString *)key selBase:(NSString *)selBase other:(NSString *)other {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                    target:self
                                                      set:NSSelectorFromString([NSString stringWithFormat:@"set%@:forSpecifier:", selBase])
                                                       get:NSSelectorFromString([NSString stringWithFormat:@"get%@:", selBase])
                                                    detail:nil
                                                      cell:PSSliderCell
                                                       edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@1 forKey:@"min"];
    [s setProperty:@4 forKey:@"max"];
    [s setProperty:@2 forKey:@"defaultValue"];
    [s setProperty:@YES forKey:@"isSegmented"];
    [s setProperty:@3 forKey:@"segmentCount"];
    [s setProperty:@YES forKey:@"showValue"];
    [s setProperty:other forKey:@"otherKey"];
    // leftImage 必须是 UIImage 对象（传图片名字符串会让 UISlider setMinimumValueImage: 崩溃）
    NSString *dirIcon = [selBase isEqualToString:@"PortraitW"] ? @"X" : @"Y";
    UIImage *dirImg = nil;
    NSString *iconPath = [[NSBundle bundleForClass:[self class]] pathForResource:dirIcon ofType:@"png"];
    if (iconPath) dirImg = [UIImage imageWithContentsOfFile:iconPath];
    if (dirImg) [s setProperty:dirImg forKey:@"leftImage"];
    return s;
}

// ---------- 尺寸滑杆 ----------
- (id)getPortraitW:(PSSpecifier *)spec  { return @([self sizeForSpecifier:spec]); }
- (id)getPortraitH:(PSSpecifier *)spec  { return @([self sizeForSpecifier:spec]); }

- (NSInteger)sizeForSpecifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"] ?: CCVKeyPortraitW;
    NSInteger v = [CCVPrefs() integerForKey:key];
    if (v <= 0) v = 2;
    return MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

- (void)setPortraitW:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value spec:spec]; }
- (void)setPortraitH:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value spec:spec]; }

- (void)saveSize:(id)value spec:(PSSpecifier *)spec {
    NSInteger v = [(NSNumber *)value integerValue];
    v = MIN(MAX(v, (NSInteger)1), (NSInteger)4);
    NSString *key = [spec propertyForKey:@"key"] ?: CCVKeyPortraitW;
    NSString *other = [spec propertyForKey:@"otherKey"];
    [CCVPrefs() setInteger:v forKey:key];
    if (other.length) [CCVPrefs() setInteger:v forKey:other];
    CCVPostSizeChange();
}

// ---------- 画面填充开关 ----------
- (id)getFill:(PSSpecifier *)spec {
    return @([CCVPrefs() boolForKey:CCVKeyForModule(CCVKeyAspectFill, [self index])]);
}

- (void)setFill:(id)value forSpecifier:(PSSpecifier *)spec {
    [CCVPrefs() setBool:[(NSNumber *)value boolValue] forKey:CCVKeyForModule(CCVKeyAspectFill, [self index])];
    CCVPostDarwin(CCVDarwinSettingsChanged);
}

// ---------- 素材库 ----------
- (void)openLibrary:(PSSpecifier *)spec {
    CCVideoLibraryViewController *vc = [[CCVideoLibraryViewController alloc] init];
    vc.moduleIndex = [self index];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
