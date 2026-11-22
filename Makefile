include $(THEOS)/makefiles/common.mk

SUBPROJECTS += module prefs

include $(THEOS_MAKE_PATH)/aggregate.mk

# 生成待创建模块 CCVideo2~8.bundle：Info.plist 改编号 + 复制模块 1 的二进制，
# 装到 jbroot/Library/CCVideoPendingBundles/（SpringBoard root 的 CCVideoSBS tweak
# 在"创建模块"时拷入 ControlCenter/Bundles 并注销载入）。
# after-stage 必须在顶层 Makefile（子项目的 after-stage 不会被 toplevel stage 调用）。
# staging 树不含 install prefix（deb 打包时统一加 /var/jb）。
# 末尾 chmod 0777：把 ControlCenter/Bundles 目录做成 mobile 可写（SpringBoard 拷贝新模块用）。
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
	done; \
	chmod 0777 "$(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles"$(ECHO_END)
