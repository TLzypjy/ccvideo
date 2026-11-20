#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"

@implementation CCVideoSettingsListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视频模块";
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *g1 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g1 setProperty:@"视频素材" forKey:@"headerTitle"];
        [g1 setProperty:@"视频会静音循环播放。进入素材库可从相册导入视频、点选或长按删除。" forKey:@"footerTitle"];
        [specs addObject:g1];

        PSSpecifier *lib = [PSSpecifier preferenceSpecifierNamed:@"素材库" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        lib.buttonAction = @selector(openLibrary:);
        [specs addObject:lib];

        PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g2 setProperty:@"模块大小（竖屏）" forKey:@"headerTitle"];
        [specs addObject:g2];
        [specs addObject:[self sliderNamed:@"宽度" key:CCVKeyPortraitW]];
        [specs addObject:[self sliderNamed:@"高度" key:CCVKeyPortraitH]];

        PSSpecifier *g3 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g3 setProperty:@"模块大小（横屏）" forKey:@"headerTitle"];
        [specs addObject:g3];
        [specs addObject:[self sliderNamed:@"宽度" key:CCVKeyLandscapeW]];
        [specs addObject:[self sliderNamed:@"高度" key:CCVKeyLandscapeH]];

        PSSpecifier *g4 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g4 setProperty:@"播放" forKey:@"headerTitle"];
        [g4 setProperty:@"画面填充：铺满模块（可能裁切）；关闭则完整显示（可能留黑边）。修改大小与选择视频即时生效，无需注销。" forKey:@"footerTitle"];
        [specs addObject:g4];

        PSSpecifier *fill = [PSSpecifier preferenceSpecifierNamed:@"画面填充" target:self set:@selector(setFill:forSpecifier:) get:@selector(getFill:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:fill];

        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)sliderNamed:(NSString *)name key:(NSString *)key {
    NSString *cap = [self capitalized:key]; // portraitW -> PortraitW
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                    target:self
                                                      set:NSSelectorFromString([NSString stringWithFormat:@"set%@:forSpecifier:", cap])
                                                       get:NSSelectorFromString([NSString stringWithFormat:@"get%@:", cap])
                                                    detail:nil
                                                      cell:PSSliderCell
                                                       edit:nil];
    [s setProperty:@1 forKey:@"min"];
    [s setProperty:@4 forKey:@"max"];
    [s setProperty:@YES forKey:@"isContinuous"];
    [s setProperty:@2 forKey:@"defaultValue"];
    return s;
}

- (NSString *)capitalized:(NSString *)key {
    if (key.length == 0) return key;
    return [[key substringToIndex:1] uppercaseString] stringByAppendingString:[key substringFromIndex:1]];
}

// ---------- 大小滑杆（键名: portraitW / portraitH / landscapeW / landscapeH） ----------
- (id)getPortraitW:(PSSpecifier *)spec  { return @([self sizeForKey:CCVKeyPortraitW]); }
- (id)getPortraitH:(PSSpecifier *)spec  { return @([self sizeForKey:CCVKeyPortraitH]); }
- (id)getLandscapeW:(PSSpecifier *)spec { return @([self sizeForKey:CCVKeyLandscapeW]); }
- (id)getLandscapeH:(PSSpecifier *)spec { return @([self sizeForKey:CCVKeyLandscapeH]); }

- (NSInteger)sizeForKey:(NSString *)key {
    NSInteger v = [CCVPrefs() integerForKey:key];
    if (v <= 0) v = 2;
    return MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

- (void)setPortraitW:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value forKey:CCVKeyPortraitW]; }
- (void)setPortraitH:(id)value forSpecifier:(PSSpecifier *)spec  { [self saveSize:value forKey:CCVKeyPortraitH]; }
- (void)setLandscapeW:(id)value forSpecifier:(PSSpecifier *)spec { [self saveSize:value forKey:CCVKeyLandscapeW]; }
- (void)setLandscapeH:(id)value forSpecifier:(PSSpecifier *)spec { [self saveSize:value forKey:CCVKeyLandscapeH]; }

- (void)saveSize:(id)value forKey:(NSString *)key {
    NSInteger v = [(NSNumber *)value integerValue];
    v = MIN(MAX(v, (NSInteger)1), (NSInteger)4);
    [CCVPrefs() setInteger:v forKey:key];
    CCVPostSizeChange();
}

// ---------- 画面填充开关 ----------
- (id)getFill:(PSSpecifier *)spec {
    return @([CCVPrefs() boolForKey:CCVKeyAspectFill]);
}

- (void)setFill:(id)value forSpecifier:(PSSpecifier *)spec {
    [CCVPrefs() setBool:[(NSNumber *)value boolValue] forKey:CCVKeyAspectFill];
    CCVPostDarwin(CCVDarwinSettingsChanged);
}

// ---------- 素材库 ----------
- (void)openLibrary:(PSSpecifier *)spec {
    CCVideoLibraryViewController *vc = [[CCVideoLibraryViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
