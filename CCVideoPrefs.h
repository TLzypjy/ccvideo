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
FOUNDATION_EXPORT NSString * const CCVKeyAspectFill;    // 画面填充模式

// Darwin 通知
FOUNDATION_EXPORT NSString * const CCVDarwinSettingsChanged;                  // 本插件：设置变更
FOUNDATION_EXPORT NSString * const CCVDarwinReloadSizes;                      // CCSupport：重新上报模块尺寸

// ---------- 工具 ----------
NSUserDefaults *CCVPrefs(void);
void CCVEnsureDirs(void);
void CCVPostDarwin(NSString *name);
void CCVPostSizeChange(void);          // SettingsChanged + ReloadSizes

NSString *CCVSelectedVideoName(void);  // 可能为空
NSArray<NSString *> *CCVVideoFileNames(void); // 排序后的视频文件名列表
NSString *CCVThumbPathForVideoName(NSString *videoName);
NSString *CCVVideoPathForName(NSString *name);
void CCVClampSize(NSUInteger *w, NSUInteger *h); // 限制在 1..4，0 归 2

NS_ASSUME_NONNULL_END
