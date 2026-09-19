import { extname } from 'node:path';
import { execute, outputFile, keepSmaller } from '../files.mjs';
import { ffmpeg } from '../ffmpeg.mjs';
import { videoOptions } from '../media-options.mjs';
import { each, text, media } from '../session.mjs';

const nativeFormats = {
  jpg: 'jpeg',
  jpeg: 'jpeg',
  png: 'png',
  heic: 'heic',
  heif: 'heic',
  tiff: 'tiff',
  tif: 'tiff',
};

function compressionOptions(extension, isImage, isAudio) {
  if (extension === 'gif') {
    return ['-vf', 'split[a][b];[a]palettegen[p];[b][p]paletteuse'];
  }
  if (isImage) {
    const options = ['-frames:v', '1'];
    if (extension === 'png') return [...options, '-compression_level', '9'];
    if (extension === 'webp') return [...options, '-quality', '82'];
    return [...options, '-q:v', '3'];
  }
  if (isAudio) return ['-vn', '-c:a', 'libmp3lame', '-q:a', '2'];
  return videoOptions.mp4;
}

export const compressAction = {
  id: 'compress',
  title: text('Compress', 'Comprimeren', 'Comprimir', 'Compresser'),
  symbol: 'arrow.down.right.and.arrow.up.left',
  acceptedTypes: media,
  async run(session) {
    const tool = session.files.every((file) =>
      Object.hasOwn(nativeFormats, extname(file.path).slice(1).toLowerCase()),
    )
      ? null
      : await ffmpeg(session);
    await each(session, (file) => {
      const extension = extname(file.path).slice(1).toLowerCase();
      const isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'tiff', 'tif', 'gif'].includes(
        extension,
      );
      const audio = ['mp3', 'wav', 'ogg', 'm4a', 'flac', 'aiff', 'aac'].includes(extension);
      let outputExtension = 'mp4';
      if (audio) outputExtension = 'mp3';
      if (isImage) outputExtension = extension;
      return outputFile(file.path, outputExtension, '-compressed', async (output) => {
        if (Object.hasOwn(nativeFormats, extension)) {
          const format = nativeFormats[extension];
          const options =
            format === 'png' ? [] : ['-s', 'formatOptions', format === 'tiff' ? 'lzw' : '80'];
          await execute('/usr/bin/sips', [
            '-s',
            'format',
            format,
            ...options,
            file.path,
            '--out',
            output,
          ]);
          await keepSmaller(file.path, output);
          return;
        }
        const options = compressionOptions(extension, isImage, audio);
        await execute(tool, ['-nostdin', '-v', 'error', '-i', file.path, ...options, '-n', output]);
        if (outputExtension === extension) await keepSmaller(file.path, output);
      });
    });
  },
};
