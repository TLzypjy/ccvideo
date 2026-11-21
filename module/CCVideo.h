#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/ControlCenterUIKit.h>

// CCUILayoutSize 来自 ControlCenterUI（theos 头文件不带），本地按真实 ABI 定义
#if __has_include(<ControlCenterUI/ControlCenterUI.h>)
#import <ControlCenterUI/ControlCenterUI.h>
#else
typedef struct CCUILayoutSize {
    NSUInteger width;
    NSUInteger height;
} CCUILayoutSize;
#endif

NS_ASSUME_NONNULL_BEGIN

@interface CCVideoModule : NSObject <CCUIContentModule>
@end

NS_ASSUME_NONNULL_END
