import type { TalosFile } from '@thom1606/talos-sdk';
import { audioRanges, type AudioWaveform } from '../audio';
import { mediaKind } from '../media';
import { ffmpeg, probe } from './shared';

export async function audioDuration(file: TalosFile, signal?: AbortSignal): Promise<number> {
  if (mediaKind(file.name) !== 'audio') throw new Error('Select an audio file.');
  const metadata = await probe(file, signal);
  const stream = metadata.streams?.find((stream: { codec_type?: string }) => stream.codec_type === 'audio');
  const duration = Number(stream?.duration ?? metadata.format?.duration);
  if (!stream || !Number.isFinite(duration) || duration <= 0 || duration > 24 * 60 * 60) {
    throw new Error('Cannot read the audio duration, or the recording is longer than 24 hours.');
  }
  return duration;
}

export async function readAudioWaveform(file: TalosFile, range: { start?: unknown; end?: unknown } = {}, signal?: AbortSignal): Promise<AudioWaveform> {
  const duration = await audioDuration(file, signal);
  const [{ start, end }] = audioRanges([{ start: range.start ?? 0, end: range.end ?? duration }], duration);
  const samples = Math.max(1, Math.ceil((end - start) * 8000 / 1024));
  // Decode in the extension process and retain only bounded amplitude summaries.
  // Measure channels separately so phase-inverted stereo cannot cancel its waveform.
  const text = await ffmpeg(['-ss', String(start), '-i', file.path, '-t', String(end - start), '-map', '0:a:0',
    '-af', `aresample=8000,asetpts=N/SR/TB,asetnsamples=n=${samples}:p=1,astats=metadata=1:reset=1:measure_perchannel=none:measure_overall=Peak_level,ametadata=print:key=lavfi.astats.Overall.Peak_level:file=-`,
    '-frames:a', '1024', '-f', 'null', '-'], signal);
  const peaks = [...text.matchAll(/lavfi\.astats\.Overall\.Peak_level=([^\r\n]+)/g)].map(([, value]) => {
    const decibels = Number(value);
    return Number.isFinite(decibels) ? Math.min(1, Math.pow(10, decibels / 20)) : 0;
  });
  if (!peaks.length) throw new Error('Cannot read the audio waveform.');
  return { duration, start, end, peaks };
}
