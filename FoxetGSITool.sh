#!/bin/bash

INPUT_DIR=$1
ROM_TYPE=$2
BASE_DIR="Temp/system"

usage() {
  echo "Usage: $0 [base_directory] [rom_type]"
  echo ""
  echo "Example: sudo bash $0 UnpackedROMs/system Pixel"
}

supported_roms() {
  echo "Available ROMs:"
  declare -a versions=(12 12.1 13 14 15 16)
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
  echo "❌ Error: Directory $INPUT_DIR does not exist"
  exit 1
fi

rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"
echo "📦 Copying to temp directory"
cp -r "$INPUT_DIR/." "$BASE_DIR/"

# 🔍 Auto-detect build.prop
BUILD_PROP=""
for path in \
  "$BASE_DIR/system/build.prop" \
  "$BASE_DIR/system/system/build.prop" \
  "$BASE_DIR/system/system_ext/build.prop"; do
  if [ -f "$path" ]; then
    BUILD_PROP="$path"
    break
  fi
done

if [ -z "$BUILD_PROP" ]; then
  echo "❌ build.prop not found in system"
  exit 1
fi

SDK_VERSION=$(grep -m1 "ro.build.version.sdk" "$BUILD_PROP" | cut -d '=' -f2 | tr -dc '0-9')
if [ -z "$SDK_VERSION" ] || ! [[ "$SDK_VERSION" =~ ^[0-9]+$ ]]; then
  echo "❌ Unable to read SDK version from $BUILD_PROP"
  exit 1
fi

case "$SDK_VERSION" in
  31) android_version="12" ;;
  32) android_version="12.1" ;;
  33) android_version="13" ;;
  34) android_version="14" ;;
  35) android_version="15" ;;
  36) android_version="16" ;;
  *) echo "❌ Unsupported SDK version $SDK_VERSION"; exit 1 ;;
esac

echo "✅ Android Version: $android_version (SDK $SDK_VERSION)"

if [ ! -d "Patches/$android_version" ]; then
  echo "❌ Error: Android version $android_version unsupported"
  exit 1
fi

if [ ! -d "ROMsPatches/$android_version/$ROM_TYPE" ]; then
  echo "❌ Error: ROM $ROM_TYPE for Android $android_version unsupported"
  supported_roms
  exit 1
fi

echo "🔧 Patching started..."
Patches/$android_version/make.sh "$BASE_DIR"
Patches/common/make.sh "$BASE_DIR"
ROMsPatches/$android_version/$ROM_TYPE/make.sh "$BASE_DIR"

# 🧩 Inject APEX
tar -xf "Patches/apex/$android_version.tar.xz" -C "$BASE_DIR/system/apex"

# 🧩 Vendor overlay
if [ -n "$(ls -A "$BASE_DIR/vendor" 2>/dev/null)" ]; then
  Tools/vendoroverlay/addvo.sh "$BASE_DIR"
  rm -rf "$BASE_DIR/vendor/"*
fi

# 🧬 Inject display ID
if grep -q "ro.build.display.id" "$BUILD_PROP"; then
  displayid="ro.build.display.id"
elif grep -q "ro.system.build.id" "$BUILD_PROP"; then
  displayid="ro.system.build.id"
elif grep -q "ro.build.id" "$BUILD_PROP"; then
  displayid="ro.build.id"
fi

displayid2=$(echo "$displayid" | sed 's/\./\\./g')
bdisplay=$(grep "$displayid" "$BUILD_PROP" | sed 's/\./\\./g; s:/:\\/:g; s/\,/\\,/g; s/\ /\\ /g')
sed -i "s/$bdisplay/$displayid2=Builded\.by\.defnotegor\.Using\.FoxetGSITool/" "$BUILD_PROP"

# 🧱 Build image
current_date=$(date +"%Y-%m-%d")
IMG_NAME="$ROM_TYPE-AB-$android_version-$current_date-FoxetGSI.img"
echo "📦 Creating image: $IMG_NAME"
rm -rf "Output"
mkdir -p "Output"
Tools/mkimage/mkimage.sh "$BASE_DIR" "Output/$IMG_NAME"
