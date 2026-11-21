#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#pragma mark - 自定义四挡位尺寸滑杆 Cell

@interface CCVSizeSliderCell : PSTableCell
@end

@implementation CCVSizeSliderCell {
    UILabel *_titleLabel;
    UILabel *_valueLabel;
    UISlider *_slider;
    NSMutableArray<UIView *> *_tickDots;
    NSString *_sizeKey;
    NSInteger _lastSnapped;
    BOOL _didSetup;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) [self ccvSetup];
    return self;
}

// 兼容部分 PSListController 路径：转发到已声明的初始化器，避免 super 未实现该选择器
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    return [self initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil specifier:specifier];
}

- (void)ccvSetup {
    if (_didSetup) return;
    _didSetup = YES;

    PSSpecifier *spec = self.specifier;
    _sizeKey = [spec propertyForKey:@"key"] ?: CCVKeyPortraitW;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:13];
    _titleLabel.textColor = [UIColor secondaryLabelColor];
    _titleLabel.text = spec.name ?: @"";
    [self.contentView addSubview:_titleLabel];

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [UIFont systemFontOfSize:15];
    _valueLabel.textColor = [UIColor labelColor];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_valueLabel];

    _slider = [[UISlider alloc] init];
    _slider.minimumValue = 1;
    _slider.maximumValue = 4;
    _slider.continuous = YES;
    _slider.minimumTrackTintColor = [UIColor systemGrayColor];
    _slider.maximumTrackTintColor = [UIColor systemGrayColor];
    _slider.value = [self ccvCurrent];
    [_slider addTarget:self action:@selector(ccvSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_slider];

    _tickDots = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        UIView *dot = [[UIView alloc] init];
        dot.layer.cornerRadius = 2;
        dot.backgroundColor = [UIColor systemGray2Color];
        dot.userInteractionEnabled = NO;
        [_tickDots addObject:dot];
        [self.contentView addSubview:dot];
    }

    _lastSnapped = (NSInteger)lroundf(_slider.value);
    _valueLabel.text = [NSString stringWithFormat:@"%.2f", _slider.value];
}

- (float)ccvCurrent {
    NSInteger v = [CCVPrefs() integerForKey:_sizeKey];
    if (v <= 0) v = 2;
    return (float)MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

- (void)ccvSliderChanged:(UISlider *)slider {
    NSInteger snapped = (NSInteger)lroundf(slider.value);
    snapped = MIN(MAX(snapped, (NSInteger)1), (NSInteger)4);
    BOOL stepped = (snapped != _lastSnapped);
    _lastSnapped = snapped;

    if ((float)snapped != slider.value) slider.value = (float)snapped; // 吸附挡位
    _valueLabel.text = [NSString stringWithFormat:@"%.2f", (float)snapped];

    if (stepped) { // 换挡时轻微触感反馈
        UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
        [gen selectionChanged];
    }

    // 横/竖屏共用同一组尺寸：同步写入对应方向键
    NSString *other = [_sizeKey isEqualToString:CCVKeyPortraitW] ? CCVKeyLandscapeW : CCVKeyLandscapeH;
    [CCVPrefs() setInteger:snapped forKey:_sizeKey];
    [CCVPrefs() setInteger:snapped forKey:other];
    CCVPostSizeChange();
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (!_didSetup) { [self ccvSetup]; return; }
    _sizeKey = [self.specifier propertyForKey:@"key"] ?: _sizeKey;
    _titleLabel.text = self.specifier.name ?: @"";
    float v = [self ccvCurrent];
    _slider.value = v;
    _lastSnapped = (NSInteger)lroundf(v);
    _valueLabel.text = [NSString stringWithFormat:@"%.2f", v];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat padX = 20;
    CGFloat titleY = 9, titleH = 16;
    _titleLabel.frame = CGRectMake(padX, titleY, b.size.width - padX * 2, titleH);

    CGFloat sliderY = titleY + titleH + 4;
    CGFloat sliderH = 31;
    CGFloat valueW = 52;
    CGFloat sliderW = b.size.width - padX * 2 - valueW - 8;
    _slider.frame = CGRectMake(padX, sliderY, sliderW, sliderH);
    _valueLabel.frame = CGRectMake(b.size.width - padX - valueW, sliderY, valueW, sliderH);

    CGFloat thumbInset = 9; // 拇指半径近似，刻度贴着轨道两端
    CGFloat x0 = padX + thumbInset;
    CGFloat span = sliderW - thumbInset * 2;
    CGFloat cy = sliderY + sliderH / 2.0;
    for (int i = 0; i < 4; i++) {
        CGFloat t = i / 3.0;
        UIView *dot = _tickDots[i];
        dot.frame = CGRectMake(x0 + t * span - 2, cy - 2, 4, 4);
    }
}

+ (CGFloat)preferredHeightForSpecifier:(PSSpecifier *)specifier { return 72; }
- (CGFloat)preferredHeightForSpecifier:(PSSpecifier *)specifier { return 72; }

@end

#pragma mark - 设置主页面

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
        [g2 setProperty:@"模块尺寸" forKey:@"headerTitle"];
        [g2 setProperty:@"横向 / 竖向各 4 个挡位（1~4 格）。拖动换挡后即时生效，无需注销。" forKey:@"footerTitle"];
        [specs addObject:g2];
        [specs addObject:[self sizeSliderNamed:@"横向宽度" key:CCVKeyPortraitW]];
        [specs addObject:[self sizeSliderNamed:@"竖向高度" key:CCVKeyPortraitH]];

        PSSpecifier *g4 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g4 setProperty:@"播放" forKey:@"headerTitle"];
        [g4 setProperty:@"画面填充：铺满模块（可能裁切）；关闭则完整显示（可能留黑边）。修改尺寸与选择视频即时生效，无需注销。" forKey:@"footerTitle"];
        [specs addObject:g4];

        PSSpecifier *fill = [PSSpecifier preferenceSpecifierNamed:@"画面填充" target:self set:@selector(setFill:forSpecifier:) get:@selector(getFill:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:fill];

        _specifiers = specs;
    }
    return _specifiers;
}

- (PSSpecifier *)sizeSliderNamed:(NSString *)name key:(NSString *)key {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                    target:self
                                                      set:nil
                                                       get:nil
                                                    detail:nil
                                                      cell:PSSliderCell
                                                       edit:nil];
    [s setProperty:[CCVSizeSliderCell class] forKey:@"cellClass"];
    [s setProperty:key forKey:@"key"];
    return s;
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
