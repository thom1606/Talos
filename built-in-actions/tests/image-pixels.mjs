import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

// Decode with the shipping codecs independently of our PNG writer and image normalizer.
// BGRA BMP is supported by the bundled encoder and exposes the decoded alpha channel.
export function decodeImage(ffmpeg, path) {
  const bitmap = execFileSync(ffmpeg, ['-v', 'error', '-i', path, '-frames:v', '1', '-c:v', 'bmp', '-pix_fmt', 'bgra', '-f', 'image2pipe', '-'], { maxBuffer: 8 * 1024 * 1024 });
  assert.equal(bitmap.toString('ascii', 0, 2), 'BM'); assert.equal(bitmap.readUInt16LE(28), 32);
  const start = bitmap.readUInt32LE(10), width = bitmap.readInt32LE(18), signedHeight = bitmap.readInt32LE(22), height = Math.abs(signedHeight);
  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const source = start + ((signedHeight > 0 ? height - 1 - y : y) * width + x) * 4, target = (y * width + x) * 4;
      pixels[target] = bitmap[source + 2]; pixels[target + 1] = bitmap[source + 1];
      pixels[target + 2] = bitmap[source]; pixels[target + 3] = bitmap[source + 3];
    }
  }
  return { width, height, pixels };
}
