#import "CCVideoLibraryViewController.h"
#import "CCVideoPrefs.h"

static NSString * const CCVCellID = @"CCVVideoCell";

#pragma mark - Cell

@interface CCVVideoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *typeBadge;
@property (nonatomic, strong) UIButton *namePill;
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UIButton *deleteBadge;
@property (nonatomic, copy) void (^pillTapped)(void);
@property (nonatomic, copy) void (^deleteTapped)(void);
@end

@implementation CCVVideoCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.clearColor;

        _thumbView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = 12;
        _thumbView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        [self.contentView addSubview:_thumbView];

        _typeBadge = [[UILabel alloc] initWithFrame:CGRectZero];
        _typeBadge.text = @"视频";
        _typeBadge.font = [UIFont boldSystemFontOfSize:9];
        _typeBadge.textColor = UIColor.whiteColor;
        _typeBadge.textAlignment = NSTextAlignmentCenter;
        _typeBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        _typeBadge.layer.cornerRadius = 4;
        _typeBadge.layer.masksToBounds = YES;
        [self.contentView addSubview:_typeBadge];

        _namePill = [UIButton buttonWithType:UIButtonTypeCustom];
        _namePill.titleLabel.font = [UIFont systemFontOfSize:11];
        [_namePill setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        _namePill.backgroundColor = [UIColor colorWithWhite:0.78 alpha:1.0];
        _namePill.layer.cornerRadius = 8;
        _namePill.layer.masksToBounds = YES;
        _namePill.titleLabel.lineBreakMode = (NSLineBreakMode)5; // 中间截断
        [_namePill addTarget:self action:@selector(onPill:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_namePill];

        _dotView = [[UIView alloc] initWithFrame:CGRectZero];
        _dotView.layer.cornerRadius = 7;
        _dotView.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        [self.contentView addSubview:_dotView];

        _deleteBadge = [UIButton buttonWithType:UIButtonTypeCustom];
        [_deleteBadge setTitle:@"−" forState:UIControlStateNormal];
        [_deleteBadge setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _deleteBadge.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        _deleteBadge.backgroundColor = [UIColor systemRedColor];
        _deleteBadge.layer.cornerRadius = 10;
        _deleteBadge.layer.masksToBounds = YES;
        _deleteBadge.hidden = YES;
        [_deleteBadge addTarget:self action:@selector(onDelete:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_deleteBadge];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat thumbH = w * 1.06;
    _thumbView.frame = CGRectMake(0, 0, w, thumbH);
    _typeBadge.frame = CGRectMake(8, 8, 30, 15);
    _namePill.frame = CGRectMake(0, thumbH + 7, w, 26);
    _dotView.frame = CGRectMake((w - 14) / 2.0, thumbH + 26 + 15, 14, 14);
    _deleteBadge.frame = CGRectMake(w - 24, -4, 20, 20);
}

- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; }

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected) {
        _dotView.backgroundColor = [UIColor systemBlueColor];
    } else {
        _dotView.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    }
}

- (void)onPill:(id)sender { if (self.pillTapped) self.pillTapped(); }
- (void)onDelete:(id)sender { if (self.deleteTapped) self.deleteTapped(); }

@end

#pragma mark - Library

@interface CCVideoLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<NSString *> *videos;
@property (nonatomic, assign) BOOL editMode;
@end

@implementation CCVideoLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
        style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入"
        style:UIBarButtonItemStylePlain target:self action:@selector(importTapped)];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, self.view.bounds.size.width - 24, 26)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hint.text = @"长按进入编辑状态，支持改名 / 删除";
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:hint];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 14;
    layout.sectionInset = UIEdgeInsetsMake(6, 14, 30, 14);

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = UIColor.clearColor;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:[CCVVideoCell class] forCellWithReuseIdentifier:CCVCellID];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [_collectionView addGestureRecognizer:lp];
    [self.view addSubview:_collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [_collectionView.topAnchor constraintEqualToAnchor:hint.bottomAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    CCVEnsureDirs();
    [self reloadVideos];
}

- (void)reloadVideos {
    self.videos = CCVVideoFileNames();
    self.title = [NSString stringWithFormat:@"素材库 (%lu)", (unsigned long)self.videos.count];
    [self.collectionView reloadData];
}

// ---------- 顶栏 ----------
- (void)closeTapped {
    if (self.editMode) { [self exitEditing]; return; }
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)enterEditing {
    self.editMode = YES;
    self.navigationItem.leftBarButtonItem.title = @"完成";
    [self.collectionView reloadData];
}

- (void)exitEditing {
    self.editMode = NO;
    self.navigationItem.leftBarButtonItem.title = @"关闭";
    [self.collectionView reloadData];
}

// ---------- 数据 ----------
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = (self.view.bounds.size.width - 14 * 2 - 10 * 2) / 3.0;
    return CGSizeMake(w, w * 1.06 + 26 + 37);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CCVVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CCVCellID forIndexPath:indexPath];
    NSString *name = self.videos[indexPath.item];
    NSString *base = [name stringByDeletingPathExtension];

    [cell.namePill setTitle:base forState:UIControlStateNormal];
    cell.typeBadge.text = [[name pathExtension].lowercaseString isEqualToString:@"gif"] ? @"GIF" : @"视频";
    cell.deleteBadge.hidden = !self.editMode;

    NSString *thumbPath = CCVThumbPathForVideoName(name);
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
        cell.thumbView.image = [UIImage imageWithContentsOfFile:thumbPath];
    } else {
        cell.thumbView.image = nil;
        [self generateThumbnailFor:name];
    }

    cell.selected = [name isEqualToString:CCVSelectedVideoName()];

    __weak typeof(self) weakSelf = self;
    cell.pillTapped = ^{
        if (weakSelf.editMode) [weakSelf beginRename:indexPath.item];
    };
    cell.deleteTapped = ^{
        if (weakSelf.editMode) [weakSelf confirmDelete:indexPath.item];
    };
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.editMode) return;
    NSString *name = self.videos[indexPath.item];
    [CCVPrefs() setObject:name forKey:CCVKeySelectedVideo];
    CCVPostDarwin(CCVDarwinSettingsChanged);
    [self.collectionView reloadData];
}

