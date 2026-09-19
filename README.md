![Talos](assets/readme-banner.png)

Drag files, hold **Shift**, and drop them on an action. Talos puts everyday file tools right under your pointer.

![The Talos action wheel](assets/wheel-preview.png)

## Get started

1. Download Talos from [Releases](https://github.com/thom1606/Talos/releases/latest).
2. Open the DMG, move Talos to Applications, and launch it.
3. Drag a file in Finder, hold **Shift**, and choose an action.

Talos runs in the background. Open it again to arrange your wheel, add extensions, or change settings. You do not need Xcode, Swift, Node.js, or Homebrew.

## Included actions

- **Convert** — hover to choose an image, audio, or video format that matches your files.
- **Archive** — collect your selected files and folders in one ZIP.
- **Remove metadata** — create a clean PNG image without copying source metadata.
- **Compress** — make smaller media files using high-quality compression.
- **Crop** — select part of one image and save it as a new PNG.

Results are saved beside the original. Your original files and existing results are never overwritten. The actions are included in Talos, including when you first launch offline. Some media operations need ffmpeg: Talos uses an existing installation or downloads a verified copy automatically on first use. That first download needs an internet connection.

## Make it yours

Open Talos to drag actions onto the wheel, organise folders, and place the same action more than once. Click a tile to change its name and settings, or press and hold a folder tile to open it. Each placement has its own settings; password fields are stored in macOS Keychain.

The interface follows your Mac's language, with English, Dutch, Spanish, and French translations, and respects reduced-motion and reduced-transparency preferences.

## Add extensions

Import a `.talos` file from **Repositories → Add → Import extension…**, or double-click the package. You can also add a GitHub repository URL in **Repositories**. Talos downloads its published JavaScript release; nothing is compiled on your Mac. Private repositories use a GitHub token with read access to repository contents.

Extensions run code on your Mac, with access to files, processes, and the network. Add repositories from authors you trust. A release checksum detects mismatched downloads; it does not certify the author or restrict what their code can do.

Want to create an extension? Start with [Talos-Actions-Example](https://github.com/thom1606/Talos-Actions-Example) and the short [SDK guide](docs/SDK.md). To work on Talos itself, see [Contributing](CONTRIBUTING.md).
