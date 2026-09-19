#!/bin/bash
# Build-time only. End users receive this runtime inside the signed Talos app.
set -euo pipefail
version=24.14.1
cache="${DERIVED_FILE_DIR:?}/node-$version"
mkdir -p "$cache" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
binaries=()
for arch in $ARCHS; do
  case "$arch" in arm64) node_arch=arm64 ;; x86_64) node_arch=x64 ;; *) exit 1 ;; esac
  name="node-v$version-darwin-$node_arch"
  if [ ! -x "$cache/$name/bin/node" ]; then
    curl --fail --location --proto '=https' --tlsv1.2 "https://nodejs.org/dist/v$version/SHASUMS256.txt" -o "$cache/SHASUMS256.txt"
    curl --fail --location --proto '=https' --tlsv1.2 "https://nodejs.org/dist/v$version/$name.tar.gz" -o "$cache/$name.tar.gz"
    (cd "$cache"; awk -v archive="$name.tar.gz" '$2 == archive {print}' SHASUMS256.txt > expected.sha256
      test -s expected.sha256
      shasum -a 256 -c expected.sha256
      tar -xzf "$name.tar.gz")
  fi
  binaries+=("$cache/$name/bin/node")
done
destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/node"
if [ "${#binaries[@]}" -eq 1 ]; then cp "${binaries[0]}" "$destination"
else /usr/bin/lipo -create "${binaries[@]}" -output "$destination"; fi
chmod 755 "$destination"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -n "$identity" ] || identity=-
/usr/bin/codesign --force --sign "$identity" --options runtime --entitlements "$SRCROOT/Configuration/Node.entitlements" "$destination"
cp "$cache/$name/LICENSE" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Node-LICENSE.txt"
