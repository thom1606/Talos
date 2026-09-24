#!/bin/bash
set -euo pipefail

source_folder="${1:?Pass the folder containing Talos.app}"
output="${2:?Pass the output DMG path}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

test -d "$source_folder/Talos.app"
test -f "$repo_root/assets/dmg-background.png"
command -v create-dmg >/dev/null

# Keep Finder from placing its support folder in the icon view, including on CI.
mkdir -p "$source_folder/.background"
cp "$repo_root/assets/dmg-background.png" "$source_folder/.background/dmg-background.png"
chflags hidden "$source_folder/.background"
SetFile -a V "$source_folder/.background"

create-dmg \
  --overwrite \
  --volname Talos \
  --background "$repo_root/assets/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 835 600 \
  --icon-size 128 \
  --text-size 14 \
  --icon Talos.app 170 290 \
  --hide-extension Talos.app \
  --app-drop-link 665 290 \
  "$output" "$source_folder"

mount_point="$(mktemp -d)"
cleanup() {
  hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$output" >/dev/null
cmp "$repo_root/assets/dmg-background.png" "$mount_point/.background/dmg-background.png"
folder_flags="$(stat -f '%f' "$mount_point/.background")"
(( (folder_flags & 0x8000) != 0 ))
[[ "$(GetFileInfo -a "$mount_point/.background")" == *V* ]]
test -s "$mount_point/.DS_Store"
strings "$mount_point/.DS_Store" | grep -F 'dmg-background.png' >/dev/null
test -d "$mount_point/Talos.app"
test "$(readlink "$mount_point/Applications")" = /Applications
