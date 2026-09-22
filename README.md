![Talos](assets/readme-banner.png)

# Talos

Drag files, hold **Shift**, and drop them on an action. Talos puts file tools
right under your pointer in a configurable action wheel.

This directory contains the macOS app. To build extensions, see the
[Talos SDK](https://github.com/thom1606/talos-sdk).

## Using Talos

1. Launch Talos and complete onboarding. Finder opens and the wheel starts with
   **Settings** as its only built-in action.
2. Open **Repositories** to link a local extension project or add a GitHub
   repository with a published Talos release.
3. Open **Wheel** and drag actions from the palette onto the wheel.
4. Drag a file or folder in Finder, hold **Shift**, and drop it on an action.

Click a wheel tile in settings to rename it. Use folders to group actions;
press and hold a folder tile to open it. The preview selector lets you see
which actions are available for folders, images, video, audio and PDFs.

Talos keeps running when you close settings. Open the app again to return to
settings. Extensions can show native dialogs, toasts, Markdown content, and
React interfaces inside native windows.

## Repositories and updates

In **Repositories → Add repository**, choose:

- **Link local project…** to select an extension project containing
  `package.json`. Build the extension with its SDK build command, then refresh
  the repository in Talos to load the latest build.
- **Add GitHub repository…** to install a published extension release. The
  optional personal access token supports private repositories and is stored
  in macOS Keychain.

Installed extensions are stored in
`~/Library/Application Support/Talos/Extensions/` and loaded from disk on
subsequent launches. Talos checks remote release metadata every hour while
running. Available updates produce notifications when macOS notification
permission is enabled; installing an update remains an explicit action in
Repositories.

The **Import .talos…** menu item is currently a placeholder. Use a linked local
project or GitHub repository to load extensions in this version.

## Build and run the app

The current project targets **macOS 27** and uses **Xcode 27**.

1. Open `Talos.xcodeproj` in Xcode.
2. Select the **Talos** scheme and **My Mac** destination.
3. Select your development team in Signing & Capabilities for the app and UI
   test targets if the checked-in signing team is unavailable.
4. Press **⌘R** to build and run.

Xcode resolves the Swift package dependencies. The build also downloads,
verifies and embeds its pinned Node.js runtime using
[`scripts/embed-node.sh`](scripts/embed-node.sh). The first build needs internet
access; people running the built app do not need to install Node.js themselves.

To build from the command line:

```sh
xcodebuild build \
  -project Talos.xcodeproj \
  -scheme Talos \
  -configuration Debug \
  -destination 'platform=macOS'
```

## App flow tests

Press **⌘U** with the Talos scheme selected. The XCUITest suite launches the
real app and exercises onboarding, settings persistence, the GitHub form,
local repository linking/removal, and wheel drag-and-drop and editing.

Tests use isolated preferences and extension storage. See
[TESTING.md](TESTING.md) for commands, desktop requirements, result bundles and
the flows that are not covered yet.

## Project layout

| Path | Contents |
| --- | --- |
| `Talos/TalosApp.swift` | App lifecycle and window scenes |
| `Talos/Features/` | Wheel, settings, onboarding, extension windows and notifications |
| `Talos/Core/SDKRuntime/` | Extension loading, Node.js host and app bridge |
| `Talos/Core/Repositories/` | Local projects, GitHub releases and update checks |
| `Talos/Core/Preferences/` | App preferences and saved wheel configuration |
| `TalosUITests/` | XCTest flows through the real app |
| `Configuration/` | App and embedded runtime entitlements |
| `scripts/` | Build-time runtime packaging |

Extension console output is forwarded to macOS unified logging. In Console,
filter on subsystem `com.thom1606.Talos` and category `Extensions` to follow
extension logs during development.

## GitHub builds

Pushes to `main` run the XCUITest flows on the `xcode-27` runner. After tests
pass, CI creates a Developer ID-signed, notarized app and uploads `Talos.zip`,
`Talos.dmg` and their checksums as a GitHub Actions artifact. Pull requests run
the tests without access to signing credentials.

The signing job uses the existing `DEVELOPER_ID_CERT_P12`,
`DEVELOPER_ID_CERT_PASSWORD`, `ASC_API_KEY_P8`, `ASC_API_KEY_ID` and
`ASC_API_ISSUER_ID` repository secrets. It does not create a GitHub Release or
change the Sparkle feed; the previous feed is retained in `docs/appcast.xml`.

The SDK has its own repository and npm publishing workflow:
[thom1606/talos-sdk](https://github.com/thom1606/talos-sdk).
