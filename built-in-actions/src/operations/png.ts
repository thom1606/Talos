import { readFile, stat } from 'node:fs/promises';
import { deflate, inflate } from 'node:zlib';
import { promisify } from 'node:util';

const zip = promisify(deflate), unzip = promisify(inflate);

// Re-deflate only IDAT scanlines; pixels, filters, bit depth and ancillary chunks stay intact.
export async function optimizePNG(path: string): Promise<Buffer> {
  if ((await stat(path)).size > 128 * 1024 * 1024) throw new Error('PNG is too large to optimize safely');
  const bytes = await readFile(path);
  if (!bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('Invalid PNG');
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
  const idat = Buffer.alloc(optimized.length + 12); idat.writeUInt32BE(optimized.length); idat.write('IDAT', 4); optimized.copy(idat, 8);
  idat.writeUInt32BE(crc32(idat.subarray(4, -4)), idat.length - 4);
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
