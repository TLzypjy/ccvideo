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

// 多模块：每个 bundle 的 NSPrincipalClass 指向一个编号子类（CCVideoModule / CCVideoModule2~8），
// 编号决定读取哪组偏好键。全部逻辑在基类 CCVideoModuleBase。
@interface CCVideoModuleBase : NSObject <CCUIContentModule>
+ (NSUInteger)moduleIndex;
@end

@interface CCVideoModule : CCVideoModuleBase   // 模块 1（CCVideo.bundle）
@end
@interface CCVideoModule2 : CCVideoModuleBase
@end
@interface CCVideoModule3 : CCVideoModuleBase
@end
@interface CCVideoModule4 : CCVideoModuleBase
@end
@interface CCVideoModule5 : CCVideoModuleBase
@end
@interface CCVideoModule6 : CCVideoModuleBase
@end
@interface CCVideoModule7 : CCVideoModuleBase
@end
@interface CCVideoModule8 : CCVideoModuleBase
@end

NS_ASSUME_NONNULL_END
