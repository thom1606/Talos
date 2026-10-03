import type { TalosFile } from '@thom1606/talos-sdk';
import { output, run, tool } from './shared';

export async function convertArchive(file: TalosFile, format: unknown, signal?: AbortSignal) {
  if (format !== 'zip' && format !== 'tar' && format !== 'gzip') throw new Error('Unsupported archive format');
  const extension = format === 'gzip' ? 'tgz' : format;
  // Treat .tar.gz/.tar.gzip as a single input suffix when naming the new copy.
  const name = file.name.replace(/\.tar\.(?:gz|gzip)$/i, '.tgz');
  return output({ ...file, name }, '-converted', extension, async destination => {
    // The helper streams entries directly between formats. Never extract paths or follow links.
    // GZIP contains a TAR so multiple entries and directory structure stay together.
    await run(await tool('archive-tool'), [file.path, destination, format], signal);
  }, signal);
}
