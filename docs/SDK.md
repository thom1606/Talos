# Create actions for Talos

Build your own native actions and make them available from the Talos wheel.
The quickest way to begin is
[Talos-Actions-Example](https://github.com/thom1606/Talos-Actions-Example),
which includes examples for a window, a notification, and background work.

## Get started

Use the example repository as a template, open its package in Xcode, and
replace the sample actions with your own Swift and SwiftUI code. Build a local
version with:

```sh
swift package --allow-writing-to-package-directory talos-build
```

Then open **Talos → Repositories → Add repository → Local repository** and
select `dist/module`. Local development does not require a Developer ID
certificate or Apple developer account.

## Write an action

Every action starts in a type conforming to `ModuleApplication`:

```swift
import TalosSDK

@main
struct MyActions: ModuleApplication {
    static func run(session: ModuleSession) async throws {
        switch session.invocation.actionID {
        case "my-action":
            try await process(session.invocation.files.map(\.url))
            try await session.complete(message: "Done")
        default:
            throw MyError.unknownAction
        }
    }
}
```

Use stable action IDs so existing wheel layouts continue to work after an
update. Declare the file types and selection limits for each action in
`config.json`; Talos only shows the action when the current Finder selection
matches.

An action may:

- report progress with `session.progress(_:message:)`;
- finish with `session.complete(message:outputs:)`;
- send a notification with `session.notify(_:actions:)`;
- check `session.checkCancellation()` between longer units of work;
- present a native SwiftUI window with `ModuleUI.showWindow`.

For example:

```swift
let accepted = await ModuleUI.showWindow(
    "Rename files",
    primary: "Rename",
    secondary: "Cancel"
) {
    RenameView()
        .padding(20)
}
```

The returned value is `true` when the primary button is chosen and `false`
after Cancel or closing the window.

## Describe your actions

Each action package includes a `config.json`. Start from the example
repository and customize its identity, version, supported macOS version,
architectures, app bundle, and actions.

Useful action fields include:

- `id`: a stable identifier, such as `images.convert`;
- `title`: the label shown in the wheel;
- `symbol`: an optional SF Symbol;
- `acceptedTypes`: Uniform Type Identifiers such as `public.image`;
- `minimumFiles` and `maximumFiles`: selection limits;
- `children`: optional nested actions for a folder.

Talos paginates larger folders automatically. A folder may declare up to 64
actions and Talos supports up to five nested levels. File-type filtering is
applied before the matching actions are shown.

## Share a repository

A repository can contain one or more action packages. List them in a
`repository.json` file at the root:

```json
{
  "schemaVersion": 1,
  "name": "My Talos Actions",
  "url": "https://github.com/YOUR-ACCOUNT/my-talos-actions",
  "maintainer": "Your name",
  "modules": ["my-actions"]
}
```

Users can add a public repository by URL. Private repositories also work with
a fine-grained GitHub token that has read access to repository contents.

## Publish a release

GitHub-installed actions must be signed with Developer ID and notarized by
Apple. Configure your signing identity and a `notarytool` Keychain profile,
then run:

```sh
export TALOS_MODULE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TALOS_NOTARY_PROFILE='your-notary-profile'

swift package --arch arm64 --arch x86_64 \
  --allow-writing-to-package-directory \
  --allow-network-connections all \
  talos-build --release
```

The command creates the release archive and `dist/release-config.json`. Upload
the archive to the matching GitHub Release, then copy the generated release
details into the package's `config.json`.

Increment the version for every update. Only list architectures that are
actually included in the app.

## Add TalosSDK

Action repositories use this repository as a Swift Package dependency. Pin a
tested revision and commit `Package.resolved` so builds remain reproducible.
The example repository already contains the recommended package setup.
