![Talos](assets/readme-banner.png)

# Talos

Drag files, hold **Shift**, and drop them on an action. Talos puts file tools
right under your pointer in a configurable action wheel.

This directory contains the macOS app. To build extensions, see the
[Talos SDK](https://github.com/thom1606/talos-sdk).

![Talos action wheel preview](assets/app-preview.png)

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

## App releases

App updates are published from `release/production`. Pushes to `main` build
and test the app without publishing an update. Set `MARKETING_VERSION` in the
Xcode project to the next version before updating the release branch.

To publish the next version, push the intended commit to the release branch:

```sh
git push origin HEAD:release/production
```

CI runs the app flows, archives and exports a Developer ID build, notarizes it,
and publishes a GitHub Release containing only `Talos.dmg` and `Talos.zip`.
It creates a version tag as a checkpoint; the release branch push starts the
build. The Xcode project sets the app version, and the CI run number provides
the increasing build number. Existing published versions cannot be overwritten.

The app reads updates from
[the appcast](https://thom1606.github.io/Talos/appcast.xml). After publishing
the release, CI commits the signed feed and
[SHA-256 checksums](https://thom1606.github.io/Talos/SHA256SUMS) to `docs/` on
`release/production`. The Pages workflow deploys these files after the release
build succeeds and verifies that the update can be downloaded publicly.

For the initial public launch, make the repository public and select
**Settings → Pages → Build and deployment → Source: GitHub Actions**. Run
**Publish appcast to GitHub Pages** once after a successful release build.
Later releases deploy automatically.
GitHub Free does not host Pages for this repository while it is private.

Signing uses the existing Apple signing/notarization secrets and
`SPARKLE_PRIVATE_KEY`. CI verifies the update signature against the public key
embedded in the app before publishing.
