#!/bin/bash
# Build an installable extension; Xcode copies the result into its own app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
workspace="$PWD/Packages/TalosExtensions"
# Xcode launched from Finder may not inherit the developer's Node PATH.
if ! command -v node >/dev/null && [ -n "${DERIVED_FILE_DIR:-}" ]; then
  for runtime in "$DERIVED_FILE_DIR"/node-*/node-*/bin/node; do
    if [ -x "$runtime" ]; then export PATH="$(dirname "$runtime"):$PATH"; break; fi
  done
fi
command -v node >/dev/null || { echo 'Node.js 24 is required to build Talos extensions.' >&2; exit 1; }
if [ ! -x "$workspace/node_modules/.bin/talos-build" ]; then
  npm ci --prefix "$workspace" --cache "${TMPDIR:-/tmp}/talos-npm-cache"
fi
npm run build --prefix "$workspace"
if [ -n "${TARGET_BUILD_DIR:-}" ]; then
  resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
  mkdir -p "$resources"
  # Remove the previous generated filename from incremental app builds.
  rm -f "$resources/built-in-actions.zip"
  cp "$workspace/built-in-actions/dist/com.talos.actions.talos" "$resources/built-in-actions.talos"
  cp "$workspace/built-in-actions/dist/release-config.json" "$resources/built-in-actions.json"
fi
