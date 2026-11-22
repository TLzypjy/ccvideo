#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"

// ---------- 自定义卡片 cell：显示模式（标题 + 三挡分段 + 卡底说明文字） ----------
@interface CCVDisplayModeCell : PSTableCell
@property (nonatomic, strong) UILabel *modeTitle;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) UILabel *descLabel;
+ (CGFloat)preferredHeight;
@end

@implementation CCVDisplayModeCell

+ (NSString *)descText {
    return @"选择图片和视频的显示方式：\n· 裁切填满：保持比例、放大并裁剪超出部分\n· 完整适应：完整显示原图，空白区域用模糊背景补齐\n· 拉伸填满：忽略比例，直接铺满模块";
}

+ (CGFloat)descHeightForWidth:(CGFloat)w {
    CGRect b = [[self descText] boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12]}
                                             context:nil];
    return ceil(b.size.height);
}

+ (CGFloat)preferredHeight {
    // 上边距16 + 标题22 + 间距12 + 分段32 + 间距12 + 说明 + 下边距16
    return 16 + 22 + 12 + 32 + 12 + [self descHeightForWidth:335] + 16;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.backgroundView = nil;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        // 卡片背景（跟随深浅色）
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.11 alpha:1.0]
                : [UIColor whiteColor];
        }];
        card.layer.cornerRadius = 22;
        self.backgroundView = card;

        _modeTitle = [[UILabel alloc] init];
        _modeTitle.text = @"显示模式";
        _modeTitle.font = [UIFont boldSystemFontOfSize:17];
        _modeTitle.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1.0];
        }];
        [self.contentView addSubview:_modeTitle];

        _segment = [[UISegmentedControl alloc] initWithItems:@[@"裁切填满", @"完整适应", @"拉伸填满"]];
        _segment.selectedSegmentIndex = CCVDisplayMode();
        if (specifier.target) {
            [_segment addTarget:specifier.target action:@selector(displayModeChanged:) forControlEvents:UIControlEventValueChanged];
        }
        [self.contentView addSubview:_segment];

        _descLabel = [[UILabel alloc] init];
        _descLabel.text = [CCVDisplayModeCell descText];
        _descLabel.font = [UIFont systemFontOfSize:12];
        _descLabel.numberOfLines = 0;
        _descLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.65 alpha:1.0]
                : [UIColor colorWithWhite:0.45 alpha:1.0];
        }];
        [self.contentView addSubview:_descLabel];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (_segment) _segment.selectedSegmentIndex = CCVDisplayMode();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat pad = 20;
    self.modeTitle.frame = CGRectMake(pad, 16, w - pad * 2, 22);
    self.segment.frame = CGRectMake(pad, 16 + 22 + 12, w - pad * 2, 32);
    CGFloat ty = 16 + 22 + 12 + 32 + 12;
    self.descLabel.frame = CGRectMake(pad, ty, w - pad * 2, [CCVDisplayModeCell descHeightForWidth:w - pad * 2]);
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
                         (unsigned long)n] forKey:@"footerTitle"];
        [specs addObject:g0];

        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *mod = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"视频模块%@", @(i)]
                    target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
            [mod setProperty:@(i) forKey:@"moduleIndex"];
            [specs addObject:mod];
        }

        if (n < CCV_MAX_MODULES) {
            PSSpecifier *create = [PSSpecifier preferenceSpecifierNamed:@"创建模块"
                    target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            create.buttonAction = @selector(createModule:);
            [specs addObject:create];
        }

        // 显示模式（全局，一张卡片：标题 + 三挡分段 + 卡底说明）
        PSSpecifier *gMode = [PSSpecifier preferenceSpecifierNamed:@""
                target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:gMode];
        PSSpecifier *dm = [PSSpecifier preferenceSpecifierNamed:@"显示模式"
                target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
        [dm setProperty:[CCVDisplayModeCell class] forKey:@"cellClass"];
        [specs addObject:dm];

        // 每个模块的尺寸设置内联在主页（模块 1 沿用原分组名，与旧版界面一致）
        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:(i == 1 ? @"模块尺寸" : [NSString stringWithFormat:@"视频模块%lu 尺寸", (unsigned long)i])
                    target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            if (i == 1) [g2 setProperty:@"X=横向 / Y=竖向，各 4 挡（1~4 格）。换挡即时生效，无需注销。" forKey:@"footerTitle"];
            [specs addObject:g2];
            [specs addObject:[self sliderForModule:i named:@"X" selBase:@"PortraitW" key:CCVKeyForModule(CCVKeyPortraitW, i) other:CCVKeyForModule(CCVKeyLandscapeW, i)]];
            [specs addObject:[self sliderForModule:i named:@"Y" selBase:@"PortraitH" key:CCVKeyForModule(CCVKeyPortraitH, i) other:CCVKeyForModule(CCVKeyLandscapeH, i)]];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

// 模块行（黑字）点击 -> 直接进入该模块的素材库选素材
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (spec && [spec propertyForKey:@"moduleIndex"]) {
        NSUInteger idx = [[spec propertyForKey:@"moduleIndex"] integerValue];
        CCVideoLibraryViewController *vc = [[CCVideoLibraryViewController alloc] init];
        vc.moduleIndex = idx;
        [self.navigationController pushViewController:vc animated:YES];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
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

// 自定义显示模式卡片：行高自己接管（PSListController 下 +preferredHeightForSpecifier: 不可靠）
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (spec && [spec propertyForKey:@"cellClass"] == [CCVDisplayModeCell class]) {
        return [CCVDisplayModeCell preferredHeight];
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
        [g1 setProperty:@"视频会静音循环播放。进入素材库可从相册导入视频、点选或长按删除。" forKey:@"footerTitle"];
        [specs addObject:g1];

        PSSpecifier *lib = [PSSpecifier preferenceSpecifierNamed:@"素材库" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        lib.buttonAction = @selector(openLibrary:);
        [specs addObject:lib];

        // 模块尺寸：原生分段滑杆（4 挡 + 数值显示）
        PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:@"模块尺寸" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g2 setProperty:@"X=横向 / Y=竖向，各 4 挡（1~4 格）。换挡即时生效，无需注销。" forKey:@"footerTitle"];
        [specs addObject:g2];
        [specs addObject:[self sliderNamed:@"X" key:CCVKeyForModule(CCVKeyPortraitW, idx) selBase:@"PortraitW" other:CCVKeyForModule(CCVKeyLandscapeW, idx)]];
        [specs addObject:[self sliderNamed:@"Y" key:CCVKeyForModule(CCVKeyPortraitH, idx) selBase:@"PortraitH" other:CCVKeyForModule(CCVKeyLandscapeH, idx)]];

        PSSpecifier *g4 = [PSSpecifier preferenceSpecifierNamed:@"播放" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g4 setProperty:@"画面填充：铺满模块（可能裁切）；关闭则完整显示（可能留黑边）。修改尺寸与选择视频即时生效，无需注销。" forKey:@"footerTitle"];
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
