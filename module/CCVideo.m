#import "CCVideo.h"
#import "CCVideoPrefs.h"
#import "CCVideoContentViewController.h"

@implementation CCVideoModuleBase
{
    CCVideoContentViewController *_contentVC;
}

+ (NSUInteger)moduleIndex { return 1; }

- (instancetype)init {
    if (self = [super init]) {
        _contentVC = [[CCVideoContentViewController alloc] initWithNibName:nil bundle:nil];
        _contentVC.moduleIndex = [[self class] moduleIndex];
    }
    return self;
}

- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController {
    return _contentVC;
}

- (UIViewController *)backgroundViewController {
    return nil;
}

// CCSupport 运行时动态尺寸：竖屏 orientation == 0，横屏 == 1
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation {
    NSUInteger idx = [[self class] moduleIndex];
    NSUInteger w, h;
    if (orientation == 0) {
        w = CCVSizeForModule(CCVKeyPortraitW, idx);
        h = CCVSizeForModule(CCVKeyPortraitH, idx);
    } else {
        w = CCVSizeForModule(CCVKeyLandscapeW, idx);
        h = CCVSizeForModule(CCVKeyLandscapeH, idx);
    }
    CCUILayoutSize size;
    size.width = w;
    size.height = h;
    return size;
}

@end

@implementation CCVideoModule
+ (NSUInteger)moduleIndex { return 1; }
@end
@implementation CCVideoModule2
+ (NSUInteger)moduleIndex { return 2; }
@end
@implementation CCVideoModule3
+ (NSUInteger)moduleIndex { return 3; }
@end
@implementation CCVideoModule4
+ (NSUInteger)moduleIndex { return 4; }
@end
@implementation CCVideoModule5
+ (NSUInteger)moduleIndex { return 5; }
@end
@implementation CCVideoModule6
+ (NSUInteger)moduleIndex { return 6; }
@end
@implementation CCVideoModule7
+ (NSUInteger)moduleIndex { return 7; }
@end
@implementation CCVideoModule8
+ (NSUInteger)moduleIndex { return 8; }
@end
