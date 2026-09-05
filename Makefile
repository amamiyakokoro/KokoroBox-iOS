SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.SILENT:

APPLICATION_SIGN_IDENTITY := 34EED4C8F8E609CD5D253D88202A071521D1BE74
INSTALLER_SIGN_IDENTITY := 21E03A44ACC2B48753BABB3DAE9B5F9A9CFF0480
XCODEBUILD_FLAGS ?= -skipPackagePluginValidation
export DISABLE_SWIFTLINT := 1

build_all: build_ios build_macos

build_ios_deb:
	bash Jailbreak/package.sh

build_ios:
	xcodebuild build $(XCODEBUILD_FLAGS) -scheme KokoroBoxI -configuration Debug -destination 'generic/platform=iOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_macos:
	xcodebuild build $(XCODEBUILD_FLAGS) -scheme KokoroBoxM -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_macos_standalone:
	xcodebuild build $(XCODEBUILD_FLAGS) -scheme SFM.System -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

release: release_ios release_macos

release_ios: archive_ios upload_ios

archive_ios:
	rm -rf build/KokoroBoxI.xcarchive
	xcodebuild archive $(XCODEBUILD_FLAGS) -scheme KokoroBoxI -configuration Release -destination 'generic/platform=iOS' -archivePath build/KokoroBoxI.xcarchive | xcbeautify

upload_ios:
	xcodebuild -exportArchive -archivePath build/KokoroBoxI.xcarchive -exportOptionsPlist SFI/Upload.plist

release_macos: archive_macos upload_macos

archive_macos:
	rm -rf build/KokoroBoxM.xcarchive
	xcodebuild archive $(XCODEBUILD_FLAGS) -scheme KokoroBoxM -configuration Release -archivePath build/KokoroBoxM.xcarchive | xcbeautify

upload_macos:
	xcodebuild -exportArchive -archivePath build/KokoroBoxM.xcarchive -exportOptionsPlist SFI/Upload.plist

release_macos_standalone: release_macos_dmg release_macos_pkg

# Archive commands
archive_macos_standalone_apple:
	rm -rf build/SFM.System-arm64.xcarchive
	xcodebuild archive $(XCODEBUILD_FLAGS) -scheme SFM.System -configuration Release -archivePath build/SFM.System-arm64.xcarchive -derivedDataPath build/SFM.System-arm64.dd ARCHS=arm64 | xcbeautify

archive_macos_standalone_intel:
	rm -rf build/SFM.System-x86_64.xcarchive
	xcodebuild archive $(XCODEBUILD_FLAGS) -scheme SFM.System -configuration Release -archivePath build/SFM.System-x86_64.xcarchive -derivedDataPath build/SFM.System-x86_64.dd ARCHS=x86_64 | xcbeautify

archive_macos_standalone_universal:
	rm -rf build/SFM.System-universal.xcarchive
	xcodebuild archive $(XCODEBUILD_FLAGS) -scheme SFM.System -configuration Release -archivePath build/SFM.System-universal.xcarchive -derivedDataPath build/SFM.System-universal.dd | xcbeautify

archive_macos_standalone: archive_macos_standalone_apple archive_macos_standalone_intel archive_macos_standalone_universal

# Export commands
export_macos_standalone_apple:
	rm -rf build/SFM.System-arm64
	xcodebuild -exportArchive -archivePath build/SFM.System-arm64.xcarchive -exportOptionsPlist SFM.System/Export.plist -exportPath build/SFM.System-arm64

export_macos_standalone_intel:
	rm -rf build/SFM.System-x86_64
	xcodebuild -exportArchive -archivePath build/SFM.System-x86_64.xcarchive -exportOptionsPlist SFM.System/Export.plist -exportPath build/SFM.System-x86_64

export_macos_standalone_universal:
	rm -rf build/SFM.System-universal
	xcodebuild -exportArchive -archivePath build/SFM.System-universal.xcarchive -exportOptionsPlist SFM.System/Export.plist -exportPath build/SFM.System-universal

# DMG commands
build_macos_dmg_apple: archive_macos_standalone_apple export_macos_standalone_apple
	rm -f build/KokoroBoxM-Apple.dmg
	create-dmg \
		--volname "KokoroBoxM" \
		--volicon "build/SFM.System-arm64/KokoroBoxM.app/Contents/Resources/AppIcon.icns" \
		--icon "KokoroBoxM.app" 0 0 \
		--hide-extension "KokoroBoxM.app" \
		--app-drop-link 0 0 \
		--skip-jenkins \
		"build/KokoroBoxM-Apple.dmg" "build/SFM.System-arm64/KokoroBoxM.app"

