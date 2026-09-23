import { talos, t, type TalosContext } from '@thom1606/talos-sdk';
import CropWindow from './windows/crop';
import { archive } from './operations/archive';
import { compress } from './operations/compress';
import { convert, homogeneous } from './operations/convert';
import { cropVideo } from './operations/crop-video';
import { stopOperations } from './operations/shared';

export async function activate(context: TalosContext) {
  try {
    if (!context.files.length) throw new Error(t('actions.noFiles'));
    if (context.action.startsWith('convert-')) {
      homogeneous(context.files);
      talos.loading(t('convert.working'));
      const results = await convert(context, context.action.slice('convert-'.length));
      talos.success(t('convert.done', { count: results.length }));
      return;
    }
    switch (context.action) {
      case 'crop':
        talos.openWindow({ title: t('crop.title'), children: <CropWindow />, width: 480, height: 680,
          onRequest: async (method, payload, context, signal) => {
            if (method !== 'cropVideo' || !payload || typeof payload !== 'object') throw new Error('Unknown crop request');
            return cropVideo(context, payload as Record<string, unknown>, signal);
          } });
        break;
      case 'archive':
        talos.loading(t('archive.working'));
        await archive(context.files);
        talos.success(t('archive.done'));
        break;
      case 'compress': {
        let saved = 0, reduced = 0, skipped = 0;
        const failures: string[] = [];
        for (const [index, file] of context.files.entries()) {
          talos.loading(t('compress.working', { current: index + 1, total: context.files.length }));
          try {
            const difference = await compress(file);
            saved += difference;
            if (difference > 0) reduced++; else skipped++;
          } catch (error) { failures.push(file.name); console.error(file.name, error); }
        }
        if (failures.length) talos.failed(t('compress.partial', { reduced, skipped, failed: failures.length }));
        else if (saved) talos.success(t(reduced === 1 ? 'compress.doneOne' : 'compress.doneMany',
          { count: reduced, size: formatBytes(saved) }));
        else talos.toast(t('compress.unchanged'));
        break;
      }
      default: throw new Error('Unknown Talos action');
    }
  } catch (error) {
    console.error(error);
    talos.failed(error instanceof Error ? error.message : String(error));
  }
}
export function deactivate() { stopOperations(); }
function formatBytes(bytes: number) {
  return bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
