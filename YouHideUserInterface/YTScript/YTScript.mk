#
# YTScript.mk
# Automatic YTScript preprocessing for Theos
#

YTSCRIPT_PATH := $(THEOS_PROJECT_DIR)/YTScript

YTSCRIPT_COMPILER := $(YTSCRIPT_PATH)/YTScriptCompiler.py

YT_XM_FILES := $(wildcard *.xm)
YT_PROCESSED_FILES := $(YT_XM_FILES:.xm=.processed.xm)

before-all::

	@echo "[YTScript] Running preprocessor..."
	@python3 "$(YTSCRIPT_COMPILER)"

clean::

	@echo "[YTScript] Cleaning generated files..."
	@rm -f $(YT_PROCESSED_FILES)

$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)
