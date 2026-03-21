# Agent Monitor — build, bundle, install
# Usage:
#   make build      — release build
#   make bundle     — build + assemble .app
#   make install    — bundle + run install.sh
#   make uninstall  — run uninstall.sh
#   make clean      — remove build artifacts
#   make dev        — swift run agm (debug)

SHELL := /bin/bash
.DEFAULT_GOAL := build

VERSION      := $(shell cat VERSION 2>/dev/null || echo 0.0.0)
INSTALL_PREFIX ?= $(HOME)/.agm
BUILD_DIR    := .build/release
APP_NAME     := Agent Monitor
APP_DIR      := build/$(APP_NAME).app

# ──────────────────────────────────────────────────────────

.PHONY: build bundle install uninstall clean dev sync-version

sync-version:
	@printf 'enum AppVersion {\n    static let string = "%s"\n}\n' "$(VERSION)" \
		> Sources/agm/AppVersion.swift

build: sync-version
	swift build -c release

bundle: build
	@echo "==> Assembling $(APP_NAME).app"
	@mkdir -p "$(APP_DIR)/Contents/MacOS"
	@mkdir -p "$(APP_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/agm" "$(APP_DIR)/Contents/MacOS/agm"
	sed 's/__VERSION__/$(VERSION)/g' packaging/Info.plist.template > "$(APP_DIR)/Contents/Info.plist"
	codesign --force --sign - --entitlements packaging/agm.entitlements "$(APP_DIR)"
	@echo "==> $(APP_DIR) ready (v$(VERSION))"

install: bundle
	bash install.sh --no-build

uninstall:
	bash uninstall.sh

clean:
	swift package clean
	rm -rf build/

dev: sync-version
	swift run agm
