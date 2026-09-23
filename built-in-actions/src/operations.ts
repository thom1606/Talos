import { spawn } from 'node:child_process';
import { chmod, cp, link, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflate, inflate } from 'node:zlib';
import { promisify } from 'node:util';
import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';
import { formats, mediaKind, type MediaKind } from './media';

const packageRoot = dirname(fileURLToPath(import.meta.url));
const zip = promisify(deflate), unzip = promisify(inflate);
const active = new Set<AbortController>();
const lifecycle = new AbortController();
export function stopOperations() { lifecycle.abort(); for (const controller of active) controller.abort(); }

async function tool(name: 'ffmpeg' | 'ffprobe' | 'jpegtran'): Promise<string> {
  const executable = join(packageRoot, 'vendor', 'bin', process.arch === 'arm64' ? 'arm64' : 'x86_64', name);
  await chmod(executable, 0o755); // .talos extraction intentionally defaults to non-executable files.
  return executable;
}
async function run(executable: string, args: string[], signal?: AbortSignal, cwd?: string): Promise<string> {
  lifecycle.signal.throwIfAborted();
  signal?.throwIfAborted();
  const controller = new AbortController();
  active.add(controller);
  const abort = () => controller.abort();
  signal?.addEventListener('abort', abort, { once: true });
  const deadline = setTimeout(abort, 30 * 60_000);
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn(executable, args, { cwd, signal: controller.signal, stdio: ['ignore', 'pipe', 'pipe'] });
      let output = '', error = '';
      child.stdout.on('data', chunk => {
        output += chunk.toString();
        if (output.length > 1_048_576) controller.abort();
      });
      child.stderr.on('data', chunk => { error = (error + chunk.toString()).slice(-8192); });
      child.once('error', reject);
      child.once('close', code => code === 0 ? resolve(output) : reject(new Error(error.trim() || `Operation stopped (${code})`)));
    });
  } finally {
    clearTimeout(deadline); active.delete(controller); signal?.removeEventListener('abort', abort);
  }
}
async function ffmpeg(args: string[], signal?: AbortSignal) {
  return run(await tool('ffmpeg'), ['-nostdin', '-hide_banner', '-loglevel', 'error', '-n', ...args], signal);
}
async function probe(file: TalosFile, signal?: AbortSignal) {
  return JSON.parse(await run(await tool('ffprobe'), ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file.path], signal));
}
function chosen(context: TalosContext, index: unknown): TalosFile {
  if (!Number.isInteger(index) || Number(index) < 0 || Number(index) >= context.files.length) throw new Error('Invalid selected file');
  return context.files[Number(index)];
}

