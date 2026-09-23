import { link, lstat, mkdir, rename, rmdir, unlink } from 'node:fs/promises';
import { basename, dirname, extname, join } from 'node:path';
import { talos, type TalosFile } from '@thom1606/talos-sdk';

interface Item {
  file: TalosFile;
  size: number;
  modified: string;
  directory: boolean;
  device: number;
  inode: number;
}

/** Plan every move before touching the filesystem. Each model call fits the on-device context window. */
export async function organize(files: TalosFile[], onMoving: () => void): Promise<number> {
  const groups = new Map<string, Item[]>();
  for (const file of files) {
    const info = await lstat(file.path);
    if (basename(file.path) !== file.name || (!info.isFile() && !info.isDirectory() && !info.isSymbolicLink())) {
      throw new Error(`Cannot organize ${file.name}`);
    }
    const directory = dirname(file.path);
    const items = groups.get(directory) ?? [];
    items.push({ file, size: info.size, modified: info.mtime.toISOString().slice(0, 10),
      directory: info.isDirectory(), device: info.dev, inode: info.ino });
    groups.set(directory, items);
  }

  const plans: { directory: string; items: Item[]; categories: string[]; assignments: number[] }[] = [];
  for (const [directory, items] of groups) {
    const categories = await chooseCategories(items);
    const assignments: number[] = [];
    for (let start = 0; start < items.length; start += 10) {
      const batch = items.slice(start, start + 10);
      assignments.push(...await classify(batch, categories));
    }
    plans.push({ directory, items, categories, assignments });
  }

  // All model output has been checked before the first item is moved.
  onMoving();
  const selectedPaths = new Set(files.map(file => file.path));
  const createdFolders: string[] = [];
  const completed: { source: string; destination: string }[] = [];
  try {
    for (const plan of plans) {
      const destinations = new Map<number, string>();
      for (let i = 0; i < plan.items.length; i++) {
        const item = plan.items[i]!;
        const category = plan.assignments[i]!;
        let folder = destinations.get(category);
        if (!folder) {
          const resolved = await categoryFolder(plan.directory, plan.categories[category]!, selectedPaths);
          folder = resolved.path;
          if (resolved.created) createdFolders.push(folder);
          destinations.set(category, folder);
        }
        const current = await lstat(item.file.path);
        if (current.dev !== item.device || current.ino !== item.inode) {
          throw new Error(`${item.file.name} changed while organizing`);
        }
        const destination = await moveItem(item.file.path, folder, current.isFile());
        completed.push({ source: item.file.path, destination });
      }
    }
  } catch (error) {
    const unrestored: string[] = [];
    for (const move of completed.reverse()) {
      try { await rename(move.destination, move.source); }
      catch { unrestored.push(move.destination); }
    }
    for (const folder of createdFolders.reverse()) await rmdir(folder).catch(() => {});
    if (unrestored.length) {
      throw new Error(`Organizing stopped. ${unrestored.length} items could not be restored; they remain in the new folders.`);
    }
    throw error;
  }
  return completed.length;
}

async function chooseCategories(items: Item[]): Promise<string[]> {
  const sample = items.length <= 50 ? items : Array.from({ length: 50 }, (_, i) => items[Math.floor(i * items.length / 50)]!);
  const prompt = `Create ${items.length < 10 ? '1 to 3' : '3 to 8'} broad, useful folder names for organizing these selected items. Use the language of the names where possible. Group by purpose or subject when clear; otherwise by file type. Never create one folder per item. Do not use dates, file extensions, MIME identifiers or sizes as folder names. For example, invoice.pdf and budget.xlsx belong in Finance, while vacation.jpg belongs in Photos. Return ONLY a JSON array of folder name strings, no Markdown. Keep each name short.\n${sample.map(item => describe(item)).join('\n')}`;
  for (let attempt = 0; attempt < 2; attempt++) {
    const answer = await askModel(prompt + (attempt ? '\nRespond with a valid JSON array only.' : ''));
    try {
      const parsed: unknown = parseArray(answer);
      if (!Array.isArray(parsed) || parsed.length < 1 || parsed.length > 8) continue;
      const names = parsed.map(name => safeCategory(name));
      if (new Set(names.map(name => name.toLocaleLowerCase())).size === names.length) return names;
    } catch { /* Retry a malformed response once. */ }
  }
  throw new Error('Apple Intelligence could not suggest valid folders');
}

