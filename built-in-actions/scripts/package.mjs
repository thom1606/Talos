import { cp, mkdtemp, readdir, rm, stat } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('..', import.meta.url));
const archive = join(root, 'dist/talos-actions.talos');
const stage = await mkdtemp(join(tmpdir(), 'talos-builtin-package-'));
try {
  execFileSync('/usr/bin/ditto', ['-x', '-k', archive, stage]);
  for (const directory of ['bin', 'licenses', 'sources']) {
    await cp(join(root, 'vendor', directory), join(stage, 'vendor', directory), { recursive: true });
  }
  await cp(join(root, 'scripts/build-tools.sh'), join(stage, 'vendor/build-tools.sh'));
  await cp(join(root, 'scripts/build-pdf-tool.sh'), join(stage, 'vendor/build-pdf-tool.sh'));
  await cp(join(root, 'scripts/pdf-tool.swift'), join(stage, 'vendor/pdf-tool.swift'));
  await cp(join(root, 'scripts/build-image-tool.sh'), join(stage, 'vendor/build-image-tool.sh'));
  await cp(join(root, 'scripts/image-tool.swift'), join(stage, 'vendor/image-tool.swift'));
  const architectures = (process.env.ARCHS ?? (process.arch === 'arm64' ? 'arm64' : 'x86_64')).split(/\s+/).filter(Boolean);
  // Do not accidentally ship an unsigned stale binary from another local build architecture.
  for (const arch of await readdir(join(stage, 'vendor/bin'))) {
    if (!architectures.includes(arch)) await rm(join(stage, 'vendor/bin', arch), { recursive: true });
  }
  for (const arch of architectures) for (const tool of ['ffmpeg', 'ffprobe', 'jpegtran', 'cjpeg', 'djpeg', 'pdf-tool', 'image-tool']) await stat(join(stage, 'vendor/bin', arch, tool));
  await rm(archive);
  execFileSync('/usr/bin/ditto', ['-c', '-k', '--norsrc', '--noextattr', '--noqtn', stage, archive]);
  console.log(`Bundled Talos actions: ${((await stat(archive)).size / 1024 / 1024).toFixed(1)} MB`);
} finally { await rm(stage, { recursive: true, force: true }); }
