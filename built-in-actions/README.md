# Talos actions

The built-in tools are a regular React/TypeScript SDK extension, displayed as **Talos**.
Their source, codec builds and packaging live here. The app only installs bundled packages,
passes activation context to windows, routes generic requests and serves local preview files.

`src/index.tsx` routes commands. `src/operations/` contains one file per action, with shared
process and output handling in `shared.ts` and JPEG/PNG helpers beside Compress.

- **Crop:** free or 1:1, 16:9, 9:16, 4:3 and 3:4 selection; pixel dimensions; Reset / Apply.
  Images save a numbered `-cropped` copy beside the original: PNG stays PNG; other images become JPEG
  with a white transparency background. The crop window closes after saving.
  MP4/MOV/M4V video previews load the first frame and provide play/pause and seeking in the same crop interface;
  they write `-cropped` beside the original.
  Video is re-encoded using VideoToolbox, audio is copied, and the container stays the same.
  HDR video and other video containers are rejected rather than silently changing their appearance.
- **Archive:** selection (including folders) becomes `Archive.zip` beside the first input.
  Files stream directly into the ZIP without a copied staging folder. Duplicate basenames are numbered;
  symlinks remain symlinks; originals stay untouched.
- **Organize:** uses on-device Apple Intelligence to group selected files and folders into
  categories beside their originals. It checks the full plan before moving anything and attempts
  to restore completed moves if a later move fails.
- **Compress:** no window. PNG scanlines are recompressed without altering pixels, metadata or bit depth;
  JPEG files are re-encoded at quality 85 when that saves at least 5%; otherwise coefficients are optimized
  losslessly with jpegtran. Integer PCM audio up to 24-bit can become FLAC.
  FLAC is recompressed; other audio/video is remuxed without re-encoding. Outputs are kept only when smaller.
  Animated PNG and unsupported image optimizations are left unchanged. Savings are never guaranteed.
- **Convert:** wheel submenu (no window), showing formats for a homogeneous image/video/audio selection. Images: PNG, JPEG, TIFF, BMP.
  Video: MP4/MOV. Audio: M4A, WAV, FLAC. Converted copies receive `-converted` suffixes.
  Video and M4A conversions may be lossy. Originals are never overwritten.

## Build

Requires Node 24, Xcode command-line tools and CMake on the **build machine** only.

```sh
npm ci
npm run typecheck
npm run package
```

`ARCHS="arm64 x86_64" npm run package` includes both architectures. Xcode passes its selected architectures
and signing identity. Runtime dependencies are shipped; users need neither Homebrew nor a codec download.
The app build copies `dist/talos-actions.talos` into `Contents/Resources/BundledExtensions`.
Installed built-ins are cached separately by package SHA-256 and refreshed when the app ships a new archive.
New installations start with Crop, Archive, Organize, Compress, Convert, and Settings.

## Codec distribution

FFmpeg 8.1 is built from its checksum-pinned official source with GPL, nonfree, networking and autodetection
disabled; only system frameworks/libraries are linked. libjpeg-turbo 3.1.3 provides jpegtran, cjpeg and djpeg.
The `.talos` includes both exact source archives, license notices and the build script, alongside signed tools.
This keeps corresponding source available with every app distribution. Modifications and codec policy remain
in this extension. Do not move image/audio/video operations into the app or SDK.
