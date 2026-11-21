TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCVideoPrefs
CCVideoPrefs_FILES = ../module/CCVideoPrefs.m ../module/CCVideoSettingsListController.m ../module/CCVideoLibraryViewController.m
CCVideoPrefs_CFLAGS = -fobjc-arc
CCVideoPrefs_FRAMEWORKS = UIKit AVFoundation PhotosUI CoreMedia
CCVideoPrefs_PRIVATE_FRAMEWORKS = Preferences
CCVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
