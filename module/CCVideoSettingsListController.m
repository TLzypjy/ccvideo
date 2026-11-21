#import "CCVideoSettingsListController.h"
#import "CCVideoPrefs.h"
#import "CCVideoLibraryViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#pragma mark - 「模块尺寸」卡片 Cell（标题 + 横向/竖向两条四挡滑杆）

@interface CCVSizeCardCell : PSTableCell
@end

@implementation CCVSizeCardCell {
    UILabel *_titleLabel;
    NSArray<UISlider *> *_sliders;                       // 0=横向宽度 1=竖向高度
    NSArray<UILabel *> *_valueLabels;
    NSArray<NSArray<UIView *> *> *_dots;                 // 每条滑杆 4 个刻度点
    NSArray<NSString *> *_keys;
    NSArray<NSString *> *_otherKeys;                     // 同步写入的另一方向键
    NSInteger _lastSnapped[2];
    BOOL _didSetup;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) [self ccvSetup];
    return self;
}

// 兼容 PSListController 可能走的初始化路径
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    return [self initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil specifier:specifier];
}

- (void)ccvSetup {
    if (_didSetup) return;
    _didSetup = YES;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    _keys = @[CCVKeyPortraitW, CCVKeyPortraitH];
    _otherKeys = @[CCVKeyLandscapeW, CCVKeyLandscapeH];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.text = @"模块尺寸";
    [self.contentView addSubview:_titleLabel];

    NSMutableArray *sliders = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    NSMutableArray *dotGroups = [NSMutableArray array];

    for (int i = 0; i < 2; i++) {
        UILabel *v = [[UILabel alloc] init];
        v.font = [UIFont systemFontOfSize:15];
        v.textColor = [UIColor labelColor];
        v.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:v];
        [labels addObject:v];

        UISlider *s = [[UISlider alloc] init];
        s.tag = i;
        s.minimumValue = 1;
        s.maximumValue = 4;
        s.continuous = YES;
        s.minimumTrackTintColor = [UIColor systemGrayColor];
        s.maximumTrackTintColor = [UIColor systemGrayColor];
        s.value = [self ccvCurrentForKey:_keys[i]];
        [s addTarget:self action:@selector(ccvSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:s];
        [sliders addObject:s];

        NSMutableArray *dots = [NSMutableArray array];
        for (int j = 0; j < 4; j++) {
            UIView *dot = [[UIView alloc] init];
            dot.layer.cornerRadius = 2;
            dot.backgroundColor = [UIColor systemGray2Color];
            dot.userInteractionEnabled = NO;
            [self.contentView addSubview:dot];
            [dots addObject:dot];
        }
        [dotGroups addObject:dots];

        _lastSnapped[i] = (NSInteger)lroundf(s.value);
        v.text = [NSString stringWithFormat:@"%.2f", s.value];
    }

    _sliders = sliders;
    _valueLabels = labels;
    _dots = dotGroups;
}

- (float)ccvCurrentForKey:(NSString *)key {
    NSInteger v = [CCVPrefs() integerForKey:key];
    if (v <= 0) v = 2;
    return (float)MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

- (void)ccvSliderChanged:(UISlider *)sender {
    NSInteger idx = sender.tag;
    NSInteger snapped = (NSInteger)lroundf(sender.value);
    snapped = MIN(MAX(snapped, (NSInteger)1), (NSInteger)4);
    BOOL stepped = (snapped != _lastSnapped[idx]);
    _lastSnapped[idx] = snapped;

    if ((float)snapped != sender.value) sender.value = (float)snapped; // 吸附挡位
    _valueLabels[idx].text = [NSString stringWithFormat:@"%.2f", (float)snapped];

    if (stepped) { // 换挡触感反馈
        UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
        [gen selectionChanged];
    }

    // 横/竖屏共用同一组尺寸：同步写入对应方向键
    [CCVPrefs() setInteger:snapped forKey:_keys[idx]];
    [CCVPrefs() setInteger:snapped forKey:_otherKeys[idx]];
    CCVPostSizeChange();
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (!_didSetup) { [self ccvSetup]; return; }
    for (int i = 0; i < 2; i++) {
        float v = [self ccvCurrentForKey:_keys[i]];
        _sliders[i].value = v;
        _lastSnapped[i] = (NSInteger)lroundf(v);
        _valueLabels[i].text = [NSString stringWithFormat:@"%.2f", v];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat padX = 20;
    CGFloat w = b.size.width;
    _titleLabel.frame = CGRectMake(padX, 12, w - padX * 2, 18);

    CGFloat valueW = 50;
    CGFloat sliderW = w - padX * 2 - valueW - 10;
    CGFloat ys[2] = {42, 84};
    CGFloat sliderH = 31;

    CGFloat thumbInset = 9; // 拇指半径近似，刻度贴着轨道两端
    for (int i = 0; i < 2; i++) {
        UISlider *s = _sliders[i];
        s.frame = CGRectMake(padX, ys[i], sliderW, sliderH);
        UILabel *v = _valueLabels[i];
        v.frame = CGRectMake(padX + sliderW + 10, ys[i], valueW, sliderH);

        CGFloat x0 = padX + thumbInset;
        CGFloat span = sliderW - thumbInset * 2;
        CGFloat cy = ys[i] + sliderH / 2.0;
        for (int j = 0; j < 4; j++) {
            UIView *dot = _dots[i][j];
            dot.frame = CGRectMake(x0 + (j / 3.0) * span - 2, cy - 2, 4, 4);
        }
    }
}

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

        // 模块尺寸：单张卡片 cell（无外部小节标题）
        PSSpecifier *g2 = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g2 setProperty:@"横向 / 竖向各 4 个挡位（1~4 格）。拖动换挡后即时生效，无需注销。" forKey:@"footerTitle"];
        [specs addObject:g2];

        PSSpecifier *card = [PSSpecifier preferenceSpecifierNamed:@"模块尺寸"
                                                           target:self
                                                             set:nil
                                                              get:nil
                                                           detail:nil
                                                             cell:PSSliderCell
                                                              edit:nil];
        [card setProperty:[CCVSizeCardCell class] forKey:@"cellClass"];
        [specs addObject:card];

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

// 行高自己接管：卡片 cell 固定 130pt，其余走默认逻辑
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *specs = [self specifiers];
    if (indexPath.row < (NSInteger)specs.count) {
        PSSpecifier *spec = [specs objectAtIndex:indexPath.row];
        if ([[spec propertyForKey:@"cellClass"] isEqual:[CCVSizeCardCell class]]) return 130;
    }
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
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