// Outputs are committed with an exclusive link on the same volume. Existing files are never overwritten.
async function output(file: TalosFile, suffix: string, extension: string,
  generate: (temporary: string) => Promise<boolean | void>, signal?: AbortSignal): Promise<string | null> {
  const directory = dirname(file.path);
  const temporary = await mkdtemp(join(directory, '.talos-'));
  try {
    const path = join(temporary, `result.${extension}`);
    if (await generate(path) === false) return null;
    lifecycle.signal.throwIfAborted();
    signal?.throwIfAborted();
    const stem = basename(file.name, extname(file.name)) + suffix;
    for (let number = 0; number < 10_000; number++) {
      const destination = join(directory, `${stem}${number ? `-${number + 1}` : ''}.${extension}`);
      try { await link(path, destination); return destination; }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
    }
    throw new Error('Could not find an available output filename');
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

export async function archive(files: TalosFile[]) {
  if (!files.length) throw new Error('Select files to archive');
  const directory = await mkdtemp(join(dirname(files[0].path), '.talos-archive-'));
  try {
    const used = new Set<string>();
    for (const file of files) {
      lifecycle.signal.throwIfAborted();
      let name = basename(file.name), number = 1;
      while (used.has(name.toLocaleLowerCase())) name = `${basename(file.name, extname(file.name))}-${++number}${extname(file.name)}`;
      used.add(name.toLocaleLowerCase());
      await cp(file.path, join(directory, name), { recursive: true, dereference: false, verbatimSymlinks: true, preserveTimestamps: true });
    }
    return await output({ ...files[0], name: 'Archive' }, '', 'zip', async path => {
      await run('/usr/bin/zip', ['-q', '-r', '-y', path, '.'], undefined, directory);
    });
  } finally { await rm(directory, { recursive: true, force: true }); }
}

export async function convert(context: TalosContext, format: unknown, signal?: AbortSignal) {
  const kind = homogeneous(context.files);
  if (typeof format !== 'string' || !(formats[kind] as readonly string[]).includes(format)) throw new Error('Unsupported output format');
  const results: string[] = [];
  for (const file of context.files) {
    signal?.throwIfAborted();
    const path = await output(file, '-converted', format, async path => {
      if (kind === 'image') {
        // ImageIO via sips supports macOS image formats (including HEIC) without another host API.
        await run('/usr/bin/sips', ['-s', 'format', format === 'jpg' ? 'jpeg' : format, file.path, '--out', path], signal);
      } else {
        const codecs = kind === 'video'
          ? ['-map', '0:v:0', '-map', '0:a?', '-c:v', 'h264_videotoolbox', '-allow_sw', '1', '-q:v', '70', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart']
          : ['-map', '0:a:0', '-vn', '-c:a', format === 'm4a' ? 'aac' : format === 'flac' ? 'flac' : 'pcm_s24le', ...(format === 'm4a' ? ['-b:a', '256k'] : [])];
        await ffmpeg(['-i', file.path, ...codecs, '-map_metadata', '0', path], signal);
      }
    }, signal);
    if (path) results.push(path);
  }
  return results;
}
export function homogeneous(files: TalosFile[]): MediaKind {
  const kind = files[0] && mediaKind(files[0].name);
  if (!kind || !files.every(file => mediaKind(file.name) === kind)) throw new Error('Select only images, only videos, or only audio files to convert.');
  return kind;
}

export async function cropVideo(context: TalosContext, payload: Record<string, unknown>, signal: AbortSignal) {
  const file = chosen(context, payload.index);
  const extension = extname(file.name).slice(1).toLowerCase();
  if (!['mp4', 'mov', 'm4v'].includes(extension)) throw new Error('Video crop currently supports MP4, MOV and M4V. Convert other video formats first.');
  const rect = payload.rect as Record<string, number>;
  if (!rect || !['x', 'y', 'width', 'height'].every(key => Number.isSafeInteger(rect[key]) && rect[key] >= (key === 'x' || key === 'y' ? 0 : 2))) throw new Error('Invalid crop rectangle');
  if (rect.width % 2 || rect.height % 2) throw new Error('Video crop dimensions must be even');
  const metadata = await probe(file, signal);
  const video = metadata.streams.find((stream: any) => stream.codec_type === 'video');
  if (!video) throw new Error('No video stream found');
  const rotation = Number(video.side_data_list?.find((data: any) => data.rotation !== undefined)?.rotation ?? video.tags?.rotate ?? 0);
  const rotated = Math.abs(rotation % 180) === 90;
  const width = rotated ? video.height : video.width, height = rotated ? video.width : video.height;
  if (rect.x + rect.width > width || rect.y + rect.height > height) throw new Error('Crop extends outside the video');
  if (['smpte2084', 'arib-std-b67'].includes(video.color_transfer)) throw new Error('HDR video crop is not supported yet; the original has not been changed.');
  return output(file, '-cropped', extension, async path => {
    // Keep the container and copy audio; cropping necessarily encodes a new video stream.
    const filter = `crop=${rect.width}:${rect.height}:${rect.x}:${rect.y}:exact=1,format=yuv420p`;
    await ffmpeg(['-i', file.path, '-map', '0:v:0', '-map', '0:a?', '-vf', filter,
      '-c:v', video.codec_name === 'hevc' ? 'hevc_videotoolbox' : 'h264_videotoolbox', '-allow_sw', '1', '-q:v', '80',
      '-c:a', 'copy', '-map_metadata', '0', '-metadata:s:v:0', 'rotate=0', '-movflags', '+faststart', path], signal);
  }, signal);
}

export async function compress(file: TalosFile): Promise<number> {
  const before = (await stat(file.path)).size;
  let extension = extname(file.name).slice(1).toLowerCase();
  const kind = mediaKind(file.name);
  if (!kind) return 0;
  let pcm = false;
  if (kind === 'audio' && ['wav', 'aif', 'aiff'].includes(extension)) {
    const metadata = await probe(file);
    const audio = metadata.streams.find((stream: any) => stream.codec_type === 'audio');
    // FLAC cannot preserve floating point samples or more than 24 bits with this encoder.
    if (!audio || !['s16', 's32'].includes(audio.sample_fmt) || Number(audio.bits_per_raw_sample || audio.bits_per_sample) > 24) return 0;
    pcm = true; extension = 'flac';
  }
  let saved = 0;
  await output(file, '-compressed', extension, async path => {
    if (/^jpe?g$/i.test(extension)) await run(await tool('jpegtran'), ['-copy', 'all', '-optimize', '-progressive', '-outfile', path, file.path]);
    else if (extension === 'png') await writeFile(path, await optimizePNG(file.path));
    else if (kind === 'image') return false; // No lossy re-encoding disguised as compression.
    else if (pcm || extension === 'flac') await ffmpeg(['-i', file.path, '-map', '0:a:0', '-c:a', 'flac', '-compression_level', '12', '-map_metadata', '0', path]);
    else await ffmpeg(['-i', file.path, '-map', '0', '-c', 'copy', '-map_metadata', '0', path]);
    const after = (await stat(path)).size;
    saved = Math.max(0, before - after);
    return saved > 0;
  });
  return saved;
}

// Re-deflate the existing PNG scanlines; pixels, filters, bit depth and ancillary chunks stay intact.
async function optimizePNG(path: string): Promise<Buffer> {
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
