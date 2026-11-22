#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ---------- 常量 ----------
FOUNDATION_EXPORT NSString * const CCVBundleID;
FOUNDATION_EXPORT NSString * const CCVLibraryRoot;   // /var/mobile/Library/CCVideo
FOUNDATION_EXPORT NSString * const CCVVideoDir;      // .../Video
FOUNDATION_EXPORT NSString * const CCVThumbDir;      // .../Thumb

// 偏好键
FOUNDATION_EXPORT NSString * const CCVKeySelectedVideo; // 选中的视频文件名
FOUNDATION_EXPORT NSString * const CCVKeyPortraitW;     // 竖屏宽
FOUNDATION_EXPORT NSString * const CCVKeyPortraitH;     // 竖屏高
FOUNDATION_EXPORT NSString * const CCVKeyLandscapeW;    // 横屏宽
FOUNDATION_EXPORT NSString * const CCVKeyLandscapeH;    // 横屏高
FOUNDATION_EXPORT NSString * const CCVKeyAspectFill;    // 画面填充模式（旧版，仅迁移用）
FOUNDATION_EXPORT NSString * const CCVKeyDisplayMode;   // 显示模式 0=裁切填满 1=完整适应(模糊背景) 2=拉伸填满（全局，适用所有模块）
FOUNDATION_EXPORT NSString * const CCVKeyMaxModules;    // 已创建模块数（1~8）

// Darwin 通知
FOUNDATION_EXPORT NSString * const CCVDarwinSettingsChanged;                  // 本插件：设置变更
FOUNDATION_EXPORT NSString * const CCVDarwinReloadSizes;                      // CCSupport：重新上报模块尺寸

// ---------- 工具 ----------
NSUserDefaults *CCVPrefs(void);
void CCVEnsureDirs(void);
void CCVPostDarwin(NSString *name);
void CCVPostSizeChange(void);          // SettingsChanged + ReloadSizes

// ---------- 多模块 ----------
#define CCV_MAX_MODULES 8
NSUInteger CCVMaxModules(void);                          // 已创建模块数，1~8
void CCVSetMaxModules(NSUInteger n);
NSString *CCVKeyForModule(NSString *baseKey, NSUInteger moduleIndex); // 模块 1 = 原键（兼容旧数据）
NSInteger CCVDisplayMode(void);                          // 全局显示模式，0~2（自动从旧画面填充键迁移）
NSString *CCVSelectedVideoNameForModule(NSUInteger moduleIndex);
void CCVSetSelectedVideo(NSString *name, NSUInteger moduleIndex);
NSUInteger CCVSizeForModule(NSString *baseKey, NSUInteger moduleIndex); // 读取并钳位 1~4

NSString *CCVSelectedVideoName(void);  // 模块 1 便捷（可能为空）
NSArray<NSString *> *CCVVideoFileNames(void); // 排序后的视频文件名列表
NSString *CCVThumbPathForVideoName(NSString *videoName);
NSString *CCVVideoPathForName(NSString *name);
void CCVClampSize(NSUInteger *w, NSUInteger *h); // 限制在 1..4，0 归 2

NS_ASSUME_NONNULL_END
