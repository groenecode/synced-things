# SyncThings — build & run helpers
#
# Usage:
#   make run        Build + run in the iPhone 17 Simulator
#   make device     Build + run on a cabled iPhone (needs DEV_TEAM)
#   make mac        Build + run as a native macOS app
#   make generate   Regenerate the Xcode project (tuist install + generate)
#   make clean      Remove build outputs
#
# Overridable on the command line, e.g.  make run SIMULATOR='iPhone 17 Pro'

# Use bash with pipefail so a failed xcodebuild propagates through the
# `| xcbeautify` pipe instead of being masked by the formatter's exit code.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

WORKSPACE  := SyncThings.xcworkspace
SCHEME     := SyncThings
CONFIG     := Debug
BUNDLE_ID  := studio.groeneveld.SyncThings
SIMULATOR  ?= iPhone 17
DERIVED    := .build/DerivedData

# Machine-specific settings (DEV_TEAM, …). Gitignored; optional.
-include Local.mk

# Pipe xcodebuild through xcbeautify when available; otherwise pass through raw.
ifneq ($(shell command -v xcbeautify 2>/dev/null),)
  FORMAT := | xcbeautify
else
  FORMAT :=
endif

# The build environment occasionally has CC=gcc-15 exported, which breaks
# xcodebuild. Neutralize it for everything this Makefile runs.
unexport CC

# Built product locations (derived from the pinned derivedDataPath).
SIM_APP    := $(DERIVED)/Build/Products/$(CONFIG)-iphonesimulator/$(SCHEME).app
DEVICE_APP := $(DERIVED)/Build/Products/$(CONFIG)-iphoneos/$(SCHEME).app
MAC_APP    := $(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app

XCODEBUILD := xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) \
              -configuration $(CONFIG) -derivedDataPath $(DERIVED)

# CoreDevice identifier of the connected iPhone (override with DEVICE=…).
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | grep -w connected \
            | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
            | head -1)

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Project generation (only runs when the workspace is missing)
# ---------------------------------------------------------------------------
$(WORKSPACE):
	tuist install
	tuist generate --no-open

.PHONY: generate
generate:
	tuist install
	tuist generate --no-open

# ---------------------------------------------------------------------------
# Simulator (iPhone 17)
# ---------------------------------------------------------------------------
.PHONY: build-sim run run-sim
build-sim: $(WORKSPACE)
	$(XCODEBUILD) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		CODE_SIGNING_ALLOWED=NO build $(FORMAT)

run run-sim: build-sim
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted '$(SIM_APP)'
	xcrun simctl launch booted $(BUNDLE_ID)

# ---------------------------------------------------------------------------
# Cabled device
# ---------------------------------------------------------------------------
.PHONY: build-device device run-device
build-device: $(WORKSPACE) check-team
	$(XCODEBUILD) -destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(DEV_TEAM) CODE_SIGN_STYLE=Automatic build $(FORMAT)

device run-device: build-device
	@test -n "$(DEVICE)" || { echo "No connected device found. Plug one in or pass DEVICE=<id|name>."; exit 1; }
	xcrun devicectl device install app --device '$(DEVICE)' '$(DEVICE_APP)'
	xcrun devicectl device process launch --terminate-existing --device '$(DEVICE)' $(BUNDLE_ID)

# ---------------------------------------------------------------------------
# Native macOS
# ---------------------------------------------------------------------------
# Signs with DEV_TEAM when available (needed for iCloud to work); otherwise
# builds unsigned so it still compiles.
.PHONY: build-mac mac run-mac
build-mac: $(WORKSPACE)
ifeq ($(strip $(DEV_TEAM)),)
	$(XCODEBUILD) -destination 'platform=macOS,arch=arm64' \
		CODE_SIGNING_ALLOWED=NO build $(FORMAT)
else
	$(XCODEBUILD) -destination 'platform=macOS,arch=arm64' \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(DEV_TEAM) CODE_SIGN_STYLE=Automatic build $(FORMAT)
endif

mac run-mac: build-mac
	open '$(MAC_APP)'

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------
.PHONY: clean check-team help
clean:
	rm -rf $(DERIVED)

check-team:
	@test -n "$(strip $(DEV_TEAM))" || { \
		echo "DEV_TEAM is not set. Add it to Local.mk, e.g.:"; \
		echo "    echo 'DEV_TEAM = XXXXXXXXXX' >> Local.mk"; \
		exit 1; }

help:
	@echo "Targets:"
	@echo "  make run       Build + run in the $(SIMULATOR) Simulator"
	@echo "  make device    Build + run on a cabled iPhone (DEV_TEAM required)"
	@echo "  make mac       Build + run as a native macOS app"
	@echo "  make generate  Regenerate the Xcode project"
	@echo "  make clean     Remove build outputs ($(DERIVED))"
