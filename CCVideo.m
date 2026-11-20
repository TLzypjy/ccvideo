#import "CCVideo.h"
#import "CCVideoPrefs.h"
#import "CCVideoContentViewController.h"

@interface CCVideoModule ()
@property (nonatomic, strong) CCVideoContentViewController *contentVC;
@end

@implementation CCVideoModule

- (instancetype)init {
    if (self = [super init]) {
        _contentVC = [[CCVideoContentViewController alloc] initWithNibName:nil bundle:nil];
    }
    return self;
}

- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController {
    return self.contentVC;
}

- (UIViewController *)backgroundViewController {
    return nil;
}

// CCSupport 运行时动态尺寸：竖屏 orientation == 0，横屏 == 1
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation {
    NSUserDefaults *p = CCVPrefs();
    NSUInteger w, h;
    if (orientation == 0) {
        w = (NSUInteger)[p integerForKey:CCVKeyPortraitW];
        h = (NSUInteger)[p integerForKey:CCVKeyPortraitH];
    } else {
        w = (NSUInteger)[p integerForKey:CCVKeyLandscapeW];
        h = (NSUInteger)[p integerForKey:CCVKeyLandscapeH];
    }
    CCVClampSize(&w, &h);
    CCUILayoutSize size;
    size.width = w;
    size.height = h;
    return size;
}

@end
