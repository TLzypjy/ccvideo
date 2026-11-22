TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

# 控制中心模块 bundle（模块 1 常驻；模块 2~8 由 after-stage 打包进 PendingBundles）
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

# 生成待创建模块 CCVideo2~8.bundle：Info.plist 改编号 + 复制模块 1 的二进制，
# 装到 jbroot/Library/CCVideoPendingBundles/（SpringBoard root 在"创建模块"时拷入 ControlCenter/Bundles）。
# staging 树不含 install prefix（deb 打包时统一加 /var/jb）。
after-stage::
	$(ECHO_NOTHING)CCBIN="$(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/CCVideo.bundle"; \
	PEND="$(THEOS_STAGING_DIR)/Library/CCVideoPendingBundles"; \
	mkdir -p "$$PEND"; \
	for n in 2 3 4 5 6 7 8; do \
		d="$$PEND/CCVideo$$n.bundle"; \
		mkdir -p "$$d"; \
		sed -e "s|<string>com\.wuba\.ccvideo</string>|<string>com.wuba.ccvideo$$n</string>|" \
		    -e "s|<string>视频模块1</string>|<string>视频模块$$n</string>|" \
		    -e "s|<string>CCVideoModule</string>|<string>CCVideoModule$$n</string>|" \
		    "$$CCBIN/Info.plist" > "$$d/Info.plist" || exit 1; \
		cp "$$CCBIN/CCVideo" "$$d/CCVideo" || exit 1; \
	done$(ECHO_END)
