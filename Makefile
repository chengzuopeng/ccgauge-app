# Makefile — build & run ccgauge-bar as a proper .app bundle
#
# Usage:
#   make            — universal release binary (arm64 + x86_64)
#   make bundle     — package into build/CCGaugeBar.app (with icon + hardened runtime)
#   make run        — bundle + open the app (status item appears in menubar)
#   make debug      — debug build (current host arch only, faster compile)
#   make run-debug  — debug binary, runs attached so logs show in terminal
#   make test       — run unit tests
#   make icon       — regenerate Resources/AppIcon.icns from the Swift renderer
#   make clean      — wipe .build/ and build/

APP_NAME      := CCGaugeBar
BUNDLE_DIR    := build/$(APP_NAME).app
# Universal builds land under .build/apple/Products/Release; debug builds
# stay at .build/debug for the current host arch.
RELEASE_BIN   := .build/apple/Products/Release/$(APP_NAME)
DEBUG_BIN     := .build/debug/$(APP_NAME)
INFO_PLIST    := Info.plist
RESOURCE_DIR  := Resources

# Default target
.PHONY: all
all: build

# ─── Build ─────────────────────────────────────────────────────────────
# Universal binary (Apple Silicon + Intel). Output goes to
# .build/apple/Products/Release/$(APP_NAME) — different from the single-arch
# .build/release/ path that swift defaults to.
.PHONY: build
build:
	swift build -c release --arch arm64 --arch x86_64

# Single-arch debug for fast iteration on the dev machine.
.PHONY: debug
debug:
	swift build -c debug

