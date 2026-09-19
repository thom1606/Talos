import { cp, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { execute, outputFile } from '../files.mjs';
import { text, all } from '../session.mjs';

export const archiveAction = {
  id: 'archive',
  title: text('Archive', 'Archiveren', 'Archivar', 'Archiver'),
  symbol: 'archivebox',
  acceptedTypes: all,
  async run(session) {
    const staging = await mkdtemp(join(tmpdir(), 'talos-archive-'));
    try {
      const used = new Set();
      for (const file of session.files) {
        let name = basename(file.path),
          index = 2;
        while (used.has(name)) name = `${index++}-${basename(file.path)}`;
        used.add(name);
        await cp(file.path, join(staging, name), { recursive: true, dereference: false });
      }
      const result = await outputFile(session.files[0].path, 'zip', '-archive', (output) =>
        execute('/usr/bin/ditto', ['-c', '-k', '--norsrc', staging, output]),
      );
      await session.complete('Archive created', [result]);
    } finally {
      await rm(staging, { recursive: true, force: true });
    }
  },
};
