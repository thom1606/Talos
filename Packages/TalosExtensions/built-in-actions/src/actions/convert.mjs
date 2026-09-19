import { rm } from 'node:fs/promises';
import { execute, outputFile } from '../files.mjs';
import { ffmpeg } from '../ffmpeg.mjs';
import { audioOptions, videoOptions } from '../media-options.mjs';
import { each, text, image, media } from '../session.mjs';

function conversionOptions(kind, format) {
  if (kind === 'audio') return ['-vn', ...audioOptions[format]];
  if (kind === 'video') return videoOptions[format];
  if (format === 'gif') return [];

  const options = ['-frames:v', '1'];
  if (format === 'jpg') options.push('-q:v', '2');
  if (format === 'webp') options.push('-quality', '90');
  return options;
}

function convert(format, acceptedTypes, kind) {
  return {
    id: `convert.${kind}.${format}`,
    title: format.toUpperCase(),
    acceptedTypes,
    async run(session) {
      const nativeFormat = kind === 'image' && ['jpg', 'png', 'heic'].includes(format);
      const tool = nativeFormat ? null : await ffmpeg(session);
      await each(session, (file) =>
        outputFile(file.path, format, '', async (output) => {
          if (nativeFormat)
            await execute('/usr/bin/sips', [
              '-s',
              'format',
              format === 'jpg' ? 'jpeg' : format,
              file.path,
              '--out',
              output,
            ]);
          else {
            const options = conversionOptions(kind, format);
            const nativeInput = /\.hei[cf]$/i.test(file.path) && kind === 'image';
            const input = nativeInput ? output + '.input.png' : file.path;
            try {
              if (nativeInput)
                await execute('/usr/bin/sips', ['-s', 'format', 'png', file.path, '--out', input]);
              await execute(tool, [
                '-nostdin',
                '-v',
                'error',
                '-i',
                input,
                ...options,
                '-n',
                output,
              ]);
            } finally {
              if (nativeInput) await rm(input, { force: true });
            }
          }
        }),
      );
    },
  };
}

export const convertAction = {
  id: 'convert',
  title: text('Convert', 'Converteren', 'Convertir', 'Convertir'),
  symbol: 'arrow.triangle.2.circlepath',
  acceptedTypes: media,
  children: [
    ...['jpg', 'png', 'webp', 'gif', 'heic'].map((format) => convert(format, image, 'image')),
    ...['mp3', 'wav', 'ogg'].map((format) => convert(format, ['public.audio'], 'audio')),
    ...['mp4', 'mov', 'mkv', 'avi', 'webm'].map((format) =>
      convert(format, ['public.movie'], 'video'),
    ),
  ],
};
