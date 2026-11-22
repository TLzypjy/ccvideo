#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIContentModuleContentViewController-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

@interface CCVideoContentViewController : UIViewController <CCUIContentModuleContentViewController>
@property (nonatomic, assign) NSUInteger moduleIndex; // 默认 1
@end

NS_ASSUME_NONNULL_END
