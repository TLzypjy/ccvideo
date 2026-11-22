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

// ---------- 自定义模块行 cell：白卡黑字+箭头，整块触摸区自己处理点击 ----------
// PSLinkCell 无 detail 时 iOS16 渲染成灰色不可点行（didSelect 都不触发），
// 且基类会自己画一遍 specifier 标题（与我们的大字叠加）。所以：
// 1) init/refresh 都隐藏基类文字；2) 全尺寸透明触摸区 + hitTest 强制转发。
@interface CCVModuleCell : PSTableCell
@property (nonatomic, strong) UILabel *modTitle;
@property (nonatomic, strong) UILabel *chevron;
@property (nonatomic, strong) UIControl *tapZone;
@end

@implementation CCVModuleCell

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

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.11 alpha:1.0]
                : [UIColor colorWithWhite:1.0 alpha:0.72];
        }];
        card.layer.cornerRadius = 22;
        card.userInteractionEnabled = NO;
        self.backgroundView = card;

        _modTitle = [[UILabel alloc] init];
        _modTitle.text = specifier.name;
        _modTitle.font = [UIFont systemFontOfSize:17];
        _modTitle.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1.0];
        }];
        _modTitle.userInteractionEnabled = NO;
        [self.contentView addSubview:_modTitle];

        _chevron = [[UILabel alloc] init];
        _chevron.text = @"›";
        _chevron.font = [UIFont boldSystemFontOfSize:20];
        _chevron.textAlignment = NSTextAlignmentCenter;
        _chevron.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.5 alpha:1.0]
                : [UIColor colorWithWhite:0.75 alpha:1.0];
        }];
        _chevron.userInteractionEnabled = NO;
        [self.contentView addSubview:_chevron];

        // 全尺寸透明触摸区（hitTest 强制转发到这里，与显示模式分段按钮同一机制）
        _tapZone = [[UIControl alloc] init];
        _tapZone.backgroundColor = [UIColor clearColor];
        [_tapZone addTarget:self action:@selector(moduleTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_tapZone];
    }
    return self;
}

- (void)moduleTapped {
    PSSpecifier *spec = self.specifier;
    id target = [spec target];
    if ([target respondsToSelector:@selector(openModule:)]) {
        [target performSelector:@selector(openModule:) withObject:spec];
    }
}

// 整个 cell 区域的触摸全部交给 tapZone（防止基类/表格截走导致点不了）
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
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
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.modTitle.frame = CGRectMake(20, (h - 22) / 2, w - 60, 22);
    self.chevron.frame = CGRectMake(w - 34, (h - 24) / 2, 24, 24);
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
        [g0 setProperty:[NSString stringWithFormat:@"点击模块名可选择该模块播放的视频素材。已创建 %lu / 8 个，新创建的模块将在下次注销后出现在控制中心。",
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
            create.buttonAction = @selector(createModule:);
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
        return 56;
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
