TARGET := iphone:clang:16.5:14.0
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReoFix
ReoFix_FILES = Tweak.x
ReoFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += reofixprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
