import { access, chmod, mkdir, mkdtemp, rename, rm, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { execute } from './files.mjs';
const release = 'https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1';
const checksums = {
  arm64: '8923876afa8db5585022d7860ec7e589af192f441c56793971276d450ed3bbfa',
  x64: '929b375c1182d956c51f7ac25e0b2b0411fb01f6f407aa15c9758efeb4242106',
};
export async function ffmpeg(session) {
  for (const path of ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg']) {
    try {
      await access(path, constants.X_OK);
      await execute(path, ['-version']);
      return path;
    } catch {}
  }
  const directory = join(
    homedir(),
    'Library/Application Support/Talos/Tools',
    'ffmpeg-b6.1.1-' + process.arch,
  );
  const destination = join(directory, 'ffmpeg');
  try {
    await access(destination, constants.X_OK);
    return destination;
  } catch {}
  if (!checksums[process.arch]) throw new Error('Unsupported Mac architecture');
  await session.progress(0, 'Preparing media tools…');
  await mkdir(directory, { recursive: true });
  const staging = await mkdtemp(join(directory, '.download-'));
  try {
    const response = await fetch(`${release}/ffmpeg-darwin-${process.arch}.gz`, {
      signal: AbortSignal.timeout(120000),
    });
    if (!response.ok)
      throw new Error('Cannot download media tools. Check your internet connection.');
    const compressed = Buffer.from(await response.arrayBuffer());
    if (createHash('sha256').update(compressed).digest('hex') !== checksums[process.arch])
      throw new Error('Media tool checksum does not match');
    const executable = join(staging, 'ffmpeg');
    await writeFile(executable, gunzipSync(compressed));
    await chmod(executable, 0o755);
    // Keep the upstream license alongside the downloaded executable.
    const license = await fetch(`${release}/darwin-${process.arch}.LICENSE`);
    if (!license.ok) throw new Error('Cannot retrieve media tool license');
    await writeFile(join(directory, 'LICENSE'), await license.text());
    await execute(executable, ['-version']);
    await rename(executable, destination);
    return destination;
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}
