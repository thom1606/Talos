import { spawn, type ChildProcess } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { tool } from './shared';

export async function recompressJPEG(input: string, output: string, signal: AbortSignal): Promise<void> {
  signal.throwIfAborted();
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal.addEventListener('abort', abort, { once: true });
  const children: ChildProcess[] = [];
  const completions: Promise<void>[] = [];
  let killTimer: ReturnType<typeof setTimeout> | undefined;
  const forceStop = () => {
    killTimer ??= setTimeout(() => { for (const child of children) child.kill('SIGKILL'); }, 250);
  };
  controller.signal.addEventListener('abort', forceStop, { once: true });
  const deadline = setTimeout(() => controller.abort(), 30 * 60_000);
  try {
    // Stream decoded pixels to the encoder instead of writing a large intermediate image.
    const [decoderPath, encoderPath] = await Promise.all([tool('djpeg'), tool('cjpeg')]);
    signal.throwIfAborted();
    const decoder = spawn(decoderPath, ['-ppm', input], { signal: controller.signal, stdio: ['ignore', 'pipe', 'pipe'] });
    children.push(decoder);
    const encoder = spawn(encoderPath, ['-quality', '85', '-optimize', '-progressive', '-outfile', output],
      { signal: controller.signal, stdio: ['pipe', 'ignore', 'pipe'] });
    children.push(encoder);
    decoder.stdout.pipe(encoder.stdin);
    encoder.stdin.on('error', () => {}); // The encoder may close before the decoder finishes after a failure.
    const completed = (child: ChildProcess) => new Promise<void>((resolve, reject) => {
      let error = '';
      child.stderr?.on('data', chunk => { error = (error + chunk.toString()).slice(-8192); });
      child.once('error', reject);
      child.once('close', code => code === 0 ? resolve() : reject(new Error(error.trim() || `JPEG operation stopped (${code})`)));
    });
    completions.push(...children.map(child => completed(child).catch(error => { controller.abort(); throw error; })));
    await Promise.all(completions);
    signal.throwIfAborted();
    await copyJPEGMetadata(input, output);
  } finally {
    controller.abort();
    await Promise.allSettled(completions);
    clearTimeout(deadline);
    if (killTimer) clearTimeout(killTimer);
    signal.removeEventListener('abort', abort);
    controller.signal.removeEventListener('abort', forceStop);
  }
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
