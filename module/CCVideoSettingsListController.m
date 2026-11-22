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

// ---------- 自定义模块行 cell：白卡黑字+箭头，左滑露出删除按钮 ----------
// PSLinkCell 无 detail 时 iOS16 渲染成灰色不可点行（didSelect 都不触发），
// 且基类会自己画一遍 specifier 标题（与我们的大字叠加）。所以：
// 1) init/refresh 都隐藏基类文字；2) 全尺寸透明触摸区 + hitTest 强制转发；
// 3) 卡片装进 cardWrap 容器，左滑平移露出右侧红色"删除"，点击删除该模块。
@interface CCVModuleCell : PSTableCell <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *cardWrap;      // 卡片容器（整体平移）
@property (nonatomic, strong) UILabel *modTitle;
@property (nonatomic, strong) UILabel *chevron;
@property (nonatomic, strong) UIControl *tapZone;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, assign) CGFloat dragBase;      // 手势开始时的偏移
@property (nonatomic, assign) BOOL swipeOpen;        // 是否处于左滑展开态
@end

@implementation CCVModuleCell

static const CGFloat CCVSwipeWidth = 76.0; // 删除按钮宽度

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = YES;
        self.contentView.userInteractionEnabled = YES;

        // 隐藏基类按 specifier name 画的行标题（否则与我们的标题叠成大字）
        self.textLabel.text = @"";
        self.textLabel.hidden = YES;
        if (self.detailTextLabel) self.detailTextLabel.hidden = YES;

        // 红色删除按钮（垫在卡片下面，左滑露出）
        _deleteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _deleteBtn.backgroundColor = [UIColor systemRedColor];
        _deleteBtn.layer.cornerRadius = 22;
        [_deleteBtn setTitle:@"删除" forState:UIControlStateNormal];
        [_deleteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _deleteBtn.titleLabel.font = [UIFont systemFontOfSize:12];
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
                : [UIColor colorWithWhite:1.0 alpha:0.72];
        }];
        card.layer.cornerRadius = 22;
        card.userInteractionEnabled = NO;
        [_cardWrap addSubview:card];

        _modTitle = [[UILabel alloc] init];
        _modTitle.text = specifier.name;
        _modTitle.font = [UIFont systemFontOfSize:12];
        _modTitle.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1.0];
        }];
        _modTitle.userInteractionEnabled = NO;
        [_cardWrap addSubview:_modTitle];

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
        [_tapZone addTarget:self action:@selector(moduleTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_tapZone];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [_tapZone addGestureRecognizer:pan];
    }
    return self;
}

// 与表格竖向滚动并行识别：横向滑动归我们，竖向滚动归表格
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithOtherGesture:(UIGestureRecognizer *)other {
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    if (p.state == UIGestureRecognizerStateBegan) {
        self.dragBase = self.swipeOpen ? -CCVSwipeWidth : 0;
    } else if (p.state == UIGestureRecognizerStateChanged) {
        if (fabs(t.x) <= fabs(t.y)) return; // 竖向交给表格滚动
        CGFloat x = self.dragBase + t.x;
        if (x > 0) x = 0;
        if (x < -CCVSwipeWidth) x = -CCVSwipeWidth;
        self.cardWrap.transform = CGAffineTransformMakeTranslation(x, 0);
    } else if (p.state == UIGestureRecognizerStateEnded || p.state == UIGestureRecognizerStateCancelled) {
        if (fabs(t.x) <= fabs(t.y)) return;
        CGPoint v = [p velocityInView:self];
        CGFloat x = self.dragBase + t.x;
        BOOL open = (x < -CCVSwipeWidth / 2.0) || (v.x < -400 && x < 0);
        [UIView animateWithDuration:0.2 animations:^{
            self.cardWrap.transform = CGAffineTransformMakeTranslation(open ? -CCVSwipeWidth : 0, 0);
        }];
        self.swipeOpen = open;
    }
}

- (void)moduleTapped {
    if (self.swipeOpen) { // 展开态先收起
        [UIView animateWithDuration:0.2 animations:^{
            self.cardWrap.transform = CGAffineTransformIdentity;
        }];
        self.swipeOpen = NO;
        return;
    }
    PSSpecifier *spec = self.specifier;
    id target = [spec target];
    if ([target respondsToSelector:@selector(openModule:)]) {
        [target performSelector:@selector(openModule:) withObject:spec];
    }
}

- (void)deleteTapped {
    PSSpecifier *spec = self.specifier;
    id target = [spec target];
    if ([target respondsToSelector:@selector(deleteModule:)]) {
        [target performSelector:@selector(deleteModule:) withObject:spec];
    }
}

// 展开态：删除按钮区域的触摸给按钮；其余给触摸区
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.swipeOpen && self.deleteBtn &&
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
    self.modTitle.text = specifier.name;
    self.textLabel.text = @"";
    self.textLabel.hidden = YES;
    if (self.detailTextLabel) self.detailTextLabel.hidden = YES;
    // 复用/刷新时收起滑动状态
    self.swipeOpen = NO;
    self.cardWrap.transform = CGAffineTransformIdentity;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.deleteBtn.frame = CGRectMake(w - CCVSwipeWidth, 0, CCVSwipeWidth, h);
    self.cardWrap.frame = CGRectMake(0, 0, w, h);
    UIView *card = self.cardWrap.subviews.firstObject;
    card.frame = CGRectMake(0, 0, w, h);
    self.modTitle.frame = CGRectMake(20, (h - 16) / 2, w - 60, 16);
    self.chevron.frame = CGRectMake(w - 34, (h - 18) / 2, 24, 18);
    self.tapZone.frame = self.contentView.bounds;
}

