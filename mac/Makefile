# 組裝「九官鳥.app」：SwiftUI 前端＋內附 Python 語音服務。
#
#   make app       → build/九官鳥.app
#   make test      → swift test＋生命週期驗收
#   make install   → 裝到 ~/Applications
#   make dmg       → dist/Myna-<版本>.dmg（發布用）

APP     := build/九官鳥.app
INSTALL := $(HOME)/Applications/九官鳥.app
BIN      = $(shell swift build -c release --show-bin-path)/VoiceStudio

.PHONY: all app release install clean test dmg

all: app

release:
	swift build -c release

Resources/VoiceStudio.icns: scripts/make-icon.swift
	swift scripts/make-icon.swift $@

app: release Resources/VoiceStudio.icns
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/VoiceStudio"
	strip -S -x "$(APP)/Contents/MacOS/VoiceStudio"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/VoiceStudio.icns "$(APP)/Contents/Resources/"
	cp -R Resources/zh-Hant.lproj "$(APP)/Contents/Resources/"
	cp Resources/ThirdPartyLicenses.txt "$(APP)/Contents/Resources/"
	./scripts/bundle-backend.sh "$(APP)"
	@# 內附後端塞了上千個檔案，一定要在之後簽章，否則封印會壞
	codesign --force --deep --sign - "$(APP)"
	@codesign --verify --deep --strict "$(APP)" && echo "簽章驗證通過" || { echo "✗ 簽章驗證失敗"; exit 1; }

test:
	swift test
	./scripts/acceptance.sh

install: app
	rm -rf "$(INSTALL)"
	mkdir -p "$(HOME)/Applications"
	ditto "$(APP)" "$(INSTALL)"
	@echo "已安裝：$(INSTALL)"

dmg: app
	./scripts/make-dmg.sh "$(APP)"

clean:
	rm -rf build dist .build
