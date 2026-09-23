#!/bin/bash
# The UI runner is sandboxed. Create input files in build products so Talos can
# save beside them without a Save panel, while the runner only needs read access.
set -euo pipefail
root="${BUILT_PRODUCTS_DIR:?}/TalosUITestFixtures"
rm -rf "$root"
for test in crop convert compress video archive; do
  directory="$root/$test"
  mkdir -p "$directory"
  cp "${SRCROOT:?}/TalosUITests/Fixtures/sample.png" "$directory/sample.png"
done
cp "$SRCROOT/TalosUITests/Fixtures/sample.mp4" "$root/video/sample.mp4"
printf 'A second selected file' > "$root/archive/notes.txt"