@end

// ---------- 自定义"创建模块" cell：蓝字 12pt（系统 PSButtonCell 字号无法控制） ----------
@interface CCVCreateCell : PSTableCell
@property (nonatomic, strong) UILabel *createTitle;
@property (nonatomic, strong) UIControl *tapZone;
@end

@implementation CCVCreateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = YES;
        self.contentView.userInteractionEnabled = YES;

        self.textLabel.text = @"";
        self.textLabel.hidden = YES;
        if (self.detailTextLabel) self.detailTextLabel.hidden = YES;

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.11 alpha:1.0]
                : [UIColor colorWithWhite:1.0 alpha:0.72];
        }];
        card.layer.cornerRadius = 22;
        card.userInteractionEnabled = NO;
        self.backgroundView = card;

        _createTitle = [[UILabel alloc] init];
        _createTitle.text = specifier.name; // 创建模块
        _createTitle.font = [UIFont systemFontOfSize:12];
        _createTitle.textColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        _createTitle.userInteractionEnabled = NO;
        [self.contentView addSubview:_createTitle];

        _tapZone = [[UIControl alloc] init];
        _tapZone.backgroundColor = [UIColor clearColor];
        [_tapZone addTarget:self action:@selector(createTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_tapZone];
    }
    return self;
}

- (void)createTapped {
    PSSpecifier *spec = self.specifier;
    id target = [spec target];
    if ([target respondsToSelector:@selector(createModule:)]) {
        [target performSelector:@selector(createModule:) withObject:spec];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.tapZone && [self.tapZone pointInside:[self convertPoint:point toView:self.tapZone] withEvent:event]) {
        return self.tapZone;
    }
    return [super hitTest:point withEvent:event];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.createTitle.text = specifier.name;
    self.textLabel.text = @"";
    self.textLabel.hidden = YES;
    if (self.detailTextLabel) self.detailTextLabel.hidden = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.createTitle.frame = CGRectMake(20, (h - 16) / 2, w - 40, 16);
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

        // 小分类：模块行 + 创建模块紧挨着（同一个组）
        PSSpecifier *g0 = [PSSpecifier preferenceSpecifierNamed:@""
                target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g0 setProperty:[NSString stringWithFormat:@"点击模块名可选择素材，左滑模块行可删除该模块。已创建 %lu / 8 个，创建/删除的模块在下次注销后同步到控制中心。",
                         (unsigned long)n] forKey:@"footerText"];
        [specs addObject:g0];

        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *mod = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"视频模块%@", @(i)]
                    target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
            [mod setProperty:@(i) forKey:@"moduleIndex"];
            [mod setProperty:[CCVModuleCell class] forKey:@"cellClass"]; // 自绘黑字卡片行
            mod.buttonAction = @selector(openModule:);                    // 兜底触发
            [specs addObject:mod];
        }

        if (n < CCV_MAX_MODULES) {
            PSSpecifier *create = [PSSpecifier preferenceSpecifierNamed:@"创建模块"
                    target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [create setProperty:[CCVCreateCell class] forKey:@"cellClass"]; // 蓝字 12pt 自绘
            create.buttonAction = @selector(createModule:);                 // 兜底触发
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

// 模块行（黑字）点击 -> 直接进入该模块的素材库选素材
// specifierAtIndexPath 在 iOS16 上可能返回 nil，兜底按行号取（组头也占一行，row 与 specifiers 下标一一对应）
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (!spec) {
        NSArray *specs = [self specifiers];
        NSUInteger row = indexPath.row;
        if (specs && row < specs.count) spec = specs[row];
    }
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
    CCVPostDarwin(CCVDarwinSettingsChanged);

    _specifiers = nil;
    [self reloadSpecifiers];
}

// 创建模块：直接创建（无弹窗、不注销），SpringBoard 侧只拷贝 bundle，下次注销自动载入
- (void)createModule:(PSSpecifier *)spec {
    NSUInteger n = CCVMaxModules();
    if (n >= CCV_MAX_MODULES) return;
    CCVSetMaxModules(n + 1);
    CCVPostDarwin(CCVDarwinSettingsChanged);
    _specifiers = nil;
    [self reloadSpecifiers];
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

// 自定义显示模式卡片/模块行：行高自己接管（PSListController 下 +preferredHeightForSpecifier: 不可靠）
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (!spec) {
        NSArray *specs = [self specifiers];
        NSUInteger row = indexPath.row;
        if (specs && row < specs.count) spec = specs[row];
    }
    Class cls = [spec propertyForKey:@"cellClass"];
    if (cls == [CCVDisplayModeCell class]) {
        return [CCVDisplayModeCell preferredHeight];
    }
    if (cls == [CCVModuleCell class]) {
        return 44;
    }
    if (cls == [CCVCreateCell class]) {
        return 44;
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
