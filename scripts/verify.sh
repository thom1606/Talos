#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm ci --prefix Packages/TalosExtensions --cache /tmp/talos-npm-cache
npm run format:check --prefix Packages/TalosExtensions
npm test --prefix Packages/TalosExtensions
scripts/build-actions.sh
xcodebuild -project Talos.xcodeproj -scheme Talos -configuration Debug -derivedDataPath /tmp/Talos-build build CODE_SIGNING_ALLOWED=NO > /tmp/talos-build.log 2>&1
python3 scripts/check-bundled-actions.py /tmp/Talos-build/Build/Products/Debug/Talos.app
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(python3 - <<'PYFILES'
from pathlib import Path
for source in sorted(list(Path("Talos").rglob("*.swift")) + list(Path("TalosSettings").rglob("*.swift"))):
    if source.name not in ("TalosApp.swift", "TalosSettingsApp.swift"):
        print(source)
PYFILES
)
for suite in ExtensionContractChecks WheelChecks NativeDropChecks ModuleHostChecks SettingsChecks TaskPillChecks JavaScriptHostChecks ImageActionChecks; do
    xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
        "${sources[@]}" Tests/Support/WheelFixtures.swift "Tests/$suite.swift" -o "/tmp/talos-$suite"
    if [ "$suite" = ModuleHostChecks ] || [ "$suite" = SettingsChecks ]; then
        "/tmp/talos-$suite" "$PWD/Tests/Fixtures/HostTestModule" /tmp/Talos-build/Build/Products/Debug/Talos.app
    elif [ "$suite" = JavaScriptHostChecks ]; then
        "/tmp/talos-$suite" /tmp/Talos-build/Build/Products/Debug/Talos.app
    else
        "/tmp/talos-$suite"
    fi
done
