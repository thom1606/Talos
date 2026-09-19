# Talos JavaScript SDK

Talos supplies the Node runtime and renders native settings. Extension authors do not need Xcode or an Apple developer account.

Import `defineExtension`, `settings`, and `localize` from `@thom1606/talos-sdk`. Define actions in `src/index.mjs`, then run `talos-build .` to create `dist/<extension-id>.talos`.

See the [SDK guide](https://github.com/thom1606/Talos/blob/main/docs/SDK.md) and [example extension](https://github.com/thom1606/Talos-Actions-Example).

Install with `npm install --save-dev @thom1606/talos-sdk`. For development inside the Talos repository, use the SDK workspace.
