#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift test --package-path Packages/TalosSDK
xcodebuild -project Talos.xcodeproj -scheme Talos -configuration Debug -derivedDataPath /tmp/Talos-build build CODE_SIGNING_ALLOWED=NO > /tmp/talos-build.log 2>&1
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(python3 - <<'PYFILES'
from pathlib import Path
for source in sorted(Path("Talos").rglob("*.swift")):
    if source.as_posix() != "Talos/App/TalosApp.swift":
        print(source)
PYFILES
)
xcrun swift package --package-path Tests/Fixtures/HostTestModule --allow-writing-to-package-directory talos-build
for suite in WheelChecks NativeDropChecks ModuleHostChecks SettingsChecks TaskPillChecks; do
    xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
        -I /tmp/Talos-build/Build/Products/Debug /tmp/Talos-build/Build/Products/Debug/TalosSDK.o \
        "${sources[@]}" Tests/Support/WheelFixtures.swift "Tests/$suite.swift" -o "/tmp/talos-$suite"
    if [ "$suite" = ModuleHostChecks ] || [ "$suite" = SettingsChecks ]; then
        "/tmp/talos-$suite" "$PWD/Tests/Fixtures/HostTestModule/dist/module"
    else
        "/tmp/talos-$suite"
    fi
done
