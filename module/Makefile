TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

# 控制中心模块 bundle（模块 1 常驻；模块 2~8 由根 Makefile 的 after-stage 打包进 PendingBundles）
BUNDLE_NAME = CCVideo
CCVideo_BUNDLE_EXTENSION = bundle
CCVideo_FILES = CCVideoPrefs.m CCVideo.m CCVideoContentViewController.m CCVideoSettingsListController.m CCVideoLibraryViewController.m
CCVideo_CFLAGS = -fobjc-arc
CCVideo_FRAMEWORKS = UIKit AVFoundation PhotosUI CoreMedia
CCVideo_PRIVATE_FRAMEWORKS = ControlCenterUIKit Preferences
CCVideo_INSTALL_PATH = /Library/ControlCenter/Bundles/

# SpringBoard 助手 tweak：创建模块时拷贝 bundle 并注销
TWEAK_NAME = CCVideoSBS
CCVideoSBS_FILES = CCVideoSBS.m
CCVideoSBS_CFLAGS = -fobjc-arc
CCVideoSBS_FRAMEWORKS = Foundation
CCVideoSBS_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tweak.mk
