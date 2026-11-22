#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

NS_ASSUME_NONNULL_BEGIN

// 主页：视频模块1~N 列表（黑字）+ 创建模块（蓝字，最多 8 个）
@interface CCVideoSettingsListController : PSListController
@end

// 子页：单个模块的设置（素材库 / 模块尺寸 / 播放），键带模块编号
@interface CCVideoModuleListController : PSListController
@property (nonatomic, assign) NSUInteger moduleIndex; // 默认 1
@end

NS_ASSUME_NONNULL_END
