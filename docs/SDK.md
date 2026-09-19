# Talos JavaScript SDK

Create actions in JavaScript; Talos supplies the runtime and native interface. Start from [Talos-Actions-Example](https://github.com/thom1606/Talos-Actions-Example) for project setup, local builds, and GitHub releases. Extension authors do not need an Apple developer account.

Install the SDK with `npm install --save-dev @thom1606/talos-sdk`.

## Define an action

```js
import { defineExtension, settings } from '@thom1606/talos-sdk';

export default defineExtension({
  id: 'com.example.actions',
  name: 'My actions',
  actions: [{
    id: 'upload',
    title: { en: 'Upload', nl: 'Uploaden', es: 'Subir', fr: 'Téléverser' },
    symbol: 'square.and.arrow.up',
    acceptedTypes: ['public.data'],
    settings: [
      settings.text('username', 'Username', { required: true }),
      settings.password('password', 'Password', { required: true }),
      settings.number('days', 'Expires after (days)', { defaultValue: 7, minimum: 1 }),
    ],
    async run(session) {
      await upload(session.files.map(file => file.path), session.settings);
      await session.complete('Uploaded');
    },
  }],
});
```

`session.files` contains the selected file paths, URLs, and type identifiers. `session.settings` contains this tile's values as strings. Node's standard libraries, `fetch`, and child processes are available.

## Settings

`settings.text`, `settings.password`, `settings.number`, `settings.toggle`, and `settings.select` describe native controls. Supply an ID, label, and optional options. Select also takes an array of choices: `settings.select('format', 'Format', ['png', 'jpg'])`.

Talos renders the form when someone clicks a tile. Passwords are stored in Keychain and passed to the action through a private pipe. Do not log them. Every tile also has a built-in name field.

## Progress and results

- `await session.progress(0.5, 'Uploading…')` updates the task indicator; progress ranges from 0 to 1.
- `await session.complete('Done', ['/path/to/result'])` finishes with optional output paths.
- `await session.notify('Upload complete')` posts a macOS notification, subject to the user's notification settings.
- `await session.checkCancellation()` stops work if the task was cancelled.
- Throw an `Error` to show an action failure. Talos also completes a handler that returns normally.

## Native image tools

`await session.crop(session.files[0].path)` opens Talos's native crop window and saves a new PNG beside the original. It finishes the action when the window closes.

`await session.image({ input, output, stripMetadata: true })` writes a PNG without source metadata. The output must not already exist.

## Menus and translations

Use `children` to declare submenu actions. `acceptedTypes`, `minimumFiles`, and `maximumFiles` determine which choices appear for the dragged files. Keep action IDs stable across releases.

Titles and settings labels accept either a string or an object with `en`, `nl`, `es`, and `fr`. English is the fallback. For messages, use `localize({ en: 'Done', nl: 'Klaar' }, session.language)` from the SDK.

## Installable packages

Run `talos-build .` to create `dist/<extension-id>.talos`. This ZIP-based package contains the compiled JavaScript and its manifest. Double-click it or choose **Repositories → Add → Import extension…** in Talos Settings. The original package is kept. GitHub releases distribute the same `.talos` file with a SHA-256 checksum in `release-config.json`.
