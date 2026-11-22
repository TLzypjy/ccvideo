#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CCVideoLibraryViewController : UIViewController
@property (nonatomic, assign) NSUInteger moduleIndex; // 默认 1；选中视频写对应模块的键
@end

NS_ASSUME_NONNULL_END
