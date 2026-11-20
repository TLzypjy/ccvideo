TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCVideo
CCVideo_BUNDLE_EXTENSION = bundle
CCVideo_FILES = CCVideoPrefs.m CCVideo.m CCVideoContentViewController.m CCVideoSettingsListController.m CCVideoLibraryViewController.m
CCVideo_CFLAGS = -fobjc-arc
CCVideo_FRAMEWORKS = UIKit AVFoundation PhotosUI CoreMedia
CCVideo_PRIVATE_FRAMEWORKS = ControlCenterUIKit Preferences
CCVideo_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk
