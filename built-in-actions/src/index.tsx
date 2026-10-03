import { defineActions, talos, t, type TalosActivationContext } from '@thom1606/talos-sdk';
import CropWindow from './windows/crop';
import RedactWindow from './windows/redact';
import { archive } from './operations/archive';
import { compress } from './operations/compress';
import { convert, homogeneous } from './operations/convert';
import { cropVideo } from './operations/crop-video';
import { redactImage } from './operations/redact-image';
import { audioPreview, audioWaveform, redactAudio } from './operations/redact-audio';
import { cropImage } from './operations/crop-image';
import { organize } from './operations/organize';

const actions = defineActions({
  crop: () => talos.openWindow({
    title: t('crop.title'), children: <CropWindow />, width: 480, height: 680,
    onRequest: async (method, payload, context, signal) => {
      if (!payload || typeof payload !== 'object') throw new Error('Unknown crop request');
      if (method === 'cropVideo') return cropVideo(context, payload as Record<string, unknown>, signal);
      if (method === 'cropImage') return cropImage(context, payload as Record<string, unknown>, signal);
      throw new Error('Unknown crop request');
    },
  }),
  redact: () => talos.openWindow({
    title: t('redact.title'), children: <RedactWindow />, width: 480, height: 680,
    onRequest: async (method, payload, context, signal) => {
      if (!payload || typeof payload !== 'object') throw new Error('Unknown redact request');
      const data = payload as Record<string, unknown>;
      if (method === 'redactImage') return redactImage(context, data, signal);
      if (method === 'audioWaveform') return audioWaveform(context, data, signal);
      if (method === 'audioPreview') return audioPreview(context, data, signal);
      if (method === 'redactAudio') return redactAudio(context, data, signal);
      throw new Error('Unknown redact request');
    },
  }),
  organize: async (context) => {
    talos.loading(t('organize.sorting'));
    await organize(context.files, () => talos.loading(t('organize.moving')), context.signal);
    talos.success(t('organize.done'));
  },
  archive: async (context) => {
    talos.loading(t('archive.working'));
    await archive(context.files, context.signal);
    talos.success(t('archive.done'));
  },
  compress: compressSelection,
  'convert-png': convertTo('png'),
  'convert-svg': convertTo('svg'),
  'convert-webp': convertTo('webp'),
  'convert-jpg': convertTo('jpg'),
  'convert-docx': convertTo('docx'),
  'convert-tiff': convertTo('tiff'),
  'convert-bmp': convertTo('bmp'),
  'convert-mp4': convertTo('mp4'),
  'convert-mov': convertTo('mov'),
  'convert-m4a': convertTo('m4a'),
  'convert-wav': convertTo('wav'),
  'convert-flac': convertTo('flac'),
  'convert-zip': convertTo('zip'),
  'convert-tar': convertTo('tar'),
  'convert-gzip': convertTo('gzip'),
});

export async function activate(context: TalosActivationContext) {
  try {
    if (!context.files.length) throw new Error(t('actions.noFiles'));
    await actions(context);
  } catch (error) {
    if (context.signal.aborted) { talos.done(); throw error; }
    console.error(error);
    talos.failed(error instanceof Error ? error.message : String(error));
    throw error;
  }
}

function convertTo(format: string) {
  return async (context: TalosActivationContext) => {
    homogeneous(context.files);
    talos.loading(t('convert.working'));
    const results = await convert(context, format, context.signal);
    talos.success(t('convert.done', { count: results.length }));
  };
}
async function compressSelection(context: TalosActivationContext) {
  let saved = 0, reduced = 0, skipped = 0;
  const failures: string[] = [];
  for (const [index, file] of context.files.entries()) {
    context.signal.throwIfAborted();
    talos.loading(t('compress.working', { current: index + 1, total: context.files.length }));
    try {
      const difference = await compress(file, context.signal);
      saved += difference;
      if (difference > 0) reduced++; else skipped++;
    } catch (error) {
      context.signal.throwIfAborted();
      failures.push(file.name); console.error(file.name, error);
    }
  }
  if (failures.length) talos.failed(t('compress.partial', { reduced, skipped, failed: failures.length }));
  else if (saved) talos.success(t(reduced === 1 ? 'compress.doneOne' : 'compress.doneMany',
    { count: reduced, size: formatBytes(saved) }));
  else talos.toast(t('compress.unchanged'));
}
// Invocation scopes cancel SDK work before the runner calls this hook.
export function deactivate() {}
function formatBytes(bytes: number) {
  return bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
