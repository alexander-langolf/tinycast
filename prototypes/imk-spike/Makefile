ARCH := $(shell uname -m)
SDK := $(shell xcrun --show-sdk-path)
APP := build/Tinycast IMK Spike.app
EXECUTABLE := $(APP)/Contents/MacOS/TinycastIMKSpike
SIGN_IDENTITY ?= -

.PHONY: build sign

build:
	mkdir -p "$(APP)/Contents/MacOS"
	cp Info.plist "$(APP)/Contents/Info.plist"
	xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
		-target $(ARCH)-apple-macos26.0 -sdk "$(SDK)" \
		-framework AppKit -framework Carbon -framework InputMethodKit \
		IMKSpike.swift -o "$(EXECUTABLE)"

sign:
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
