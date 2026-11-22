#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"

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
        for (NSUInteger i = 1; i <= n; i++) {
            PSSpecifier *mod = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"视频模块%@", @(i)]
                    target:self set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
            [mod setProperty:@(i) forKey:@"moduleIndex"];
            [specs addObject:mod];
        }

        PSSpecifier *g = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g setProperty:[NSString stringWithFormat:@"已创建 %lu / 8 个模块。每个模块在控制中心里独立显示、独立选择视频和尺寸。",
                        (unsigned long)n] forKey:@"footerTitle"];
        [specs addObject:g];

        if (n < CCV_MAX_MODULES) {
            PSSpecifier *create = [PSSpecifier preferenceSpecifierNamed:@"创建模块"
                    target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            create.buttonAction = @selector(createModule:);
            [specs addObject:create];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

// 模块行黑字（PSLinkCell）点击 -> 自己解析编号并推入子页
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (spec && [spec.name hasPrefix:@"视频模块"]) {
        NSUInteger idx = (NSUInteger)[[spec propertyForKey:@"moduleIndex"] integerValue];
        CCVideoModuleListController *vc = [[CCVideoModuleListController alloc] init];
        vc.moduleIndex = idx;
        [self.navigationController pushViewController:vc animated:YES];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// 创建模块：MaxModules+1 -> 通知 SpringBoard 拷贝 bundle 并注销载入
- (void)createModule:(PSSpecifier *)spec {
    NSUInteger n = CCVMaxModules();
    if (n >= CCV_MAX_MODULES) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"创建视频模块"
        message:[NSString stringWithFormat:@"将在控制中心新增视频模块%@，并自动注销一次以载入新模块。", @(n + 1)]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        CCVSetMaxModules(n + 1);
        CCVPostDarwin(CCVDarwinSettingsChanged); // SpringBoard 侧据此拷贝 bundle 并注销
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