async function classify(items: Item[], categories: string[]): Promise<number[]> {
  const prompt = `Categorize the ${items.length} items below. Return ONLY a JSON array of exactly ${items.length} category codes, one per item in order. Each code must be one of these: ${categories.map((name, i) => `${i}=${name}`).join('; ')}. Example: if item 1 belongs in category 2 and item 2 in category 0, respond [2,0]. Never copy item numbers as category codes. No Markdown.\n${items.map((item, i) => `${i + 1}. ${describe(item)}`).join('\n')}`;
  for (let attempt = 0; attempt < 2; attempt++) {
    // Model errors such as unavailability or a full context should stop immediately.
    const answer = await askModel(prompt + (attempt ? '\nRespond with exactly the requested number of codes in a valid JSON array.' : ''));
    try {
      const values: unknown = parseArray(answer);
      if (Array.isArray(values) && values.length === items.length &&
          values.every(value => Number.isInteger(value) && value >= 0 && value < categories.length)) {
        return values as number[];
      }
    } catch { /* Try a stricter prompt, then a smaller batch. */ }
  }
  if (items.length > 1) {
    const middle = Math.ceil(items.length / 2);
    return [...await classify(items.slice(0, middle), categories),
      ...await classify(items.slice(middle), categories)];
  }
  throw new Error('Apple Intelligence could not classify a selected item');
}

function describe(item: Item): string {
  const type = item.directory ? 'folder' : item.file.contentType === 'public.data'
    ? `${extname(item.file.name).slice(1) || 'file'} file`
    : item.file.contentType.split('.').at(-1);
  return `${JSON.stringify(item.file.name)} | ${type} | ${Math.round(item.size / 1024)} KB | ${item.modified}`;
}

function parseArray(answer: string): unknown {
  const start = answer.indexOf('[');
  const end = answer.lastIndexOf(']');
  if (start < 0 || end <= start) throw new Error('Apple Intelligence did not return a list');
  return JSON.parse(answer.slice(start, end + 1));
}

function safeCategory(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Apple Intelligence returned an invalid folder name');
  const name = value.replace(/[\\/:\x00-\x1f]/g, '-').replace(/\s+/g, ' ').trim().replace(/^\.+|\.+$/g, '').slice(0, 40);
  if (!name || name === '.' || name === '..') throw new Error('Apple Intelligence returned an invalid folder name');
  return name;
}

/** Reuse an existing category folder, unless that folder is itself selected for moving. */
async function categoryFolder(directory: string, category: string, selectedPaths: Set<string>): Promise<{ path: string; created: boolean }> {
  for (let number = 1; number <= 10_000; number++) {
    const path = join(directory, number === 1 ? category : `${category} ${number}`);
    if (selectedPaths.has(path)) continue;
    try { await mkdir(path); return { path, created: true }; }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
      const existing = await lstat(path);
      if (existing.isDirectory()) return { path, created: false };
    }
  }
  throw new Error('Could not create a category folder');
}

/** Reserve regular-file destinations without replacing an existing name. */
async function moveItem(source: string, folder: string, regularFile: boolean): Promise<string> {
  const name = basename(source);
  const extension = extname(name);
  const stem = name.slice(0, name.length - extension.length);
  for (let number = 1; number <= 10_000; number++) {
    const destination = join(folder, number === 1 ? name : `${stem} (${number})${extension}`);
    if (regularFile) {
      try { await link(source, destination); }
      catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'EEXIST') continue;
        throw error;
      }
      try { await unlink(source); }
      catch (error) { await unlink(destination).catch(() => {}); throw error; }
      return destination;
    }
    try { await lstat(destination); continue; }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
    try { await rename(source, destination); return destination; }
    catch (error) {
      if (['EEXIST', 'ENOTEMPTY'].includes((error as NodeJS.ErrnoException).code ?? '')) continue;
      throw error;
    }
  }
  throw new Error(`Could not find an available name for ${name}`);
}

// Built-ins can use the host bridge before the next public SDK package is published.
// Newer SDK installations provide the same bridge as talos.appleIntelligence.respond.
function askModel(prompt: string): Promise<string> {
  const sdk = talos as typeof talos & { appleIntelligence?: { respond(prompt: string): Promise<string> } };
  if (sdk.appleIntelligence) return sdk.appleIntelligence.respond(prompt);
  const request = (globalThis as typeof globalThis & {
    [key: symbol]: ((prompt: string) => Promise<string>) | undefined;
  })[Symbol.for('talos.modelRequest')];
  if (!request) throw new Error('Apple Intelligence requires a newer Talos app');
  return request(prompt);
}
