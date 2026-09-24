import type { TalosContext } from '@thom1606/talos-sdk';
import { mediaKind } from '../media';
import { chosen, output, run, tool } from './shared';

export async function cropImage(context: TalosContext, payload: Record<string, unknown>, signal: AbortSignal) {
  const file = chosen(context, payload.index);
  if (mediaKind(file.name) !== 'image') throw new Error('Select an image to crop');
  const rect = payload.rect as Record<string, number>;
  if (!rect || !['x', 'y', 'width', 'height'].every(key => Number.isSafeInteger(rect[key]) && rect[key] >= (key === 'x' || key === 'y' ? 0 : 1))) {
    throw new Error('Invalid crop rectangle');
  }
  const format = /\.png$/i.test(file.name) ? 'png' : 'jpg';
  return output(file, '-cropped', format, async path => {
    await run(await tool('image-tool'), [file.path, path, String(rect.x), String(rect.y),
      String(rect.width), String(rect.height), format], signal);
  }, signal);
}
