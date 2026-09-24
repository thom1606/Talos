import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { chmod, link, rm } from 'node:fs/promises';
import { basename, dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';

const packageRoot = dirname(fileURLToPath(import.meta.url));
// One lifecycle stops all running codec processes when Talos unloads this extension.
export const active = new Set<AbortController>();
export const lifecycle = new AbortController();
export function stopOperations() { lifecycle.abort(); for (const controller of active) controller.abort(); }

export async function tool(name: 'ffmpeg' | 'ffprobe' | 'jpegtran' | 'cjpeg' | 'djpeg' | 'pdf-tool' | 'image-tool'): Promise<string> {
  const executable = join(packageRoot, 'vendor', 'bin', process.arch === 'arm64' ? 'arm64' : 'x86_64', name);
  // Extracted .talos files are not executable until the bundled binary is needed.
  await chmod(executable, 0o755);
  return executable;
}
// Bound process lifetime and output so a codec cannot leave the extension running forever.
export async function run(executable: string, args: string[], signal?: AbortSignal): Promise<string> {
  lifecycle.signal.throwIfAborted();
  signal?.throwIfAborted();
  const controller = new AbortController();
  active.add(controller);
  const abort = () => controller.abort();
  signal?.addEventListener('abort', abort, { once: true });
  const deadline = setTimeout(abort, 30 * 60_000);
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn(executable, args, { signal: controller.signal, stdio: ['ignore', 'pipe', 'pipe'] });
      let output = '', error = '';
      child.stdout.on('data', chunk => {
        output += chunk.toString();
        if (output.length > 1_048_576) controller.abort();
      });
      child.stderr.on('data', chunk => { error = (error + chunk.toString()).slice(-8192); });
      child.once('error', reject);
      child.once('close', code => code === 0 ? resolve(output) : reject(new Error(error.trim() || `Operation stopped (${code})`)));
    });
  } finally {
    clearTimeout(deadline); active.delete(controller); signal?.removeEventListener('abort', abort);
  }
}
export async function ffmpeg(args: string[], signal?: AbortSignal) {
  return run(await tool('ffmpeg'), ['-nostdin', '-hide_banner', '-loglevel', 'error', '-n', ...args], signal);
}

export async function probe(file: TalosFile, signal?: AbortSignal) {
  return JSON.parse(await run(await tool('ffprobe'), ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file.path], signal));
}
export function chosen(context: TalosContext, index: unknown): TalosFile {
  if (!Number.isInteger(index) || Number(index) < 0 || Number(index) >= context.files.length) throw new Error('Invalid selected file');
  return context.files[Number(index)];
}

// Generate beside the input, then atomically link to an available name. The original and
// any existing outputs remain untouched even if generation fails or two actions finish together.
export async function output(file: TalosFile, suffix: string, extension: string,
  generate: (temporary: string) => Promise<boolean | void>, signal?: AbortSignal): Promise<string | null> {
  const directory = dirname(file.path);
  const temporary = join(directory, `.talos-${randomUUID()}.${extension}`);
  try {
    if (await generate(temporary) === false) return null;
    lifecycle.signal.throwIfAborted();
    signal?.throwIfAborted();
    const stem = basename(file.name, extname(file.name)) + suffix;
    for (let number = 0; number < 10_000; number++) {
      const destination = join(directory, `${stem}${number ? `-${number + 1}` : ''}.${extension}`);
      try { await link(temporary, destination); return destination; }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
    }
    throw new Error('Could not find an available output filename');
  } finally { await rm(temporary, { force: true }); }
}
