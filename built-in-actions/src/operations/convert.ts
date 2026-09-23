import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';
import { formats, mediaKind, type MediaKind } from '../media';
import { ffmpeg, output, run } from './shared';

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
