#import "CCVideoLibraryViewController.h"
#import "CCVideoPrefs.h"

static NSString * const CCVCellID = @"CCVVideoCell";

#pragma mark - Cell

@interface CCVVideoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UILabel *videoTagLabel;
@end

@implementation CCVVideoCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.layer.cornerRadius = 14;
        self.contentView.clipsToBounds = YES;
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.93 alpha:1.0];

        _thumbView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        [self.contentView addSubview:_thumbView];

        _videoTagLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _videoTagLabel.text = @"视频";
        _videoTagLabel.font = [UIFont boldSystemFontOfSize:9];
        _videoTagLabel.textColor = [UIColor whiteColor];
        _videoTagLabel.textAlignment = NSTextAlignmentCenter;
        _videoTagLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _videoTagLabel.layer.cornerRadius = 8;
        _videoTagLabel.layer.masksToBounds = YES;
        [self.contentView addSubview:_videoTagLabel];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont systemFontOfSize:9];
        _nameLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.lineBreakMode = (NSLineBreakMode)UILineBreakModeMiddleTruncation;
        [self.contentView addSubview:_nameLabel];

        _dotView = [[UIView alloc] initWithFrame:CGRectZero];
        _dotView.layer.cornerRadius = 6;
        _dotView.layer.borderWidth = 1.5;
        _dotView.backgroundColor = [UIColor clearColor];
        _dotView.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
        [self.contentView addSubview:_dotView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    _thumbView.frame = CGRectMake(0, 0, w, w * 0.75);
    _videoTagLabel.frame = CGRectMake(8, 8, 30, 16);
    _nameLabel.frame = CGRectMake(4, w * 0.75 + 4, w - 8, 14);
    _dotView.frame = CGRectMake((w - 12) / 2.0, w * 0.75 + 22, 12, 12);
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected) {
        _dotView.backgroundColor = [UIColor systemBlueColor];
        _dotView.layer.borderColor = [UIColor systemBlueColor].CGColor;
    } else {
        _dotView.backgroundColor = [UIColor clearColor];
        _dotView.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
    }
}

@end

#pragma mark - Library

@interface CCVideoLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<NSString *> *videos;
@end

@implementation CCVideoLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"素材库";

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入"
        style:UIBarButtonItemStylePlain target:self action:@selector(importTapped)];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 14;
    layout.sectionInset = UIEdgeInsetsMake(14, 14, 30, 14);

    _collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:[CCVVideoCell class] forCellWithReuseIdentifier:CCVCellID];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [_collectionView addGestureRecognizer:lp];
    [self.view addSubview:_collectionView];

    CCVEnsureDirs();
    [self reloadVideos];
}

- (void)reloadVideos {
    self.videos = CCVVideoFileNames();
    [self.collectionView reloadData];
}

// ---------- 数据 ----------
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat w = (self.view.bounds.size.width - 14 * 2 - 12 * 2) / 3.0;
    return CGSizeMake(w, w * 0.75 + 42);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CCVVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CCVCellID forIndexPath:indexPath];
    NSString *name = self.videos[indexPath.item];
    cell.nameLabel.text = name;

    NSString *thumbPath = CCVThumbPathForVideoName(name);
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
        cell.thumbView.image = [UIImage imageWithContentsOfFile:thumbPath];
    } else {
        cell.thumbView.image = nil;
        [self generateThumbnailFor:name];
    }

    NSString *selected = CCVSelectedVideoName();
    cell.selected = [name isEqualToString:selected];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = self.videos[indexPath.item];
    [CCVPrefs() setObject:name forKey:CCVKeySelectedVideo];
    CCVPostDarwin(CCVDarwinSettingsChanged);
    [self.collectionView reloadData];
}

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    // 空实现占位
}

// ---------- 长按删除 ----------
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gr locationInView:self.collectionView];
    NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:p];
    if (!ip || ip.item >= self.videos.count) return;
    NSString *name = self.videos[ip.item];

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
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"导入完成"
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [weakSelf presentViewController:done animated:YES completion:nil];
    });
}

- (BOOL)saveImportedVideoFromURL:(NSURL *)tmpURL suggestedName:(NSString *)suggestedName {
    NSFileManager *fm = [NSFileManager defaultManager];
    CCVEnsureDirs();

    NSString *ext = tmpURL.pathExtension ?: @"mp4";
    if (ext.length == 0) ext = @"mp4";
    NSString *base = suggestedName.length ? suggestedName : @"导入视频";
    // 清理文件名里的非法字符
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

    // 同步生成缩略图（导入线程）
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:dest] options:nil];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(360, 360);
    NSError *imgErr = nil;
    CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.3, 600) actualTime:nil error:&imgErr];
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
        NSError *err = nil;
        CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.3, 600) actualTime:nil error:&err];
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
