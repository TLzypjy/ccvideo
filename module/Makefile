TARGET := iphone:clang:latest:14.0
# 诊断版：不再主动 kill SpringBoard（避免安装动作本身触发启动期崩溃），只重启设置进程
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

# 控制中心模块 bundle（模块 1 常驻；模块 2~8 由根 Makefile 的 after-stage 打包进 PendingBundles）
BUNDLE_NAME = CCVideo
CCVideo_BUNDLE_EXTENSION = bundle
CCVideo_FILES = CCVideoPrefs.m CCVideo.m CCVideoContentViewController.m CCVideoSettingsListController.m CCVideoLibraryViewController.m
CCVideo_CFLAGS = -fobjc-arc
CCVideo_FRAMEWORKS = UIKit AVFoundation PhotosUI CoreMedia
CCVideo_PRIVATE_FRAMEWORKS = ControlCenterUIKit Preferences
CCVideo_INSTALL_PATH = /Library/ControlCenter/Bundles/

# v0.1.31 诊断版：移除注入 SpringBoard 的 CCVideoSBS tweak（排查 SpringBoard 安全模式）
# 创建/删除模块的 bundle 同步改由设置页 CCVSyncPendingBundles 独立完成（此前实测已可用，
# 且 deb 的 postinst 已把 ControlCenter/Bundles 放开为 0777，mobile 可写）。
# 旧版残留的 CCVideoSBS.dylib/.plist 由 layout/DEBIAN/postinst 清理。
include $(THEOS_MAKE_PATH)/bundle.mk
