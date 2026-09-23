import { spawn, type ChildProcess } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { active, lifecycle, tool } from './shared';

export async function recompressJPEG(input: string, output: string): Promise<void> {
  lifecycle.signal.throwIfAborted();
  const controller = new AbortController();
  active.add(controller);
  const deadline = setTimeout(() => controller.abort(), 30 * 60_000);
  try {
    // Stream decoded pixels to the encoder instead of writing a large intermediate image.
    const decoder = spawn(await tool('djpeg'), ['-ppm', input], { signal: controller.signal, stdio: ['ignore', 'pipe', 'pipe'] });
    const encoder = spawn(await tool('cjpeg'), ['-quality', '85', '-optimize', '-progressive', '-outfile', output],
      { signal: controller.signal, stdio: ['pipe', 'ignore', 'pipe'] });
    decoder.stdout.pipe(encoder.stdin);
    encoder.stdin.on('error', () => {}); // The encoder may close before the decoder finishes after a failure.
    const completed = (child: ChildProcess) => new Promise<void>((resolve, reject) => {
      let error = '';
      child.stderr?.on('data', chunk => { error = (error + chunk.toString()).slice(-8192); });
      child.once('error', reject);
      child.once('close', code => code === 0 ? resolve() : reject(new Error(error.trim() || `JPEG operation stopped (${code})`)));
    });
    await Promise.all([completed(decoder), completed(encoder)]).catch(error => { controller.abort(); throw error; });
    await copyJPEGMetadata(input, output);
  } finally { clearTimeout(deadline); active.delete(controller); }
}

// cjpeg writes new image data but not the original application markers. Copy metadata
// markers before the image stream, leaving its new JFIF and color-transform markers intact.
async function copyJPEGMetadata(input: string, output: string): Promise<void> {
  const original = await readFile(input), encoded = await readFile(output);
  if (original.readUInt16BE(0) !== 0xffd8 || encoded.readUInt16BE(0) !== 0xffd8) throw new Error('Invalid JPEG');
  const markers: Buffer[] = [];
  for (let offset = 2; offset + 4 <= original.length;) {
    if (original[offset] !== 0xff) throw new Error('Invalid JPEG metadata');
    const marker = original[offset + 1];
    if (marker === 0xda || marker === 0xd9) break;
    const size = original.readUInt16BE(offset + 2);
    if (size < 2 || offset + 2 + size > original.length) throw new Error('Invalid JPEG metadata');
    if ((marker >= 0xe1 && marker <= 0xed && marker !== 0xee) || marker === 0xef || marker === 0xfe)
      markers.push(original.subarray(offset, offset + 2 + size));
    offset += 2 + size;
  }
  await writeFile(output, Buffer.concat([encoded.subarray(0, 2), ...markers, encoded.subarray(2)]));
}
