# App flow tests

Open `Talos.xcodeproj`, select the **Talos** scheme and **My Mac**, then press
**⌘U**. `TalosUITests` uses XCTest/XCUITest to launch the app and operate its real
windows with mouse and keyboard input.

From this directory:

```sh
xcodebuild test \
  -project Talos.xcodeproj \
  -scheme Talos \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/TalosFlows.xcresult
```

Use a new result bundle path for each run. Run on an unlocked Mac with the
project's supported macOS/Xcode version. The tests take over the mouse and
keyboard; leave them alone while they run. Allow Xcode's UI testing access if
macOS requests it. Tests run serially because they share the desktop.

## Flows

- Complete onboarding, verify Finder opens, then relaunch and verify the wheel
  contains only Settings and onboarding stays completed.
- Navigate the settings pages, change a sound preference, and verify it after
  relaunch.
- Open the GitHub form, check URL validation and the optional token field,
  cancel, and verify the form resets without adding a repository.
- Select a local project through the native folder picker, verify its build
  status and wheel tile, relaunch, remove it, and verify removal persists.
- Drag a folder from the palette onto the wheel, rename it, relaunch, and
  verify that cancelling a later edit preserves its saved name.

Assertions check visible outcomes and persistence through the UI. Tests do not
import app models, call internal actions, seed the wheel, or mock the screens.
The local-project test creates its own disposable, unbuilt project as input.

This suite does not yet cover live GitHub release installation, system
notification delivery, Finder-to-wheel action execution, or React window file
export. A passing run must not be treated as verification of those flows.

## Storage and failures

Each test passes a unique `TALOS_UI_TEST_RUN` UUID. Debug builds use that UUID for
a separate preferences suite and extension directory. Relaunches within a test
reuse the UUID, so persistence is real. Sparkle's background updater is disabled
during these runs. Release builds ignore the test environment variable.

Tests remove their own preferences, extension directory and project fixture at
teardown. An interrupted runner can leave its UUID directory under
`~/Library/Application Support/Talos/UITests/`. Normal Talos preferences and
repositories are not used by the suite.

Open the `.xcresult` bundle in Xcode to see the failed action, screenshots and
accessibility hierarchy. Fix the flow or its actual UI locator; do not replace
failed gestures with calls into the app's model.

The old standalone Swift/Node checks and `scripts/test-*.sh` runners are removed.
Build tooling remains: `scripts/embed-node.sh` packages the JavaScript runtime,
and the SDK's build scripts compile and package extensions.
