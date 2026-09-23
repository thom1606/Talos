import { createWriteStream } from 'node:fs';
import { lstat, readdir, readlink } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { basename, extname, join } from 'node:path';
import { finished } from 'node:stream/promises';
import type { ZipArchive } from 'archiver';
import type { TalosFile } from '@thom1606/talos-sdk';
import { lifecycle, output } from './shared';

export async function archive(files: TalosFile[]) {
  if (!files.length) throw new Error('Select files to archive');
  // Archiver's bundled CommonJS dependencies need Node's require at evaluation time.
  (globalThis as typeof globalThis & { require?: NodeRequire }).require ??= createRequire(import.meta.url);
  const { ZipArchive } = await import('archiver');
  return output({ ...files[0], name: 'Archive' }, '', 'zip', async path => {
    const zipArchive = new ZipArchive({ zlib: { level: 6 } });
    const destination = createWriteStream(path, { flags: 'wx' });
    const completed = finished(destination);
    zipArchive.on('warning', error => destination.destroy(error));
    zipArchive.on('error', error => destination.destroy(error));
    zipArchive.pipe(destination);
    const abort = () => { zipArchive.abort(); destination.destroy(new Error('Archive stopped')); };
    lifecycle.signal.addEventListener('abort', abort, { once: true });
    try {
      const used = new Set<string>();
      for (const file of files) {
        lifecycle.signal.throwIfAborted();
        // Finder selections from different folders may share a basename in the ZIP root.
        let name = basename(file.name), number = 1;
        while (used.has(name.toLocaleLowerCase())) name = `${basename(file.name, extname(file.name))}-${++number}${extname(file.name)}`;
        used.add(name.toLocaleLowerCase());
        await appendArchiveEntry(zipArchive, file.path, name, path);
      }
      await zipArchive.finalize();
      await completed;
    } catch (error) {
      zipArchive.abort();
      destination.destroy();
      await completed.catch(() => {});
      throw error;
    } finally {
      lifecycle.signal.removeEventListener('abort', abort);
    }
  });
}

async function appendArchiveEntry(archive: ZipArchive, path: string, name: string, outputPath: string): Promise<void> {
  lifecycle.signal.throwIfAborted();
  // The selected folder may contain the temporary ZIP being written beside an input file.
  if (path === outputPath) return;
  const info = await lstat(path);
  if (info.isSymbolicLink()) {
    // Store the link itself; traversing it would change the archive's structure.
    archive.symlink(name, await readlink(path), info.mode);
  } else if (info.isDirectory()) {
    archive.append(Buffer.alloc(0), { name: `${name}/`, type: 'directory', date: info.mtime, mode: info.mode });
    for (const child of (await readdir(path)).sort()) await appendArchiveEntry(archive, join(path, child), `${name}/${child}`, outputPath);
  } else if (info.isFile()) {
    archive.file(path, { name, date: info.mtime, mode: info.mode, stats: info });
  } else {
    throw new Error(`Cannot archive unsupported file: ${path}`);
  }
}
