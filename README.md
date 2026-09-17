<!-- markdownlint-disable-next-line first-line-heading -->

![Talos](./assets/readme-banner.png)

Welcome to **Talos**. Keep working in Finder: drag files, hold Shift, and a
small action wheel appears under your pointer. Pick what you want to do and
Talos hands the selected files to a native action on your Mac.

## Getting Started

1. Download the latest Talos release from [GitHub Releases](https://github.com/thom1606/Talos/releases/latest).
2. Open the DMG and drag **Talos** to your Applications folder.
3. Launch Talos once and complete the short setup.
4. In Finder, start dragging a file or folder and hold **Shift**. Drop it on
   an action in the wheel.

Talos runs quietly in the background, without a Dock icon or menu bar item.
Open it again whenever you want to change its settings or arrange your wheel.

## Features

- Actions appear only when they support every file in the current drag.
- Organise actions into folders, place an action more than once, and order the
  wheel exactly as you prefer.
- Hold over a folder to open it; hold over the centre to return.
- Add actions from public or private GitHub repositories, or a local folder.
- Native modules run separately from Talos and can report progress,
  notifications, and completion in the background.
- Choose whether Talos starts at login, checks for updates, and plays sounds.

## Privacy & Security

Talos only passes files to the action you drop them on. Modules are installed
as signed macOS app bundles and verified before Talos runs them. Repository
tokens for private sources are stored in your Keychain.

## Development

Talos is built with Swift 6 and SwiftUI. To contribute to the host app, clone
this repository and open `Talos.xcodeproj` in Xcode 27. Build and run the
automated checks with:

```sh
scripts/verify.sh
```

To create an action, start with
[Talos-Actions-Example](https://github.com/thom1606/Talos-Actions-Example).
The [SDK guide](docs/SDK.md) covers local development, release packaging,
signing, and distribution.