build_macos_dmg_intel: archive_macos_standalone_intel export_macos_standalone_intel
	rm -f build/KokoroBoxM-Intel.dmg
	create-dmg \
		--volname "KokoroBoxM" \
		--volicon "build/SFM.System-x86_64/KokoroBoxM.app/Contents/Resources/AppIcon.icns" \
		--icon "KokoroBoxM.app" 0 0 \
		--hide-extension "KokoroBoxM.app" \
		--app-drop-link 0 0 \
		--skip-jenkins \
		"build/KokoroBoxM-Intel.dmg" "build/SFM.System-x86_64/KokoroBoxM.app"

build_macos_dmg_universal: archive_macos_standalone_universal export_macos_standalone_universal
	rm -f build/KokoroBoxM-Universal.dmg
	create-dmg \
		--volname "KokoroBoxM" \
		--volicon "build/SFM.System-universal/KokoroBoxM.app/Contents/Resources/AppIcon.icns" \
		--icon "KokoroBoxM.app" 0 0 \
		--hide-extension "KokoroBoxM.app" \
		--app-drop-link 0 0 \
		--skip-jenkins \
		"build/KokoroBoxM-Universal.dmg" "build/SFM.System-universal/KokoroBoxM.app"

build_macos_dmg: build_macos_dmg_apple build_macos_dmg_intel build_macos_dmg_universal

# DMG notarize commands
notarize_macos_dmg_apple:
	xcrun notarytool submit "build/KokoroBoxM-Apple.dmg" --wait --keychain-profile "notarytool-password"
	xcrun stapler staple "build/KokoroBoxM-Apple.dmg"

notarize_macos_dmg_intel:
	xcrun notarytool submit "build/KokoroBoxM-Intel.dmg" --wait --keychain-profile "notarytool-password"
	xcrun stapler staple "build/KokoroBoxM-Intel.dmg"

notarize_macos_dmg_universal:
	xcrun notarytool submit "build/KokoroBoxM-Universal.dmg" --wait --keychain-profile "notarytool-password"
	xcrun stapler staple "build/KokoroBoxM-Universal.dmg"

notarize_macos_dmg: notarize_macos_dmg_apple notarize_macos_dmg_intel notarize_macos_dmg_universal

# DMG release commands
release_macos_dmg_apple: build_macos_dmg_apple notarize_macos_dmg_apple
release_macos_dmg_intel: build_macos_dmg_intel notarize_macos_dmg_intel
release_macos_dmg_universal: build_macos_dmg_universal notarize_macos_dmg_universal
release_macos_dmg: release_macos_dmg_apple release_macos_dmg_intel release_macos_dmg_universal

# PKG commands
build_macos_pkg_apple: archive_macos_standalone_apple export_macos_standalone_apple
	rm -f build/KokoroBoxM-Apple.pkg
	rm -rf build/pkgroot-arm64
	mkdir -p build/pkgroot-arm64
	ditto "build/SFM.System-arm64/KokoroBoxM.app" "build/pkgroot-arm64/KokoroBoxM.app"
	pkgbuild --root "build/pkgroot-arm64" \
		--component-plist SFM.System/component.plist \
		--identifier com.amamiyakokoro.box.standalone \
		--install-location /Applications \
		--min-os-version 13.0 \
		--compression latest \
		build/component-arm64.pkg
	productbuild --distribution SFM.System/distribution-arm64.xml \
		--package-path build \
		--resources SFM.System/Resources \
		--sign "$(INSTALLER_SIGN_IDENTITY)" \
		build/KokoroBoxM-Apple.pkg
	rm -rf build/pkgroot-arm64
	rm -f build/component-arm64.pkg

build_macos_pkg_intel: archive_macos_standalone_intel export_macos_standalone_intel
	rm -f build/KokoroBoxM-Intel.pkg
	rm -rf build/pkgroot-x86_64
	mkdir -p build/pkgroot-x86_64
	ditto "build/SFM.System-x86_64/KokoroBoxM.app" "build/pkgroot-x86_64/KokoroBoxM.app"
	pkgbuild --root "build/pkgroot-x86_64" \
		--component-plist SFM.System/component.plist \
		--identifier com.amamiyakokoro.box.standalone \
		--install-location /Applications \
		--min-os-version 13.0 \
		--compression latest \
		build/component-x86_64.pkg
	productbuild --distribution SFM.System/distribution-x86_64.xml \
		--package-path build \
		--resources SFM.System/Resources \
		--sign "$(INSTALLER_SIGN_IDENTITY)" \
		build/KokoroBoxM-Intel.pkg
	rm -rf build/pkgroot-x86_64
	rm -f build/component-x86_64.pkg

