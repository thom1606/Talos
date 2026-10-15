export type AudioRange = { start: number; end: number };
export type AudioWaveform = { duration: number; start: number; end: number; peaks: number[] };
export const bleepFrequency = 1000;
export const bleepAmplitude = 0.18;
export const previewSeconds = 2;
export const maximumRanges = 128;

// Both preview and export use these intervals. Overlap must never bring source audio back.
export function audioRanges(input: unknown, duration: number): AudioRange[] {
  if (!Array.isArray(input) || input.length > maximumRanges) throw new Error('Invalid audio selections');
  const ranges = input.map((value: unknown) => {
    if (!value || typeof value !== 'object') throw new Error('Invalid audio selection');
    const { start, end } = value as Record<string, unknown>;
    if (typeof start !== 'number' || typeof end !== 'number' || !Number.isFinite(start) || !Number.isFinite(end)
      || start < 0 || end <= start || end > duration) throw new Error('Invalid audio selection');
    return { start, end };
  }).sort((a, b) => a.start - b.start);
  const merged: AudioRange[] = [];
  for (const range of ranges) {
    const previous = merged.at(-1);
    if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
    else merged.push({ ...range });
  }
  return merged;
}

export function audioTime(seconds: number, precise = false): string {
  const rounded = precise ? Math.round(seconds * 100) / 100 : Math.floor(seconds);
  const minutes = Math.floor(rounded / 60);
  const remainder = rounded - minutes * 60;
  return `${minutes}:${(precise ? remainder.toFixed(2) : String(Math.floor(remainder))).padStart(precise ? 5 : 2, '0')}`;
}
