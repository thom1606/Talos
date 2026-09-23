#!/bin/bash
# Package extension-owned tools into the app; no codecs or media logic are linked into Talos.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "${SRCROOT:?}/built-in-actions"
command -v npm >/dev/null || { echo 'Node/npm is required to build bundled extensions.' >&2; exit 1; }
command -v cmake >/dev/null || { echo 'CMake is required to build extension codecs.' >&2; exit 1; }
dependency_hash="$(shasum -a 256 package-lock.json | cut -d ' ' -f 1)"
if [[ ! -f node_modules/.talos-lock ]] || [[ "$(cat node_modules/.talos-lock)" != "$dependency_hash" ]]; then
  npm ci --cache "${DERIVED_FILE_DIR}/npm-cache"
  printf '%s' "$dependency_hash" > node_modules/.talos-lock
fi
npm run typecheck
npm run package
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/BundledExtensions"
mkdir -p "$resources"
cp dist/talos-actions.talos "$resources/talos-actions.talos"
