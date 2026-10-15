#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
headers="vendor/sources/libarchive-3.7.4-headers"
mkdir -p "$headers"
fetch_header() {
  local name="$1" checksum="$2"
  test -f "$headers/$name" || curl --fail --location --proto '=https' --tlsv1.2 "https://raw.githubusercontent.com/libarchive/libarchive/v3.7.4/libarchive/$name" -o "$headers/$name"
  printf '%s  %s\n' "$checksum" "$headers/$name" | shasum -a 256 -c -
}
# Xcode ships libarchive's system library but omits its public BSD-licensed headers.
# Package these exact headers (including their license notices); no runtime download.
fetch_header archive.h 618cd16c8fa40ddabc44f2d3eb3a35860f6b1d1d856b62a7f4f035b7a319bdab
fetch_header archive_entry.h 3695eb0193741b16b99e06cf1fc5e6db427b68a9475696ef746c024ae0a6ae72
source_hash="$(cat scripts/archive-tool.c scripts/build-archive-tool.sh | shasum -a 256 | cut -d ' ' -f 1)"
for arch in ${ARCHS:-$(uname -m)}; do
  destination="vendor/bin/$arch/archive-tool"
  mkdir -p "vendor/bin/$arch"
  if [[ ! -x "$destination" ]] || [[ "$(cat "vendor/bin/$arch/.archive-configuration" 2>/dev/null || true)" != "$source_hash" ]]; then
    xcrun clang -arch "$arch" -mmacosx-version-min=14.0 -O2 -Wall -Wextra -Werror -I"$headers" scripts/archive-tool.c -larchive -framework CoreFoundation -o "$destination"
    printf '%s' "$source_hash" > "vendor/bin/$arch/.archive-configuration"
  fi
  if otool -L "$destination" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)'; then
    echo "Unexpected non-system archive tool dependency" >&2; exit 1
  fi
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime "$destination"
done
