TARGET := iphone:clang:16.5:14.0
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouCast
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation SystemConfiguration AVFoundation AVKit MediaPlayer QuartzCore
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unused-function "-I." "-I../../YouTubeHeader" "-I../../"
$(TWEAK_NAME)_FILES = YouCast.x
$(TWEAK_NAME)_LDFLAGS = -weak_framework AVFoundation -weak_framework AVKit -weak_framework MediaPlayer

include $(THEOS_MAKE_PATH)/tweak.mk