// ---------- 长按编辑态 ----------
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gr locationInView:self.collectionView];
    NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:p];
    if (!ip) return;
    if (!self.editMode) [self enterEditing];
}

// ---------- 改名 ----------
- (void)beginRename:(NSInteger)item {
    if (item >= self.videos.count) return;
    NSString *name = self.videos[item];
    NSString *base = [name stringByDeletingPathExtension];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"改名"
        message:@"输入新名称（不含扩展名）" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = base; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *newBase = alert.textFields.firstObject.text;
        [self doRename:name to:newBase];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)doRename:(NSString *)oldName to:(NSString *)newBase {
    NSString *trimmed = [newBase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@""];
    if (trimmed.length == 0) return;

    NSString *ext = [oldName pathExtension];
    NSString *newName = [NSString stringWithFormat:@"%@.%@", trimmed, ext];
    if ([newName isEqualToString:oldName]) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *oldPath = CCVVideoPathForName(oldName);
    NSString *newPath = [CCVVideoDir stringByAppendingPathComponent:newName];
    if ([fm fileExistsAtPath:newPath]) {
        [self showAlert:@"名称已存在，请换一个" title:@"改名失败"];
        return;
    }
    NSError *err = nil;
    if (![fm moveItemAtPath:oldPath toPath:newPath error:&err]) {
        [self showAlert:err.localizedDescription ?: @"文件移动失败" title:@"改名失败"];
        return;
    }

    // 缩略图同步改名
    NSString *oldThumb = CCVThumbPathForVideoName(oldName);
    NSString *newThumb = CCVThumbPathForVideoName(newName);
    if ([fm fileExistsAtPath:oldThumb]) [fm moveItemAtPath:oldThumb toPath:newThumb error:nil];

    // 选中项同步
    if ([CCVSelectedVideoName() isEqualToString:oldName]) {
        [CCVPrefs() setObject:newName forKey:CCVKeySelectedVideo];
        CCVPostDarwin(CCVDarwinSettingsChanged);
    }
    [self reloadVideos];
}

// ---------- 删除 ----------
- (void)confirmDelete:(NSInteger)item {
    if (item >= self.videos.count) return;
    NSString *name = self.videos[item];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
        message:@"删除该视频素材？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self deleteVideo:name];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteVideo:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:CCVVideoPathForName(name) error:nil];
    [fm removeItemAtPath:CCVThumbPathForVideoName(name) error:nil];
    if ([CCVSelectedVideoName() isEqualToString:name]) {
        [CCVPrefs() removeObjectForKey:CCVKeySelectedVideo];
        CCVPostDarwin(CCVDarwinSettingsChanged);
    }
    [self reloadVideos];
}

- (void)showAlert:(NSString *)msg title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// ---------- 导入（PHPicker，免相册权限） ----------
- (void)importTapped {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 0;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    __weak typeof(self) weakSelf = self;
    __block int imported = 0;
    dispatch_group_t group = dispatch_group_create();

    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) continue;

        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:@"public.movie"
            completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
            if (url && [weakSelf saveImportedVideoFromURL:url suggestedName:provider.suggestedName]) imported++;
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [weakSelf reloadVideos];
        NSString *msg = imported > 0
            ? [NSString stringWithFormat:@"已导入 %d 个视频到素材库", imported]
            : @"没有可导入的视频";
        [weakSelf showAlert:msg title:@"导入完成"];
    });
}

- (BOOL)saveImportedVideoFromURL:(NSURL *)tmpURL suggestedName:(NSString *)suggestedName {
    NSFileManager *fm = [NSFileManager defaultManager];
    CCVEnsureDirs();

    NSString *ext = tmpURL.pathExtension ?: @"mp4";
    if (ext.length == 0) ext = @"mp4";
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
    if (!dest) return NO;

    NSError *err = nil;
    if (![fm copyItemAtPath:tmpURL.path toPath:dest error:&err]) return NO;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:dest] options:nil];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(360, 360);
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
        gen.appliesPreferredTrackTransform = YES;
        gen.maximumSize = CGSizeMake(360, 360);
        CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.3, 600) actualTime:nil error:nil];
        if (img) {
            UIImage *thumb = [UIImage imageWithCGImage:img];
            CGImageRelease(img);
            [UIImagePNGRepresentation(thumb) writeToFile:CCVThumbPathForVideoName(name) atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.collectionView reloadData];
            });
        }
    });
}

@end
