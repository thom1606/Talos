import { readFile, stat } from 'node:fs/promises';
import { deflate, inflate } from 'node:zlib';
import { promisify } from 'node:util';

const zip = promisify(deflate), unzip = promisify(inflate);
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export async function encodePNG(width: number, height: number, rgba: Buffer): Promise<Buffer> {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 || rgba.length !== width * height * 4) {
    throw new Error('Invalid RGBA image');
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6; // 8-bit RGBA, unassociated alpha.
  const stride = width * 4, scanlines = Buffer.alloc((stride + 1) * height);
  for (let row = 0; row < height; row++) rgba.copy(scanlines, row * (stride + 1) + 1, row * stride, (row + 1) * stride);
  return Buffer.concat([signature, chunk('IHDR', header), chunk('sRGB', Buffer.from([0])),
    chunk('IDAT', await zip(scanlines)), chunk('IEND', Buffer.alloc(0))]);
}

function chunk(type: string, data: Buffer): Buffer {
  const bytes = Buffer.alloc(data.length + 12);
  bytes.writeUInt32BE(data.length); bytes.write(type, 4); data.copy(bytes, 8);
  bytes.writeUInt32BE(crc32(bytes.subarray(4, -4)), bytes.length - 4);
  return bytes;
}

// Re-deflate only IDAT scanlines; pixels, filters, bit depth and ancillary chunks stay intact.
export async function optimizePNG(path: string): Promise<Buffer> {
  if ((await stat(path)).size > 128 * 1024 * 1024) throw new Error('PNG is too large to optimize safely');
  const bytes = await readFile(path);
  if (!bytes.subarray(0, 8).equals(signature)) throw new Error('Invalid PNG');
  const chunks: { type: string; data: Buffer }[] = [], image: Buffer[] = [];
  for (let offset = 8; offset < bytes.length;) {
    if (offset + 12 > bytes.length) throw new Error('Truncated PNG');
    const length = bytes.readUInt32BE(offset), end = offset + length + 12;
    if (end > bytes.length) throw new Error('Truncated PNG chunk');
    const data = bytes.subarray(offset, end), type = data.toString('ascii', 4, 8);
    if (crc32(data.subarray(4, -4)) !== data.readUInt32BE(data.length - 4)) throw new Error('Invalid PNG checksum');
    if (type === 'acTL') return bytes; // Animated PNG requires per-frame handling; preserve it unchanged.
    chunks.push({ type, data });
    if (type === 'IDAT') image.push(data.subarray(8, -4));
    offset = end;
  }
  if (!image.length || chunks.at(-1)?.type !== 'IEND') throw new Error('Incomplete PNG');
  const original = Buffer.concat(image);
  const scanlines = await unzip(original, { maxOutputLength: 512 * 1024 * 1024 });
  const optimized = await zip(scanlines, { level: 9 });
  if (optimized.length >= original.length) return bytes;
  const idat = chunk('IDAT', optimized);
  let written = false;
  return Buffer.concat([bytes.subarray(0, 8), ...chunks.flatMap(chunk => {
    if (chunk.type !== 'IDAT') return [chunk.data];
    if (written) return []; written = true; return [idat];
  })]);
}
function crc32(bytes: Buffer) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
