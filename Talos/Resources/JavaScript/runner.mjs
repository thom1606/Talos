// One process per action: extension crashes and imports cannot block the wheel.
import { readFile, appendFile, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

const [entrypoint, invocationPath] = process.argv.slice(2);
const invocation = JSON.parse(await readFile(invocationPath, 'utf8'));
const workspace = fileURLToPath(invocation.workspace);
let finished = false;
let pending = Promise.resolve();
function emit(kind, message, extra = {}) {
  if (finished) return pending;
  const data = JSON.stringify({ kind, taskID: invocation.taskID, message, ...extra }) + '\n';
  if (Buffer.byteLength(data) >= 1_000_000) throw new Error('Talos event exceeds 1 MB');
  if (kind === 'completed' || kind === 'failed') finished = true;
  pending = pending.then(() => appendFile(join(workspace, 'events.jsonl'), data));
  return pending;
}
function find(actions, id) {
  for (const action of actions) {
    if (action.id === id) return action;
    const child = find(action.children ?? [], id);
    if (child) return child;
  }
}
async function nativeRequest(kind, options) {
  const id = randomUUID();
  const requestPath = join(workspace, 'native-request.json');
  await writeFile(requestPath, JSON.stringify({ id, kind, ...options }));
  for (;;) {
    try {
      const reply = JSON.parse(await readFile(join(workspace, id + '.response.json'), 'utf8'));
      if (reply.error) throw new Error(reply.error);
      return reply.output;
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await delay(100);
  }
}
try {
  // Secrets arrive over a private pipe, never in arguments, environment or job files.
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const settings = JSON.parse(input || '{}');
  const extension = (await import(pathToFileURL(resolve(entrypoint)))).default;
  const action = find(extension.actions, invocation.actionID);
  if (typeof action?.run !== 'function') throw new Error('Action has no JavaScript handler');
  const language = invocation.language ?? 'en';
  const session = {
    files: invocation.files.map(file => ({ ...file, path: fileURLToPath(file.url) })),
    settings, language,
    image: options => nativeRequest('image', options),
    async crop(input) {
      const output = await nativeRequest('crop', { input });
      return emit('completed', output ? 'Image saved' : 'Cancelled', { outputs: output ? [pathToFileURL(output).href] : [] });
    },
    notificationAction: invocation.notificationAction,
    progress(fraction, message) {
      if (!Number.isFinite(fraction)) throw new Error('Invalid progress');
      return emit('progress', message, { fraction: Math.min(1, Math.max(0, fraction)) });
    },
    notify: (message, actions = []) => emit('notification', message, { actions: actions.slice(0, 4) }),
    complete: (message = 'Done', outputs = []) => emit('completed', message, { outputs: outputs.map(path => pathToFileURL(path).href) }),
    async checkCancellation() {
      try { await readFile(join(workspace, 'cancel')); } catch (error) {
        if (error.code === 'ENOENT') return;
        throw error;
      }
      throw new Error('Cancelled');
    },
  };
  await action.run(session);
  if (!finished) await session.complete();
} catch (error) {
  await emit('failed', error instanceof Error ? error.message : 'Action failed');
  process.exitCode = 1;
}
await pending;
