import { rename, rm, stat, writeFile } from 'node:fs/promises';
import { extname } from 'node:path';
import type { TalosFile } from '@thom1606/talos-sdk';
import { mediaKind } from '../media';
import { recompressJPEG } from './jpeg';
import { optimizePNG } from './png';
import { ffmpeg, lifecycle, output, probe, run, tool } from './shared';

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
    if (/^jpe?g$/i.test(extension)) {
      const lossless = `${path}.lossless.jpg`;
      try {
        // Keep a lossless candidate so quality 85 is used only when it saves enough space.
        await run(await tool('jpegtran'), ['-copy', 'all', '-optimize', '-progressive', '-outfile', lossless, file.path]);
        // Quality 85 saves about 9–10% on the supplied JPEGs while retaining full dimensions.
        // Prefer the lossless result unless re-encoding saves at least 5%.
        try {
          await recompressJPEG(file.path, path);
          const reencodedSize = (await stat(path)).size;
          const losslessSize = (await stat(lossless)).size;
          if (reencodedSize >= Math.min(losslessSize, before * 0.95)) await rename(lossless, path);
        } catch {
          lifecycle.signal.throwIfAborted();
          await rename(lossless, path);
        }
      } finally { await rm(lossless, { force: true }); }
    }
    else if (extension === 'png') await writeFile(path, await optimizePNG(file.path));
    else if (kind === 'image') return false; // No lossy re-encoding disguised as compression.
    else if (pcm || extension === 'flac') await ffmpeg(['-i', file.path, '-map', '0:a:0', '-c:a', 'flac', '-compression_level', '12', '-map_metadata', '0', path]);
    else await ffmpeg(['-i', file.path, '-map', '0', '-c', 'copy', '-map_metadata', '0', path]);
    const after = (await stat(path)).size;
    // output() discards the temporary result when compression did not beat the input.
    saved = Math.max(0, before - after);
    return saved > 0;
  });
  return saved;
}
