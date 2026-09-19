import { copyFile, mkdtemp, rm, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { dirname, basename, extname, join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
export const execute = promisify(execFile);

/** A temporary output is published with exclusive creation, even if two actions finish together. */
export async function outputFile(input, extension, suffix, write) {
  const directory = dirname(input);
  const staging = await mkdtemp(join(directory, '.talos-'));
  try {
    const temporary = join(staging, 'output.' + extension);
    await write(temporary);
    const stem = basename(input, extname(input)) + suffix;
    for (let number = 1; number < 10000; number++) {
      const result = join(directory, `${stem}${number === 1 ? '' : ` ${number}`}.${extension}`);
      try {
        await copyFile(temporary, result, constants.COPYFILE_EXCL);
        return result;
      } catch (error) {
        if (error.code !== 'EEXIST') throw error;
      }
    }
    throw new Error('Cannot find a free output filename');
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}
export async function keepSmaller(original, output) {
  if ((await stat(output)).size >= (await stat(original)).size) await copyFile(original, output);
}
