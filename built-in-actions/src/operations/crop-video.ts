import { extname } from 'node:path';
import type { TalosContext } from '@thom1606/talos-sdk';
import { chosen, ffmpeg, output, probe } from './shared';

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
  // Crop coordinates come from the displayed orientation, which can differ from encoded dimensions.
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
