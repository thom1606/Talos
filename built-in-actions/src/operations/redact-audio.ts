import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { audioRanges, bleepAmplitude, bleepFrequency, previewSeconds, type AudioRange, type AudioWaveform } from '../audio';
import { audioDuration, readAudioWaveform } from './audio-waveform';
import { chosen, ffmpeg, output } from './shared';

async function audioInput(context: TalosContext, index: unknown, signal?: AbortSignal) {
  const file = chosen(context, index);
  return { file, duration: await audioDuration(file, signal) };
}

function interval(payload: Record<string, unknown>, duration: number) {
  const [range] = audioRanges([{ start: payload.start ?? 0, end: payload.end ?? duration }], duration);
  return range;
}

export async function audioWaveform(context: TalosContext, payload: Record<string, unknown>, signal?: AbortSignal): Promise<AudioWaveform> {
  return readAudioWaveform(chosen(context, payload.index), payload, signal);
}

function bleepFilter(ranges: AudioRange[], offset = 0): string {
  const time = offset ? `(t+${offset})` : 't';
  const selected = ranges.map(({ start, end }) => `gte(${time},${start})*lt(${time},${end})`).join('+');
  // aeval replaces every sample in every channel; it does not mix a tone over private speech.
  return `asetpts=N/SR/TB${ranges.length ? `,aeval='if(${selected},${bleepAmplitude}*sin(2*PI*${bleepFrequency}*${time}),val(ch))':c=same` : ''}`;
}

export async function redactAudio(context: TalosContext, payload: Record<string, unknown>, signal?: AbortSignal) {
  const { file, duration } = await audioInput(context, payload.index, signal);
  const ranges = audioRanges(payload.ranges, duration);
  if (!ranges.length) throw new Error('Select part of the waveform to redact.');
  // WAV avoids codec delay/smearing at redaction boundaries. Never carry alternate tracks,
  // embedded artwork, subtitles, chapters or descriptive source metadata into the copy.
  return output(file, '-redacted', 'wav', path => render(file, ranges, path, signal), signal);
}

async function render(file: TalosFile, ranges: AudioRange[], destination: string, signal?: AbortSignal) {
  await ffmpeg(['-i', file.path, '-map', '0:a:0', '-af', bleepFilter(ranges), '-c:a', 'pcm_s24le',
    '-map_metadata', '-1', '-map_chapters', '-1', destination], signal);
}

export async function audioPreview(context: TalosContext, payload: Record<string, unknown>, signal?: AbortSignal) {
  const { file, duration } = await audioInput(context, payload.index, signal);
  const range = interval(payload, duration);
  if (range.end - range.start > previewSeconds + 0.001) throw new Error('Audio preview exceeds two seconds.');
  const ranges = audioRanges(payload.ranges, duration);
  const directory = await mkdtemp(join(tmpdir(), 'talos-audio-preview-'));
  try {
    const path = join(directory, 'preview.wav');
    // Censor before the stereo downmix, including any other input channels.
    await ffmpeg(['-ss', String(range.start), '-i', file.path, '-t', String(range.end - range.start), '-map', '0:a:0',
      '-af', bleepFilter(ranges, range.start), '-ac', '2', '-ar', '48000', '-c:a', 'pcm_s16le',
      '-map_metadata', '-1', '-map_chapters', '-1', path], signal);
    signal?.throwIfAborted();
    return (await readFile(path)).toString('base64');
  } finally { await rm(directory, { recursive: true, force: true }); }
}
