![Talos](assets/readme-banner.png)

# Talos

Drag files, hold **Shift**, and drop them on an action. Talos puts file tools
right under your pointer in a configurable action wheel.

This directory contains the macOS app. To build extensions, see the
[Talos SDK](https://github.com/thom1606/talos-sdk).

![Talos action wheel preview](assets/app-preview.png)

## Using Talos

1. Launch Talos and complete onboarding. Finder opens and the wheel starts with
   **Crop**, **Archive**, **Organize**, **Compress**, **Convert**, and **Settings**.
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

## Sponsorship

If Talos is useful to you, you can support its development through
[GitHub Sponsors](https://github.com/sponsors/thom1606). Your support helps keep
Talos maintained and open source.
