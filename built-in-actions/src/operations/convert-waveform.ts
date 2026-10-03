import type { TalosFile } from '@thom1606/talos-sdk';
import { writeFile } from 'node:fs/promises';
import { readAudioWaveform } from './audio-waveform';
import { encodePNG } from './png';

const width = 1600, height = 400, padding = 16, count = 512;
// Matches the shipping accent in TalosAppearance.swift; exports use sRGB in both formats.
const color = '#CA491C';
const rgb = Buffer.from(color.slice(1), 'hex');

export async function convertWaveform(file: TalosFile, format: 'svg' | 'png', destination: string, signal?: AbortSignal) {
  const { peaks } = await readAudioWaveform(file, {}, signal);
  const pitch = (width - padding * 2) / count, barWidth = pitch - 1;
  const bars = Array.from({ length: count }, (_, index) => {
    const start = Math.floor(index * peaks.length / count), end = Math.max(start + 1, Math.floor((index + 1) * peaks.length / count));
    const amplitude = Math.max(...peaks.slice(start, end));
    const barHeight = Math.max(2, Math.sqrt(amplitude) * (height - padding * 2));
    return { x: padding + index * pitch, y: (height - barHeight) / 2, width: barWidth, height: barHeight,
      radius: Math.min(barWidth, barHeight) / 2 };
  });
  signal?.throwIfAborted();
  if (format === 'svg') {
    const number = (value: number) => String(Number(value.toFixed(3)));
    const rectangles = bars.map(bar => `<rect x="${number(bar.x)}" y="${number(bar.y)}" width="${number(bar.width)}" height="${number(bar.height)}" rx="${number(bar.radius)}"/>`).join('');
    await writeFile(destination, `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><g fill="${color}">${rectangles}</g></svg>\n`);
  } else {
    const pixels = Buffer.alloc(width * height * 4);
    for (const bar of bars) {
      for (let y = Math.floor(bar.y); y < Math.ceil(bar.y + bar.height); y++) {
        for (let x = Math.floor(bar.x); x < Math.ceil(bar.x + bar.width); x++) {
          // Signed distance to the same rounded rectangle as the SVG, with one-pixel antialiasing.
          const dx = Math.abs(x + 0.5 - bar.x - bar.width / 2) - bar.width / 2 + bar.radius;
          const dy = Math.abs(y + 0.5 - height / 2) - bar.height / 2 + bar.radius;
          const distance = Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) + Math.min(Math.max(dx, dy), 0) - bar.radius;
          const offset = (y * width + x) * 4;
          pixels[offset] = rgb[0]; pixels[offset + 1] = rgb[1]; pixels[offset + 2] = rgb[2];
          pixels[offset + 3] = Math.round(Math.max(0, Math.min(1, 0.5 - distance)) * 255);
        }
      }
    }
    await writeFile(destination, await encodePNG(width, height, pixels));
  }
}
