#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor/build/image-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/vendor/build/image-module-cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/vendor/build/image-module-cache"
source_hash="$(shasum -a 256 scripts/image-tool.swift | cut -d ' ' -f 1)"
for arch in ${ARCHS:-$(uname -m)}; do
  destination="vendor/bin/$arch/image-tool"
  mkdir -p "vendor/bin/$arch"
  if [[ ! -x "$destination" ]] || [[ "$(cat "vendor/bin/$arch/.image-configuration" 2>/dev/null || true)" != "$source_hash" ]]; then
    xcrun swiftc -target "$arch-apple-macosx14.0" -O scripts/image-tool.swift -o "$destination"
    printf '%s' "$source_hash" > "vendor/bin/$arch/.image-configuration"
  fi
  if otool -L "$destination" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)'; then
    echo "Unexpected non-system image tool dependency" >&2; exit 1
  fi
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime "$destination"
done
