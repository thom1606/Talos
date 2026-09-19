#!/usr/bin/env node
import { build } from 'esbuild';
import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { localize } from './src/index.mjs';

if (process.argv.includes('--help')) {
  console.log('Usage: talos-build [extension-directory]');
  process.exit(0);
}
const root = resolve(process.argv[2] ?? '.');
const pkg = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
const destination = join(root, 'dist');
await mkdir(destination, { recursive: true });
const moduleDirectory = join(destination, 'module');
await rm(moduleDirectory, { recursive: true, force: true });
await mkdir(moduleDirectory);
const entrypoint = join(moduleDirectory, 'extension.mjs');
await build({
  entryPoints: [join(root, pkg.talos?.entry ?? 'src/index.mjs')],
  outfile: entrypoint,
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'esm',
  packages: 'bundle',
  alias: { '@thom1606/talos-sdk': join(dirname(fileURLToPath(import.meta.url)), 'src/index.mjs') },
});
const extension = (await import(pathToFileURL(entrypoint))).default;
const identifier = (value) =>
  typeof value === 'string' &&
  /^[a-zA-Z0-9._-]{1,120}$/.test(value) &&
  !['.', '..'].includes(value);
if (!identifier(extension?.id) || !Array.isArray(extension?.actions) || !extension.actions.length)
  throw new Error('Invalid extension identity or actions');
const ids = new Set();
function validateActions(actions, depth = 0) {
  if (depth > 5 || actions.length > 64) throw new Error('Too many actions or submenu levels');
  for (const action of actions) {
    if (!identifier(action.id) || ids.has(action.id) || !localize(action.title))
      throw new Error('Invalid or duplicate action');
    ids.add(action.id);
    if (action.children) validateActions(action.children, depth + 1);
    else if (typeof action.run !== 'function') throw new Error('An action needs a run function');
    for (const field of action.settings ?? []) {
      if (!identifier(field.id) || !localize(field.label))
        throw new Error('Invalid settings field');
    }
  }
}
validateActions(extension.actions);
function actionManifest(action) {
  const fields = action.settings ?? [];
  return {
    id: action.id,
    title: localize(action.title),
    translations: typeof action.title === 'object' ? action.title : undefined,
    symbol: action.symbol,
    acceptedTypes: action.acceptedTypes ?? ['public.item', 'public.folder'],
    minimumFiles: action.minimumFiles ?? 1,
    maximumFiles: action.maximumFiles,
    settings: fields.map((field) => ({
      ...field,
      label: localize(field.label),
      translations: typeof field.label === 'object' ? field.label : undefined,
      defaultValue: field.defaultValue == null ? undefined : String(field.defaultValue),
    })),
    children: action.children?.map(actionManifest),
  };
}
const manifest = {
  id: extension.id,
  name: localize(extension.name),
  description: localize(extension.description ?? ''),
  version: pkg.version,
  sdkVersion: 1,
  runtime: 'javascript',
  entrypoint: 'extension.mjs',
  minimumMacOS: '26.0',
  architectures: ['arm64', 'x86_64'],
  actions: extension.actions.map(actionManifest),
};
await writeFile(join(moduleDirectory, 'config.json'), JSON.stringify(manifest, null, 2) + '\n');
const archive = join(destination, extension.id + '.talos');
await rm(archive, { force: true });
// Packaging runs on the maker's computer/CI, never on an end user's Mac.
execFileSync('/usr/bin/zip', ['-q', '-r', archive, '.'], { cwd: moduleDirectory });
const release = {
  tag: 'v' + pkg.version,
  asset: extension.id + '.talos',
  sha256: createHash('sha256')
    .update(await readFile(archive))
    .digest('hex'),
};
await writeFile(
  join(destination, 'release-config.json'),
  JSON.stringify({ ...manifest, release }, null, 2) + '\n',
);
console.log(`Built ${archive}`);