# ─── Bundle into .app ──────────────────────────────────────────────────
# SwiftPM produces a bare executable; we wrap it into the standard
# .app/Contents/{MacOS,Resources} layout macOS expects for menubar apps.
#
# Hardened runtime (--options runtime) is required for future notarization
# and silences the "unverified developer" warning some macOS versions
# show on ad-hoc-signed apps. We don't ship JIT or DYLD injection, so no
# runtime exceptions / entitlements are needed.
.PHONY: bundle
bundle: build
	@echo "==> Packaging $(BUNDLE_DIR)"
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(RELEASE_BIN)" "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	@cp "$(INFO_PLIST)" "$(BUNDLE_DIR)/Contents/Info.plist"
	@if [ -d "$(RESOURCE_DIR)" ]; then \
		cp -R "$(RESOURCE_DIR)"/* "$(BUNDLE_DIR)/Contents/Resources/" 2>/dev/null || true; \
	fi
	@# SwiftPM copies the resources bundle next to the binary; move it inside the .app
	@if [ -d ".build/apple/Products/Release/$(APP_NAME)_CCGaugeBar.bundle" ]; then \
		cp -R ".build/apple/Products/Release/$(APP_NAME)_CCGaugeBar.bundle" "$(BUNDLE_DIR)/Contents/Resources/"; \
	elif [ -d ".build/release/$(APP_NAME)_CCGaugeBar.bundle" ]; then \
		cp -R ".build/release/$(APP_NAME)_CCGaugeBar.bundle" "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@codesign --force --deep --options runtime --sign - "$(BUNDLE_DIR)" 2>/dev/null || true
	@echo "==> Built $(BUNDLE_DIR)"
	@file "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" | sed 's/^/    /'

# ─── Run ───────────────────────────────────────────────────────────────
.PHONY: run
run: bundle
	@# Kill any existing instance so we always launch the fresh build.
	@pkill -f "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@open "$(BUNDLE_DIR)"
	@echo "==> Launched. Look for the gauge icon in your menubar."

# Run unbundled — useful for tailing logs during dev.
.PHONY: run-debug
run-debug: debug
	@pkill -f "$(DEBUG_BIN)" 2>/dev/null || true
	@"$(DEBUG_BIN)"

# ─── Test ──────────────────────────────────────────────────────────────
.PHONY: test
test:
	swift test

# ─── App icon ──────────────────────────────────────────────────────────
# Regenerate Resources/AppIcon.icns from the Swift renderer. Only needs to
# run when the icon design changes — the produced .icns is committed to
# the repo so cold checkouts can build immediately.
ICON_SRC      := Tools/generate-app-icon.swift
ICON_PNG      := build/AppIcon-1024.png
ICON_SET      := build/AppIcon.iconset
ICON_OUT      := $(RESOURCE_DIR)/AppIcon.icns

.PHONY: icon
icon:
	@echo "==> Rendering $(ICON_PNG)"
	@mkdir -p build "$(RESOURCE_DIR)"
	@swift "$(ICON_SRC)" "$(ICON_PNG)"
	@echo "==> Building $(ICON_SET)"
	@rm -rf "$(ICON_SET)"
	@mkdir -p "$(ICON_SET)"
	@sips -z 16 16     "$(ICON_PNG)" --out "$(ICON_SET)/icon_16x16.png"       >/dev/null
	@sips -z 32 32     "$(ICON_PNG)" --out "$(ICON_SET)/icon_16x16@2x.png"    >/dev/null
	@sips -z 32 32     "$(ICON_PNG)" --out "$(ICON_SET)/icon_32x32.png"       >/dev/null
	@sips -z 64 64     "$(ICON_PNG)" --out "$(ICON_SET)/icon_32x32@2x.png"    >/dev/null
	@sips -z 128 128   "$(ICON_PNG)" --out "$(ICON_SET)/icon_128x128.png"     >/dev/null
	@sips -z 256 256   "$(ICON_PNG)" --out "$(ICON_SET)/icon_128x128@2x.png"  >/dev/null
	@sips -z 256 256   "$(ICON_PNG)" --out "$(ICON_SET)/icon_256x256.png"     >/dev/null
	@sips -z 512 512   "$(ICON_PNG)" --out "$(ICON_SET)/icon_256x256@2x.png"  >/dev/null
	@sips -z 512 512   "$(ICON_PNG)" --out "$(ICON_SET)/icon_512x512.png"     >/dev/null
	@cp "$(ICON_PNG)" "$(ICON_SET)/icon_512x512@2x.png"
	@iconutil -c icns -o "$(ICON_OUT)" "$(ICON_SET)"
	@echo "==> Wrote $(ICON_OUT) ($$(du -h "$(ICON_OUT)" | cut -f1))"

# ─── DMG installer ────────────────────────────────────────────────────
# Wrap the .app into a drag-to-install disk image. Uses macOS-stock
# `hdiutil` so there's no Homebrew dependency. Layout inside the mounted
# DMG is the conventional "App + alias to /Applications" pair.
#
# Output filename embeds the version from Info.plist so successive
# builds don't clobber each other.
DMG_VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(INFO_PLIST))
DMG_VOLNAME  := ccgauge-bar
DMG_STAGE    := build/dmg-staging
DMG_OUT      := build/ccgauge-bar-$(DMG_VERSION).dmg

.PHONY: dmg
dmg: bundle
	@echo "==> Staging DMG layout (v$(DMG_VERSION))"
	@rm -rf "$(DMG_STAGE)" "$(DMG_OUT)"
	@mkdir -p "$(DMG_STAGE)"
	@cp -R "$(BUNDLE_DIR)" "$(DMG_STAGE)/"
	@# Drag-to-install alias. ln -s creates a relative symlink that the
	@# Finder resolves to the user's /Applications when the DMG mounts.
	@ln -s /Applications "$(DMG_STAGE)/Applications"
	@echo "==> Creating $(DMG_OUT)"
	@hdiutil create \
		-volname "$(DMG_VOLNAME)" \
		-srcfolder "$(DMG_STAGE)" \
		-ov \
		-format UDZO \
		-fs HFS+ \
		"$(DMG_OUT)" >/dev/null
	@rm -rf "$(DMG_STAGE)"
	@echo "==> Built $(DMG_OUT) ($$(du -h "$(DMG_OUT)" | cut -f1))"

# ─── Clean ─────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	rm -rf .build build

# ─── Format / Lint ─────────────────────────────────────────────────────
# Optional: requires swift-format from Apple (https://github.com/apple/swift-format)
.PHONY: format
format:
	@command -v swift-format >/dev/null 2>&1 && \
		find Sources Tests -name '*.swift' -print0 | xargs -0 swift-format -i || \
		echo "swift-format not installed; skipping"

.PHONY: help
help:
	@echo "Targets:"
	@echo "  build       — universal release binary (arm64 + x86_64)"
	@echo "  bundle      — wrap into build/CCGaugeBar.app + icon + hardened runtime"
	@echo "  run         — bundle + open (foreground)"
	@echo "  debug       — debug build (current host arch only)"
	@echo "  run-debug   — debug binary, runs attached so logs show in terminal"
	@echo "  test        — swift test"
	@echo "  icon        — regenerate Resources/AppIcon.icns"
	@echo "  dmg         — build a drag-to-install .dmg installer"
	@echo "  clean       — wipe build artifacts"
