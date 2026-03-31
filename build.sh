#!/usr/bin/env bash
# WattSec+ build script — no Xcode project required.
# Compiles with swiftc and assembles the .app bundle manually.
set -e

error() { echo "Error: $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
version=$(cat VERSION 2>/dev/null | tr -d '[:space:]')
[ -z "$version" ] && error "VERSION file not found or empty"

dest_dir=dist
create_dmg=false
sign_app=false
universal=false
# Native arch by default — faster build, smaller binary; use --universal to distribute
native_arch=$(uname -m)   # arm64 or x86_64

# Signing
developer_id=
bundle_identifier="com.oliverbagley.WattSecPlus"
keychain_profile=
entitlements_file=WattSec/WattSec.entitlements

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Build WattSec+ — no Xcode project needed.

Options:
  -h, --help             Show help and exit
  -v, --version VERSION  Override version (default: contents of VERSION file)
  -u, --universal        Build a universal binary (arm64 + x86_64) for distribution
                         (default: native arch only — faster and smaller)
  -d, --create-dmg       Package the app in a DMG file
  -s, --sign ID          Code sign with the given Developer ID
  -k, --keychain PROFILE Keychain profile for notarization (required with --sign)
EOF
    exit "$1"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)    usage 0 ;;
        -v|--version)
            [ -z "$2" ] && error "--version requires an argument"
            version=$2; shift 2 ;;
        -u|--universal)
            universal=true; shift ;;
        -d|--create-dmg)
            create_dmg=true; shift ;;
        -s|--sign)
            [ -z "$2" ] && error "--sign requires a developer ID"
            sign_app=true; developer_id=$2; shift 2 ;;
        -k|--keychain)
            [ -z "$2" ] && error "--keychain requires a profile name"
            keychain_profile=$2; shift 2 ;;
        *) echo "Unknown option: $1"; usage 1 ;;
    esac
done

echo "Building WattSec+ v${version}..."

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
command -v swiftc  >/dev/null || error "swiftc not found — install Xcode or the Command Line Tools"
command -v xcrun   >/dev/null || error "xcrun not found"

if $create_dmg; then
    command -v iconutil   >/dev/null || error "iconutil not found (required for DMG)"
    command -v create-dmg >/dev/null || error "create-dmg not found (required for DMG) — install via: brew install create-dmg"
fi

if $sign_app; then
    command -v codesign >/dev/null || error "codesign not found"
fi

# Warn if Command Line Tools are the active toolchain — swiftc works but some SDK
# paths may differ.  Full Xcode is recommended.
if xcrun --find swiftc 2>/dev/null | grep -q CommandLineTools; then
    echo "Warning: active toolchain is Command Line Tools. Full Xcode is recommended."
fi

# ---------------------------------------------------------------------------
# Clean destination
# ---------------------------------------------------------------------------
if [ -d "$dest_dir" ]; then
    read -rp "Destination \"$dest_dir\" already exists. Delete and rebuild? (Y/n): " response
    case "$response" in
        [Nn]*) echo "Exiting"; exit 1 ;;
        *)     rm -rf "$dest_dir" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Resolve SDK
# ---------------------------------------------------------------------------
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
[ -d "$sdk_path" ] || error "Could not locate macOS SDK via xcrun"

# ---------------------------------------------------------------------------
# Assemble .app bundle skeleton
# ---------------------------------------------------------------------------
app_path="$dest_dir/WattSecPlus.app"
contents="$app_path/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"

mkdir -p "$macos_dir" "$resources_dir"

# PkgInfo
printf 'APPL????' > "$contents/PkgInfo"

# Info.plist — substitute __VERSION__ placeholder
sed "s/__VERSION__/$version/g" WattSec/Info.plist > "$contents/Info.plist"

# App icon (convert iconset → icns if needed)
iconset_src="WattSec/Assets.xcassets/AppIcon.appiconset"
if [ -d "$iconset_src" ]; then
    cp -r "$iconset_src" "$dest_dir/_AppIcon.iconset"
    iconutil -c icns "$dest_dir/_AppIcon.iconset" -o "$resources_dir/AppIcon.icns"
    rm -rf "$dest_dir/_AppIcon.iconset"
fi

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
src_files=(
    WattSec/main.swift
    WattSec/SMC.swift
    WattSec/WattSecApp.swift
)

swiftc_flags=(
    -O
    -sdk "$sdk_path"
    -module-name WattSecPlus
    -framework Cocoa
    -framework IOKit
    -framework ServiceManagement
)

binary="$macos_dir/WattSecPlus"

if $universal; then
    echo "Compiling arm64 + x86_64 (universal)..."
    swiftc "${swiftc_flags[@]}" -target arm64-apple-macos13.0 "${src_files[@]}" -o "$dest_dir/_arm64"
    swiftc "${swiftc_flags[@]}" -target x86_64-apple-macos13.0 "${src_files[@]}" -o "$dest_dir/_x86_64"
    lipo -create -output "$binary" "$dest_dir/_arm64" "$dest_dir/_x86_64"
    rm "$dest_dir/_arm64" "$dest_dir/_x86_64"
else
    echo "Compiling for ${native_arch} (native)..."
    swiftc "${swiftc_flags[@]}" -target "${native_arch}-apple-macos13.0" "${src_files[@]}" -o "$binary"
fi

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
if $sign_app; then
    echo "Code signing WattSec+..."
    [ -f "$entitlements_file" ] || error "Entitlements file not found: $entitlements_file"
    codesign -s "$developer_id" -f --timestamp -o runtime \
        -i "$bundle_identifier" \
        --entitlements "$entitlements_file" \
        "$app_path"
fi

# ---------------------------------------------------------------------------
# DMG packaging
# ---------------------------------------------------------------------------
if ! $create_dmg; then
    $universal && arch_label="universal" || arch_label="$native_arch"
    echo "Build v${version} (${arch_label}) complete: $app_path"
    exit 0
fi

echo "Creating DMG..."
pushd "$dest_dir" >/dev/null

mkdir tmp_dmg
cp -r WattSecPlus.app tmp_dmg/

create-dmg \
    --volname "WattSec+" \
    --volicon ../WattSec/Assets.xcassets/AppIcon.appiconset/icon_128x128.png \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon WattSecPlus.app 200 190 \
    --hide-extension WattSecPlus.app \
    --app-drop-link 600 185 \
    WattSecPlus.dmg \
    tmp_dmg/

rm -rf tmp_dmg

popd >/dev/null

if $sign_app; then
    echo "Notarizing WattSec+.dmg..."
    xcrun notarytool submit "$dest_dir/WattSecPlus.dmg" --keychain-profile "$keychain_profile" --wait
    echo "Stapling ticket..."
    xcrun stapler staple "$dest_dir/WattSecPlus.dmg"
fi

echo "Build v${version} complete: $dest_dir/WattSecPlus.dmg"
