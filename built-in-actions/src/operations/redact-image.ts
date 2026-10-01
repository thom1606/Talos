import type { TalosContext } from '@thom1606/talos-sdk';
import { mediaKind } from '../media';
import { chosen, output, run, tool } from './shared';

export async function redactImage(context: TalosContext, payload: Record<string, unknown>, signal: AbortSignal) {
  const file = chosen(context, payload.index);
  if (mediaKind(file.name) !== 'image') throw new Error('Select an image to redact');
  if (!Array.isArray(payload.rects) || !payload.rects.length) throw new Error('Draw at least one redaction');
  const rects = payload.rects.map(value => {
    if (!value || typeof value !== 'object') throw new Error('Invalid redaction rectangle');
    const rect = value as Record<string, unknown>;
    for (const key of ['x', 'y', 'width', 'height']) {
      if (!Number.isSafeInteger(rect[key]) || Number(rect[key]) < (key === 'x' || key === 'y' ? 0 : 1)) {
        throw new Error('Invalid redaction rectangle');
      }
    }
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
  });
  const format = /\.png$/i.test(file.name) ? 'png' : 'jpg';
  return output(file, '-redacted', format, async path => {
    await run(await tool('image-tool'), [file.path, path, 'redact', JSON.stringify(rects), format], signal);
  }, signal);
}
