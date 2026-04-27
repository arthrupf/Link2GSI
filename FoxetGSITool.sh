#!/bin/bash

INPUT_DIR=$1
ROM_TYPE=$2
BASE_DIR="Temp/system"

usage() {
  echo "Usage: $0 [base_directory] [rom_type]"
  echo ""
  echo "Parameters:"
  echo "  base_directory  - Path to the base ROM directory"
  echo "  rom_type        - Type of rom"
  echo ""
  echo "Example:"
  echo "  sudo bash $0 system Pixel"
  echo ""
}

supported_roms() {
    echo "Available ROMs:"
    echo ""
    declare -a versions=(12 12.1 13 14 15 16 17)

    for version in "${versions[@]}"; do
        rom_dir="ROMsPatches/$version"
        if [ -d "$rom_dir" ]; then
            names=$(find "$rom_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)
            filtered=$(echo "$names" | grep -vxF -f <(printf '%s\n' "${versions[@]}"))
            if [ -n "$filtered" ]; then
                echo "Android $version:"
                echo "$filtered" | sed 's|^|  - |'
                echo ""
            fi
        fi
    done
}

if [ -z "$2" ]; then
  usage
  supported_roms
  exit 0
fi

if [ ! -d "$INPUT_DIR" ]; then
  echo "Error: Directory $INPUT_DIR does not exist"
  exit 1
fi

rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

echo "Copying to temp directory"
cp -r "$INPUT_DIR/." "$BASE_DIR/"

SDK_VERSION=$(grep -m1 "ro.build.version.sdk" "$BASE_DIR/system/build.prop" | cut -d '=' -f2 | tr -dc '0-9')

if [ -z "$SDK_VERSION" ] || ! [[ "$SDK_VERSION" =~ ^[0-9]+$ ]]; then
  echo "Error: Unable to read SDK version from '$BASE_DIR/system/build.prop'."
  exit 1
fi

case "$SDK_VERSION" in
  31) android_version="12" ;;
  32) android_version="12.1" ;;
  33) android_version="13" ;;
  34) android_version="14" ;;
  35) android_version="15" ;;
  36) android_version="16" ;;
  37) android_version="17" ;;  # ✅ Android 17 support
  *)
    echo "Error: Unsupported SDK version $SDK_VERSION"
    exit 1
    ;;
esac

echo "Android Version: $android_version (SDK $SDK_VERSION)"

if [ ! -d "Patches/$android_version" ]; then
  echo "Error: Android version $android_version unsupported"
  exit 1
fi

if [ ! -d "ROMsPatches/$android_version/$ROM_TYPE" ]; then
  echo "Error: ROM $ROM_TYPE for Android $android_version unsupported"
  supported_roms
  exit 1
fi

echo "Patching started..."

Patches/$android_version/make.sh "$BASE_DIR" || exit 1
Patches/common/make.sh "$BASE_DIR" || exit 1
ROMsPatches/$android_version/$ROM_TYPE/make.sh "$BASE_DIR" || exit 1

# Extract APEX safely
if [ -f "Patches/apex/$android_version.tar.xz" ]; then
  tar -xf "Patches/apex/$android_version.tar.xz" -C "$BASE_DIR/system/apex"
else
  echo "Warning: Missing apex archive for Android $android_version"
fi

# Vendor overlay
if [ -n "$(ls -A "$BASE_DIR/vendor" 2>/dev/null)" ]; then
  Tools/vendoroverlay/addvo.sh "$BASE_DIR"
  rm -rf "$BASE_DIR/vendor/"*
fi

# Build.prop modification
if grep -q "ro.build.display.id" "$BASE_DIR/system/build.prop"; then
    displayid="ro.build.display.id"
elif grep -q "ro.system.build.id" "$BASE_DIR/system/build.prop"; then
    displayid="ro.system.build.id"
elif grep -q "ro.build.id" "$BASE_DIR/system/build.prop"; then
    displayid="ro.build.id"
else
    echo "Warning: No build ID property found"
    displayid=""
fi

if [ -n "$displayid" ]; then
    displayid2=$(echo "$displayid" | sed 's/\./\\./g')
    bdisplay=$(grep "$displayid" "$BASE_DIR/system/build.prop" | sed 's/[.[\*^$]/\\&/g; s:/:\\/:g; s/,/\\,/g; s/ /\\ /g')

    sed -i "s/$bdisplay/$displayid2=Builded.by.defnotegor.Using.FoxetGSITool/" "$BASE_DIR/system/build.prop"
fi

current_date=$(date +"%Y-%m-%d")

OUTPUT_DIR="Output"
OUTPUT_IMG="$OUTPUT_DIR/$ROM_TYPE-AB-$android_version-$current_date-FoxetGSI.img"

echo "Creating image: $OUTPUT_IMG"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

Tools/mkimage/mkimage.sh "$BASE_DIR" "$OUTPUT_IMG" || exit 1

echo "Done!"
