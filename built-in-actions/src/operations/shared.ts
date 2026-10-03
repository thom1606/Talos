import { runProcess, writeOutput } from '@thom1606/talos-sdk/node';
import { chmod } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { TalosContext, TalosFile } from '@thom1606/talos-sdk';

const packageRoot = dirname(fileURLToPath(import.meta.url));
export async function tool(name: 'ffmpeg' | 'ffprobe' | 'jpegtran' | 'cjpeg' | 'djpeg' | 'pdf-tool' | 'image-tool'): Promise<string> {
  const executable = join(packageRoot, 'vendor', 'bin', process.arch === 'arm64' ? 'arm64' : 'x86_64', name);
  // Extracted .talos files are not executable until the bundled binary is needed.
  await chmod(executable, 0o755);
  return executable;
}
export function run(executable: string, args: string[], signal?: AbortSignal): Promise<string> {
  return runProcess(executable, args, { ...(signal ? { signal } : {}), timeout: 30 * 60_000 });
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

// Media processing stays here; the SDK owns generic process and output lifetimes.
export function output(file: TalosFile, suffix: string, extension: string,
  generate: (temporary: string) => Promise<boolean | void>, signal?: AbortSignal): Promise<string | null> {
  return writeOutput(file, { suffix, extension, ...(signal ? { signal } : {}) }, generate);
}