build_macos_pkg_universal: archive_macos_standalone_universal export_macos_standalone_universal
	rm -f build/KokoroBoxM-Universal.pkg
	rm -rf build/pkgroot-universal
	mkdir -p build/pkgroot-universal
	ditto "build/SFM.System-universal/KokoroBoxM.app" "build/pkgroot-universal/KokoroBoxM.app"
	pkgbuild --root "build/pkgroot-universal" \
		--component-plist SFM.System/component.plist \
		--identifier com.amamiyakokoro.box.standalone \
		--install-location /Applications \
		--min-os-version 13.0 \
		--compression latest \
		build/component-universal.pkg
	productbuild --distribution SFM.System/distribution-universal.xml \
		--package-path build \
		--resources SFM.System/Resources \
		--sign "$(INSTALLER_SIGN_IDENTITY)" \
		build/KokoroBoxM-Universal.pkg
	rm -rf build/pkgroot-universal
	rm -f build/component-universal.pkg

build_macos_pkg: build_macos_pkg_apple build_macos_pkg_intel build_macos_pkg_universal

build_macos_pkg_all: archive_macos_standalone_universal export_macos_standalone_universal
	APPLICATION_SIGN_IDENTITY="$(APPLICATION_SIGN_IDENTITY)" INSTALLER_SIGN_IDENTITY="$(INSTALLER_SIGN_IDENTITY)" bash SFM.System/package_from_universal.sh

# PKG notarize commands
notarize_macos_pkg_apple:
	xcrun notarytool submit build/KokoroBoxM-Apple.pkg --wait --keychain-profile "notarytool-password"
	xcrun stapler staple build/KokoroBoxM-Apple.pkg

notarize_macos_pkg_intel:
	xcrun notarytool submit build/KokoroBoxM-Intel.pkg --wait --keychain-profile "notarytool-password"
	xcrun stapler staple build/KokoroBoxM-Intel.pkg

notarize_macos_pkg_universal:
	xcrun notarytool submit build/KokoroBoxM-Universal.pkg --wait --keychain-profile "notarytool-password"
	xcrun stapler staple build/KokoroBoxM-Universal.pkg

notarize_macos_pkg: notarize_macos_pkg_apple notarize_macos_pkg_intel notarize_macos_pkg_universal

notarize_macos_pkg_all:
	set -e; \
	xcrun notarytool submit build/KokoroBoxM-Apple.pkg --wait --keychain-profile "notarytool-password" & apple_pid=$$!; \
	xcrun notarytool submit build/KokoroBoxM-Intel.pkg --wait --keychain-profile "notarytool-password" & intel_pid=$$!; \
	xcrun notarytool submit build/KokoroBoxM-Universal.pkg --wait --keychain-profile "notarytool-password" & universal_pid=$$!; \
	wait $$apple_pid; wait $$intel_pid; wait $$universal_pid
	xcrun stapler staple build/KokoroBoxM-Apple.pkg
	xcrun stapler staple build/KokoroBoxM-Intel.pkg
	xcrun stapler staple build/KokoroBoxM-Universal.pkg

# PKG release commands
release_macos_pkg_apple: build_macos_pkg_apple notarize_macos_pkg_apple
release_macos_pkg_intel: build_macos_pkg_intel notarize_macos_pkg_intel
release_macos_pkg_universal: build_macos_pkg_universal notarize_macos_pkg_universal
release_macos_pkg: release_macos_pkg_apple release_macos_pkg_intel release_macos_pkg_universal

fmt:
	swiftformat .

fmt_install:
	brew install swiftformat

lint:
	swiftlint

lint_install:
	brew install swiftlint

dmg_install:
	brew install create-dmg

clean:
	rm -rf build/KokoroBoxI.xcarchive
	rm -rf build/KokoroBoxM.xcarchive
	rm -rf build/SFM.System-arm64.xcarchive
	rm -rf build/SFM.System-x86_64.xcarchive
	rm -rf build/SFM.System-universal.xcarchive
	rm -rf build/SFM.System-arm64
	rm -rf build/SFM.System-x86_64
	rm -rf build/SFM.System-universal
	rm -rf build/KokoroBoxI.dd
	rm -rf build/KokoroBoxM.dd
	rm -rf build/SFM.System-arm64.dd
	rm -rf build/SFM.System-x86_64.dd
	rm -rf build/SFM.System-universal.dd
	rm -f build/KokoroBoxM-Apple.dmg build/KokoroBoxM-Intel.dmg build/KokoroBoxM-Universal.dmg
	rm -f build/KokoroBoxM-Apple.pkg build/KokoroBoxM-Intel.pkg build/KokoroBoxM-Universal.pkg
