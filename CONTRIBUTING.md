# Contributing to Talos

Use Xcode 27 and Node.js 24. Open `Talos.xcodeproj` for the native apps.

```sh
npm ci --prefix Packages/TalosExtensions
scripts/verify.sh
```

The verification script builds the included JavaScript actions, tests the JavaScript SDK and app contracts, builds both apps, and runs the host integration checks. The host build downloads and embeds its pinned Node runtime; this is a developer/CI step, not an end-user dependency.

## Source layout

- `Talos/App` — host lifecycle and wheel startup.
- `Talos/Features/DragWheel` — drag tracking, geometry, and wheel rendering.
- `Talos/Data` — repository installation, persistence, credentials, and action execution.
- `TalosSettings` — onboarding, settings, tile forms, and native action windows.
- `Packages/TalosExtensions/sdk` — public JavaScript SDK and `.talos` packaging CLI.
- `Packages/TalosExtensions/tests` — JavaScript integration tests.
- `Packages/TalosExtensions/built-in-actions` — the standard actions shipped with Talos.

Extension builds produce a bundled `extension.mjs`, a manifest, and a checksummed release archive. No install scripts or package manager are run on an end user's Mac. Dependencies must be bundled JavaScript; native npm addons are not a portable extension format.

Keep file transformations off the wheel's main actor. Preserve selected originals, use exclusive output creation, give controls accessible labels, and add translations for user-facing strings. Verify meaningful behavior with real fixtures and running processes.

Talos itself is signed and notarized for distribution. Its JavaScript extensions do not need their own Apple certificates. `scripts/release.sh` publishes the signed host; run `scripts/verify.sh` before release.

## Extension tooling

All npm metadata, dependencies, and Biome configuration live in `Packages/TalosExtensions`; the repository root is the native app project. This npm workspace contains the SDK and built-in actions as separate packages.

```sh
npm run format --prefix Packages/TalosExtensions
npm test --prefix Packages/TalosExtensions
scripts/build-actions.sh
```

Xcode's **Build and Embed Talos Actions** phase builds `built-in-actions/dist/com.talos.actions.talos` and copies it plus its checksummed manifest directly into the app's Resources. Generated archives are ignored by Git. Both local builds and CI use this same phase; `verify.sh` checks the actual bundled archive. CI also uploads the `.talos` artifact.

Use a signed Xcode build when running Talos locally: both apps need their App Group entitlements. The unsigned build in `verify.sh` is for compilation and isolated integration fixtures only; do not launch it against your personal library.


Native extension packages are no longer supported. Shared manifest and IPC types belong to the app under `Talos/Models/Extensions`. All extension execution uses JavaScript.
