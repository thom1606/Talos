import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';
import { copyFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { formats, mediaKind, type MediaKind } from '../media';
import { ffmpeg, output, run, tool } from './shared';

export async function convert(context: TalosContext, format: unknown, signal?: AbortSignal) {
  const kind = homogeneous(context.files);
  if (typeof format !== 'string' || !(formats[kind] as readonly string[]).includes(format)) throw new Error('Unsupported output format');
  const results: string[] = [];
  for (const file of context.files) {
    signal?.throwIfAborted();
    if (kind === 'pdf') {
      results.push(...await convertPDF(file, format, signal));
      continue;
    }
    const path = await output(file, '-converted', format, async path => {
      if (kind === 'image') {
        // ImageIO via sips supports macOS image formats (including HEIC) without another host API.
        await run('/usr/bin/sips', ['-s', 'format', format === 'jpg' ? 'jpeg' : format, file.path, '--out', path], signal);
      } else {
        const codecs = kind === 'video'
          ? ['-map', '0:v:0', '-map', '0:a?', '-c:v', 'h264_videotoolbox', '-allow_sw', '1', '-q:v', '70', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart']
          : ['-map', '0:a:0', '-vn', '-c:a', format === 'm4a' ? 'aac' : format === 'flac' ? 'flac' : 'pcm_s24le', ...(format === 'm4a' ? ['-b:a', '256k'] : [])];
        await ffmpeg(['-i', file.path, ...codecs, '-map_metadata', '0', path], signal);
      }
    }, signal);
    if (path) results.push(path);
  }
  return results;
}
export function homogeneous(files: TalosFile[]): MediaKind {
  const kind = files[0] && mediaKind(files[0].name);
  if (!kind || !files.every(file => mediaKind(file.name) === kind)) throw new Error('Select only images, PDFs, videos, or audio files to convert.');
  return kind;
}

async function convertPDF(file: TalosFile, format: string, signal?: AbortSignal): Promise<string[]> {
  if (format === 'docx') return [await convertPDFToDOCX(file, signal)];
  const directory = await mkdtemp(join(dirname(file.path), '.talos-pdf-'));
  try {
    const pageCount = Number((await run(await tool('pdf-tool'), ['render', file.path, directory, format], signal)).trim());
    if (!Number.isSafeInteger(pageCount) || pageCount < 1) throw new Error('PDF rendering did not return a page count');
    const results: string[] = [];
    for (let page = 1; page <= pageCount; page++) {
      signal?.throwIfAborted();
      const suffix = pageCount === 1 ? '-converted' : `-converted-page-${page}`;
      const result = await output(file, suffix, format,
        temporary => copyFile(join(directory, `page-${page}.${format}`), temporary), signal);
      if (result) results.push(result);
    }
    return results;
  } finally { await rm(directory, { recursive: true, force: true }); }
}

async function convertPDFToDOCX(file: TalosFile, signal?: AbortSignal): Promise<string> {
  const pages: unknown = JSON.parse(await run(await tool('pdf-tool'), ['text', file.path], signal));
  if (!Array.isArray(pages) || !pages.length || !pages.every(page => typeof page === 'string')) {
    throw new Error('Cannot read PDF pages');
  }
  const { Document, ImageRun, Packer, Paragraph, TextRun } = await import('docx');
  const imageDirectory = pages.some(page => !page.trim())
    ? await mkdtemp(join(dirname(file.path), '.talos-pdf-')) : null;
  try {
    if (imageDirectory) await run(await tool('pdf-tool'), ['render', file.path, imageDirectory, 'png'], signal);
    const paragraphs: InstanceType<typeof Paragraph>[] = [];
    for (const [index, text] of pages.entries()) {
      signal?.throwIfAborted();
      if (text.trim()) {
        for (const [lineNumber, line] of text.split(/\r?\n/).entries()) {
          paragraphs.push(new Paragraph({ pageBreakBefore: index > 0 && lineNumber === 0,
            children: [new TextRun(line)] }));
        }
      } else {
        const image = await readFile(join(imageDirectory!, `page-${index + 1}.png`));
        const width = image.readUInt32BE(16), height = image.readUInt32BE(20);
        const scale = Math.min(1, 600 / width, 800 / height);
        paragraphs.push(new Paragraph({ pageBreakBefore: index > 0, children: [
          new ImageRun({ type: 'png', data: image,
            transformation: { width: Math.max(1, Math.round(width * scale)),
              height: Math.max(1, Math.round(height * scale)) } })
        ] }));
      }
    }
    const document = new Document({ sections: [{ children: paragraphs }] });
    const data = await Packer.toBuffer(document);
    const result = await output(file, '-converted', 'docx', path => writeFile(path, data), signal);
    if (!result) throw new Error('Cannot save DOCX');
    return result;
  } finally {
    if (imageDirectory) await rm(imageDirectory, { recursive: true, force: true });
  }
}
