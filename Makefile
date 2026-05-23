# Makefile — build & run ccgauge-bar as a proper .app bundle
#
# Usage:
#   make            — build release binary
#   make bundle     — package into build/CCGaugeBar.app
#   make run        — bundle + open the app (status item appears in menubar)
#   make debug      — debug build (faster compile, slower runtime)
#   make test       — run unit tests
#   make clean      — wipe .build/ and build/

APP_NAME      := CCGaugeBar
BUNDLE_DIR    := build/$(APP_NAME).app
RELEASE_BIN   := .build/release/$(APP_NAME)
DEBUG_BIN     := .build/debug/$(APP_NAME)
INFO_PLIST    := Info.plist
RESOURCE_DIR  := Resources

# Default target
.PHONY: all
all: build

# ─── Build ─────────────────────────────────────────────────────────────
.PHONY: build
build:
	swift build -c release

.PHONY: debug
debug:
	swift build -c debug

# ─── Bundle into .app ──────────────────────────────────────────────────
# SwiftPM produces a bare executable; we wrap it into the standard
# .app/Contents/{MacOS,Resources} layout macOS expects for menubar apps.
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
	@if [ -d ".build/release/$(APP_NAME)_CCGaugeBar.bundle" ]; then \
		cp -R ".build/release/$(APP_NAME)_CCGaugeBar.bundle" "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@codesign --force --deep --sign - "$(BUNDLE_DIR)" 2>/dev/null || true
	@echo "==> Built $(BUNDLE_DIR)"

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
	@echo "  build       — release binary in .build/release/"
	@echo "  bundle      — wrap into build/CCGaugeBar.app"
	@echo "  run         — bundle + open (foreground)"
	@echo "  run-debug   — debug binary, runs attached so logs show in terminal"
	@echo "  test        — swift test"
	@echo "  clean       — wipe build artifacts"
