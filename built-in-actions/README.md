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
- **Redact:** images and audio. Drag to draw solid black blocks, select and move them, resize with handles,
  or delete with Backspace/Delete. Reset removes all blocks. Saves a numbered `-redacted` copy beside
  the original (PNG stays PNG; other images become JPEG). Blocks are baked into the pixels;
  image metadata is not copied.
  Audio opens a zoomable waveform with multiple editable selections and a bleeped play/pause preview.
  Every channel in a selected interval is replaced with a 1 kHz tone, not mixed over the source.
  Exports a numbered `-redacted.wav` copy with a single audio track and no source metadata or chapters.
  WAV keeps redaction boundaries free of lossy codec smearing. Previews decode at most two two-second
  chunks at a time; the waveform sends only 1,024 amplitude summaries to the window.
  WAV, AIFF, FLAC, ALAC, M4A, AAC, MP3, OGG and Opus inputs up to 24 hours are supported.
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
- **Convert:** wheel submenu (no window), showing formats for a homogeneous image/PDF/video/audio/archive selection.
  Images: PNG, WebP, JPEG, TIFF, BMP. WebP uses quality 85, preserves transparency,
  applies EXIF orientation and converts pixels to sRGB before encoding. PDFs: one PNG or JPG per page, or a DOCX with editable extracted text
  and page breaks. PDF pages without extractable text are included as images in the DOCX.
  Archives: ZIP, TAR and GZIP (a gzip-compressed TAR with a `.tgz` suffix). ZIP, TAR,
  TGZ and TAR.GZ inputs are streamed directly between formats without extracting their contents.
  Paths, empty directories and symbolic links stay inside the archive; originals remain untouched.
  Unicode paths and link targets use the same normalization so links work across platforms.
  Corrupt or unsupported entries fail the conversion rather than saving an incomplete copy.
  RAR output is deferred; its encoder requires [separate bundling permission](https://www.rarlab.com/license.htm).
  Video: MP4/MOV. Audio: M4A, WAV, FLAC, plus transparent waveform SVG/PNG exports
  in the Talos accent (#CA491C). Both waveform formats use the same rounded bars at 1600 × 400;
  SVG scales without losing detail. Waveform decoding retains at most 1,024 amplitude summaries. Converted copies receive `-converted` suffixes;
  PDF images also include page numbers. DOCX text extraction cannot preserve every PDF layout detail.
  Video and M4A conversions may be lossy. Originals are never overwritten.

## Build

Requires Node 24, Xcode command-line tools, CMake and pkg-config on the **build machine** only.

```sh
npm ci
npm run typecheck
npm run package
npm run test:images
```

`ARCHS="arm64 x86_64" npm run package` includes both architectures. Xcode passes its selected architectures
and signing identity. Runtime dependencies are shipped; users need neither Homebrew nor a codec download.
The app build copies `dist/talos-actions.talos` into `Contents/Resources/BundledExtensions`.
Installed built-ins are cached separately by package SHA-256 and refreshed when the app ships a new archive.
New installations start with Crop, Archive, Organize, Compress, Convert, and Settings.

## Image export checks

After building the image tool, run its real pixel and orientation checks (Python 3 with Pillow):

```sh
python3 tests/image-tool.py "vendor/bin/$(uname -m)/image-tool"
```

## Audio checks

After building the bundled codecs, verify actual waveform images, preview and redaction samples:

```sh
npm run test:audio
```

The native UI tests also drag real audio from Finder, select a bleep, play it, save it and decode
the result with AVFoundation. They verify image redaction still exports solid black blocks.

## Archive conversion checks

Verify real ZIP/TAR/GZIP round trips, archive entries, links and cancelled/corrupt output cleanup:

```sh
npm run test:archives
```

## Codec distribution

FFmpeg 8.1 is built from its checksum-pinned official source with GPL, nonfree, networking and autodetection
disabled; only system frameworks/libraries are linked. libjpeg-turbo 3.1.3 provides jpegtran, cjpeg and djpeg. libwebp 1.6.0 is statically linked
into FFmpeg for WebP encoding; its pinned source archive and license ship with the extension.
The `.talos` includes exact codec source archives, license notices and build scripts, alongside signed tools.
The archive helper uses macOS's system libarchive with pinned public headers and their BSD license notices.
This keeps corresponding source available with every app distribution. Modifications and codec policy remain
in this extension. Do not move image/audio/video operations into the app or SDK.
